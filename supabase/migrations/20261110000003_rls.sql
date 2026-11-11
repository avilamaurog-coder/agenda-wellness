-- =============================================================================
-- Agenda Wellness · Migración 0003 · Row Level Security
-- =============================================================================
-- Matriz de permisos (resumen)
-- ┌──────────────────────┬──────────────┬───────────────┬──────────────────────┐
-- │ Recurso              │ Admin        │ Recepcionista │ Profesional          │
-- ├──────────────────────┼──────────────┼───────────────┼──────────────────────┤
-- │ Clientes             │ CRUD         │ CRU           │ R (solo sus clientes)│
-- │ Turnos               │ CRUD         │ CRU           │ R/U (solo propios)   │
-- │ Servicios / combos   │ CRUD         │ R             │ R                    │
-- │ Precios (historial)  │ R            │ R             │ —                    │
-- │ Pagos                │ CRUD         │ CR            │ R (de sus turnos)    │
-- │ Historia clínica     │ CRUD         │ —             │ CRU (sus clientes)   │
-- │ Plantillas mensajes  │ CRUD         │ R             │ —                    │
-- │ Usuarios / roles     │ CRUD         │ R             │ R                    │
-- │ Reportes / dashboard │ ✓            │ ✓ (sin $ mes) │ solo propios         │
-- └──────────────────────┴──────────────┴───────────────┴──────────────────────┘
-- La recepción NO ve historia clínica (datos de salud) por diseño.
-- =============================================================================

do $$
declare t text;
begin
  foreach t in array array[
    'centers','profiles','therapist_schedules','schedule_blocks','clients',
    'service_categories','services','service_therapists','service_price_history',
    'combos','combo_items','promotions','appointments','appointment_events',
    'payments','clinical_records','clinical_photos','message_templates',
    'appointment_reminders','internal_notifications','audit_log'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
  end loop;
end $$;

-- ---------------------------------------------------------------- centers
create policy centers_select on public.centers for select to authenticated
  using (id = public.current_center_id());
create policy centers_update on public.centers for update to authenticated
  using (id = public.current_center_id() and public.is_admin())
  with check (id = public.current_center_id());

-- ---------------------------------------------------------------- profiles
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or center_id = public.current_center_id());
create policy profiles_update_self on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
create policy profiles_update_admin on public.profiles for update to authenticated
  using (center_id = public.current_center_id() and public.is_admin())
  with check (center_id = public.current_center_id());

-- ---------------------------------------------------------------- horarios y bloqueos
create policy schedules_select on public.therapist_schedules for select to authenticated
  using (exists (select 1 from public.profiles p where p.id = therapist_id and p.center_id = public.current_center_id()));
create policy schedules_write on public.therapist_schedules for all to authenticated
  using (public.is_admin() or therapist_id = auth.uid())
  with check ((public.is_admin() and exists (select 1 from public.profiles p where p.id = therapist_id and p.center_id = public.current_center_id()))
              or therapist_id = auth.uid());

create policy blocks_select on public.schedule_blocks for select to authenticated
  using (center_id = public.current_center_id());
create policy blocks_write on public.schedule_blocks for all to authenticated
  using (center_id = public.current_center_id() and (public.is_front_desk() or therapist_id = auth.uid()))
  with check (center_id = public.current_center_id() and (public.is_front_desk() or therapist_id = auth.uid()));

-- ---------------------------------------------------------------- clientes
create policy clients_select on public.clients for select to authenticated
  using (center_id = public.current_center_id()
         and (public.is_front_desk() or public.therapist_has_client(id)));
create policy clients_insert on public.clients for insert to authenticated
  with check (center_id = public.current_center_id() and public.is_front_desk());
create policy clients_update on public.clients for update to authenticated
  using (center_id = public.current_center_id() and public.is_front_desk())
  with check (center_id = public.current_center_id());
create policy clients_delete on public.clients for delete to authenticated
  using (center_id = public.current_center_id() and public.is_admin());

-- ---------------------------------------------------------------- catálogo
create policy categories_select on public.service_categories for select to authenticated
  using (center_id = public.current_center_id());
create policy categories_write on public.service_categories for all to authenticated
  using (center_id = public.current_center_id() and public.is_admin())
  with check (center_id = public.current_center_id() and public.is_admin());

create policy services_select on public.services for select to authenticated
  using (center_id = public.current_center_id());
create policy services_write on public.services for all to authenticated
  using (center_id = public.current_center_id() and public.is_admin())
  with check (center_id = public.current_center_id() and public.is_admin());

create policy service_therapists_select on public.service_therapists for select to authenticated
  using (exists (select 1 from public.services s where s.id = service_id and s.center_id = public.current_center_id()));
create policy service_therapists_write on public.service_therapists for all to authenticated
  using (public.is_admin() and exists (select 1 from public.services s where s.id = service_id and s.center_id = public.current_center_id()))
  with check (public.is_admin() and exists (select 1 from public.services s where s.id = service_id and s.center_id = public.current_center_id()));

create policy price_history_select on public.service_price_history for select to authenticated
  using (public.is_front_desk() and exists (select 1 from public.services s where s.id = service_id and s.center_id = public.current_center_id()));

create policy combos_select on public.combos for select to authenticated
  using (center_id = public.current_center_id());
create policy combos_write on public.combos for all to authenticated
  using (center_id = public.current_center_id() and public.is_admin())
  with check (center_id = public.current_center_id() and public.is_admin());

create policy combo_items_select on public.combo_items for select to authenticated
  using (exists (select 1 from public.combos c where c.id = combo_id and c.center_id = public.current_center_id()));
create policy combo_items_write on public.combo_items for all to authenticated
  using (public.is_admin() and exists (select 1 from public.combos c where c.id = combo_id and c.center_id = public.current_center_id()))
  with check (public.is_admin() and exists (select 1 from public.combos c where c.id = combo_id and c.center_id = public.current_center_id()));

create policy promotions_select on public.promotions for select to authenticated
  using (center_id = public.current_center_id());
create policy promotions_write on public.promotions for all to authenticated
  using (center_id = public.current_center_id() and public.is_admin())
  with check (center_id = public.current_center_id() and public.is_admin());

-- ---------------------------------------------------------------- turnos
create policy appointments_select on public.appointments for select to authenticated
  using (center_id = public.current_center_id()
         and (public.is_front_desk() or therapist_id = auth.uid()));
create policy appointments_insert on public.appointments for insert to authenticated
  with check (center_id = public.current_center_id() and public.is_front_desk());
create policy appointments_update on public.appointments for update to authenticated
  using (center_id = public.current_center_id()
         and (public.is_front_desk() or therapist_id = auth.uid()))
  with check (center_id = public.current_center_id()
              and (public.is_front_desk() or therapist_id = auth.uid()));
create policy appointments_delete on public.appointments for delete to authenticated
  using (center_id = public.current_center_id() and public.is_admin());

create policy appointment_events_select on public.appointment_events for select to authenticated
  using (exists (select 1 from public.appointments a where a.id = appointment_id)); -- hereda RLS de appointments

-- ---------------------------------------------------------------- pagos
create policy payments_select on public.payments for select to authenticated
  using (center_id = public.current_center_id()
         and (public.is_front_desk()
              or exists (select 1 from public.appointments a where a.id = appointment_id and a.therapist_id = auth.uid())));
create policy payments_insert on public.payments for insert to authenticated
  with check (center_id = public.current_center_id() and public.is_front_desk());
create policy payments_update on public.payments for update to authenticated
  using (center_id = public.current_center_id() and public.is_admin())
  with check (center_id = public.current_center_id());
create policy payments_delete on public.payments for delete to authenticated
  using (center_id = public.current_center_id() and public.is_admin());

-- ---------------------------------------------------------------- historia clínica
create policy clinical_select on public.clinical_records for select to authenticated
  using (exists (select 1 from public.clients c where c.id = client_id and c.center_id = public.current_center_id())
         and (public.is_admin() or public.therapist_has_client(client_id)));
create policy clinical_insert on public.clinical_records for insert to authenticated
  with check (exists (select 1 from public.clients c where c.id = client_id and c.center_id = public.current_center_id())
              and (public.is_admin() or (public.therapist_has_client(client_id) and therapist_id = auth.uid())));
create policy clinical_update on public.clinical_records for update to authenticated
  using (public.is_admin() or therapist_id = auth.uid())
  with check (public.is_admin() or therapist_id = auth.uid());
create policy clinical_delete on public.clinical_records for delete to authenticated
  using (public.is_admin());

create policy clinical_photos_select on public.clinical_photos for select to authenticated
  using (exists (select 1 from public.clinical_records r where r.id = record_id)); -- hereda RLS
create policy clinical_photos_write on public.clinical_photos for all to authenticated
  using (exists (select 1 from public.clinical_records r where r.id = record_id
                 and (public.is_admin() or r.therapist_id = auth.uid())))
  with check (exists (select 1 from public.clinical_records r where r.id = record_id
                      and (public.is_admin() or r.therapist_id = auth.uid())));

-- ---------------------------------------------------------------- mensajería
create policy templates_select on public.message_templates for select to authenticated
  using (center_id = public.current_center_id() and public.is_front_desk());
create policy templates_write on public.message_templates for all to authenticated
  using (center_id = public.current_center_id() and public.is_admin())
  with check (center_id = public.current_center_id() and public.is_admin());

create policy reminders_select on public.appointment_reminders for select to authenticated
  using (public.is_front_desk() and exists (select 1 from public.appointments a where a.id = appointment_id));

create policy notifications_select on public.internal_notifications for select to authenticated
  using (center_id = public.current_center_id() and (user_id is null or user_id = auth.uid()));
create policy notifications_update on public.internal_notifications for update to authenticated
  using (center_id = public.current_center_id() and (user_id is null or user_id = auth.uid()))
  with check (center_id = public.current_center_id());

-- ---------------------------------------------------------------- auditoría
create policy audit_select on public.audit_log for select to authenticated
  using (public.is_admin());

-- ---------------------------------------------------------------- privilegios
revoke all on all tables in schema public from anon;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
