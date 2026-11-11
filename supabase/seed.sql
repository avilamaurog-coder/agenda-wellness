-- =============================================================================
-- Agenda Wellness · Datos iniciales
-- Precios de EJEMPLO en ARS: ajustar desde la app (Servicios › Editar).
-- El primer usuario que se registre queda como Administrador de este centro.
-- =============================================================================

insert into public.centers (id, name, phone, email, address, opening_time, closing_time, slot_minutes)
values ('00000000-0000-0000-0000-000000000001', 'Agenda Wellness Spa', '+54 9 376 400-0000',
        'hola@agendawellness.com', 'Posadas, Misiones', '09:00', '21:00', 15)
on conflict (id) do nothing;

-- Categorías
insert into public.service_categories (id, center_id, name, icon, sort_order) values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Masajes',                    'spa',            1),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'Estética Facial',            'face_retouching_natural', 2),
  ('10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 'Tratamientos Complementarios','self_improvement', 3)
on conflict do nothing;

-- Servicios
insert into public.services (id, center_id, category_id, name, description, duration_minutes, buffer_minutes, price, color_hex) values
  ('20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
   'Masaje Descontracturante','Trabajo profundo sobre contracturas de espalda, cuello y hombros.',60,10,28000,'#8FA998'),
  ('20000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
   'Masaje Relajante','Maniobras suaves y envolventes para reducir el estrés.',60,10,25000,'#A8C3B8'),
  ('20000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
   'Drenaje Linfático','Técnica manual que estimula el sistema linfático y reduce la retención de líquidos.',60,10,30000,'#9DB4C0'),
  ('20000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
   'Masaje Deportivo','Preparación y recuperación muscular para deportistas.',50,10,28000,'#7E9C8C'),
  ('20000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
   'Masaje Exfoliante','Exfoliación corporal con hidratación final.',60,15,32000,'#C9B79C'),
  ('20000000-0000-0000-0000-000000000006','00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
   'Masaje de Cuerpo Completo','Masaje integral de pies a cabeza.',90,15,38000,'#6F8F7F'),
  ('20000000-0000-0000-0000-000000000007','00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002',
   'Tratamiento Facial','Tratamiento personalizado según biotipo cutáneo.',60,10,30000,'#D4A5A5'),
  ('20000000-0000-0000-0000-000000000008','00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002',
   'Yoga Facial','Ejercicios y masaje facial para tonificar y relajar.',45,10,20000,'#E3B5A4'),
  ('20000000-0000-0000-0000-000000000009','00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002',
   'Limpieza de Cutis','Limpieza profunda, extracción e hidratación.',60,10,26000,'#E8C7B7'),
  ('20000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003',
   'Electrodos','Electroestimulación muscular complementaria.',30,5,15000,'#B5A8C9'),
  ('20000000-0000-0000-0000-000000000011','00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003',
   'Reflexología','Estimulación de puntos reflejos en pies.',45,10,22000,'#A3A3C2')
on conflict do nothing;

-- Combos
insert into public.combos (id, center_id, name, description, price) values
  ('30000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','Combo Relax',
   'Masaje Relajante + Yoga Facial', 40000),
  ('30000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001','Combo Premium',
   'Masaje Cuerpo Completo + Tratamiento Facial + Reflexología', 78000)
on conflict do nothing;

insert into public.combo_items (combo_id, service_id, sort_order) values
  ('30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002',1),
  ('30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000008',2),
  ('30000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000006',1),
  ('30000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000007',2),
  ('30000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000011',3)
on conflict do nothing;

-- Plantillas de recordatorio
insert into public.message_templates (center_id, channel, hours_before, subject, body) values
  ('00000000-0000-0000-0000-000000000001','whatsapp',48,null,
   'Hola {{nombre}} 🌿 Te recordamos tu turno para {{servicio}} el día {{fecha}} a las {{hora}} hs con {{profesional}}. Respondé SI para confirmar o escribinos si necesitás reprogramar.'),
  ('00000000-0000-0000-0000-000000000001','whatsapp',24,null,
   'Hola {{nombre}}, te recordamos tu turno para {{servicio}} el día {{fecha}} a las {{hora}} hs.'),
  ('00000000-0000-0000-0000-000000000001','whatsapp',2,null,
   '¡Hola {{nombre}}! Te esperamos hoy a las {{hora}} hs en {{centro}} para tu {{servicio}}. 💆'),
  ('00000000-0000-0000-0000-000000000001','email',48,'Recordatorio de tu turno · {{centro}}',
   'Hola {{nombre}},\n\nTe recordamos tu turno para {{servicio}} el día {{fecha}} a las {{hora}} hs con {{profesional}}.\n\nSi necesitás cancelar o reprogramar, respondé este correo.\n\n{{centro}}'),
  ('00000000-0000-0000-0000-000000000001','email',24,'Mañana te esperamos · {{centro}}',
   'Hola {{nombre}},\n\nTe esperamos mañana {{fecha}} a las {{hora}} hs para tu {{servicio}}.\n\n{{centro}}'),
  ('00000000-0000-0000-0000-000000000001','push',2,'Turno en 2 horas',
   '{{nombre}} · {{servicio}} a las {{hora}} hs')
on conflict do nothing;

-- Plantillas de Telegram (incluyen botones Confirmar / Reprogramar / Cancelar)
insert into public.message_templates (center_id, channel, hours_before, subject, body) values
  ('00000000-0000-0000-0000-000000000001','telegram',48,null,
   '🌿 Hola {{nombre}}! Te recordamos tu turno de {{servicio}} el {{fecha}} a las {{hora}} hs con {{profesional}}. ¿Nos confirmás tu asistencia?'),
  ('00000000-0000-0000-0000-000000000001','telegram',24,null,
   'Hola {{nombre}}, mañana {{fecha}} a las {{hora}} hs te esperamos para tu {{servicio}}.'),
  ('00000000-0000-0000-0000-000000000001','telegram',2,null,
   '¡Hola {{nombre}}! Te esperamos hoy a las {{hora}} hs en {{centro}} 💆')
on conflict do nothing;

-- Vitrina: productos y publicación de ejemplo (editar o borrar desde la app)
insert into public.products (center_id, name, description, category, price, stock, is_featured, sort_order) values
  ('00000000-0000-0000-0000-000000000001','Aceite de masaje relajante 250 ml','Lavanda y almendras, ideal para uso en casa.','Corporal',12000,10,true,1),
  ('00000000-0000-0000-0000-000000000001','Crema hidratante facial','Ácido hialurónico, todo tipo de piel.','Facial',18000,8,false,2),
  ('00000000-0000-0000-0000-000000000001','Gift card Relax','Regalá una sesión de Masaje Relajante.','Regalos',25000,null,true,3)
on conflict do nothing;

insert into public.promo_posts (center_id, title, body, combo_id, cta_label, is_featured) values
  ('00000000-0000-0000-0000-000000000001','Combo Relax de la semana',
   'Masaje Relajante + Yoga Facial a precio especial. ¡Cupos limitados!',
   '30000000-0000-0000-0000-000000000001','Reservar por WhatsApp',true)
on conflict do nothing;
