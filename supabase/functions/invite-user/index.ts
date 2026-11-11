// =============================================================================
// Edge Function: invite-user
// Un administrador invita a un miembro del staff por email con un rol dado.
// El rol y el centro viajan en app_metadata (no editable por el usuario),
// y el trigger handle_new_user crea el perfil ya activo.
//
// POST /functions/v1/invite-user
// Authorization: Bearer <JWT del admin>
// { "email": "ana@spa.com", "full_name": "Ana Pérez", "role": "therapist" }
// =============================================================================
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const url = Deno.env.get("SUPABASE_URL")!;
  const authHeader = req.headers.get("Authorization") ?? "";

  // Cliente con el JWT del llamador → respeta RLS para validar que sea admin
  const asCaller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: me } = await asCaller.rpc("current_profile");
  if (!me || me.role !== "admin") {
    return Response.json({ error: "Solo administradores" }, { status: 403, headers: cors });
  }

  const { email, full_name, role } = await req.json();
  if (!email || !["admin", "receptionist", "therapist"].includes(role)) {
    return Response.json({ error: "Datos inválidos" }, { status: 400, headers: cors });
  }

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data, error } = await admin.auth.admin.inviteUserByEmail(email, {
    data: { full_name },
    redirectTo: Deno.env.get("INVITE_REDIRECT_URL") ?? "agendawellness://auth-callback",
  });
  if (error) return Response.json({ error: error.message }, { status: 400, headers: cors });

  // app_metadata se fija tras crear el usuario; el trigger lee raw_app_meta_data
  // en el INSERT, por eso además se actualiza el perfil directamente.
  await admin.auth.admin.updateUserById(data.user.id, {
    app_metadata: { center_id: me.center_id, role },
  });
  await admin.from("profiles")
    .update({ center_id: me.center_id, role, is_active: true, full_name: full_name ?? email })
    .eq("id", data.user.id);

  return Response.json({ user_id: data.user.id }, { headers: cors });
});
