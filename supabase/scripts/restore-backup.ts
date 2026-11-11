// =============================================================================
// Restaura un backup de Agenda Wellness en un proyecto Supabase.
//
// Uso (Deno):
//   SUPABASE_URL=https://<ref>.supabase.co \
//   SUPABASE_SERVICE_ROLE_KEY=<service_role> \
//   BACKUP_ENCRYPTION_KEY=<clave usada al crear el backup>   # si el archivo termina en .enc
//   deno run -A supabase/scripts/restore-backup.ts agenda-wellness-2026-11-10-06-00.zip.enc [--dry-run]
//
// Antes de restaurar en un proyecto nuevo:
//   1. Aplicar las migraciones (supabase db push).
//   2. Recrear los usuarios del staff (auth/users.json trae id y email): invitarlos con el MISMO id
//      vía Admin API, o restaurar sin `profiles` y volver a invitar.
// Las filas se insertan con upsert por id: es seguro correrlo más de una vez.
// =============================================================================
import { createClient } from "jsr:@supabase/supabase-js@2";
import { unzipSync, strFromU8 } from "npm:fflate@0.8.2";

const file = Deno.args.find((a) => !a.startsWith("--"));
const dryRun = Deno.args.includes("--dry-run");
if (!file) {
  console.error("Indicá el archivo de backup");
  Deno.exit(1);
}

let data = await Deno.readFile(file);

if (new TextDecoder().decode(data.slice(0, 4)) === "AWB1") {
  const pass = Deno.env.get("BACKUP_ENCRYPTION_KEY");
  if (!pass) throw new Error("El backup está cifrado: definí BACKUP_ENCRYPTION_KEY");
  const salt = data.slice(4, 20), iv = data.slice(20, 32), cipher = data.slice(32);
  const base = await crypto.subtle.importKey("raw", new TextEncoder().encode(pass), "PBKDF2", false, ["deriveKey"]);
  const key = await crypto.subtle.deriveKey(
    { name: "PBKDF2", salt, iterations: 210_000, hash: "SHA-256" }, base,
    { name: "AES-GCM", length: 256 }, false, ["decrypt"],
  );
  data = new Uint8Array(await crypto.subtle.decrypt({ name: "AES-GCM", iv }, key, cipher));
  console.log("🔓 Backup descifrado");
}

const zip = unzipSync(data);
const manifest = JSON.parse(strFromU8(zip["manifest.json"]));
console.log(`📦 Backup del ${manifest.created_at}`, manifest.tables);

// Columnas generadas: no se pueden insertar
const GENERATED: Record<string, string[]> = {
  clients: ["search_vector"],
  appointments: ["final_price"],
};
const ORDER = [
  "centers", "profiles", "therapist_schedules", "schedule_blocks", "clients",
  "service_categories", "services", "service_therapists", "service_price_history",
  "combos", "combo_items", "promotions", "products", "promo_posts",
  "appointments", "appointment_events", "payments",
  "clinical_records", "clinical_photos", "message_templates",
  "appointment_reminders", "internal_notifications", "backups",
];
const CONFLICT: Record<string, string> = {
  service_therapists: "service_id,therapist_id",
  combo_items: "combo_id,service_id",
};

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

for (const table of ORDER) {
  const entry = zip[`data/${table}.json`];
  if (!entry) continue;
  // deno-lint-ignore no-explicit-any
  let rows: any[] = JSON.parse(strFromU8(entry));
  const drop = GENERATED[table] ?? [];
  rows = rows.map((r) => Object.fromEntries(Object.entries(r).filter(([k]) => !drop.includes(k))));

  // Turnos con auto-referencia: primero sin rescheduled_from_id, luego se completa
  const selfRefs = table === "appointments" ? rows.filter((r) => r.rescheduled_from_id) : [];
  if (table === "appointments") rows = rows.map((r) => ({ ...r, rescheduled_from_id: null }));

  console.log(`${dryRun ? "[simulación] " : ""}${table}: ${rows.length} filas`);
  if (dryRun || rows.length === 0) continue;

  for (let i = 0; i < rows.length; i += 500) {
    const { error } = await db.from(table).upsert(rows.slice(i, i + 500), { onConflict: CONFLICT[table] ?? "id" });
    if (error) {
      console.error(`  ✗ ${table}: ${error.message}`);
      break;
    }
  }
  for (const r of selfRefs) {
    await db.from("appointments").update({ rescheduled_from_id: r.rescheduled_from_id }).eq("id", r.id);
  }
}

// Fotos clínicas incluidas en el backup
const photos = Object.keys(zip).filter((k) => k.startsWith("storage/clinical-photos/"));
for (const key of photos) {
  const path = key.replace("storage/clinical-photos/", "");
  if (!dryRun) {
    await db.storage.from("clinical-photos").upload(path, zip[key], { upsert: true, contentType: "image/jpeg" });
  }
}
if (photos.length) console.log(`🖼  ${photos.length} fotos clínicas ${dryRun ? "detectadas" : "restauradas"}`);
console.log("✅ Restauración finalizada");
