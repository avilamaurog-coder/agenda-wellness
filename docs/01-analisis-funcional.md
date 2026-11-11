# 1. Análisis funcional

## 1.1 Contexto y objetivo

Agenda Wellness es una aplicación móvil (Android + iOS) para que el **staff** de un centro de estética, bienestar y masoterapia gestione su operación diaria: clientes, agenda, catálogo, precios, cobros, fichas clínicas, recordatorios y reportes.

El cliente final **no usa la app**: recibe recordatorios por WhatsApp o email. Esto simplifica la seguridad (solo usuarios internos autenticados) y deja la puerta abierta a una futura app/portal de reservas online.

## 1.2 Actores y roles

| Rol | Quién es | Objetivo principal |
|---|---|---|
| **Administrador** | Dueño/a o encargado/a | Configurar el centro, precios, equipo; ver facturación y reportes |
| **Recepcionista** | Atención al público | Agendar, reprogramar, cancelar, cobrar, cargar clientes |
| **Profesional / Terapeuta** | Masajista, cosmetóloga | Ver su agenda, confirmar asistencia, registrar evolución clínica |
| *Sistema* | Procesos automáticos | Enviar recordatorios, marcar ausencias, alertas internas |

### Matriz de permisos

| Funcionalidad | Admin | Recepción | Profesional |
|---|:-:|:-:|:-:|
| Ver/crear/editar clientes | ✅ | ✅ | 👁 solo sus clientes |
| Archivar clientes | ✅ | — | — |
| Crear turnos / reprogramar (incl. arrastrar) | ✅ | ✅ | — |
| Cambiar estado (confirmar, completar, ausente) | ✅ | ✅ | ✅ solo propios |
| Cancelar turnos | ✅ | ✅ | — |
| Catálogo, precios, combos, promociones | ✅ | 👁 | 👁 |
| Historial de precios | ✅ | ✅ | — |
| Registrar pagos | ✅ | ✅ | — |
| Ver facturación / reportes | ✅ | ✅ | — |
| Historia clínica y fotos | ✅ | — | ✅ sus clientes |
| Plantillas de recordatorio | ✅ | 👁 | — |
| Equipo, roles, aprobaciones | ✅ | — | — |

> La recepción **no accede a la historia clínica** (datos de salud sensibles, Ley 26.529 de Derechos del Paciente y Ley 25.326 de Protección de Datos Personales). Sí ve **alergias y contraindicaciones** en la ficha del cliente, porque son necesarias para agendar con seguridad.

Los permisos se aplican en **dos capas**: la UI oculta acciones no permitidas (`AppUser.can*`) y la base de datos las **impide** con Row Level Security. La UI es comodidad; RLS es la garantía.

## 1.3 Módulos y casos de uso

### M1 · Autenticación y seguridad
| CU | Descripción | Reglas |
|---|---|---|
| CU-01 | Iniciar sesión con email y contraseña | Usuarios inactivos no ingresan (mensaje "pendiente de aprobación") |
| CU-02 | Registrarse | El **primer** usuario del sistema queda como Administrador. Los demás quedan inactivos hasta aprobación |
| CU-03 | Recuperar contraseña | Enlace por email → deep link `agendawellness://auth-callback` → pantalla "Nueva contraseña" |
| CU-04 | Invitar miembro del equipo (admin) | Edge Function `invite-user`; el rol viaja en `app_metadata` (no editable por el usuario) |
| CU-05 | Aprobar / cambiar rol / desactivar (admin) | Un admin no puede quitarse su propio rol ni desactivarse |

Contraseña: mínimo 8 caracteres con mayúsculas, minúsculas y dígitos. Sesión con PKCE, refresh token rotativo.

### M2 · Clientes
| CU | Descripción |
|---|---|
| CU-10 | Alta de cliente (nombre, apellido, DNI, teléfono, WhatsApp, email, nacimiento, dirección, observaciones, alergias, contraindicaciones, notas internas, consentimiento de recordatorios y canal preferido) |
| CU-11 | Búsqueda por nombre, apellido, DNI, teléfono o email con scroll infinito |
| CU-12 | Ficha del cliente: resumen, alertas de salud, contacto directo (WhatsApp/llamar/email) |
| CU-13 | Historial: turnos, asistencias, cancelaciones, ausencias, gasto acumulado, próximo turno |
| CU-14 | Editar / archivar (baja lógica: se conserva historial y pagos) |

Reglas: DNI único por centro; email válido; alerta visible (ícono naranja) si hay alergias o contraindicaciones, también al momento de agendar.

### M3 · Agenda de turnos
| CU | Descripción |
|---|---|
| CU-20 | Ver agenda **diaria** (columna por profesional), **semanal** (columna por día) y **mensual** (calendario con indicadores por estado) |
| CU-21 | Crear turno: cliente, servicio o combo, profesional, fecha/hora (con sugerencia de huecos libres), descuento, notas, confirmado sí/no |
| CU-22 | **Arrastrar y soltar** un turno a otra franja u otro profesional (mantener presionado → mover → confirmar) |
| CU-23 | Reprogramar desde el detalle (fecha + hora) |
| CU-24 | Cancelar con motivo obligatorio → sugerencia automática de huecos para reprogramar |
| CU-25 | Cambiar estado: Pendiente → Confirmado → Completado / Ausente |
| CU-26 | Filtrar por profesional; ocultar/mostrar cancelados |

**Estados y colores**

| Estado | Color | Ícono | Transiciones permitidas |
|---|---|---|---|
| Pendiente | Ámbar `#E0A245` | reloj | → Confirmado, Completado, Ausente, Cancelado |
| Confirmado | Verde azulado `#4F8A8B` | check | → Pendiente, Completado, Ausente, Cancelado |
| Completado | Verde `#5F9A62` | tarea | (final) |
| Cancelado | Rojo suave `#C0605F` | cruz | (final) |
| Ausente | Gris violáceo `#8C879B` | persona tachada | → Completado (llegó tarde) |

**Reglas de negocio de la agenda**

1. Un profesional **no puede tener dos turnos activos superpuestos** (restricción `EXCLUDE` en PostgreSQL; imposible de saltear desde la app).
2. No se agenda sobre **bloqueos** (vacaciones, feriados, licencias).
3. `ends_at` se calcula desde la duración del servicio (o suma del combo); el precio se toma del catálogo (promo vigente si existe) salvo que se indique otro.
4. Al reprogramar un turno confirmado vuelve a **Pendiente** (hay que reconfirmar) y se **regeneran los recordatorios**.
5. Tras 3 reprogramaciones se exige un motivo.
6. Turnos activos que terminaron hace más de 3 h sin cerrarse pasan automáticamente a **Ausente**.
7. Cada cambio queda en la bitácora `appointment_events` (quién, cuándo, de qué estado/horario a cuál, motivo).

### M4 · Catálogo de servicios
Categorías iniciales: **Masajes** (Descontracturante, Relajante, Drenaje Linfático, Deportivo, Exfoliante, Cuerpo Completo), **Estética Facial** (Tratamiento Facial, Yoga Facial, Limpieza de Cutis), **Complementarios** (Electrodos, Reflexología).

Cada servicio: nombre, descripción, duración, tiempo de preparación entre turnos, precio, precio promocional (con vencimiento opcional), imagen, color en agenda, profesionales habilitados (si no se elige ninguno, todos pueden), activo/inactivo.

### M5 · Precios, promociones y combos
- Cambios de precio y promo quedan en **`service_price_history`** automáticamente (trigger), con usuario y fecha.
- **Promociones**: % o monto fijo, por servicio o generales, con vigencia, código opcional y tope de usos.
- **Combos**: precio cerrado; la app muestra el ahorro frente a la suma de servicios. Seed: *Combo Relax* (Relajante + Yoga Facial) y *Combo Premium* (Cuerpo Completo + Facial + Reflexología).
- **Descuento manual** por turno (validado: no puede superar el precio).

> Estado en el código inicial: precio promocional por servicio, historial de precios, descuento manual y reserva de combos están implementados en la app. Las tablas `promotions` y `combos` ya tienen esquema, RLS y seed; las **pantallas de alta/edición de promociones y combos** quedan como siguiente iteración (se administran desde el Table Editor de Supabase mientras tanto).

### M6 · Recordatorios automáticos
- Canales: **WhatsApp** (Meta Cloud API), **Email** (Resend), **Push** (FCM, dirigido al profesional).
- Momentos: **48 h, 24 h y 2 h** antes. Se programan al crear/reprogramar y se anulan al cancelar/completar.
- **Plantillas editables** por canal y anticipación con variables `{{nombre}} {{servicio}} {{fecha}} {{hora}} {{profesional}} {{centro}}`.
- Respeta el consentimiento del cliente (`accepts_reminders`).
- Reintentos: hasta 3; estado por recordatorio (programado, enviado, fallido, omitido).

> WhatsApp exige plantillas **pre-aprobadas por Meta** para mensajes iniciados por el negocio. El sistema usa una plantilla genérica `recordatorio_turno` con un parámetro de texto, y el contenido editable vive en la app.

### M7 · Cancelaciones y reprogramaciones
Se registra fecha, motivo y usuario responsable. Estadísticas de cancelaciones, reprogramaciones y ausencias en dashboard y reporte. **Reprogramación automática**: al cancelar, `suggest_reschedule` propone los próximos huecos libres priorizando el mismo profesional y franja horaria; un toque crea el nuevo turno.

### M8 · Historia clínica y fichas
Evaluaciones con fecha, profesional, evaluación, objetivos del tratamiento, evolución, observaciones, escala de dolor (0-10) y **fotos de seguimiento** en bucket privado (URLs firmadas de 10 min). Visible solo para admin y profesionales que atendieron al cliente.

### M9 · Dashboard gerencial
Turnos de hoy, facturación del día y del período, clientes nuevos, clientes activos (90 días), servicios más y menos vendidos, horarios con mayor demanda, tasa de cancelación y ausentismo, pagos pendientes, cobros por medio de pago, gráfico de facturación diaria. Períodos: 7 días, mes en curso, 90 días, año.

### M10 · Reportes
Ventas, Turnos, Servicios, Clientes y Cancelaciones, agrupables por **día, semana, mes o año**, con rango libre. Exportación a **PDF** (con fila de totales) y **Excel (.xlsx)**.

### M11 · Notificaciones internas
Campana en tiempo real: turno en 30 min (al profesional), cliente nuevo, cancelación (al profesional), usuario pendiente de aprobación, pago pendiente.

### M12 · Pagos
Medios: efectivo, transferencia, tarjeta, Mercado Pago (registro manual con nº de operación). Pagos parciales; saldo por turno; historial por cliente; anulación solo por admin.

## 1.4 Requerimientos no funcionales

| Categoría | Requerimiento |
|---|---|
| Seguridad | RLS en el 100% de las tablas; sin secretos de servidor en la app; bucket clínico privado; auditoría de tablas sensibles |
| Privacidad | Consentimiento de recordatorios; baja lógica; datos de salud segregados por rol |
| Rendimiento | Agenda diaria < 500 ms (vista indexada por centro+fecha); listados paginados de 30 |
| Disponibilidad | Supabase gestionado; backups diarios (PITR en plan Pro) |
| Tiempo real | Agenda y campana se actualizan sin recargar (Supabase Realtime) |
| Usabilidad | Material 3, modo claro/oscuro, objetivos táctiles ≥ 48 px, estados con color + ícono + texto |
| Localización | es-AR: fechas dd/MM, moneda ARS, zona America/Argentina/Buenos_Aires |
| Escalabilidad | Modelo con `center_id` en todas las entidades → multi-sede / SaaS sin migrar datos |
| Mantenibilidad | Clean Architecture, tests unitarios y de base de datos (pgTAP), CI en cada PR |

## 1.5 Alcance de esta versión y roadmap

**Incluido (v1.0):** todo lo anterior.

**Próximas versiones sugeridas:**
1. Portal web de reservas online para clientes (misma base, rol `client`).
2. Cobro online con Mercado Pago Checkout Pro + webhooks (hoy se registra manualmente).
3. Respuesta a recordatorios por WhatsApp ("SI" confirma el turno) vía webhook de Meta.
4. Gift cards y paquetes de sesiones prepagas.
5. Comisiones por profesional y liquidación mensual.
6. Facturación electrónica AFIP/ARCA.
