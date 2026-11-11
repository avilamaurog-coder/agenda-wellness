// =============================================================================
// Panel web de administración · Agenda Wellness
// Usuarios (aprobar, roles, invitar, horarios), agenda (día/semana, arrastrar,
// crear, estados, cancelar, cobrar), clientes y resumen del mes.
// Solo administradores: la autorización real la garantiza RLS en Supabase.
// =============================================================================
import { createDemoApi, createSupabaseApi, friendlyError } from "./api.js";

// ----------------------------------------------------------------------------- Utilidades
const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
const esc = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const pad = (n) => String(n).padStart(2, "0");
const ymd = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const hm = (d) => `${pad(d.getHours())}:${pad(d.getMinutes())}`;
const parseYmd = (s) => { const [y, m, d] = s.split("-").map(Number); return new Date(y, m - 1, d); };
const addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };
const startOfDay = (d) => { const x = new Date(d); x.setHours(0, 0, 0, 0); return x; };
const startOfWeek = (d) => { const x = startOfDay(d); const wd = (x.getDay() + 6) % 7; return addDays(x, -wd); };
const sameDay = (a, b) => a.toDateString() === b.toDateString();
const money = (n) => new Intl.NumberFormat("es-AR", { style: "currency", currency: "ARS", maximumFractionDigits: 0 }).format(Number(n) || 0);
const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);
const longDate = (d) => cap(new Intl.DateTimeFormat("es-AR", { weekday: "long", day: "numeric", month: "long" }).format(d));
const shortDate = (d) => cap(new Intl.DateTimeFormat("es-AR", { weekday: "short", day: "numeric", month: "short" }).format(d));
const initials = (name) => (name ?? "?").trim().split(/\s+/).map((p) => p[0]).filter(Boolean).slice(0, 2).join("").toUpperCase();
const debounce = (fn, ms = 250) => { let t; return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); }; };
const store = {
  get(k) { try { return localStorage.getItem(k); } catch { return null; } },
  set(k, v) { try { localStorage.setItem(k, v); } catch { /* sin almacenamiento */ } },
};

const STATUS = {
  pending: "Pendiente", confirmed: "Confirmado", completed: "Completado", cancelled: "Cancelado", no_show: "Ausente",
};
const NEXT = { pending: ["confirmed", "completed", "no_show"], confirmed: ["completed", "no_show", "pending"], no_show: ["completed"] };
const ACTION_LABEL = { confirmed: "Confirmar asistencia", completed: "Marcar completado", no_show: "Marcar ausente", pending: "Volver a pendiente" };
const ROLES = { admin: "Administrador", receptionist: "Recepcionista", therapist: "Profesional" };
const WEEKDAYS = ["Domingo", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado"];
const WD_SHORT = ["Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"];
const METHODS = { cash: "Efectivo", transfer: "Transferencia", card: "Tarjeta", mercado_pago: "Mercado Pago" };
const START_H = 8, END_H = 22, PPM = 1.2, SNAP = 15;

// ----------------------------------------------------------------------------- Estado
const state = {
  api: null,
  me: null,
  staff: [],
  services: [],
  schedules: [],
  appts: [],
  agenda: { date: startOfDay(new Date()), mode: store.get("aw.mode") || "day", therapist: "" },
  view: "agenda",
};

// ----------------------------------------------------------------------------- Avisos y diálogos
let toastTimer;
function toast(msg, error = false) {
  const t = $("#toast");
  t.textContent = msg;
  t.className = `toast${error ? " error" : ""}`;
  t.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => (t.hidden = true), error ? 5000 : 2800);
}
const fail = (e) => toast(friendlyError(e), true);

/** Abre un formulario modal. `onSubmit` recibe FormData; si devuelve false el modal sigue abierto. */
function openModal(title, bodyHtml, { submit = "Guardar", danger = false, onSubmit, onOpen, wide = false } = {}) {
  const dlg = $("#modal");
  if (dlg.open) dlg.close(); // un modal a la vez (el anterior resuelve como cancelado)
  dlg.style.width = wide ? "min(680px, calc(100vw - 32px))" : "";
  dlg.innerHTML = `
    <form method="dialog" novalidate>
      <header><h2>${esc(title)}</h2><button class="btn ghost icon" value="cancel" type="button" data-close aria-label="Cerrar">×</button></header>
      ${bodyHtml}
      <p class="form-error" data-error role="alert"></p>
      <footer>
        <button class="btn" type="button" data-close>Cancelar</button>
        <button class="btn ${danger ? "danger solid" : "primary"}" type="submit">${esc(submit)}</button>
      </footer>
    </form>`;
  const form = $("form", dlg);
  $$("[data-close]", dlg).forEach((b) => b.addEventListener("click", () => dlg.close()));
  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    if (!form.reportValidity()) return;
    const btn = $('button[type="submit"]', form);
    btn.disabled = true;
    $("[data-error]", form).textContent = "";
    try {
      const ok = await onSubmit?.(new FormData(form), form);
      if (ok !== false) dlg.close();
    } catch (err) {
      $("[data-error]", form).textContent = friendlyError(err);
    } finally {
      btn.disabled = false;
    }
  });
  dlg.showModal();
  onOpen?.(form);
  return form;
}

function confirmDialog(title, message, { ok = "Confirmar", danger = false } = {}) {
  return new Promise((resolve) => {
    let answered = false;
    openModal(title, `<p style="margin:0">${esc(message).replace(/\n/g, "<br>")}</p>`, {
      submit: ok, danger, onSubmit: () => { answered = true; resolve(true); },
    });
    $("#modal").addEventListener("close", () => { if (!answered) resolve(false); }, { once: true });
  });
}

// ----------------------------------------------------------------------------- Arranque y sesión
async function boot() {
  applyTheme(store.get("aw.theme") || "system");
  const cfg = window.AW_CONFIG ?? {};
  const configured = Boolean(cfg.supabaseUrl && cfg.supabaseAnonKey);
  const wantsDemo = new URLSearchParams(location.search).has("demo");

  if (!configured || wantsDemo) {
    $("#demo-box").hidden = false;
    if (wantsDemo) return startDemo();
    showLogin();
    return;
  }

  try {
    state.api = await createSupabaseApi(cfg);
  } catch (e) {
    showLogin("No se pudo cargar el cliente de Supabase. Revisá tu conexión.");
    return;
  }
  state.api.onAuth((event) => {
    if (event === "PASSWORD_RECOVERY") askNewPassword();
    if (event === "SIGNED_OUT") showLogin();
  });
  const branding = await state.api.publicBranding().catch(() => null);
  if (branding) applyBranding(branding, true);

  if (await state.api.session()) await enter();
  else showLogin();
}

function showLogin(error = "") {
  $("#app-view").hidden = true;
  $("#login-view").hidden = false;
  $("#drawer").hidden = true;
  $("#login-error").textContent = error;
}

async function startDemo() {
  state.api = createDemoApi();
  await enter();
}

async function enter() {
  try {
    const me = await state.api.me();
    if (!me || !me.is_active) {
      await state.api.signOut();
      return showLogin("Tu cuenta está pendiente de aprobación.");
    }
    if (me.role !== "admin") {
      await state.api.signOut();
      return showLogin("El panel web es solo para administradores. Usá la app móvil.");
    }
    state.me = me;
    const [staff, services, schedules, center] = await Promise.all([
      state.api.staff(), state.api.services(), state.api.schedules(), state.api.center().catch(() => null),
    ]);
    Object.assign(state, { staff, services, schedules });
    if (center) applyBranding(center, false);

    $("#me-name").textContent = me.full_name;
    $("#me-email").textContent = me.email;
    $("#me-avatar").textContent = initials(me.full_name);
    $("#me-avatar").style.background = me.color_hex ?? "";
    $("#demo-banner").hidden = !state.api.demo;
    $("#login-view").hidden = true;
    $("#app-view").hidden = false;

    state.api.subscribe(debounce(async (what) => {
      if (what === "profiles") { state.staff = await state.api.staff(); renderPendingBadge(); if (state.view === "usuarios") renderUsers(); }
      if (what === "appointments" && state.view === "agenda") loadAgenda();
    }, 400));

    route();
  } catch (e) {
    showLogin(friendlyError(e));
  }
}

function applyBranding(center, loginOnly) {
  const logo = center.logo_url;
  for (const id of loginOnly ? ["#login-logo"] : ["#login-logo", "#side-logo"]) {
    const el = $(id);
    if (logo) { el.classList.add("has-logo"); el.style.backgroundImage = `url("${encodeURI(logo)}")`; }
  }
  if (center.name) {
    $("#login-title").textContent = center.name;
    if (!loginOnly) $("#center-name").textContent = center.name;
  }
}

function askNewPassword() {
  openModal("Nueva contraseña", `
    <label>Contraseña nueva<input type="password" name="password" required minlength="8" autocomplete="new-password"></label>
    <p class="muted tiny">Mínimo 8 caracteres, con mayúsculas, minúsculas y números.</p>`, {
    onSubmit: async (fd) => {
      const pw = fd.get("password");
      if (!/[a-z]/.test(pw) || !/[A-Z]/.test(pw) || !/\d/.test(pw)) throw new Error("Usá mayúsculas, minúsculas y al menos un número.");
      await state.api.updatePassword(pw);
      toast("Contraseña actualizada");
    },
  });
}

$("#login-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const fd = new FormData(e.target);
  const btn = $('button[type="submit"]', e.target);
  btn.disabled = true;
  $("#login-error").textContent = "";
  try {
    if (!state.api) throw new Error("No hay un proyecto Supabase configurado. Usá el modo demo o completá config.js.");
    await state.api.signIn(String(fd.get("email")).trim(), String(fd.get("password")));
    await enter();
  } catch (err) {
    $("#login-error").textContent = friendlyError(err);
  } finally {
    btn.disabled = false;
  }
});

$("#forgot-btn").addEventListener("click", () => {
  if (!state.api || state.api.demo) return toast("Disponible con el proyecto Supabase configurado");
  openModal("Recuperar contraseña", `<label>Email<input type="email" name="email" required value="${esc($('#login-form [name="email"]').value)}"></label>`, {
    submit: "Enviar enlace",
    onSubmit: async (fd) => { await state.api.resetPassword(String(fd.get("email")).trim()); toast("Si el email existe, te enviamos un enlace."); },
  });
});
$("#demo-btn").addEventListener("click", startDemo);
$("#logout-btn").addEventListener("click", async () => {
  await state.api.signOut();
  if (state.api.demo) { state.api = null; location.search = ""; }
  showLogin();
});

function applyTheme(mode) {
  if (mode === "system") document.documentElement.removeAttribute("data-theme");
  else document.documentElement.dataset.theme = mode;
  store.set("aw.theme", mode);
}
$("#theme-btn").addEventListener("click", () => {
  const order = ["system", "light", "dark"];
  const next = order[(order.indexOf(store.get("aw.theme") || "system") + 1) % 3];
  applyTheme(next);
  toast({ system: "Tema automático", light: "Tema claro", dark: "Tema oscuro" }[next]);
});

// ----------------------------------------------------------------------------- Navegación
function route() {
  const view = (location.hash.replace("#", "") || "agenda");
  state.view = ["agenda", "usuarios", "clientes", "resumen"].includes(view) ? view : "agenda";
  $$(".view").forEach((v) => (v.hidden = v.id !== `view-${state.view}`));
  $$(".nav a").forEach((a) => a.classList.toggle("on", a.dataset.view === state.view));
  $("#drawer").hidden = true;
  renderPendingBadge();
  ({ agenda: initAgenda, usuarios: renderUsers, clientes: renderClients, resumen: renderSummary })[state.view]();
}
window.addEventListener("hashchange", () => { if (state.me) route(); });
document.addEventListener("keydown", (e) => { if (e.key === "Escape" && !$("#modal").open) $("#drawer").hidden = true; });

const therapists = () => state.staff.filter((s) => s.is_active && (s.role === "therapist" ||
  (s.role === "admin" && state.schedules.some((x) => x.therapist_id === s.id))));
const person = (id) => state.staff.find((s) => s.id === id);

// ============================================================================= AGENDA
let agendaWired = false;
function initAgenda() {
  if (!agendaWired) {
    agendaWired = true;
    $$("[data-agenda-view]").forEach((b) => b.addEventListener("click", () => {
      state.agenda.mode = b.dataset.agendaView;
      store.set("aw.mode", state.agenda.mode);
      loadAgenda();
    }));
    const step = (dir) => { state.agenda.date = addDays(state.agenda.date, dir * (state.agenda.mode === "week" ? 7 : 1)); loadAgenda(); };
    $("#prev-btn").addEventListener("click", () => step(-1));
    $("#next-btn").addEventListener("click", () => step(1));
    $("#today-btn").addEventListener("click", () => { state.agenda.date = startOfDay(new Date()); loadAgenda(); });
    $("#date-input").addEventListener("change", (e) => { if (e.target.value) { state.agenda.date = parseYmd(e.target.value); loadAgenda(); } });
    $("#therapist-filter").addEventListener("change", (e) => { state.agenda.therapist = e.target.value; renderAgenda(); });
    $("#new-appt-btn").addEventListener("click", () => openAppointmentForm({}));
    setInterval(() => { if (state.view === "agenda" && !$("#app-view").hidden) renderNowLine(); }, 60_000);
  }
  loadAgenda();
}

function agendaRange() {
  const { date, mode } = state.agenda;
  const from = mode === "week" ? startOfWeek(date) : startOfDay(date);
  return [from, addDays(from, mode === "week" ? 7 : 1)];
}

async function loadAgenda() {
  const [from, to] = agendaRange();
  try {
    state.appts = await state.api.appointments(from, to);
    renderAgenda();
  } catch (e) {
    fail(e);
  }
}

/** Ventanas de trabajo de un profesional para un día (minutos desde 00:00). */
function workWindows(therapistId, date) {
  return state.schedules
    .filter((s) => s.therapist_id === therapistId && s.weekday === date.getDay())
    .map((s) => { const [a, b] = [s.start_time, s.end_time].map((t) => { const [h, m] = t.split(":").map(Number); return h * 60 + m; }); return [a, b]; });
}

function renderAgenda() {
  const { date, mode, therapist } = state.agenda;
  $$("[data-agenda-view]").forEach((b) => b.classList.toggle("on", b.dataset.agendaView === mode));
  $("#date-input").value = ymd(date);

  // Filtro de profesionales
  const sel = $("#therapist-filter");
  const ts = therapists();
  sel.innerHTML = `<option value="">Todos los profesionales</option>` +
    ts.map((t) => `<option value="${t.id}" ${t.id === therapist ? "selected" : ""}>${esc(t.full_name)}</option>`).join("");

  const visible = state.appts.filter((a) => !therapist || a.therapist_id === therapist);
  const active = visible.filter((a) => a.status !== "cancelled");
  const [from] = agendaRange();
  $("#agenda-title").textContent = mode === "week"
    ? `Semana del ${from.getDate()} de ${new Intl.DateTimeFormat("es-AR", { month: "long" }).format(from)}`
    : longDate(date);
  $("#agenda-sub").textContent = `${active.length} ${active.length === 1 ? "turno" : "turnos"} · ` +
    `${active.filter((a) => a.status === "confirmed").length} confirmados · ${active.filter((a) => a.status === "pending").length} pendientes`;

  $("#legend").innerHTML = Object.entries(STATUS).map(([k, v]) => `<span class="chip st-${k}">${v}</span>`).join("");

  // Columnas
  let cols;
  if (mode === "day") {
    const list = therapist ? ts.filter((t) => t.id === therapist) : ts;
    cols = list.map((t) => ({
      key: t.id, title: t.full_name, color: t.color_hex, date, therapistId: t.id,
      sub: `${visible.filter((a) => a.therapist_id === t.id && a.status !== "cancelled").length} turnos`,
      appts: visible.filter((a) => a.therapist_id === t.id),
      windows: workWindows(t.id, date),
    }));
    if (!cols.length) cols = [{ key: "all", title: "Turnos", date, appts: visible, windows: null }];
  } else {
    cols = Array.from({ length: 7 }, (_, i) => {
      const d = addDays(from, i);
      const dayAppts = visible.filter((a) => sameDay(new Date(a.starts_at), d));
      return {
        key: ymd(d), title: shortDate(d), date: d, therapistId: therapist || null, today: sameDay(d, new Date()),
        sub: `${dayAppts.filter((a) => a.status !== "cancelled").length} turnos`, appts: dayAppts,
        windows: therapist ? workWindows(therapist, d) : null,
      };
    });
  }

  const height = (END_H - START_H) * 60 * PPM;
  const grid = $("#grid");
  grid.style.gridTemplateColumns = `56px repeat(${cols.length}, minmax(var(--col-min), 1fr))`;
  grid.style.gridTemplateRows = `auto ${height + 12}px`;
  grid.innerHTML =
    `<div class="gh-cell corner"></div>` +
    cols.map((c) => `<div class="gh-cell ${c.today ? "today" : ""}"><strong>${c.color ? `<i class="dot" style="background:${esc(c.color)}"></i>` : ""}${esc(c.title)}</strong><span>${esc(c.sub)}</span></div>`).join("") +
    `<div class="hours" style="height:${height}px">${Array.from({ length: END_H - START_H + 1 }, (_, i) =>
      `<div style="top:${i * 60 * PPM}px">${pad(START_H + i)}:00</div>`).join("")}</div>` +
    cols.map((c, i) => `<div class="col" data-col="${i}" style="height:${height}px">${offBlocks(c.windows)}${c.appts.map(apptBlock).join("")}</div>`).join("");

  $$(".col", grid).forEach((el) => wireColumn(el, cols[Number(el.dataset.col)]));
  $$(".appt", grid).forEach(wireAppt);
  renderNowLine();

  // Llevar la vista a la hora actual (o al primer turno) al cargar
  const wrap = $("#grid-wrap");
  if (!wrap.dataset.scrolled) {
    const first = visible.map((a) => new Date(a.starts_at)).sort((a, b) => a - b)[0];
    const target = sameDay(date, new Date()) ? new Date() : first;
    if (target) wrap.scrollTop = Math.max(0, ((target.getHours() - START_H) * 60 + target.getMinutes() - 45) * PPM);
    wrap.dataset.scrolled = "1";
  }
}

function offBlocks(windows) {
  if (!windows) return "";
  const startMin = START_H * 60, endMin = END_H * 60;
  const free = [];
  let cursor = startMin;
  for (const [a, b] of [...windows].sort((x, y) => x[0] - y[0])) {
    if (a > cursor) free.push([cursor, Math.min(a, endMin)]);
    cursor = Math.max(cursor, b);
  }
  if (cursor < endMin) free.push([cursor, endMin]);
  return free.filter(([a, b]) => b > a).map(([a, b]) =>
    `<div class="off-block" style="position:absolute;left:0;right:0;top:${(a - startMin) * PPM}px;height:${(b - a) * PPM}px;` +
    `background:repeating-linear-gradient(135deg,transparent 0 6px,color-mix(in srgb,var(--line) 55%,transparent) 6px 7px);pointer-events:none"></div>`).join("");
}

function apptBlock(a) {
  const s = new Date(a.starts_at), e = new Date(a.ends_at);
  const top = ((s.getHours() - START_H) * 60 + s.getMinutes()) * PPM;
  const h = Math.max(26, ((e - s) / 60000) * PPM - 2);
  const movable = a.status === "pending" || a.status === "confirmed";
  const faded = a.status === "cancelled" || a.status === "no_show";
  const compact = h < 44;
  return `<div class="appt ${movable ? "" : "locked"} ${faded ? "faded" : ""}" data-id="${a.id}" ${movable ? 'draggable="true"' : ""}
      style="top:${top}px;height:${h}px;--c:${esc(a.service_color || a.therapist_color || "#5E7D6F")};--s:var(--st-${a.status})"
      title="${esc(`${a.client_name} · ${a.service_name} · ${hm(s)}–${hm(e)} · ${STATUS[a.status]}`)}">
    ${compact
      ? `<div class="when"><span>${hm(s)} <b class="who" style="display:inline">${esc(a.client_name)}</b></span></div>`
      : `<div class="when"><span>${hm(s)}–${hm(e)}</span><span class="chip st-${a.status} plain" style="padding:0 6px">${STATUS[a.status]}</span></div>
         <div class="who">${esc(a.client_name)}</div><div class="what">${esc(a.service_name)}${state.agenda.mode === "week" && !state.agenda.therapist ? ` · ${esc(a.therapist_name.split(" ")[0])}` : ""}</div>`}
  </div>`;
}

function renderNowLine() {
  $$(".now-line").forEach((n) => n.remove());
  const now = new Date();
  if (now.getHours() < START_H || now.getHours() >= END_H) return;
  const top = ((now.getHours() - START_H) * 60 + now.getMinutes()) * PPM;
  const cols = $$(".col");
  const idx = state.agenda.mode === "week"
    ? cols.findIndex((_, i) => sameDay(addDays(agendaRange()[0], i), now))
    : (sameDay(state.agenda.date, now) ? -2 : -1);
  cols.forEach((c, i) => {
    if (idx === -2 || i === idx) c.insertAdjacentHTML("beforeend", `<div class="now-line" style="top:${top}px"></div>`);
  });
}

// ---- Drag & drop y clic en huecos
let drag = null; // { id, offsetY, duration }

function wireAppt(el) {
  el.addEventListener("click", (e) => { e.stopPropagation(); openAppointmentDetail(el.dataset.id); });
  el.addEventListener("dragstart", (e) => {
    const a = state.appts.find((x) => x.id === el.dataset.id);
    drag = { id: a.id, offsetY: e.clientY - el.getBoundingClientRect().top, duration: (new Date(a.ends_at) - new Date(a.starts_at)) / 60000 };
    e.dataTransfer.effectAllowed = "move";
    e.dataTransfer.setData("text/plain", a.id);
    requestAnimationFrame(() => el.classList.add("dragging"));
  });
  el.addEventListener("dragend", () => {
    el.classList.remove("dragging");
    $$(".drop-ghost").forEach((g) => g.remove());
    $$(".col.drop").forEach((c) => c.classList.remove("drop"));
    drag = null;
  });
}

function minuteAt(colEl, clientY, offsetY = 0) {
  const y = clientY - colEl.getBoundingClientRect().top - offsetY;
  const raw = Math.min(Math.max(y / PPM, 0), (END_H - START_H) * 60 - SNAP);
  return START_H * 60 + Math.round(raw / SNAP) * SNAP;
}
const atMinute = (date, min) => { const d = startOfDay(date); d.setMinutes(min); return d; };

function wireColumn(colEl, col) {
  colEl.addEventListener("dragover", (e) => {
    if (!drag) return;
    e.preventDefault();
    const min = minuteAt(colEl, e.clientY, drag.offsetY);
    colEl.classList.add("drop");
    let g = $(".drop-ghost", colEl);
    if (!g) { $$(".drop-ghost").forEach((x) => x.remove()); g = document.createElement("div"); g.className = "drop-ghost"; colEl.appendChild(g); }
    g.style.top = `${(min - START_H * 60) * PPM}px`;
    g.style.height = `${drag.duration * PPM}px`;
    g.textContent = `${pad(Math.floor(min / 60))}:${pad(min % 60)}`;
  });
  colEl.addEventListener("dragleave", (e) => {
    if (!colEl.contains(e.relatedTarget)) { colEl.classList.remove("drop"); $(".drop-ghost", colEl)?.remove(); }
  });
  colEl.addEventListener("drop", async (e) => {
    e.preventDefault();
    if (!drag) return;
    const { id, offsetY } = drag;
    const a = state.appts.find((x) => x.id === id);
    const start = atMinute(col.date, minuteAt(colEl, e.clientY, offsetY));
    const therapistId = col.therapistId ?? a.therapist_id;
    $$(".drop-ghost").forEach((g) => g.remove());
    colEl.classList.remove("drop");
    const oldStart = new Date(a.starts_at);
    if (+start === +oldStart && therapistId === a.therapist_id) return;
    const newT = person(therapistId);
    const ok = await confirmDialog("Reprogramar turno",
      `${a.client_name} · ${a.service_name}\n${shortDate(oldStart)} ${hm(oldStart)} → ${shortDate(start)} ${hm(start)}` +
      (therapistId !== a.therapist_id ? `\nProfesional: ${a.therapist_name} → ${newT?.full_name ?? ""}` : "") +
      (a.status === "confirmed" ? "\n\nEl turno vuelve a Pendiente y se reenvían los recordatorios." : ""),
      { ok: "Reprogramar" });
    if (!ok) return;
    try {
      await state.api.reschedule(id, start, therapistId !== a.therapist_id ? therapistId : null, "Reprogramado desde el panel web");
      toast("Turno reprogramado");
      loadAgenda();
    } catch (err) {
      fail(err);
    }
  });
  colEl.addEventListener("click", (e) => {
    if (e.target.closest(".appt")) return;
    const start = atMinute(col.date, minuteAt(colEl, e.clientY));
    openAppointmentForm({ start, therapistId: col.therapistId });
  });
}

// ---- Alta de turno
function openAppointmentForm({ start, therapistId, client }) {
  const d = start ?? (() => { const n = new Date(); n.setMinutes(Math.ceil(n.getMinutes() / 15) * 15, 0, 0); return sameDay(state.agenda.date, n) ? n : atMinute(state.agenda.date, 10 * 60); })();
  let chosen = client ?? null;

  const form = openModal("Nuevo turno", `
    <div class="picker">
      <label>Cliente<input name="client_q" placeholder="Buscar por nombre, DNI o teléfono" autocomplete="off" value="${esc(chosen ? `${chosen.first_name} ${chosen.last_name}` : "")}" required></label>
      <div class="picker-list" hidden></div>
    </div>
    <div data-alert></div>
    <label>Servicio<select name="service_id" required>
      <option value="">Elegí un servicio</option>
      ${state.services.map((s) => `<option value="${s.id}">${esc(s.name)} · ${s.duration_minutes} min · ${money(s.promo_price ?? s.price)}</option>`).join("")}
    </select></label>
    <label>Profesional<select name="therapist_id" required>
      <option value="">Elegí un profesional</option>
      ${therapists().map((t) => `<option value="${t.id}" ${t.id === therapistId ? "selected" : ""}>${esc(t.full_name)}</option>`).join("")}
    </select></label>
    <div class="grid-2">
      <label>Fecha<input type="date" name="date" required value="${ymd(d)}"></label>
      <label>Hora<input type="time" name="time" required step="300" value="${hm(d)}"></label>
    </div>
    <div data-slots></div>
    <div class="grid-2">
      <label>Descuento ($)<input type="number" name="discount" min="0" step="100" value="0"></label>
      <label class="check" style="align-self:end;padding-bottom:10px"><input type="checkbox" name="confirmed"> Ya confirmó asistencia</label>
    </div>
    <label>Notas<textarea name="notes" placeholder="Opcional"></textarea></label>`, {
    submit: "Agendar turno",
    wide: true,
    onSubmit: async (fd) => {
      if (!chosen) throw new Error("Elegí un cliente de la lista (o creá uno nuevo).");
      const [y, m, dd] = String(fd.get("date")).split("-").map(Number);
      const [hh, mi] = String(fd.get("time")).split(":").map(Number);
      const startsAt = new Date(y, m - 1, dd, hh, mi);
      if (startsAt < new Date(Date.now() - 5 * 60000)) throw new Error("No se pueden crear turnos en el pasado.");
      const svc = state.services.find((s) => s.id === fd.get("service_id"));
      const discount = Number(fd.get("discount")) || 0;
      if (discount > Number(svc.promo_price ?? svc.price)) throw new Error("El descuento supera el precio del servicio.");
      await state.api.createAppointment({
        client_id: chosen.id, therapist_id: fd.get("therapist_id"), service_id: svc.id, starts_at: startsAt.toISOString(),
        price: discount ? Number(svc.promo_price ?? svc.price) : 0, discount_amount: discount,
        notes: String(fd.get("notes") || "").trim(), confirmed: fd.get("confirmed") === "on",
      });
      toast(`Turno agendado: ${shortDate(startsAt)} ${hm(startsAt)}`);
      state.agenda.date = startOfDay(startsAt);
      if (state.view === "agenda") loadAgenda();
    },
  });

  const q = form.elements.client_q;
  const list = $(".picker-list", form);
  const showAlert = () => {
    const al = [chosen?.allergies && `Alergias: ${chosen.allergies}`, chosen?.contraindications && `Contraindicaciones: ${chosen.contraindications}`].filter(Boolean);
    $("[data-alert]", form).innerHTML = al.length ? `<div class="alert">⚠️ ${al.map(esc).join("<br>")}</div>` : "";
  };
  showAlert();
  const search = debounce(async () => {
    const term = q.value.trim();
    const res = await state.api.clients(term, 8).catch(() => []);
    list.innerHTML = res.map((c) => `<button type="button" data-id="${c.id}">${esc(c.first_name)} ${esc(c.last_name)}
        <span class="muted tiny">${esc([c.dni, c.whatsapp ?? c.phone].filter(Boolean).join(" · "))}</span></button>`).join("") +
      `<button type="button" data-new><b>+ Crear cliente nuevo${term ? `: “${esc(term)}”` : ""}</b></button>`;
    list.hidden = false;
    $$("button[data-id]", list).forEach((b) => b.addEventListener("click", () => {
      chosen = res.find((c) => c.id === b.dataset.id);
      q.value = `${chosen.first_name} ${chosen.last_name}`;
      list.hidden = true;
      showAlert();
    }));
    $("button[data-new]", list).addEventListener("click", () => {
      const keep = new FormData(form);
      const parts = term.split(/\s+/);
      openClientForm({ first_name: parts[0] ?? "", last_name: parts.slice(1).join(" ") }, (created) => {
        openAppointmentForm({ start: atTime(keep), therapistId: keep.get("therapist_id"), client: created });
      });
    });
  }, 200);
  q.addEventListener("input", () => { chosen = null; showAlert(); search(); });
  q.addEventListener("focus", search);
  form.addEventListener("click", (e) => { if (!e.target.closest(".picker")) list.hidden = true; });

  const loadSlots = debounce(async () => {
    const box = $("[data-slots]", form);
    const svc = form.elements.service_id.value, date = form.elements.date.value;
    if (!svc || !date) { box.innerHTML = ""; return; }
    box.innerHTML = `<p class="muted tiny">Buscando horarios libres…</p>`;
    try {
      const slots = await state.api.slots(date, svc, form.elements.therapist_id.value);
      const seen = new Set();
      const unique = slots.filter((s) => !seen.has(s.slot_start + s.therapist_id) && seen.add(s.slot_start + s.therapist_id)).slice(0, 40);
      box.innerHTML = unique.length
        ? `<label>Horarios libres</label><div class="slots">${unique.map((s) => {
            const t = new Date(s.slot_start);
            return `<button type="button" class="slot" data-t="${hm(t)}" data-th="${s.therapist_id}" title="${esc(s.therapist_name)}">${hm(t)}${form.elements.therapist_id.value ? "" : ` · ${esc(s.therapist_name.split(" ")[0])}`}</button>`;
          }).join("")}</div>`
        : `<p class="muted tiny">No hay horarios libres cargados para ese día. Podés elegir la hora a mano (revisá los horarios en Usuarios).</p>`;
      $$(".slot", box).forEach((b) => b.addEventListener("click", () => {
        form.elements.time.value = b.dataset.t;
        form.elements.therapist_id.value = b.dataset.th;
        $$(".slot", box).forEach((x) => x.classList.toggle("on", x === b));
      }));
    } catch {
      box.innerHTML = "";
    }
  }, 150);
  ["service_id", "date", "therapist_id"].forEach((n) => form.elements[n].addEventListener("change", loadSlots));
  if (!chosen) q.focus();
}
const atTime = (fd) => {
  const [y, m, d] = String(fd.get("date")).split("-").map(Number);
  const [hh, mi] = String(fd.get("time")).split(":").map(Number);
  return new Date(y, m - 1, d, hh, mi);
};

// ---- Detalle del turno (panel lateral)
async function openAppointmentDetail(id) {
  const drawer = $("#drawer");
  let a;
  try { a = await state.api.appointment(id); } catch (e) { return fail(e); }
  const s = new Date(a.starts_at), e = new Date(a.ends_at);
  const balance = Math.max(Number(a.final_price) - Number(a.paid_amount), 0);
  const active = a.status === "pending" || a.status === "confirmed";
  const phone = (a.client_phone ?? "").replace(/\D/g, "");

  drawer.innerHTML = `
    <div class="row" style="justify-content:space-between"><span class="chip st-${a.status}">${STATUS[a.status]}</span>
      <button class="btn ghost icon" data-close aria-label="Cerrar">×</button></div>
    <div><h2>${esc(a.service_name)}</h2><p class="muted">${longDate(s)} · ${hm(s)}–${hm(e)}</p>
      ${a.reschedule_count ? `<p class="muted tiny">Reprogramado ${a.reschedule_count} ${a.reschedule_count === 1 ? "vez" : "veces"}</p>` : ""}</div>
    <div class="info">
      <div><span>Cliente</span><strong>${esc(a.client_name)}</strong></div>
      ${a.client_phone ? `<div><span>WhatsApp</span><a href="https://wa.me/${phone.startsWith("54") ? phone : `549${phone}`}" target="_blank" rel="noopener">${esc(a.client_phone)}</a></div>` : ""}
      <div><span>Profesional</span><strong>${esc(a.therapist_name)}</strong></div>
      <div><span>Precio</span><strong>${money(a.final_price)}${Number(a.discount_amount) ? ` <span class="muted tiny">(desc. ${money(a.discount_amount)})</span>` : ""}</strong></div>
      <div><span>Pagado</span><strong>${money(a.paid_amount)}</strong></div>
      ${a.status !== "cancelled" ? `<div><span>Saldo</span><strong style="color:${balance ? "var(--danger)" : "var(--st-completed)"}">${balance ? money(balance) : "Pagado"}</strong></div>` : ""}
      ${a.notes ? `<div><span>Notas</span><span style="color:var(--text);text-align:right">${esc(a.notes)}</span></div>` : ""}
      ${a.cancellation_reason ? `<div><span>Motivo</span><span style="color:var(--text);text-align:right">${esc(a.cancellation_reason)}</span></div>` : ""}
    </div>
    ${(NEXT[a.status] ?? []).length ? `<div class="stack"><strong class="tiny muted">CAMBIAR ESTADO</strong>
      ${NEXT[a.status].map((st) => `<button class="btn" data-status="${st}"><span class="chip st-${st} plain" style="padding:0">●</span> ${ACTION_LABEL[st]}</button>`).join("")}</div>` : ""}
    <div class="stack">
      ${a.status !== "cancelled" && balance > 0 ? `<button class="btn primary" data-pay>Registrar pago · ${money(balance)}</button>` : ""}
      ${active ? `<button class="btn" data-move>Reprogramar</button><button class="btn danger" data-cancel>Cancelar turno</button>` : ""}
    </div>`;
  drawer.hidden = false;

  const refresh = () => { loadAgenda(); openAppointmentDetail(id); };
  $("[data-close]", drawer).addEventListener("click", () => (drawer.hidden = true));
  $$("[data-status]", drawer).forEach((b) => b.addEventListener("click", async () => {
    b.disabled = true;
    try { await state.api.setStatus(id, b.dataset.status); toast(`Estado: ${STATUS[b.dataset.status]}`); refresh(); } catch (err) { fail(err); b.disabled = false; }
  }));

  $("[data-pay]", drawer)?.addEventListener("click", () => openModal("Registrar pago", `
    <p class="muted" style="margin:0">${esc(a.client_name)} · ${esc(a.service_name)}</p>
    <label>Monto<input type="number" name="amount" min="1" step="1" required value="${balance}"></label>
    <label>Medio de pago<select name="method">${Object.entries(METHODS).map(([k, v]) => `<option value="${k}">${v}</option>`).join("")}</select></label>
    <label>Nº de operación / comprobante<input name="reference" placeholder="Opcional"></label>`, {
    submit: "Confirmar pago",
    onSubmit: async (fd) => {
      await state.api.addPayment({ appointment_id: id, client_id: a.client_id, amount: Number(fd.get("amount")), method: fd.get("method"), reference: fd.get("reference") || null });
      toast(`Pago registrado: ${money(fd.get("amount"))}`);
      refresh();
    },
  }));

  $("[data-move]", drawer)?.addEventListener("click", () => openModal("Reprogramar turno", `
    <div class="grid-2">
      <label>Fecha<input type="date" name="date" required value="${ymd(s)}"></label>
      <label>Hora<input type="time" name="time" required step="300" value="${hm(s)}"></label>
    </div>
    <label>Profesional<select name="therapist_id">${therapists().map((t) => `<option value="${t.id}" ${t.id === a.therapist_id ? "selected" : ""}>${esc(t.full_name)}</option>`).join("")}</select></label>
    <label>Motivo<input name="reason" placeholder="Opcional"></label>`, {
    submit: "Reprogramar",
    onSubmit: async (fd) => {
      const start = atTime(fd);
      if (start < new Date()) throw new Error("Elegí un horario futuro.");
      const th = fd.get("therapist_id");
      await state.api.reschedule(id, start, th !== a.therapist_id ? th : null, String(fd.get("reason") || "") || "Reprogramado desde el panel web");
      toast("Turno reprogramado");
      state.agenda.date = startOfDay(start);
      refresh();
    },
  }));

  $("[data-cancel]", drawer)?.addEventListener("click", () => openModal("Cancelar turno", `
    <p class="muted" style="margin:0">${esc(a.client_name)} · ${shortDate(s)} ${hm(s)}</p>
    <div class="slots">${["Enfermedad", "Imprevisto personal", "Pidió reprogramar", "Clima", "No especificado"].map((r) => `<button type="button" class="slot" data-r="${r}">${r}</button>`).join("")}</div>
    <label>Motivo<input name="reason" required minlength="3" placeholder="Motivo de la cancelación"></label>`, {
    submit: "Cancelar turno", danger: true,
    onOpen: (f) => $$(".slot", f).forEach((b) => b.addEventListener("click", () => {
      f.elements.reason.value = b.dataset.r;
      $$(".slot", f).forEach((x) => x.classList.toggle("on", x === b));
    })),
    onSubmit: async (fd) => { await state.api.cancel(id, String(fd.get("reason")).trim()); toast("Turno cancelado"); refresh(); },
  }));
}

// ============================================================================= USUARIOS
let usersWired = false;
function renderPendingBadge() {
  const n = state.staff.filter((s) => !s.is_active).length;
  const b = $("#pending-badge");
  b.hidden = !n;
  b.textContent = n;
}

function scheduleSummary(id) {
  const rows = state.schedules.filter((s) => s.therapist_id === id).sort((a, b) => a.weekday - b.weekday);
  if (!rows.length) return `<span class="chip warn plain">Sin horario</span>`;
  // Agrupa días consecutivos con el mismo horario: "Lun–Vie 09:00–19:00"
  const order = [1, 2, 3, 4, 5, 6, 0];
  const byDay = new Map(rows.map((r) => [r.weekday, `${r.start_time.slice(0, 5)}–${r.end_time.slice(0, 5)}`]));
  const groups = [];
  for (const wd of order) {
    const range = byDay.get(wd);
    const last = groups.at(-1);
    if (range && last && last.range === range && order.indexOf(wd) === order.indexOf(last.to) + 1) last.to = wd;
    else if (range) groups.push({ from: wd, to: wd, range });
  }
  return `<span class="tiny">${groups.map((g) => `${WD_SHORT[g.from]}${g.to !== g.from ? `–${WD_SHORT[g.to]}` : ""} ${g.range}`).join("<br>")}</span>`;
}

async function renderUsers() {
  if (!usersWired) {
    usersWired = true;
    $("#invite-btn").addEventListener("click", openInvite);
    $("#user-search").addEventListener("input", debounce(drawUsers, 150));
  }
  try {
    [state.staff, state.schedules] = await Promise.all([state.api.staff(), state.api.schedules()]);
  } catch (e) { fail(e); }
  renderPendingBadge();
  drawUsers();
}

function drawUsers() {
  const q = $("#user-search").value.trim().toLowerCase();
  const list = state.staff.filter((u) => !q || `${u.full_name} ${u.email}`.toLowerCase().includes(q));
  const pending = state.staff.filter((u) => !u.is_active);

  $("#pending-users").innerHTML = pending.length ? `
    <div class="pending-card">
      <h2>Solicitudes de acceso (${pending.length})</h2>
      ${pending.map((u) => `<div class="pending-row">
        <div class="person row gap-s"><span class="avatar" style="background:${esc(u.color_hex)}">${esc(initials(u.full_name))}</span>
          <div><strong>${esc(u.full_name)}</strong><span class="muted tiny" style="display:block">${esc(u.email)}</span></div></div>
        <div class="row gap-s">
          <select data-approve-role="${u.id}" aria-label="Rol">${Object.entries(ROLES).map(([k, v]) => `<option value="${k}" ${k === u.role ? "selected" : ""}>${v}</option>`).join("")}</select>
          <button class="btn primary small" data-approve="${u.id}">Aprobar</button>
        </div></div>`).join("")}
    </div>` : "";

  const tbody = $("#users-table tbody");
  tbody.innerHTML = list.length ? list.map((u) => {
    const isMe = u.id === state.me.id;
    const works = u.role === "therapist" || state.schedules.some((s) => s.therapist_id === u.id);
    return `<tr>
      <td><div class="person"><span class="avatar" style="background:${esc(u.color_hex)}">${esc(initials(u.full_name))}</span>
        <div><strong>${esc(u.full_name)}${isMe ? ' <span class="muted tiny">(vos)</span>' : ""}</strong><span class="muted tiny">${esc(u.email)}</span></div></div></td>
      <td><select data-role="${u.id}" ${isMe || !u.is_active ? "disabled" : ""} aria-label="Rol de ${esc(u.full_name)}">
        ${Object.entries(ROLES).map(([k, v]) => `<option value="${k}" ${k === u.role ? "selected" : ""}>${v}</option>`).join("")}</select></td>
      <td>${u.is_active ? '<span class="chip ok">Activo</span>' : '<span class="chip off">Sin acceso</span>'}</td>
      <td>${works ? scheduleSummary(u.id) : '<span class="muted">—</span>'}</td>
      <td><div class="actions">
        ${u.role !== "receptionist" ? `<button class="btn small" data-schedule="${u.id}">Horario</button>` : ""}
        ${isMe ? "" : u.is_active
          ? `<button class="btn small danger" data-toggle="${u.id}">Quitar acceso</button>`
          : `<button class="btn small" data-toggle="${u.id}">Dar acceso</button>`}
      </div></td></tr>`;
  }).join("") : `<tr><td colspan="5" class="empty">Sin resultados</td></tr>`;

  const update = async (u, role, active, msg) => {
    try { await state.api.updateUser(u.id, role, active); toast(msg); await renderUsers(); } catch (e) { fail(e); drawUsers(); }
  };
  $$("[data-approve]").forEach((b) => b.addEventListener("click", () => {
    const u = person(b.dataset.approve);
    const role = $(`[data-approve-role="${u.id}"]`).value;
    update(u, role, true, `${u.full_name} ya puede ingresar como ${ROLES[role]}`);
  }));
  $$("[data-role]").forEach((s) => s.addEventListener("change", async () => {
    const u = person(s.dataset.role);
    const ok = await confirmDialog("Cambiar rol", `${u.full_name}: ${ROLES[u.role]} → ${ROLES[s.value]}`, { ok: "Cambiar rol" });
    if (ok) update(u, s.value, u.is_active, "Rol actualizado"); else s.value = u.role;
  }));
  $$("[data-toggle]").forEach((b) => b.addEventListener("click", async () => {
    const u = person(b.dataset.toggle);
    if (u.is_active) {
      const ok = await confirmDialog("Quitar acceso", `${u.full_name} no podrá ingresar a la app ni al panel. Sus turnos e historial se conservan.`, { ok: "Quitar acceso", danger: true });
      if (ok) update(u, u.role, false, "Acceso desactivado");
    } else {
      update(u, u.role, true, "Acceso habilitado");
    }
  }));
  $$("[data-schedule]").forEach((b) => b.addEventListener("click", () => openSchedule(person(b.dataset.schedule))));
}

function openInvite() {
  openModal("Invitar usuario", `
    <label>Nombre y apellido<input name="full_name" required></label>
    <label>Email<input type="email" name="email" required></label>
    <label>Rol<select name="role">${Object.entries(ROLES).map(([k, v]) => `<option value="${k}" ${k === "therapist" ? "selected" : ""}>${v}</option>`).join("")}</select></label>
    <p class="muted tiny" style="margin:0">Le llega un email para crear su contraseña. Queda activo con el rol elegido.</p>`, {
    submit: "Enviar invitación",
    onSubmit: async (fd) => {
      await state.api.inviteUser({ email: String(fd.get("email")).trim(), full_name: String(fd.get("full_name")).trim(), role: fd.get("role") });
      toast(`Invitación enviada a ${fd.get("email")}`);
      await renderUsers();
    },
  });
}

function openSchedule(u) {
  const rows = state.schedules.filter((s) => s.therapist_id === u.id);
  const multi = new Set(rows.map((r) => r.weekday)).size !== rows.length;
  const order = [1, 2, 3, 4, 5, 6, 0];
  openModal(`Horario de ${u.full_name}`, `
    <p class="muted tiny" style="margin:0">Define los horarios libres que se ofrecen al agendar y la zona sombreada en la agenda.</p>
    ${multi ? `<div class="alert">Este profesional tiene más de una franja en algún día: al guardar se conserva una franja por día.</div>` : ""}
    ${order.map((wd) => {
      const r = rows.find((x) => x.weekday === wd);
      return `<div class="sched-row">
        <label class="check"><input type="checkbox" name="on_${wd}" ${r ? "checked" : ""}> ${WEEKDAYS[wd]}</label>
        <input type="time" name="from_${wd}" value="${r?.start_time?.slice(0, 5) ?? "09:00"}" step="900" aria-label="Desde">
        <input type="time" name="to_${wd}" value="${r?.end_time?.slice(0, 5) ?? "19:00"}" step="900" aria-label="Hasta">
      </div>`;
    }).join("")}
    <div class="row gap-s"><button type="button" class="btn small" data-copy>Copiar lunes a todos los días hábiles</button></div>
    <label>Color en la agenda<input type="color" name="color" value="${esc(u.color_hex || "#7C9A92")}" style="height:40px;padding:4px"></label>`, {
    submit: "Guardar horario",
    onOpen: (f) => $("[data-copy]", f).addEventListener("click", () => {
      for (const wd of [2, 3, 4, 5]) {
        f.elements[`on_${wd}`].checked = f.elements.on_1.checked;
        f.elements[`from_${wd}`].value = f.elements.from_1.value;
        f.elements[`to_${wd}`].value = f.elements.to_1.value;
      }
    }),
    onSubmit: async (fd) => {
      const out = [];
      for (const wd of order) {
        if (fd.get(`on_${wd}`) !== "on") continue;
        const from = fd.get(`from_${wd}`), to = fd.get(`to_${wd}`);
        if (!from || !to || to <= from) throw new Error(`${WEEKDAYS[wd]}: la hora de fin debe ser posterior al inicio.`);
        out.push({ weekday: wd, start_time: from, end_time: to });
      }
      await state.api.saveSchedule(u.id, out);
      if (fd.get("color") !== u.color_hex) await state.api.updateUserColor(u.id, fd.get("color"));
      toast("Horario guardado");
      state.staff = await state.api.staff();
      await renderUsers();
    },
  });
}

// ============================================================================= CLIENTES
let clientsWired = false;
async function renderClients() {
  if (!clientsWired) {
    clientsWired = true;
    $("#client-search").addEventListener("input", debounce(renderClients, 250));
    $("#new-client-btn").addEventListener("click", () => openClientForm({}, () => renderClients()));
  }
  const q = $("#client-search").value;
  let list = [];
  try { list = await state.api.clients(q, 100); } catch (e) { fail(e); }
  $("#clients-count").textContent = q ? `${list.length} resultados` : `${list.length}${list.length === 100 ? "+" : ""} clientes`;
  $("#clients-table tbody").innerHTML = list.length ? list.map((c) => `<tr>
      <td><div class="person"><span class="avatar" style="background:var(--primary)">${esc(initials(`${c.first_name} ${c.last_name}`))}</span>
        <div><strong>${esc(c.first_name)} ${esc(c.last_name)}</strong><span class="muted tiny">${esc(c.email ?? "")}</span></div></div></td>
      <td>${esc(c.dni ?? "—")}</td>
      <td>${esc(c.whatsapp ?? c.phone ?? "—")}</td>
      <td>${c.allergies || c.contraindications ? `<span class="chip warn" title="${esc([c.allergies, c.contraindications].filter(Boolean).join(" · "))}">Salud</span>` : ""}</td>
      <td><div class="actions"><button class="btn small" data-book="${c.id}">Agendar</button><button class="btn small" data-edit="${c.id}">Editar</button></div></td>
    </tr>`).join("") : `<tr><td colspan="5" class="empty">${q ? "Sin resultados" : "Todavía no hay clientes"}</td></tr>`;
  $$("[data-edit]").forEach((b) => b.addEventListener("click", () => openClientForm(list.find((c) => c.id === b.dataset.edit), () => renderClients())));
  $$("[data-book]").forEach((b) => b.addEventListener("click", () => openAppointmentForm({ client: list.find((c) => c.id === b.dataset.book) })));
}

function openClientForm(c, onSaved) {
  const v = (k) => esc(c?.[k] ?? "");
  openModal(c?.id ? "Editar cliente" : "Nuevo cliente", `
    <div class="grid-2">
      <label>Nombre<input name="first_name" required value="${v("first_name")}"></label>
      <label>Apellido<input name="last_name" required value="${v("last_name")}"></label>
      <label>DNI<input name="dni" inputmode="numeric" pattern="[0-9. ]{7,10}" value="${v("dni")}"></label>
      <label>Fecha de nacimiento<input type="date" name="birth_date" value="${v("birth_date")}"></label>
      <label>Teléfono / WhatsApp<input name="phone" type="tel" value="${esc(c?.whatsapp ?? c?.phone ?? "")}"></label>
      <label>Email<input type="email" name="email" value="${v("email")}"></label>
    </div>
    <label>Alergias<input name="allergies" value="${v("allergies")}"></label>
    <label>Contraindicaciones<input name="contraindications" value="${v("contraindications")}"></label>
    <label>Observaciones<textarea name="observations">${v("observations")}</textarea></label>
    <label class="check"><input type="checkbox" name="accepts_reminders" ${c?.accepts_reminders === false ? "" : "checked"}> Acepta recordatorios automáticos</label>`, {
    wide: true,
    submit: c?.id ? "Guardar cambios" : "Crear cliente",
    onSubmit: async (fd) => {
      const clean = (k) => { const x = String(fd.get(k) ?? "").trim(); return x || null; };
      const phone = clean("phone");
      const saved = await state.api.saveClient({
        ...(c?.id ? { id: c.id } : {}),
        first_name: clean("first_name"), last_name: clean("last_name"),
        dni: clean("dni")?.replace(/\D/g, "") ?? null, birth_date: clean("birth_date"),
        phone, whatsapp: phone, email: clean("email")?.toLowerCase() ?? null,
        allergies: clean("allergies"), contraindications: clean("contraindications"), observations: clean("observations"),
        accepts_reminders: fd.get("accepts_reminders") === "on",
      });
      toast(c?.id ? "Cliente actualizado" : "Cliente creado");
      // El callback abre otro modal: se ejecuta después de cerrar este
      setTimeout(() => onSaved?.(saved), 0);
    },
  });
}

// ============================================================================= RESUMEN
async function renderSummary() {
  const today = new Date();
  const from = new Date(today.getFullYear(), today.getMonth(), 1);
  $("#summary-period").textContent = `Del ${from.getDate()} al ${today.getDate()} de ${new Intl.DateTimeFormat("es-AR", { month: "long", year: "numeric" }).format(today)}`;
  $("#kpis").innerHTML = `<div class="kpi"><span>Cargando…</span><strong>—</strong></div>`;
  let s;
  try { s = await state.api.dashboard(ymd(from), ymd(today)); } catch (e) { return fail(e); }
  const kpi = (label, value) => `<div class="kpi"><span>${label}</span><strong>${value}</strong></div>`;
  $("#kpis").innerHTML = [
    kpi("Turnos de hoy", s.today_appointments ?? 0),
    kpi("Facturación de hoy", money(s.revenue_today)),
    kpi("Facturación del mes", money(s.revenue_period)),
    kpi("Clientes nuevos", s.new_clients ?? 0),
    kpi("Clientes activos (90 días)", s.active_clients ?? 0),
    kpi("Tasa de cancelación", `${Number(s.cancellation_rate ?? 0).toFixed(1)} %`),
    kpi("Ausentismo", `${Number(s.no_show_rate ?? 0).toFixed(1)} %`),
    kpi("Turnos con saldo pendiente", s.pending_payments ?? 0),
  ].join("");

  const top = s.top_services ?? [];
  const max = Math.max(1, ...top.map((t) => t.count));
  $("#top-services").innerHTML = top.length ? top.map((t) => `<div class="bar-row"><span>${esc(t.name)}</span>
      <strong>${t.count} · ${money(t.revenue)}</strong><div class="bar"><i style="width:${(t.count / max) * 100}%"></i></div></div>`).join("")
    : `<p class="muted">Sin turnos completados este mes.</p>`;

  const hours = s.peak_hours ?? [];
  const hmax = Math.max(1, ...hours.map((h) => h.count));
  $("#peak-hours").innerHTML = hours.length ? `<div class="hours-chart">${hours.sort((a, b) => a.hour - b.hour).map((h) =>
      `<div title="${h.count} turnos"><i class="${h.count === hmax ? "peak" : ""}" style="height:${(h.count / hmax) * 100}%"></i>${h.hour}h</div>`).join("")}</div>`
    : `<p class="muted">Sin datos todavía.</p>`;
}

boot();
