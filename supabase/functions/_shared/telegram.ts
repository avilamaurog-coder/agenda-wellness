// =============================================================================
// Cliente mínimo de la Bot API de Telegram.
// Docs: https://core.telegram.org/bots/api
// =============================================================================
import type { SendResult } from "./providers.ts";

const token = () => Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "";

export type InlineButton = { text: string; callback_data?: string; url?: string };

async function call<T = unknown>(method: string, payload: Record<string, unknown>): Promise<{ ok: boolean; result?: T; description?: string }> {
  if (!token()) return { ok: false, description: "Telegram no configurado" };
  const res = await fetch(`https://api.telegram.org/bot${token()}/${method}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  return await res.json().catch(() => ({ ok: false, description: `HTTP ${res.status}` }));
}

export async function sendTelegram(chatId: string, text: string, buttons?: InlineButton[][]): Promise<SendResult> {
  const r = await call<{ message_id: number }>("sendMessage", {
    chat_id: chatId,
    text,
    disable_web_page_preview: true,
    ...(buttons ? { reply_markup: { inline_keyboard: buttons } } : {}),
  });
  return r.ok ? { ok: true, providerId: String(r.result?.message_id) } : { ok: false, error: r.description };
}

export async function sendTelegramPhoto(chatId: string, photoUrl: string, caption: string, buttons?: InlineButton[][]): Promise<SendResult> {
  const r = await call<{ message_id: number }>("sendPhoto", {
    chat_id: chatId,
    photo: photoUrl,
    caption: caption.slice(0, 1024),
    ...(buttons ? { reply_markup: { inline_keyboard: buttons } } : {}),
  });
  return r.ok ? { ok: true, providerId: String(r.result?.message_id) } : { ok: false, error: r.description };
}

export const answerCallback = (id: string, text?: string) =>
  call("answerCallbackQuery", { callback_query_id: id, text, show_alert: false });

export const editMessage = (chatId: string | number, messageId: number, text: string, buttons?: InlineButton[][]) =>
  call("editMessageText", {
    chat_id: chatId,
    message_id: messageId,
    text,
    reply_markup: { inline_keyboard: buttons ?? [] },
  });

/** Botones que acompañan cada recordatorio de turno. */
export const reminderButtons = (appointmentId: string): InlineButton[][] => [
  [{ text: "✅ Confirmo", callback_data: `c:${appointmentId}` }],
  [
    { text: "🔁 Reprogramar", callback_data: `r:${appointmentId}` },
    { text: "❌ Cancelar", callback_data: `x:${appointmentId}` },
  ],
];
