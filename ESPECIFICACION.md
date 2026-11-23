# QueRuleErTrono — Especificación funcional y técnica

**Versión:** 1.0 — alcance funcional MVP confirmado  
**Fecha:** 23/11/2026  
**Estado:** Listo para implementación, con decisiones técnicas detalladas a validar

## 1. Objetivo
Web informal para asignar mediante sorteo la silla buena de una oficina («Er Trono»). Cada compañero se identifica solo por nombre y confirma si acudirá al **siguiente día de oficina disponible**. Se muestra el ganador del día, un calendario semanal y un historial cronológico.

## 2. Alcance MVP
- Interfaz responsive, en español, con tono humorístico.
- Identificación únicamente por nombre único (sin login, PIN ni correo); recordar nombre en el navegador.
- Inscribir o cancelar asistencia al siguiente día habilitado, sin duplicados.
- Mostrar lista de inscritos, fecha y cierre.
- Sorteo único e idempotente, ejecutado en base de datos al primer acceso posterior al cierre.
- Resultado del día, calendario semanal (lunes a viernes) e historial de ganadores.
- Bloqueo de festivos y otros días directamente en Supabase, sin panel de administración.
- Sin rankings, medallas, estadísticas avanzadas, notificaciones ni múltiples oficinas.

## 3. Calendario e inscripciones
- Zona horaria obligatoria: `Europe/Madrid` (incluidos cambios de hora).
- Semana de cómputo: lunes a domingo, conforme al calendario local.
- Días habilitados: lunes a viernes, excepto fechas registradas en `blocked_days`.
- Solo puede inscribirse para el **siguiente día habilitado con inscripciones abiertas**. Una vez cerrado su plazo, la UI avanza al siguiente día habilitado, aunque el sorteo anterior aún no se haya consultado.
- Cierre a las **22:00 del día natural anterior** a la fecha de oficina; en ese instante ya no se permiten altas ni bajas.
- Las inscripciones para el lunes están disponibles desde el viernes anterior y cierran **domingo a las 22:00**.
- Para festivos y cierres, se salta al siguiente día habilitado. La ventana de inscripción del próximo día comienza al cerrar la ventana del anterior, o antes si no existe otro día habilitado intermedio; nunca se permiten inscripciones para dos fechas a la vez desde la interfaz.
- Los sábados y domingos no tienen sorteo, pero se puede consultar la web y apuntarse para el lunes u otro próximo día habilitado.
- Si se bloquea un día antes de celebrarse su sorteo, sus inscripciones se invalidan y ese día se muestra «Sin sorteo»; el sistema debe impedir bloqueos retroactivos de días con resultado definitivo.
- **Nota operativa:** los cambios manuales directos en tablas de Supabase deben ejecutarse mediante una función SQL de administración que valide estas restricciones; no basta con insertar arbitrariamente en `blocked_days`.

## 4. Reglas de adjudicación
**RN-01.** Una inscripción activa por participante y fecha; solo inscritos válidos entran en el sorteo.

**RN-02.** Límite ordinario: máximo **2 victorias** en la semana actual.

**RN-03.** Si el participante obtuvo **2 o más victorias** en la semana inmediatamente anterior, su límite ordinario para esta semana es **1 victoria**.

**RN-04.** Si solo hay un inscrito, gana automáticamente, aunque supere su límite. Es victoria excepcional cuando ya había alcanzado el límite aplicable.

**RN-05.** Si hay varios inscritos y algunos son elegibles, se sortea **solo entre los elegibles**.

**RN-06.** Si hay varios inscritos y **todos** han alcanzado su límite, se sortea excepcionalmente entre **todos**, con idéntica probabilidad.

**RN-07.** Toda victoria excepcional cuenta para el historial, para el límite semanal acumulado y para la restricción de la semana siguiente.

**RN-08.** Si no hay inscritos, se registra resultado `no_participants` y Er Trono queda desierto.

**RN-09.** Los candidatos del conjunto seleccionado tienen probabilidad uniforme `1/N`, sin preferencia por orden de inscripción ni historial.

**RN-10.** Cada fecha tiene un resultado persistido único; no se puede repetir el sorteo por refrescar la página ni por accesos simultáneos.

**RN-11.** Los sorteos pendientes se resuelven cronológicamente antes de calcular uno posterior, para que las cuotas sean coherentes.

## 5. Algoritmo del sorteo
```text
resolver_sorteos_pendientes(hasta_fecha):
  procesar fechas habilitadas con cierre vencido, en orden ascendente
  para cada fecha, en una transacción con bloqueo de concurrencia:
    si existe resultado: continuar
    inscritos = inscripciones válidas
    si ninguno: guardar no_participants
    si solo uno: ganador = ese inscrito; marcar excepción si excede cuota
    si varios:
      elegibles = inscritos que no han alcanzado su límite ordinario
      candidatos = elegibles si hay alguno; de lo contrario, todos
      ganador = selección aleatoria uniforme en servidor
      exceptional = (elegibles está vacío)
      guardar ganador, tipo y fecha de sorteo
```
El sorteo se dispara por la **primera consulta posterior a las 22:00**, no por un proceso cron. Si nadie visita la web esa noche, se ejecutará al siguiente acceso; no se promete publicación exactamente a las 22:00.

## 6. Requisitos funcionales
| ID | Requisito | Prioridad |
|---|---|---|
| RF-01 | Crear o reutilizar participante por nombre normalizado | Alta |
| RF-02 | Recordar nombre en almacenamiento local del navegador | Alta |
| RF-03 | Consultar próxima fecha habilitada y cierre | Alta |
| RF-04 | Inscribir/cancelar asistencia solo para próxima fecha habilitada antes de cierre | Alta |
| RF-05 | Mostrar inscritos de la próxima fecha | Alta |
| RF-06 | Resolver sorteo en servidor de forma atómica e idempotente | Alta |
| RF-07 | Aplicar límites y excepciones semanales | Alta |
| RF-08 | Gestionar calendario laboral lunes-viernes y festivos | Alta |
| RF-09 | Mostrar ganador actual, calendario semanal e historial | Alta |
| RF-10 | Gestionar bloqueos únicamente desde Supabase | Alta |
| RF-11 | No admitir inscripciones simultáneas para varios días | Alta |

## 7. Modelo de datos propuesto (PostgreSQL / Supabase)
### `participants`
`id UUID PK`, `display_name TEXT`, `normalized_name TEXT UNIQUE NOT NULL`, `created_at TIMESTAMPTZ`, `active BOOLEAN`.

### `registrations`
`id UUID PK`, `participant_id UUID FK`, `office_date DATE`, `status TEXT CHECK (status IN ('registered','cancelled','invalidated'))`, `created_at TIMESTAMPTZ`, `updated_at TIMESTAMPTZ`, `UNIQUE(participant_id,office_date)`.

### `draws`
`office_date DATE PK`, `status TEXT CHECK (status IN ('winner','no_participants'))`, `winner_participant_id UUID NULL`, `exceptional BOOLEAN`, `eligible_count INTEGER`, `drawn_at TIMESTAMPTZ`.

### `blocked_days`
`date DATE PK`, `reason TEXT NULL`, `created_at TIMESTAMPTZ DEFAULT now()`.

Se recomienda encapsular la modificación de bloqueos en `admin_block_day(date, reason)` y `admin_unblock_day(date)`, accesibles **solo desde una sesión administrativa de Supabase**. Las tablas no tendrán permisos de escritura para la clave pública. La función de bloqueo invalida inscripciones existentes y rechaza fechas ya sorteadas.

## 8. Seguridad y límites de la identidad por nombre
- No hay autenticación real: cualquier usuario que conozca un nombre puede intentar actuar como ese participante. Esto se acepta explícitamente para un juego de confianza; no mostrar datos confidenciales.
- Las operaciones públicas de inscripción y sorteo pasan por funciones RPC de base de datos con validaciones de fechas, estados y restricciones; RLS y permisos mínimos, sin escrituras directas a tablas.
- **Nunca** exponer claves `service_role`, secretos de administración o credenciales de base de datos en el frontend.
- Funciones `SECURITY DEFINER` con `search_path` controlado, privilegios limitados, comprobación de entradas y protección de concurrencia.
- Considerar limitación de frecuencia y protección antiabuso: el enlace público no es una barrera de acceso.
- La función que dispara el sorteo debe poder ser llamada desde un navegador sin permitir elegir arbitrariamente fechas futuras ni alterar resultados.

## 9. Arquitectura y despliegue
- **Frontend:** React + TypeScript + Vite.
- **Publicación:** GitHub Pages mediante GitHub Actions, con `base` correcto para el nombre del repositorio.
- **Backend y datos:** Supabase Free, PostgreSQL y RPC.
- **Variables de cliente:** `VITE_SUPABASE_URL` y clave pública de Supabase; nunca claves privilegiadas.
- **Coste previsto:** 0 € para un equipo pequeño dentro de cuotas gratuitas; no garantizado a perpetuidad. Supabase Free puede pausar proyectos inactivos.

## 10. Pantallas
1. **Inicio:** ganador de hoy o estado pendiente/desierto/bloqueado; nombre recordado.
2. **Próximo sorteo:** siguiente fecha disponible, contador hasta cierre, inscritos, alta y cancelación.
3. **Calendario semanal:** lunes a viernes, ganador o estado de cada fecha.
4. **Historial:** resultados cronológicos, indicando excepciones cuando proceda.

## 11. Casos de aceptación
| Caso | Entrada | Resultado |
|---|---|---|
| CA-01 | Una persona inscrita, con cuota agotada | Gana automáticamente; victoria excepcional |
| CA-02 | Tres inscritos, uno con cuota agotada | Sorteo solo entre los otros dos |
| CA-03 | Tres inscritos, todos con cuota agotada | Sorteo excepcional entre los tres |
| CA-04 | Dos victorias la semana anterior | Máximo una ordinaria esta semana |
| CA-05 | Victoria excepcional que eleva el total semanal a 2 o más | La siguiente semana limita a una victoria ordinaria |
| CA-06 | Ningún inscrito | `no_participants`, sin ganador |
| CA-07 | Dos accesos simultáneos tras cierre | Un solo ganador persistido |
| CA-08 | Cancelación después de las 22:00 | Rechazada |
| CA-09 | Viernes con lunes hábil | Próxima inscripción para lunes; cierre domingo 22:00 |
| CA-10 | Lunes bloqueado | Próxima inscripción para martes u otro día hábil |
| CA-11 | Día bloqueado con inscripciones abiertas | Inscripciones invalidadas y fecha excluida |
| CA-12 | Día con sorteo ya resuelto | Bloqueo retroactivo rechazado |
| CA-13 | Sorteo anterior pendiente y consulta de fecha posterior | Se resuelve el anterior primero |
| CA-14 | Cierre de hoy ya vencido | Se puede inscribir al siguiente día habilitado |
| CA-15 | Nombre duplicado con distinta capitalización | Se reutiliza el participante existente |

## 12. Estructura propuesta
```text
queruleertrono/
  README.md
  docs/ESPECIFICACION.md
  src/
    components/
    pages/
    lib/supabase.ts
  supabase/
    migrations/
    tests/
  .github/workflows/deploy.yml
  vite.config.ts
  package.json
```

## 13. Fases de desarrollo
1. Crear proyecto Vite/React y repositorio GitHub.
2. Crear esquema PostgreSQL, políticas y RPC seguras en Supabase.
3. Implementar inscripciones y gestión de próximo día hábil.
4. Implementar sorteo transaccional y pruebas automatizadas de reglas.
5. Implementar pantallas responsive y textos divertidos.
6. Desplegar en GitHub Pages y validar con varios navegadores.

## 14. Consideraciones de implementación
- Para el sorteo del lunes, **viernes a domingo** forman parte de la ventana de inscripción; el cierre es domingo a las 22:00.
- La especificación funcional está cerrada; quedan por decidir detalles internos como el tratamiento de errores de red, paginación del historial y política de retención.
- Los cambios de bloqueos se harán con SQL validado desde Supabase, no con modificaciones manuales sin controles.
