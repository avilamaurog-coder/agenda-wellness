// =============================================================================
// Proveedores de mensajería: WhatsApp Cloud API (Meta), Resend (email), FCM v1.
// Cada sender devuelve { ok, providerId?, error? } y nunca lanza.
// =============================================================================

export type SendResult = { ok: boolean; providerId?: string; error?: string };

const env = (k: string) => Deno.env.get(k) ?? "";

/** Normaliza un teléfono argentino a E.164 sin '+' (formato que exige WhatsApp). */
export function normalizeArPhone(raw: string): string {
  let d = raw.replace(/\D/g, "");
  if (d.startsWith("00")) d = d.slice(2);
  if (d.startsWith("0")) d = d.slice(1);
  if (!d.startsWith("54")) d = "54" + d;
  // Celulares AR: 54 9 <área> <número> (quitar el "15" local si vino)
  if (!d.startsWith("549")) d = "549" + d.slice(2);
  d = d.replace(/^549(\d{2,4})15(\d{6,8})$/, "549$1$2");
  return d;
}

// ---------------------------------------------------------------- WhatsApp
// Fuera de la ventana de 24 h Meta exige plantillas aprobadas. Se usa una
// plantilla "recordatorio_turno" con un único parámetro {{1}} = texto renderizado.
export async function sendWhatsApp(to: string, text: string): Promise<SendResult> {
  const token = env("WHATSAPP_TOKEN");
  const phoneId = env("WHATSAPP_PHONE_NUMBER_ID");
  const template = env("WHATSAPP_TEMPLATE_NAME") || "recordatorio_turno";
  if (!token || !phoneId) return { ok: false, error: "WhatsApp no configurado" };

  const res = await fetch(`https://graph.facebook.com/v21.0/${phoneId}/messages`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      messaging_product: "whatsapp",
      to: normalizeArPhone(to),
      type: "template",
      template: {
        name: template,
        language: { code: "es_AR" },
        components: [{ type: "body", parameters: [{ type: "text", text }] }],
      },
    }),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) return { ok: false, error: json?.error?.message ?? `HTTP ${res.status}` };
  return { ok: true, providerId: json?.messages?.[0]?.id };
}

// ---------------------------------------------------------------- Email (Resend)
export async function sendEmail(to: string, subject: string, text: string, logoUrl?: string): Promise<SendResult> {
  const key = env("RESEND_API_KEY");
  const from = env("EMAIL_FROM") || "Agenda Wellness <turnos@agendawellness.com>";
  if (!key) return { ok: false, error: "Email no configurado" };

  const logo = logoUrl
    ? `<img src="${escapeHtml(logoUrl)}" alt="" style="max-height:64px;max-width:200px;margin-bottom:16px">`
    : "";
  const html = `<div style="font-family:Arial,sans-serif;max-width:520px;margin:auto;padding:24px;color:#2E3B36">
    ${logo}<h2 style="color:#5E7D6F;margin-top:0">🌿 ${escapeHtml(subject)}</h2>
    <p style="line-height:1.6">${escapeHtml(text).replace(/\n/g, "<br>")}</p></div>`;

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from, to, subject, text, html }),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) return { ok: false, error: json?.message ?? `HTTP ${res.status}` };
  return { ok: true, providerId: json?.id };
}

function escapeHtml(s: string) {
  return s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
}

// ---------------------------------------------------------------- FCM HTTP v1
let cachedToken: { value: string; exp: number } | null = null;

async function googleAccessToken(): Promise<string> {
  if (cachedToken && cachedToken.exp > Date.now() / 1000 + 60) return cachedToken.value;
  const sa = JSON.parse(env("FCM_SERVICE_ACCOUNT_JSON"));
  const now = Math.floor(Date.now() / 1000);
  const b64url = (o: unknown) =>
    btoa(typeof o === "string" ? o : JSON.stringify(o)).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");

  const header = b64url({ alg: "RS256", typ: "JWT" });
  const claims = b64url({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  });
  const pem = (sa.private_key as string).replace(/-----[^-]+-----/g, "").replace(/\s/g, "");
  const key = await crypto.subtle.importKey(
    "pkcs8",
    Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`)),
  );
  const jwt = `${header}.${claims}.${b64url(String.fromCharCode(...sig))}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt }),
  });
  const json = await res.json();
  cachedToken = { value: json.access_token, exp: now + (json.expires_in ?? 3600) };
  return cachedToken.value;
}

export async function sendPush(
  tokens: string[],
  title: string,
  body: string,
  data: Record<string, string> = {},
): Promise<SendResult> {
  if (!env("FCM_SERVICE_ACCOUNT_JSON")) return { ok: false, error: "FCM no configurado" };
  if (tokens.length === 0) return { ok: false, error: "Sin dispositivos registrados" };
  const projectId = JSON.parse(env("FCM_SERVICE_ACCOUNT_JSON")).project_id;
  const access = await googleAccessToken();

  const results = await Promise.all(tokens.map(async (token) => {
    const res = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${access}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data,
          android: { priority: "high", notification: { channel_id: "turnos" } },
          apns: { payload: { aps: { sound: "default" } } },
        },
      }),
    });
    const json = await res.json().catch(() => ({}));
    return res.ok ? { ok: true, providerId: json.name } : { ok: false, error: json?.error?.message };
  }));

  const firstOk = results.find((r) => r.ok);
  return firstOk ?? { ok: false, error: results.map((r) => r.error).join("; ") };
}
