# 9. Panel web de administración

Panel liviano (HTML + JavaScript, sin compilación) para que el **administrador** gestione **usuarios** y **agenda** desde la computadora. Usa el mismo backend Supabase que la app: los permisos los sigue garantizando RLS.

Carpeta: [`admin-web/`](../admin-web)

| Sección | Qué se puede hacer |
|---|---|
| **Agenda** | Vista por día (una columna por profesional) o por semana · filtro por profesional · **arrastrar un turno** para cambiar hora, día o profesional · clic en un hueco para crear un turno · horarios libres sugeridos · alerta de alergias/contraindicaciones · confirmar, completar, marcar ausente · reprogramar · cancelar con motivo · registrar pagos · se actualiza sola cuando alguien cambia un turno desde la app |
| **Usuarios** | Solicitudes de acceso pendientes con aprobación y rol · cambiar rol · quitar o dar acceso · invitar por email · cargar el **horario semanal** y el color de cada profesional |
| **Clientes** | Búsqueda, alta, edición y agendar directo |
| **Resumen** | Turnos y facturación de hoy, facturación del mes, clientes nuevos y activos, cancelación, ausentismo, servicios más vendidos y horarios pico |

Solo ingresan usuarios con rol **Administrador**; cualquier otro rol recibe el aviso de usar la app móvil.

## Probarlo sin backend

Abrí `admin-web/index.html?demo=1` (o el botón **Ver demo** en la pantalla de ingreso cuando no hay configuración). Carga datos de ejemplo en memoria; nada se guarda.

Para servirlo en local: `cd admin-web && python3 -m http.server 8080` → http://localhost:8080/?demo=1

## Configuración

`admin-web/config.js`:

```js
window.AW_CONFIG = {
  supabaseUrl: "https://<project-ref>.supabase.co",
  supabaseAnonKey: "<anon key pública>",
};
```

En GitHub no hace falta editarlo: el workflow lo genera a partir de los secretos `SUPABASE_URL` y `SUPABASE_ANON_KEY`.

En Supabase › **Authentication › URL Configuration** agregá la dirección del panel (por ejemplo `https://tu-usuario.github.io/agenda-wellness/`) en *Redirect URLs*, para que funcione "¿Olvidaste tu contraseña?".

## Publicación

**GitHub Pages (automático):** *Settings › Pages › Source: GitHub Actions*. Cada cambio en `admin-web/` en la rama `main` lo publica el workflow **Panel web de administración**. La dirección queda en *Settings › Pages*.

> En cuentas gratuitas de GitHub, Pages solo funciona con repositorios **públicos**. El código no contiene secretos (la anon key es pública por diseño y la seguridad la da RLS), pero si preferís mantener el repositorio privado usá la opción siguiente.

**Netlify o Cloudflare Pages (repositorio privado):** descargá **panel-web** desde *Actions › Panel web de administración › Artifacts* (ya trae `config.js` generado) y arrastrá la carpeta a app.netlify.com/drop, o conectá el repositorio indicando `admin-web` como carpeta de publicación.

## Detalles técnicos

- `api.js` concentra el acceso a datos: `createSupabaseApi()` (tablas, vistas `appointments_view`, RPC `reschedule_appointment`, `cancel_appointment`, `set_appointment_status`, `available_slots`, `admin_update_user`, `dashboard_summary` y la Edge Function `invite-user`) y `createDemoApi()` con la misma interfaz.
- `supabase-js` se carga desde jsDelivr con versión fija (`@2.45.4`).
- Las reglas críticas (solapamiento de turnos, máquina de estados, permisos) se validan en la base de datos; el panel muestra el error traducido si algo no se permite.
- Horarios: el panel guarda una franja por día en `therapist_schedules`; esas franjas alimentan los horarios libres sugeridos y la zona rayada (fuera de horario) de la agenda.
- Probado en navegador (Chromium) en modo demo: arrastrar y reprogramar, cambio de estado, alta de turno con alerta de salud, vista semanal, aprobación e invitación de usuarios, horarios, clientes, resumen, modo oscuro y pantalla de celular sin desborde.
