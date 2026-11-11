// =============================================================================
// Capa de datos del panel.
//   * createSupabaseApi(): usa el mismo backend que la app móvil (RLS, RPC, Edge Functions).
//   * createDemoApi(): datos de ejemplo en memoria para probar el panel sin backend.
// Ambas exponen la misma interfaz, así la interfaz de usuario no sabe cuál está usando.
// =============================================================================

const SUPABASE_ESM = "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/+esm";

/** Traduce errores de Postgres/Auth a mensajes para el usuario. */
export function friendlyError(e) {
  const code = e?.code ?? "";
  const msg = e?.message ?? String(e);
  if (code === "23P01" || code === "P0409") return "El profesional ya tiene un turno en ese horario.";
  if (code === "23505") return msg.includes("dni") ? "Ya existe un cliente con ese DNI." : "El registro ya existe.";
  if (code === "42501") return "No tenés permisos para esta acción.";
  if (/invalid login/i.test(msg)) return "Email o contraseña incorrectos.";
  if (/email not confirmed/i.test(msg)) return "Confirmá tu email antes de ingresar.";
  if (/failed to fetch|network/i.test(msg)) return "Sin conexión con el servidor.";
  return msg;
}

const check = ({ data, error }) => {
  if (error) throw error;
  return data;
};

// ----------------------------------------------------------------------------- Supabase
export async function createSupabaseApi({ supabaseUrl, supabaseAnonKey }) {
  const { createClient } = await import(SUPABASE_ESM);
  const db = createClient(supabaseUrl, supabaseAnonKey, {
    auth: { persistSession: true, autoRefreshToken: true, flowType: "pkce" },
  });

  return {
    demo: false,

    // ---- Autenticación
    async session() {
      return (await db.auth.getSession()).data.session;
    },
    async signIn(email, password) {
      check(await db.auth.signInWithPassword({ email, password }));
    },
    async signOut() {
      await db.auth.signOut();
    },
    async resetPassword(email) {
      check(await db.auth.resetPasswordForEmail(email, { redirectTo: location.href.split("#")[0] }));
    },
    async updatePassword(password) {
      check(await db.auth.updateUser({ password }));
    },
    onAuth(cb) {
      db.auth.onAuthStateChange((event, session) => cb(event, session));
    },
    async me() {
      const uid = (await db.auth.getUser()).data.user?.id;
      if (!uid) return null;
      return check(await db.from("profiles").select("*").eq("id", uid).maybeSingle());
    },
    async center() {
      return check(await db.from("centers").select("*").limit(1).maybeSingle());
    },
    async publicBranding() {
      const { data } = await db.rpc("public_branding");
      return data ?? null;
    },

    // ---- Usuarios
    async staff() {
      return check(await db.from("profiles").select("*").order("full_name"));
    },
    async updateUser(id, role, active) {
      check(await db.rpc("admin_update_user", { p_user_id: id, p_role: role, p_active: active }));
    },
    async updateUserColor(id, color) {
      check(await db.from("profiles").update({ color_hex: color }).eq("id", id));
    },
    async inviteUser(payload) {
      const { data, error } = await db.functions.invoke("invite-user", { body: payload });
      if (error) {
        const detail = await error.context?.json?.().catch(() => null);
        throw new Error(detail?.error ?? error.message);
      }
      return data;
    },
    async schedules() {
      return check(await db.from("therapist_schedules").select("*"));
    },
    async saveSchedule(therapistId, rows) {
      check(await db.from("therapist_schedules").delete().eq("therapist_id", therapistId));
      if (rows.length) {
        check(await db.from("therapist_schedules").insert(rows.map((r) => ({ ...r, therapist_id: therapistId }))));
      }
    },

    // ---- Catálogo y clientes
    async services() {
      return check(await db.from("services").select("*").eq("is_active", true).is("deleted_at", null).order("name"));
    },
    async clients(query = "", limit = 100) {
      let q = db.from("clients").select("*").is("deleted_at", null);
      const term = query.trim().replace(/[,()*%]/g, " ").trim();
      for (const p of term.split(/\s+/).filter(Boolean)) {
        q = q.or(`first_name.ilike.%${p}%,last_name.ilike.%${p}%,dni.ilike.%${p}%,phone.ilike.%${p}%,email.ilike.%${p}%`);
      }
      return check(await q.order("last_name").order("first_name").limit(limit));
    },
    async saveClient(c) {
      const { id, ...row } = c;
      return id
        ? check(await db.from("clients").update(row).eq("id", id).select().single())
        : check(await db.from("clients").insert(row).select().single());
    },

    // ---- Agenda
    async appointments(from, to) {
      return check(
        await db.from("appointments_view").select("*")
          .gte("starts_at", from.toISOString()).lt("starts_at", to.toISOString()).order("starts_at"),
      );
    },
    async appointment(id) {
      return check(await db.from("appointments_view").select("*").eq("id", id).single());
    },
    async createAppointment(a) {
      const row = check(await db.from("appointments").insert({
        client_id: a.client_id, therapist_id: a.therapist_id, service_id: a.service_id,
        starts_at: a.starts_at, price: a.price ?? 0, discount_amount: a.discount_amount ?? 0, notes: a.notes || null,
      }).select("id").single());
      if (a.confirmed) check(await db.rpc("set_appointment_status", { p_id: row.id, p_status: "confirmed" }));
      return row.id;
    },
    async reschedule(id, start, therapistId, reason) {
      check(await db.rpc("reschedule_appointment", {
        p_id: id, p_new_start: start.toISOString(), p_new_therapist: therapistId ?? null, p_reason: reason ?? null,
      }));
    },
    async cancel(id, reason) {
      check(await db.rpc("cancel_appointment", { p_id: id, p_reason: reason }));
    },
    async setStatus(id, status) {
      check(await db.rpc("set_appointment_status", { p_id: id, p_status: status }));
    },
    async slots(date, serviceId, therapistId) {
      return check(await db.rpc("available_slots", {
        p_date: date, p_service_id: serviceId, p_therapist_id: therapistId || null,
      })) ?? [];
    },
    async addPayment(p) {
      check(await db.from("payments").insert(p));
    },
    async dashboard(from, to) {
      return check(await db.rpc("dashboard_summary", { p_from: from, p_to: to }));
    },
    subscribe(cb) {
      db.channel("panel-agenda")
        .on("postgres_changes", { event: "*", schema: "public", table: "appointments" }, () => cb("appointments"))
        .on("postgres_changes", { event: "*", schema: "public", table: "profiles" }, () => cb("profiles"))
        .subscribe();
    },
  };
}

// ----------------------------------------------------------------------------- Demo
export function createDemoApi() {
  const uid = () => crypto.randomUUID();
  const day = (offset, h, m = 0) => {
    const d = new Date();
    d.setDate(d.getDate() + offset);
    d.setHours(h, m, 0, 0);
    return d;
  };

  const services = [
    ["Masaje Descontracturante", 60, 28000, "#8FA998"], ["Masaje Relajante", 60, 25000, "#A8C3B8"],
    ["Drenaje Linfático", 60, 30000, "#9DB4C0"], ["Masaje Deportivo", 50, 28000, "#7E9C8C"],
    ["Masaje de Cuerpo Completo", 90, 38000, "#6F8F7F"], ["Tratamiento Facial", 60, 30000, "#D4A5A5"],
    ["Yoga Facial", 45, 20000, "#E3B5A4"], ["Limpieza de Cutis", 60, 26000, "#E8C7B7"],
    ["Electrodos", 30, 15000, "#B5A8C9"], ["Reflexología", 45, 22000, "#A3A3C2"],
  ].map(([name, duration_minutes, price, color_hex]) => ({ id: uid(), name, duration_minutes, price, color_hex, buffer_minutes: 10, is_active: true }));

  const me = { id: uid(), full_name: "Carla Benítez", email: "carla@agendawellness.com", role: "admin", is_active: true, color_hex: "#5E7D6F" };
  const staff = [
    me,
    { id: uid(), full_name: "Laura Gómez", email: "laura@agendawellness.com", role: "therapist", is_active: true, color_hex: "#7C9A92" },
    { id: uid(), full_name: "Sofía Ramírez", email: "sofia@agendawellness.com", role: "therapist", is_active: true, color_hex: "#C98B6B" },
    { id: uid(), full_name: "Martina López", email: "martina@agendawellness.com", role: "receptionist", is_active: true, color_hex: "#9DB4C0" },
    { id: uid(), full_name: "Julieta Sosa", email: "julieta.sosa@gmail.com", role: "therapist", is_active: false, color_hex: "#B5A8C9" },
  ];
  const schedules = [];
  for (const t of staff.filter((s) => s.role === "therapist" && s.is_active)) {
    for (const wd of [1, 2, 3, 4, 5]) schedules.push({ id: uid(), therapist_id: t.id, weekday: wd, start_time: "09:00", end_time: "19:00" });
    schedules.push({ id: uid(), therapist_id: t.id, weekday: 6, start_time: "09:00", end_time: "13:00" });
  }

  const clients = [
    ["Ana", "Pérez", "30123456", "3764 123456", "ana.perez@mail.com", "Aceite de almendras"],
    ["Juan", "Gómez", "28999111", "3764 555010", "juan.gomez@mail.com", null],
    ["Lucía", "Fernández", "35111222", "3764 401122", null, null],
    ["Marcos", "Ruiz", "31222333", "3764 220033", "marcos.ruiz@mail.com", null],
    ["Valentina", "Díaz", "38333444", "3764 330044", "valen.diaz@mail.com", null],
    ["Carolina", "Acosta", "29444555", "3764 440055", null, "Látex"],
    ["Diego", "Benítez", "33555666", "3764 550066", "diego.b@mail.com", null],
    ["Florencia", "Romero", "36666777", "3764 660077", "flor.romero@mail.com", null],
    ["Pablo", "Medina", "27777888", "3764 770088", null, null],
    ["Sabrina", "Herrera", "39888999", "3764 880099", "sabri.h@mail.com", null],
  ].map(([first_name, last_name, dni, phone, email, allergies]) => ({
    id: uid(), first_name, last_name, dni, phone, whatsapp: phone, email, allergies,
    contraindications: null, observations: null, accepts_reminders: true, birth_date: null,
  }));

  const [, laura, sofia] = staff;
  const appts = [];
  const add = (client, therapist, service, start, status = "pending", paid = 0) => {
    const a = {
      id: uid(), client_id: client.id, therapist_id: therapist.id, service_id: service.id, starts_at: start.toISOString(),
      ends_at: new Date(start.getTime() + service.duration_minutes * 60000).toISOString(), status,
      price: service.price, discount_amount: 0, final_price: service.price, paid_amount: paid, notes: null,
      cancellation_reason: null, reschedule_count: 0,
    };
    appts.push(a);
    return a;
  };
  const S = (n) => services.find((s) => s.name.startsWith(n));
  add(clients[0], laura, S("Masaje Relajante"), day(0, 9), "completed", 25000);
  add(clients[1], laura, S("Masaje Descontracturante"), day(0, 10, 30), "confirmed");
  add(clients[2], laura, S("Drenaje"), day(0, 14), "pending");
  add(clients[3], laura, S("Masaje Deportivo"), day(0, 16, 30), "pending");
  add(clients[4], sofia, S("Tratamiento Facial"), day(0, 9, 30), "completed", 30000);
  add(clients[5], sofia, S("Yoga Facial"), day(0, 11), "confirmed");
  add(clients[6], sofia, S("Limpieza"), day(0, 15), "pending");
  add(clients[7], sofia, S("Reflexología"), day(0, 17, 30), "confirmed");
  add(clients[8], laura, S("Masaje de Cuerpo"), day(1, 10), "pending");
  add(clients[9], sofia, S("Electrodos"), day(1, 12), "pending");
  add(clients[2], laura, S("Masaje Relajante"), day(2, 18), "confirmed");
  add(clients[0], sofia, S("Tratamiento Facial"), day(3, 11), "pending");
  const canc = add(clients[5], laura, S("Drenaje"), day(1, 15), "cancelled");
  canc.cancellation_reason = "Enfermedad";

  const view = (a) => {
    const c = clients.find((x) => x.id === a.client_id);
    const t = staff.find((x) => x.id === a.therapist_id);
    const s = services.find((x) => x.id === a.service_id);
    return {
      ...a, client_name: `${c.first_name} ${c.last_name}`, client_phone: c.whatsapp ?? c.phone,
      therapist_name: t.full_name, therapist_color: t.color_hex, service_name: s?.name ?? "", service_color: s?.color_hex,
    };
  };
  const overlaps = (therapistId, start, end, ignoreId) =>
    appts.some((a) => a.id !== ignoreId && a.therapist_id === therapistId && ["pending", "confirmed"].includes(a.status) &&
      new Date(a.starts_at) < end && new Date(a.ends_at) > start);
  const fail = (message, code = "P0001") => Object.assign(new Error(message), { code });
  const wait = (ms = 120) => new Promise((r) => setTimeout(r, ms));
  const listeners = [];
  const emit = (what) => listeners.forEach((cb) => cb(what));
  const transitions = { pending: ["confirmed", "completed", "no_show"], confirmed: ["pending", "completed", "no_show"], no_show: ["completed"] };

  return {
    demo: true,
    async session() { return { user: { id: me.id } }; },
    async signIn() {},
    async signOut() {},
    async resetPassword() {},
    async updatePassword() {},
    onAuth() {},
    async me() { return me; },
    async center() { return { name: "Agenda Wellness Spa (demo)", logo_url: null }; },
    async publicBranding() { return null; },

    async staff() { await wait(); return structuredClone(staff); },
    async updateUser(id, role, active) {
      await wait();
      const u = staff.find((s) => s.id === id);
      if (u.id === me.id && (role !== "admin" || !active)) throw fail("Un administrador no puede quitarse su propio rol ni desactivarse");
      Object.assign(u, { role, is_active: active });
      emit("profiles");
    },
    async updateUserColor(id, color) { staff.find((s) => s.id === id).color_hex = color; },
    async inviteUser({ email, full_name, role }) {
      await wait(300);
      if (staff.some((s) => s.email === email)) throw fail("Ya existe un usuario con ese email");
      staff.push({ id: uid(), email, full_name, role, is_active: true, color_hex: "#8FA998" });
      emit("profiles");
    },
    async schedules() { return structuredClone(schedules); },
    async saveSchedule(therapistId, rows) {
      await wait();
      for (let i = schedules.length - 1; i >= 0; i--) if (schedules[i].therapist_id === therapistId) schedules.splice(i, 1);
      rows.forEach((r) => schedules.push({ id: uid(), ...r, therapist_id: therapistId }));
    },

    async services() { return structuredClone(services); },
    async clients(query = "") {
      await wait(60);
      const q = query.trim().toLowerCase();
      return structuredClone(clients.filter((c) =>
        !q || [c.first_name, c.last_name, c.dni, c.phone, c.email].some((v) => v?.toLowerCase().includes(q)),
      ).sort((a, b) => a.last_name.localeCompare(b.last_name)));
    },
    async saveClient(c) {
      await wait();
      if (c.dni && clients.some((x) => x.dni === c.dni && x.id !== c.id)) throw fail("Ya existe un cliente con ese DNI.", "23505");
      if (c.id) return Object.assign(clients.find((x) => x.id === c.id), c);
      const n = { ...c, id: uid() };
      clients.push(n);
      return n;
    },

    async appointments(from, to) {
      await wait(80);
      return appts.filter((a) => new Date(a.starts_at) >= from && new Date(a.starts_at) < to).map(view)
        .sort((a, b) => a.starts_at.localeCompare(b.starts_at));
    },
    async appointment(id) { return view(appts.find((a) => a.id === id)); },
    async createAppointment(a) {
      await wait();
      const s = services.find((x) => x.id === a.service_id);
      const start = new Date(a.starts_at);
      const end = new Date(start.getTime() + s.duration_minutes * 60000);
      if (overlaps(a.therapist_id, start, end)) throw fail("conflict", "23P01");
      const price = a.price || s.price;
      const n = add(clients.find((c) => c.id === a.client_id), staff.find((t) => t.id === a.therapist_id), s, start,
        a.confirmed ? "confirmed" : "pending");
      Object.assign(n, { price, discount_amount: a.discount_amount ?? 0, final_price: Math.max(price - (a.discount_amount ?? 0), 0), notes: a.notes || null });
      emit("appointments");
      return n.id;
    },
    async reschedule(id, start, therapistId) {
      await wait();
      const a = appts.find((x) => x.id === id);
      if (!["pending", "confirmed"].includes(a.status)) throw fail("Turno no reprogramable en su estado actual");
      const dur = new Date(a.ends_at) - new Date(a.starts_at);
      const end = new Date(start.getTime() + dur);
      const t = therapistId ?? a.therapist_id;
      if (overlaps(t, start, end, id)) throw fail("conflict", "P0409");
      Object.assign(a, { starts_at: start.toISOString(), ends_at: end.toISOString(), therapist_id: t,
        status: a.status === "confirmed" ? "pending" : a.status, reschedule_count: a.reschedule_count + 1 });
      emit("appointments");
    },
    async cancel(id, reason) {
      await wait();
      Object.assign(appts.find((x) => x.id === id), { status: "cancelled", cancellation_reason: reason });
      emit("appointments");
    },
    async setStatus(id, status) {
      await wait();
      const a = appts.find((x) => x.id === id);
      if (!(transitions[a.status] ?? []).includes(status)) throw fail(`Transición inválida: ${a.status} → ${status}`);
      a.status = status;
      emit("appointments");
    },
    async slots(date, serviceId, therapistId) {
      await wait(80);
      const s = services.find((x) => x.id === serviceId);
      const [y, m, d] = date.split("-").map(Number);
      const wd = new Date(y, m - 1, d).getDay();
      const out = [];
      for (const sc of schedules.filter((x) => x.weekday === wd && (!therapistId || x.therapist_id === therapistId))) {
        const t = staff.find((x) => x.id === sc.therapist_id);
        if (!t?.is_active) continue;
        const [sh, sm] = sc.start_time.split(":").map(Number);
        const [eh, em] = sc.end_time.split(":").map(Number);
        for (let min = sh * 60 + sm; min + s.duration_minutes + s.buffer_minutes <= eh * 60 + em; min += 15) {
          const st = new Date(y, m - 1, d, 0, min);
          const en = new Date(st.getTime() + (s.duration_minutes + s.buffer_minutes) * 60000);
          if (st > new Date() && !overlaps(t.id, st, en)) {
            out.push({ therapist_id: t.id, therapist_name: t.full_name, slot_start: st.toISOString(), slot_end: en.toISOString() });
          }
        }
      }
      return out.sort((a, b) => a.slot_start.localeCompare(b.slot_start));
    },
    async addPayment(p) {
      await wait();
      appts.find((x) => x.id === p.appointment_id).paid_amount += Number(p.amount);
      emit("appointments");
    },
    async dashboard() {
      await wait();
      const today = appts.filter((a) => new Date(a.starts_at).toDateString() === new Date().toDateString());
      return {
        today_appointments: today.filter((a) => a.status !== "cancelled").length,
        revenue_today: today.reduce((s, a) => s + a.paid_amount, 0),
        revenue_period: 1840000, new_clients: 9, active_clients: 112, cancellation_rate: 7.4, no_show_rate: 2.1, pending_payments: 3,
        top_services: [
          { name: "Masaje Descontracturante", count: 38, revenue: 1064000 }, { name: "Masaje Relajante", count: 31, revenue: 775000 },
          { name: "Tratamiento Facial", count: 22, revenue: 660000 }, { name: "Drenaje Linfático", count: 17, revenue: 510000 },
          { name: "Reflexología", count: 9, revenue: 198000 },
        ],
        peak_hours: [9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20].map((hour, i) => ({ hour, count: [8, 12, 15, 9, 4, 7, 11, 16, 21, 24, 13, 5][i] })),
      };
    },
    subscribe(cb) { listeners.push(cb); },
  };
}
