// =============================================================================
// Edge Function: backup
// Exporta todas las tablas de negocio a JSON, las comprime en un .zip,
// opcionalmente las cifra (AES-256-GCM) y sube el archivo a Google Drive u OneDrive.
//
// Disparadores:
//   * pg_cron diario  → header x-cron-secret
//   * Botón "Hacer backup ahora" en la app → JWT de administrador
//
// Variables: BACKUP_PROVIDER (google_drive|onedrive), BACKUP_ENCRYPTION_KEY (recomendado),
//            BACKUP_RETENTION_DAYS, BACKUP_INCLUDE_PHOTOS, credenciales del proveedor.
// Restauración: supabase/scripts/restore-backup.ts
// =============================================================================
import { createClient } from "jsr:@supabase/supabase-js@2";
import { strToU8, zipSync } from "npm:fflate@0.8.2";
import { backupProvider, uploadBackup } from "../_shared/cloud_storage.ts";

const env = (k: string) => Deno.env.get(k) ?? "";
const db = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), { auth: { persistSession: false } });

// Orden compatible con las claves foráneas (el script de restauración lo respeta)
export const TABLES = [
  "centers", "profiles", "therapist_schedules", "schedule_blocks", "clients",
  "service_categories", "services", "service_therapists", "service_price_history",
  "combos", "combo_items", "promotions", "products", "promo_posts",
  "appointments", "appointment_events", "payments",
  "clinical_records", "clinical_photos", "message_templates",
  "appointment_reminders", "internal_notifications", "backups",
];

async function exportTable(table: string): Promise<unknown[]> {
  const rows: unknown[] = [];
  const page = 1000;
  for (let from = 0; ; from += page) {
    const { data, error } = await db.from(table).select("*").range(from, from + page - 1);
    if (error) throw new Error(`${table}: ${error.message}`);
    rows.push(...(data ?? []));
    if (!data || data.length < page) break;
  }
  return rows;
}

async function encrypt(data: Uint8Array, passphrase: string): Promise<Uint8Array> {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const base = await crypto.subtle.importKey("raw", new TextEncoder().encode(passphrase), "PBKDF2", false, ["deriveKey"]);
  const key = await crypto.subtle.deriveKey(
    { name: "PBKDF2", salt, iterations: 210_000, hash: "SHA-256" },
    base,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt"],
  );
  const cipher = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, new Uint8Array(data)));
  // Formato: "AWB1" | salt(16) | iv(12) | ciphertext+tag
  const out = new Uint8Array(4 + 16 + 12 + cipher.byteLength);
  out.set(new TextEncoder().encode("AWB1"), 0);
  out.set(salt, 4);
  out.set(iv, 20);
  out.set(cipher, 32);
  return out;
}

Deno.serve(async (req) => {
  // ---- Autorización: cron o administrador
  let trigger: "scheduled" | "manual" = "scheduled";
  let requestedBy: string | null = null;
  let centerId: string | null = null;

  if (req.headers.get("x-cron-secret") !== env("CRON_SECRET")) {
    const asCaller = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });
    const { data: me } = await asCaller.rpc("current_profile");
    if (!me || me.role !== "admin") return Response.json({ error: "Solo administradores" }, { status: 403 });
    trigger = "manual";
    requestedBy = me.id;
    centerId = me.center_id;
  }

  if (trigger === "scheduled") {
    const { data: c } = await db.from("centers").select("id, backup_enabled").order("created_at").limit(1).single();
    if (c && !c.backup_enabled) return Response.json({ skipped: "backup desactivado" });
    centerId = c?.id ?? null;
  }

  const provider = backupProvider();
  const { data: log } = await db.from("backups").insert({
    center_id: centerId, provider, trigger, requested_by: requestedBy, status: "running",
  }).select("id").single();

  try {
    const files: Record<string, Uint8Array> = {};
    const counts: Record<string, number> = {};

    for (const t of TABLES) {
      const rows = await exportTable(t);
      counts[t] = rows.length;
      files[`data/${t}.json`] = strToU8(JSON.stringify(rows));
    }

    // Usuarios de Auth (referencia para recrear accesos; las contraseñas no se exportan)
    const { data: users } = await db.auth.admin.listUsers({ perPage: 1000 });
    files["auth/users.json"] = strToU8(JSON.stringify(
      (users?.users ?? []).map((u: { id: string; email?: string; created_at: string; user_metadata: unknown; app_metadata: unknown }) => ({ id: u.id, email: u.email, created_at: u.created_at, user_metadata: u.user_metadata, app_metadata: u.app_metadata })),
    ));

    // Manifiesto de archivos de Storage (y opcionalmente las fotos clínicas)
    const includePhotos = env("BACKUP_INCLUDE_PHOTOS") === "true";
    const { data: photos } = await db.from("clinical_photos").select("storage_path");
    files["storage/manifest.json"] = strToU8(JSON.stringify({ clinical_photos: photos?.map((p: { storage_path: string }) => p.storage_path) ?? [] }));
    if (includePhotos) {
      for (const p of photos ?? []) {
        const { data: blob } = await db.storage.from("clinical-photos").download(p.storage_path);
        if (blob) files[`storage/clinical-photos/${p.storage_path}`] = new Uint8Array(await blob.arrayBuffer());
      }
    }

    files["manifest.json"] = strToU8(JSON.stringify({
      app: "agenda-wellness", format: 1, created_at: new Date().toISOString(), tables: counts, photos_included: includePhotos,
    }, null, 2));

    let payload = zipSync(files, { level: 6 });
    const stamp = new Date().toISOString().slice(0, 16).replace(/[:T]/g, "-");
    let name = `agenda-wellness-${stamp}.zip`;
    let mime = "application/zip";
    const key = env("BACKUP_ENCRYPTION_KEY");
    if (key) {
      payload = await encrypt(payload, key);
      name += ".enc";
      mime = "application/octet-stream";
    }

    const uploaded = await uploadBackup(name, payload, mime, {
      get: async (n) => (await db.rpc("get_integration_secret", { p_name: n })).data as string | null,
      set: async (n, v) => { await db.rpc("set_integration_secret", { p_name: n, p_value: v }); },
    });

    await db.from("backups").update({
      status: "success", file_name: name, remote_id: uploaded.remoteId, size_bytes: payload.byteLength,
      row_counts: counts, encrypted: Boolean(key), finished_at: new Date().toISOString(),
    }).eq("id", log!.id);

    return Response.json({ ok: true, file: name, size: payload.byteLength, provider, url: uploaded.webUrl });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    await db.from("backups").update({ status: "failed", error: message, finished_at: new Date().toISOString() }).eq("id", log!.id);
    if (centerId) {
      // Aviso solo a los administradores
      const { data: admins } = await db.from("profiles").select("id")
        .eq("center_id", centerId).eq("role", "admin").eq("is_active", true);
      await db.from("internal_notifications").insert(
        (admins ?? []).map((a: { id: string }) => ({
          center_id: centerId, user_id: a.id, kind: "backup", title: "⚠️ Falló el backup en la nube", body: message,
        })),
      );
    }
    return Response.json({ error: message }, { status: 500 });
  }
});
