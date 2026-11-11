// =============================================================================
// Edge Function: send-reminders
// Invocada por pg_cron cada 5 minutos. Toma los recordatorios vencidos,
// renderiza la plantilla y los despacha por WhatsApp / Email / Push.
//
// Seguridad: requiere header x-cron-secret == CRON_SECRET.
// Concurrencia: cada lote se "reclama" con un UPDATE condicionado al estado,
// de modo que dos ejecuciones simultáneas no envían duplicados.
// =============================================================================
import { createClient } from "jsr:@supabase/supabase-js@2";
import { sendEmail, sendPush, sendWhatsApp, type SendResult } from "../_shared/providers.ts";
import { reminderButtons, sendTelegram } from "../_shared/telegram.ts";

const BATCH = 100;
const MAX_ATTEMPTS = 3;
const TZ = "America/Argentina/Buenos_Aires";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

type Reminder = {
  id: string;
  appointment_id: string;
  channel: "whatsapp" | "email" | "push" | "telegram";
  hours_before: number;
  attempts: number;
};

function render(template: string, vars: Record<string, string>) {
  return template.replace(/\{\{\s*(\w+)\s*\}\}/g, (_, k) => vars[k] ?? "");
}

const fmtDate = (d: Date) =>
  new Intl.DateTimeFormat("es-AR", { timeZone: TZ, day: "2-digit", month: "2-digit" }).format(d);
const fmtTime = (d: Date) =>
  new Intl.DateTimeFormat("es-AR", { timeZone: TZ, hour: "2-digit", minute: "2-digit", hour12: false }).format(d);

Deno.serve(async (req) => {
  if (req.headers.get("x-cron-secret") !== Deno.env.get("CRON_SECRET")) {
    return new Response("Unauthorized", { status: 401 });
  }

  // 1. Reclamar lote vencido (marca attempts+1 de forma atómica vía RPC-less update)
  const { data: due, error } = await supabase
    .from("appointment_reminders")
    .select("id, appointment_id, channel, hours_before, attempts")
    .eq("status", "scheduled")
    .lte("scheduled_for", new Date().toISOString())
    .lt("attempts", MAX_ATTEMPTS)
    .order("scheduled_for")
    .limit(BATCH);

  if (error) return Response.json({ error: error.message }, { status: 500 });
  if (!due?.length) return Response.json({ processed: 0 });

  let sent = 0, failed = 0, skipped = 0;

  for (const r of due as Reminder[]) {
    // Claim optimista: solo continúa si nadie más incrementó attempts
    const { data: claimed } = await supabase
      .from("appointment_reminders")
      .update({ attempts: r.attempts + 1 })
      .eq("id", r.id).eq("attempts", r.attempts).eq("status", "scheduled")
      .select("id").maybeSingle();
    if (!claimed) continue;

    const { data: a } = await supabase
      .from("appointments_view")
      .select("id, center_id, starts_at, status, client_id, therapist_id, therapist_name, service_name")
      .eq("id", r.appointment_id).single();

    if (!a || !["pending", "confirmed"].includes(a.status)) {
      await supabase.from("appointment_reminders").update({ status: "skipped" }).eq("id", r.id);
      skipped++;
      continue;
    }

    const [{ data: client }, { data: center }, { data: tpl }] = await Promise.all([
      supabase.from("clients").select("first_name, last_name, phone, whatsapp, email, accepts_reminders, telegram_chat_id").eq("id", a.client_id).single(),
      supabase.from("centers").select("name, logo_url").eq("id", a.center_id).single(),
      supabase.from("message_templates").select("subject, body")
        .eq("center_id", a.center_id).eq("channel", r.channel).eq("hours_before", r.hours_before).eq("is_active", true)
        .maybeSingle(),
    ]);

    if (!client?.accepts_reminders || !tpl) {
      await supabase.from("appointment_reminders").update({ status: "skipped", error: "Sin plantilla o cliente sin consentimiento" }).eq("id", r.id);
      skipped++;
      continue;
    }

    const start = new Date(a.starts_at);
    const vars = {
      nombre: client.first_name,
      apellido: client.last_name,
      servicio: a.service_name ?? "",
      fecha: fmtDate(start),
      hora: fmtTime(start),
      profesional: a.therapist_name ?? "",
      centro: center?.name ?? "",
    };
    const body = render(tpl.body, vars);
    const subject = render(tpl.subject ?? "Recordatorio de turno", vars);

    let result: SendResult;
    try {
      switch (r.channel) {
        case "whatsapp":
          result = await sendWhatsApp(client.whatsapp ?? client.phone ?? "", body);
          break;
        case "email":
          result = await sendEmail(client.email ?? "", subject, body, center?.logo_url ?? undefined);
          break;
        case "telegram":
          // Los botones permiten confirmar, pedir reprogramación o cancelar desde el chat
          result = client.telegram_chat_id
            ? await sendTelegram(client.telegram_chat_id, body, r.hours_before >= 24 ? reminderButtons(a.id) : undefined)
            : { ok: false, error: "Cliente sin Telegram vinculado" };
          break;
        case "push": {
          // El push va al profesional asignado (el cliente no usa la app)
          const { data: prof } = await supabase.from("profiles").select("fcm_tokens").eq("id", a.therapist_id).single();
          result = await sendPush(prof?.fcm_tokens ?? [], subject, body, { appointment_id: a.id, route: `/agenda/turno/${a.id}` });
          break;
        }
      }
    } catch (e) {
      result = { ok: false, error: String(e) };
    }

    if (result.ok) {
      await supabase.from("appointment_reminders")
        .update({ status: "sent", sent_at: new Date().toISOString(), provider_id: result.providerId ?? null, error: null })
        .eq("id", r.id);
      sent++;
    } else {
      const final = r.attempts + 1 >= MAX_ATTEMPTS;
      await supabase.from("appointment_reminders")
        .update({ status: final ? "failed" : "scheduled", error: result.error ?? "Error desconocido" })
        .eq("id", r.id);
      failed++;
    }
  }

  return Response.json({ processed: due.length, sent, failed, skipped });
});
