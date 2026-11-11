// =============================================================================
// Edge Function: telegram-webhook
// Recibe las actualizaciones del bot de Telegram.
//
//  * /start <código>  → vincula el chat con la ficha del cliente
//  * Botón ✅ c:<id>  → confirma el turno
//  * Botón 🔁 r:<id>  → registra pedido de reprogramación y avisa al staff
//  * Botón ❌ x:<id>  → pide confirmación;  xx:<id> cancela;  k:<id> mantiene
//
// Seguridad:
//  * Telegram envía el header X-Telegram-Bot-Api-Secret-Token configurado en setWebhook.
//  * Cada acción verifica que el chat que toca el botón sea el del cliente del turno.
// =============================================================================
import { createClient } from "jsr:@supabase/supabase-js@2";
import { answerCallback, editMessage, reminderButtons, sendTelegram } from "../_shared/telegram.ts";

const TZ = "America/Argentina/Buenos_Aires";
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

const fmt = (iso: string) =>
  new Intl.DateTimeFormat("es-AR", {
    timeZone: TZ, weekday: "long", day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit", hour12: false,
  }).format(new Date(iso));

type Update = {
  message?: { chat: { id: number; username?: string; first_name?: string }; text?: string };
  callback_query?: {
    id: string;
    data?: string;
    from: { id: number };
    message?: { message_id: number; chat: { id: number }; text?: string };
  };
};

async function notifyStaff(centerId: string, therapistId: string | null, kind: string, title: string, body: string, appointmentId: string) {
  await db.from("internal_notifications").insert([
    { center_id: centerId, user_id: null, kind, title, body, payload: { appointment_id: appointmentId } },
    ...(therapistId ? [{ center_id: centerId, user_id: therapistId, kind, title, body, payload: { appointment_id: appointmentId } }] : []),
  ]);
  const { data: center } = await db.from("centers").select("telegram_admin_chat_id").eq("id", centerId).single();
  if (center?.telegram_admin_chat_id) await sendTelegram(center.telegram_admin_chat_id, `${title}\n${body}`);
}

async function handleStart(chatId: number, username: string | undefined, code: string) {
  if (!code) {
    await sendTelegram(String(chatId),
      "🌿 Hola! Para recibir tus recordatorios, abrí el enlace que te envió el centro.");
    return;
  }
  const { data: client } = await db.from("clients")
    .select("id, first_name, center_id").eq("telegram_link_code", code).is("deleted_at", null).maybeSingle();
  if (!client) {
    await sendTelegram(String(chatId), "El enlace no es válido o ya fue usado. Pedile uno nuevo al centro.");
    return;
  }
  // Rotar el código impide que el mismo enlace vincule otro chat
  await db.from("clients").update({
    telegram_chat_id: String(chatId),
    telegram_username: username ?? null,
    telegram_linked_at: new Date().toISOString(),
    telegram_link_code: crypto.randomUUID().replaceAll("-", ""),
  }).eq("id", client.id);

  const { data: center } = await db.from("centers").select("name").eq("id", client.center_id).single();
  await sendTelegram(String(chatId),
    `¡Listo, ${client.first_name}! 🌿 Vas a recibir por acá los recordatorios de tus turnos en ${center?.name ?? "el centro"} ` +
    `y podrás confirmarlos con un toque.`);

  // Si tiene un turno próximo, mostrarlo con los botones
  const { data: next } = await db.from("appointments_view")
    .select("id, starts_at, service_name, status")
    .eq("client_id", client.id).in("status", ["pending", "confirmed"]).gt("starts_at", new Date().toISOString())
    .order("starts_at").limit(1).maybeSingle();
  if (next) {
    await sendTelegram(String(chatId),
      `Tu próximo turno: ${next.service_name}, ${fmt(next.starts_at)} hs.`,
      next.status === "pending" ? reminderButtons(next.id) : undefined);
  }
}

async function handleCallback(q: NonNullable<Update["callback_query"]>) {
  const [action, appointmentId] = (q.data ?? "").split(":");
  const chatId = q.message?.chat.id;
  const messageId = q.message?.message_id;
  if (!appointmentId || chatId === undefined || messageId === undefined) {
    await answerCallback(q.id);
    return;
  }

  const { data: a } = await db.from("appointments_view")
    .select("id, center_id, client_id, therapist_id, starts_at, status, service_name, client_name")
    .eq("id", appointmentId).maybeSingle();
  const { data: client } = a
    ? await db.from("clients").select("telegram_chat_id").eq("id", a.client_id).single()
    : { data: null };

  if (!a || client?.telegram_chat_id !== String(chatId)) {
    await answerCallback(q.id, "No encontramos ese turno.");
    return;
  }
  const when = fmt(a.starts_at);
  const header = `${a.service_name} · ${when} hs`;

  if (!["pending", "confirmed"].includes(a.status)) {
    await answerCallback(q.id, "Este turno ya no está activo.");
    await editMessage(chatId, messageId, `${header}\nEstado: ${a.status === "cancelled" ? "cancelado" : a.status}`);
    return;
  }

  switch (action) {
    case "c": {
      if (a.status === "pending") {
        const { error } = await db.rpc("set_appointment_status", { p_id: a.id, p_status: "confirmed" });
        if (error) {
          await answerCallback(q.id, "No pudimos confirmar. Escribinos por favor.");
          return;
        }
        await notifyStaff(a.center_id, a.therapist_id, "client_confirmation", "✅ Turno confirmado por Telegram",
          `${a.client_name} · ${header}`, a.id);
      }
      await answerCallback(q.id, "¡Gracias por confirmar!");
      await editMessage(chatId, messageId, `${header}\n✅ Confirmado. ¡Te esperamos!`);
      break;
    }
    case "r": {
      await notifyStaff(a.center_id, a.therapist_id, "reschedule_request", "🔁 Pedido de reprogramación",
        `${a.client_name} quiere cambiar su turno de ${header}`, a.id);
      await answerCallback(q.id, "Recibimos tu pedido");
      await editMessage(chatId, messageId,
        `${header}\n🔁 Recibimos tu pedido de cambio. Te vamos a escribir con nuevos horarios.`,
        [[{ text: "❌ Prefiero cancelar", callback_data: `x:${a.id}` }]]);
      break;
    }
    case "x": {
      await answerCallback(q.id);
      await editMessage(chatId, messageId, `${header}\n¿Seguro que querés cancelar el turno?`, [[
        { text: "Sí, cancelar", callback_data: `xx:${a.id}` },
        { text: "No, mantener", callback_data: `k:${a.id}` },
      ]]);
      break;
    }
    case "xx": {
      const { error } = await db.rpc("cancel_appointment", { p_id: a.id, p_reason: "Cancelado por el cliente vía Telegram" });
      if (error) {
        await answerCallback(q.id, "No pudimos cancelar. Escribinos por favor.");
        return;
      }
      await notifyStaff(a.center_id, a.therapist_id, "cancellation", "❌ Turno cancelado por Telegram",
        `${a.client_name} · ${header}`, a.id);
      await answerCallback(q.id, "Turno cancelado");
      await editMessage(chatId, messageId, `${header}\n❌ Cancelado. Cuando quieras, escribinos para un nuevo turno.`);
      break;
    }
    case "k": {
      await answerCallback(q.id, "Perfecto");
      await editMessage(chatId, messageId, `${header}\n¿Nos confirmás tu asistencia?`, reminderButtons(a.id));
      break;
    }
    default:
      await answerCallback(q.id);
  }
}

Deno.serve(async (req) => {
  if (req.headers.get("x-telegram-bot-api-secret-token") !== Deno.env.get("TELEGRAM_WEBHOOK_SECRET")) {
    return new Response("Unauthorized", { status: 401 });
  }
  try {
    const update: Update = await req.json();
    if (update.callback_query) {
      await handleCallback(update.callback_query);
    } else if (update.message?.text?.startsWith("/start")) {
      const code = update.message.text.split(" ")[1]?.trim() ?? "";
      await handleStart(update.message.chat.id, update.message.chat.username, code);
    } else if (update.message) {
      await sendTelegram(String(update.message.chat.id),
        "Este chat es solo para recordatorios 🌿. Para consultas, escribinos por WhatsApp.");
    }
  } catch (e) {
    console.error("telegram-webhook", e);
  }
  // Siempre 200: si no, Telegram reintenta la misma actualización
  return new Response("ok");
});
