# QueRuleErTrono

Sorteo de la mejor silla de la oficina. React muestra el ganador, la inscripción, el calendario y el historial. Supabase PostgreSQL guarda el estado compartido y aplica las reglas en `Europe/Madrid`.

## Configurar Supabase

1. Abre **SQL Editor → New query** en el proyecto Supabase con el rol `postgres`. Pega y ejecuta una sola vez el archivo completo [`supabase/migrations/20261123000100_office_draw.sql`](supabase/migrations/20261123000100_office_draw.sql).
2. Si todavía no tienes `.env.local`, créalo a partir de `.env.example`. Configura la URL del proyecto y la clave publicable `sb_publishable_…` de **Settings → API Keys**. [Claves de API de Supabase](https://supabase.com/docs/guides/getting-started/api-keys).
3. Instala las dependencias y arranca Vite. Si ya estaba abierto, reinícialo para cargar las variables.

```sh
test -f .env.local || cp .env.example .env.local
# Edita .env.local con los dos valores de tu proyecto.
npm install
npm run dev
```

El historial compartido empieza en la fecha de la migración, en Madrid. Las inscripciones y resultados locales de la fase 1 quedan fuera del historial compartido. El nombre recordado se conserva como preferencia del navegador.

## Publicar en GitHub Pages

El repositorio de destino es `vicmonmena/que-rule-er-trono`. El workflow prueba el frontend y la migración en un PostgreSQL desechable, compila con Vite y publica `dist/` cuando llega un push a `main`. [Workflow de despliegue](.github/workflows/deploy.yml).

### Cuenta y copia local

1. Autentícate en GitHub CLI con la cuenta personal. Si ya está registrada, usa `gh auth switch --hostname github.com --user vicmonmena`. Si necesitas añadirla, usa `gh auth login --hostname github.com --git-protocol https --web` y selecciona `vicmonmena` en el navegador. El resultado de `gh api user --jq .login` debe ser `vicmonmena`.
2. Si tu carpeta local carece de `.git`, clona el repositorio en una carpeta distinta con `gh repo clone vicmonmena/que-rule-er-trono` y lleva el código al clon conservando su historial y licencia. Incluye `.github/`, `.gitignore` y `.env.example`. Conserva los archivos de entorno locales, las dependencias y los artefactos de compilación fuera de los cambios que vas a publicar.
3. En el clon, verifica que `git remote -v` apunta a `vicmonmena/que-rule-er-trono` y que la rama es `main`. Usa `git config --local user.name "vicmonmena"` y configura `user.email` en el clon con tu correo personal verificado o la dirección `noreply` de GitHub. La identidad de los commits se configura en Git y la cuenta que autoriza un push se comprueba con GitHub CLI.
4. Antes de publicar, revisa `git status --short` y `git diff --cached --name-only`. `git check-ignore .env.local` debe mostrar el archivo y `git ls-files -- .env.local` debe quedar vacío. Con un remoto HTTPS, el comando de push indicado abajo usa el asistente de GitHub CLI para esta operación y evita recurrir a credenciales del llavero.

### Ajustes del repositorio

1. En **Settings → Pages → Build and deployment → Source**, elige **GitHub Actions**. [Configurar la fuente de GitHub Pages](https://docs.github.com/es/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site).
2. En **Settings → Secrets and variables → Actions → Variables**, crea `VITE_SUPABASE_URL` con la URL HTTPS de tu proyecto Supabase. [Variables de GitHub Actions](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-variables).
3. En **Secrets**, crea `VITE_SUPABASE_PUBLISHABLE_KEY` con la clave `sb_publishable_…` del mismo proyecto. Vite incorpora estos dos valores al JavaScript público. Reserva las claves privilegiadas y contraseñas para administración. [Secretos de GitHub Actions](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets).
4. Cuando hayas revisado el commit y confirmado la cuenta personal, publica con el remoto HTTPS del repositorio:

   ```sh
   test "$(gh api user --jq .login)" = vicmonmena &&
     git -c credential.helper= -c 'credential.helper=!gh auth git-credential' push origin main
   ```

5. En **Actions**, comprueba que el workflow termina con éxito. La URL prevista es [vicmonmena.github.io/que-rule-er-trono/](https://vicmonmena.github.io/que-rule-er-trono/). Prueba a abrir y recargar directamente la ruta `/que-rule-er-trono/#historial`. Las vistas usan fragmentos y GitHub Pages sirve el mismo `index.html` para todas.

Para comprobar la compilación localmente, ejecuta `npm run build` y `npm run preview`, y abre la URL de Vite bajo `/que-rule-er-trono/`. El sitio necesita las RPC del proyecto de Supabase para mostrar datos reales.

## Comprobar la conexión

1. Abre la URL local que imprime Vite. En **DevTools → Network**, recarga y localiza `POST /rest/v1/rpc/office_snapshot` en el dominio de tu proyecto. Debe devolver HTTP 200 y un JSON con `serverNow`, `nextDate`, `closesAt`, `attendees` y `draws`.
2. Si aún no estás inscrito, apúntate con tu nombre. Comprueba que `register_attendance` devuelve HTTP 200 y que tu nombre aparece en la lista al abrir la app en otra ventana privada, con lo que se confirma que los datos vienen de Supabase.
3. Cancela la inscripción desde la ventana original. Comprueba que `cancel_attendance` devuelve HTTP 200 y que, al recargar la ventana privada, el nombre desaparece de la lista.
4. Tras el siguiente cierre hábil a las 22:00 de Madrid, abre la app en dos ventanas. En la pestaña **Historial** ambas deben mostrar el mismo resultado para esa fecha. Si nadie se apuntó, ambas mostrarán «Trono desierto».

Si la API devuelve HTTP 401, copia de nuevo la clave publicable del mismo proyecto que la URL y reinicia Vite. Si la consulta devuelve `PGRST202`, comprueba que la migración se ejecutó en ese proyecto.

## Cierres de oficina

En **Supabase → SQL Editor → New query**, usa el rol administrativo `postgres`. Puedes confirmarlo con `select current_user;`. Las funciones viven en `trono_private` y se ejecutan con los permisos de la sesión. El acceso del editor como `postgres` basta para ambas operaciones. [Roles de Supabase](https://supabase.com/docs/guides/database/postgres/roles).

Sustituye la fecha del ejemplo por un día hábil. Para bloquearlo, ejecuta esta consulta antes de las **22:00 del día anterior**, en `Europe/Madrid`:

```sql
select trono_private.admin_block_day(date '2026-12-25', 'Festivo');
```

Para quitar un bloqueo, ejecuta esta consulta en una operación independiente:

```sql
select trono_private.admin_unblock_day(date '2026-12-25');
```

Un bloqueo invalida las inscripciones de esa fecha. PostgreSQL rechaza el bloqueo desde el instante de cierre, incluso si el sorteo sigue pendiente, y conserva el rechazo para cualquier fecha con resultado definitivo. Las inscripciones invalidadas siguen así tras desbloquear el día. Si aún hay plazo y el día vuelve a ser el próximo disponible, los compañeros pueden apuntarse de nuevo.

La inscripción del lunes abre al cerrar la del viernes, el jueves a las 22:00 si ambos días son hábiles. Cierra el domingo a las 22:00. La primera consulta posterior al cierre resuelve en orden los sorteos vencidos.

## Permisos de la base de datos

- El cliente opera como `anon`. La migración revoca los permisos de ejecución predeterminados y concede a ese rol únicamente `EXECUTE` sobre `office_snapshot`, `register_attendance` y `cancel_attendance`, sin facultad para delegarlo. `PUBLIC`, `authenticated` y `service_role` quedan excluidos de las concesiones de estas funciones. [Permisos de funciones en Supabase](https://supabase.com/docs/guides/database/functions).
- Las tres RPC son `SECURITY DEFINER` y pertenecen a `trono_rpc_owner`, un rol sin inicio de sesión ni capacidad de saltarse RLS. Las políticas y permisos de ese rol cubren las lecturas y escrituras que requieren las tres RPC. `postgres` conserva la propiedad de las tablas y las funciones privadas, incluidas las administrativas, que son `SECURITY INVOKER`. Todas las funciones fijan `search_path = ''` y califican las referencias a los objetos del proyecto. [Seguridad de la Data API](https://supabase.com/docs/guides/api/securing-your-api).
- El reloj de PostgreSQL determina la fecha válida y el cierre. La fecha enviada en una alta o baja debe coincidir con la ventana vigente. La consulta de resultados toma sus parámetros de PostgreSQL. Un bloqueo transaccional compartido y la clave primaria por fecha garantizan un único resultado persistido.

## Abuso de las RPC públicas

La clave publicable da acceso a las mismas RPC que usa la web. Cualquier persona con acceso a la API puede suplantar un nombre, cancelar inscripciones ajenas, registrar varios nombres para aumentar sus opciones o recopilar los nombres de inscritos y ganadores. Un volumen alto de llamadas también puede ocupar conexiones y retrasar inscripciones y sorteos, porque comparten un bloqueo transaccional. La identidad por nombre deja abierta la suplantación incluso con controles de frecuencia.

Medidas posibles sin cuentas de usuario:

- Limitar las peticiones por IP y por RPC, con un límite global para picos. Se puede aplicar en la Data API con `db_pre_request` antes de entrar en el bloqueo del juego. Calibra los límites para la IP compartida de la oficina y conserva los contadores solo durante el tiempo necesario. [Controles de peticiones en Supabase](https://supabase.com/docs/guides/api/securing-your-api#configure-a-pre-request-function).
- Mantener una lista de nombres aprobada por la oficina para reducir altas ficticias y usar alias que el equipo pueda compartir. La lista controla qué nombres entran en el sorteo y cualquier persona que conozca un nombre de la lista puede seguir usándolo.
- Para automatización persistente, exigir un desafío antibots validado en servidor antes de altas y bajas. Si se añade un intermediario para validarlo, canalizar las escrituras por él y retirar el acceso directo de `anon` a las RPC de escritura para que la validación sea obligatoria.
- Revisar el volumen de altas y bajas, la latencia de las RPC y las esperas del bloqueo para detectar picos. Mantener acceso a los registros operativos solo para el equipo administrador.

## Pruebas

```sh
npm test
npm run build
```

Las pruebas SQL requieren un PostgreSQL desechable con UTF-8, ICU y los roles de Supabase `anon`, `authenticated` y `service_role`. Por ejemplo:

```sh
docker run --detach --rm --network none --name trono-pg-test \
  -e POSTGRES_HOST_AUTH_METHOD=trust postgres:16
docker exec trono-pg-test pg_isready -U postgres
docker exec trono-pg-test psql -U postgres -v ON_ERROR_STOP=1 \
  -c 'create role anon nologin; create role authenticated nologin; create role service_role nologin;' \
  -c 'create database queruleertrono_test'
docker exec -i trono-pg-test psql -U postgres -d queruleertrono_test -v ON_ERROR_STOP=1 \
  < supabase/migrations/20261123000100_office_draw.sql
docker exec -i trono-pg-test psql -U postgres -d queruleertrono_test \
  < supabase/tests/office_draw.sql
python3 supabase/tests/concurrency.py docker exec trono-pg-test psql -U postgres -d queruleertrono_test
docker stop trono-pg-test
```

Ejecuta la prueba de concurrencia al final. Usa dos conexiones reales y deja los datos sintéticos en el contenedor desechable.

## Imagen del trono

La imagen `public/trono.jpg` se generó con la herramienta integrada de generación de imágenes. Prompt original:

> Wide 3:2 editorial product photograph for a web app hero: a single luxurious black leather tufted executive office chair reimagined as a medieval throne, with restrained antique brass trim, padded armrests and a visible five-wheel swivel base, all inside a near-black smoky charcoal studio with a warm amber light from above right and a dark floor. Entire chair fully inside frame, centered around 58% horizontally, large with breathing space, warm cinematic atmosphere, restrained rich textures, realistic photography, no people, no text, no logos, no watermark.
