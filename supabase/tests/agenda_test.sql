-- Tests de base de datos (pgTAP) · ejecutar con:  supabase test db
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

-- Usuarios de prueba (el primero queda admin por el trigger handle_new_user)
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, instance_id, aud, role)
values
  ('a0000000-0000-0000-0000-000000000001', 'admin@test.com',   '{"full_name":"Admin"}',   '{}', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('a0000000-0000-0000-0000-000000000002', 'tera@test.com',    '{"full_name":"Laura"}',   '{}', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('a0000000-0000-0000-0000-000000000003', 'recep@test.com',   '{"full_name":"Recepción"}','{}', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');

select is((select role::text from public.profiles where email = 'admin@test.com'), 'admin', 'El primer usuario es administrador');
select is((select is_active from public.profiles where email = 'tera@test.com'), false, 'Los siguientes quedan pendientes de aprobación');

update public.profiles set is_active = true, role = 'therapist'    where email = 'tera@test.com';
update public.profiles set is_active = true, role = 'receptionist' where email = 'recep@test.com';

insert into public.clients (id, center_id, first_name, last_name, dni, phone, email)
values ('c0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Ana', 'Pérez', '30123456',
        '3764000000', 'ana@test.com');

-- Turno base: en 3 días 10:00 con Laura, Masaje Relajante (60 min)
insert into public.appointments (id, center_id, client_id, therapist_id, service_id, starts_at)
values ('e0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
        'c0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000002',
        '20000000-0000-0000-0000-000000000002', date_trunc('day', now()) + interval '3 days 10 hours');

select is((select ends_at - starts_at from public.appointments where id = 'e0000000-0000-0000-0000-000000000001'),
          interval '60 minutes', 'ends_at se calcula desde la duración del servicio');
select is((select price from public.appointments where id = 'e0000000-0000-0000-0000-000000000001'),
          25000.00::numeric, 'El precio se toma del catálogo');
select is((select count(*)::int from public.appointment_reminders where appointment_id = 'e0000000-0000-0000-0000-000000000001'),
          6, 'Se programan recordatorios (WhatsApp 48/24/2 h + email 48/24 h + push 2 h)');

-- Solapamiento
select throws_ok($$
  insert into public.appointments (center_id, client_id, therapist_id, service_id, starts_at)
  values ('00000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001',
          'a0000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001',
          date_trunc('day', now()) + interval '3 days 10 hours 30 minutes')
$$, '23P01', null, 'No se permiten turnos superpuestos para el mismo profesional');

-- RLS: la recepción no ve historia clínica
insert into public.clinical_records (client_id, therapist_id, evaluation)
values ('c0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000002', 'Contractura cervical');

set local role authenticated;
set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select is((select count(*)::int from public.clinical_records), 0, 'Recepción no accede a fichas clínicas');

set local request.jwt.claims = '{"sub":"a0000000-0000-0000-0000-000000000002","role":"authenticated"}';
select is((select count(*)::int from public.clinical_records), 1, 'El profesional ve las fichas de sus clientes');

select * from finish();
rollback;
