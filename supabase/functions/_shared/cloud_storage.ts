// =============================================================================
// Subida de archivos a la nube personal: Google Drive u OneDrive.
//
// Ambos usan OAuth con refresh token de la cuenta del dueño del centro
// (una cuenta personal no puede recibir archivos de una "service account").
// =============================================================================

export type UploadResult = { remoteId: string; webUrl?: string };
type SecretStore = { get(name: string): Promise<string | null>; set(name: string, value: string): Promise<void> };

const env = (k: string) => Deno.env.get(k) ?? "";

// ---------------------------------------------------------------- Google Drive
async function googleToken(): Promise<string> {
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: env("GOOGLE_CLIENT_ID"),
      client_secret: env("GOOGLE_CLIENT_SECRET"),
      refresh_token: env("GOOGLE_REFRESH_TOKEN"),
      grant_type: "refresh_token",
    }),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(`Google OAuth: ${json.error_description ?? json.error}`);
  return json.access_token as string;
}

/** Busca (o crea) la carpeta de backups. Con el scope drive.file solo ve lo que creó esta app. */
async function googleFolder(token: string): Promise<string> {
  if (env("GOOGLE_DRIVE_FOLDER_ID")) return env("GOOGLE_DRIVE_FOLDER_ID");
  const name = env("BACKUP_FOLDER_NAME") || "Agenda Wellness Backups";
  const q = encodeURIComponent(`name='${name.replace(/'/g, "\\'")}' and mimeType='application/vnd.google-apps.folder' and trashed=false`);
  const found = await fetch(`https://www.googleapis.com/drive/v3/files?q=${q}&fields=files(id)`, {
    headers: { Authorization: `Bearer ${token}` },
  }).then((r) => r.json());
  if (found.files?.length) return found.files[0].id;

  const created = await fetch("https://www.googleapis.com/drive/v3/files?fields=id", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ name, mimeType: "application/vnd.google-apps.folder" }),
  }).then((r) => r.json());
  if (!created.id) throw new Error("No se pudo crear la carpeta en Google Drive");
  return created.id;
}

async function googleUpload(name: string, data: Uint8Array, mime: string): Promise<UploadResult> {
  const token = await googleToken();
  const folder = await googleFolder(token);

  // Subida reanudable: soporta archivos grandes sin límite de 5 MB
  const init = await fetch("https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&fields=id,webViewLink", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json; charset=UTF-8",
      "X-Upload-Content-Type": mime,
      "X-Upload-Content-Length": String(data.byteLength),
    },
    body: JSON.stringify({ name, parents: [folder] }),
  });
  if (!init.ok) throw new Error(`Google Drive: ${await init.text()}`);
  const session = init.headers.get("Location")!;
  const put = await fetch(session, { method: "PUT", headers: { "Content-Type": mime }, body: new Uint8Array(data) });
  const json = await put.json();
  if (!put.ok) throw new Error(`Google Drive: ${json.error?.message ?? put.status}`);

  await googleRetention(token, folder);
  return { remoteId: json.id, webUrl: json.webViewLink };
}

async function googleRetention(token: string, folder: string) {
  const keep = Number(env("BACKUP_RETENTION_DAYS") || "30");
  const cutoff = new Date(Date.now() - keep * 86400_000).toISOString();
  const q = encodeURIComponent(`'${folder}' in parents and createdTime < '${cutoff}' and trashed=false and name contains 'agenda-wellness-'`);
  const old = await fetch(`https://www.googleapis.com/drive/v3/files?q=${q}&fields=files(id)`, {
    headers: { Authorization: `Bearer ${token}` },
  }).then((r) => r.json());
  for (const f of old.files ?? []) {
    await fetch(`https://www.googleapis.com/drive/v3/files/${f.id}`, {
      method: "DELETE",
      headers: { Authorization: `Bearer ${token}` },
    });
  }
}

// ---------------------------------------------------------------- OneDrive (Microsoft Graph)
async function msToken(secrets: SecretStore): Promise<string> {
  // Microsoft rota el refresh token: se guarda el último en la base (esquema privado)
  const refresh = (await secrets.get("onedrive_refresh_token")) ?? env("ONEDRIVE_REFRESH_TOKEN");
  const res = await fetch("https://login.microsoftonline.com/consumers/oauth2/v2.0/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: env("ONEDRIVE_CLIENT_ID"),
      client_secret: env("ONEDRIVE_CLIENT_SECRET"),
      refresh_token: refresh,
      grant_type: "refresh_token",
      scope: "Files.ReadWrite offline_access",
    }),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(`OneDrive OAuth: ${json.error_description ?? json.error}`);
  if (json.refresh_token) await secrets.set("onedrive_refresh_token", json.refresh_token);
  return json.access_token as string;
}

async function oneDriveUpload(name: string, data: Uint8Array, secrets: SecretStore): Promise<UploadResult> {
  const token = await msToken(secrets);
  const folder = encodeURIComponent(env("BACKUP_FOLDER_NAME") || "Agenda Wellness Backups");
  const session = await fetch(
    `https://graph.microsoft.com/v1.0/me/drive/root:/${folder}/${encodeURIComponent(name)}:/createUploadSession`,
    {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ item: { "@microsoft.graph.conflictBehavior": "rename" } }),
    },
  ).then((r) => r.json());
  if (!session.uploadUrl) throw new Error(`OneDrive: ${session.error?.message ?? "sin sesión de subida"}`);

  // Fragmentos múltiplos de 320 KiB (requisito de Graph)
  const chunk = 320 * 1024 * 16;
  let last: Record<string, unknown> = {};
  for (let start = 0; start < data.byteLength; start += chunk) {
    const end = Math.min(start + chunk, data.byteLength);
    const res = await fetch(session.uploadUrl, {
      method: "PUT",
      headers: {
        "Content-Length": String(end - start),
        "Content-Range": `bytes ${start}-${end - 1}/${data.byteLength}`,
      },
      body: data.slice(start, end),
    });
    if (!res.ok && res.status !== 202) throw new Error(`OneDrive: HTTP ${res.status}`);
    last = await res.json();
  }

  await oneDriveRetention(token, folder);
  return { remoteId: String(last.id ?? ""), webUrl: last.webUrl as string | undefined };
}

async function oneDriveRetention(token: string, folder: string) {
  const keep = Number(env("BACKUP_RETENTION_DAYS") || "30");
  const cutoff = Date.now() - keep * 86400_000;
  const list = await fetch(`https://graph.microsoft.com/v1.0/me/drive/root:/${folder}:/children?$select=id,name,createdDateTime`, {
    headers: { Authorization: `Bearer ${token}` },
  }).then((r) => r.json());
  for (const f of list.value ?? []) {
    if (String(f.name).startsWith("agenda-wellness-") && Date.parse(f.createdDateTime) < cutoff) {
      await fetch(`https://graph.microsoft.com/v1.0/me/drive/items/${f.id}`, {
        method: "DELETE",
        headers: { Authorization: `Bearer ${token}` },
      });
    }
  }
}

// ---------------------------------------------------------------- API
export type Provider = "google_drive" | "onedrive";

export const backupProvider = (): Provider =>
  (env("BACKUP_PROVIDER") || "google_drive") === "onedrive" ? "onedrive" : "google_drive";

export function uploadBackup(name: string, data: Uint8Array, mime: string, secrets: SecretStore): Promise<UploadResult> {
  return backupProvider() === "onedrive" ? oneDriveUpload(name, data, secrets) : googleUpload(name, data, mime);
}
