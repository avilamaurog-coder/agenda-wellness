// =============================================================================
// Edge Function: telegram-broadcast
// Publica una promoción de la vitrina en el canal de Telegram del centro.
//
// POST /functions/v1/telegram-broadcast
// Authorization: Bearer <JWT de administrador>
// { "post_id": "<uuid>" }
//
// Requisito: el bot debe ser administrador del canal (centers.telegram_channel_id).
// =============================================================================
import { createClient } from "jsr:@supabase/supabase-js@2";
import { type InlineButton, sendTelegram, sendTelegramPhoto } from "../_shared/telegram.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) => Response.json(body, { status, headers: cors });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const url = Deno.env.get("SUPABASE_URL")!;
  const asCaller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
  });
  const { data: me } = await asCaller.rpc("current_profile");
  if (!me || me.role !== "admin") return json({ error: "Solo administradores" }, 403);

  const { post_id } = await req.json().catch(() => ({}));
  if (!post_id) return json({ error: "Falta post_id" }, 400);

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: post } = await admin.from("promo_posts")
    .select("id, center_id, title, body, image_url, cta_label, ends_on, service:services(name, price), product:products(name, price), combo:combos(name, price)")
    .eq("id", post_id).eq("center_id", me.center_id).maybeSingle();
  if (!post) return json({ error: "Publicación no encontrada" }, 404);

  const { data: center } = await admin.from("centers")
    .select("name, telegram_channel_id, whatsapp_contact").eq("id", me.center_id).single();
  if (!center?.telegram_channel_id) {
    return json({ error: "Configurá el canal de Telegram en Datos del centro" }, 400);
  }

  // deno-lint-ignore no-explicit-any
  const linked: any = post.service ?? post.combo ?? post.product;
  const price = linked?.price
    ? `\n💲 ${new Intl.NumberFormat("es-AR", { style: "currency", currency: "ARS", maximumFractionDigits: 0 }).format(linked.price)}`
    : "";
  const until = post.ends_on ? `\n⏳ Válido hasta el ${post.ends_on.split("-").reverse().join("/")}` : "";
  const text = `✨ ${post.title}\n\n${post.body ?? ""}${price}${until}\n\n${center.name}`;

  const buttons: InlineButton[][] = [];
  if (center.whatsapp_contact) {
    const phone = center.whatsapp_contact.replace(/\D/g, "");
    const msg = encodeURIComponent(`Hola! Vi la promo "${post.title}" y quiero reservar.`);
    buttons.push([{ text: post.cta_label || "Reservar", url: `https://wa.me/${phone}?text=${msg}` }]);
  }
  const catalogUrl = Deno.env.get("PUBLIC_CATALOG_URL");
  if (catalogUrl) buttons.push([{ text: "Ver todos los servicios", url: catalogUrl }]);

  const result = post.image_url
    ? await sendTelegramPhoto(center.telegram_channel_id, post.image_url, text, buttons.length ? buttons : undefined)
    : await sendTelegram(center.telegram_channel_id, text, buttons.length ? buttons : undefined);

  if (!result.ok) return json({ error: `Telegram: ${result.error}` }, 502);

  await admin.from("promo_posts").update({ published_telegram_at: new Date().toISOString() }).eq("id", post.id);
  return json({ ok: true, message_id: result.providerId });
});
