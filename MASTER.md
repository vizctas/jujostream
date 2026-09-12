# MASTER.md - Sistema de diseño del launcher Classic (TV)

Fuente única de verdad para el tema **Classic** en pantallas 16:9 (FireTV,
Chromecast, escritorio ≥ 960 px). Los valores viven en
`lib/themes/classic/classic_tokens.dart`; ningún número fuera de ese archivo.

## Tesis

**Visual.** Oscuro operacional (#0E0E1C), arte del juego a sangre completa, un
solo acento violeta (#6C3CE1 / #9B71F5). Sans del sistema. Componentes planos:
chips con borde de 1 px, radio 8, sin sombras salvo el anillo de foco.
Punto medio entre Epic (cinemático) y Xbox (utilitario).

**Interacción.** Foco 130 ms, escala 1.06 + anillo violeta. Fondo crossfade
220 ms. Diálogo entra en 250 ms (fade + 12 px desde abajo) y sale en 180 ms
(solo fade). Una única curva `cubic-bezier(.2, 0, 0, 1)`. Sin hover, parallax,
Ken Burns, loops ni blur vivo en TV. Prohibido bounce, elástico y sombras
animadas.

## Color

| Token | Valor | Uso | Contraste sobre fondo |
|---|---|---|---|
| `bg` | #0E0E1C | Fondo base y degradados de legibilidad | - |
| `surface` | #16192E | Diálogo, chips activos | - |
| `surfaceVariant` | #1C1D38 | Rail, estadísticas | - |
| `accent` | #6C3CE1 | Botón primario, anillo de foco | 4.6:1 (texto blanco) |
| `accentLight` | #9B71F5 | Etiquetas, iconos activos | 7.1:1 |
| `text` | #FFFFFF | Título, cuerpo | 18.4:1 |
| `textMuted` | #FFFFFF @ 72 % | Meta, descripción | 11.9:1 |
| `textFaint` | #FFFFFF @ 48 % | Etiquetas mayúsculas | 7.2:1 |
| `line` | #FFFFFF @ 16 % | Bordes de chips y separadores | - |
| `success` | #34D399 | Sesión activa, logros 100 % | - |
| `danger` | #F87171 | Cerrar sesión | - |

Los colores base se leen del tema activo (`AppThemeColors`) para que los demás
presets de color sigan funcionando; los porcentajes de blanco son fijos.

## Tipografía

Fuente del sistema (Roboto en Android TV). Sin fuentes personalizadas.

| Token | Tamaño / peso / tracking | Uso |
|---|---|---|
| `display` | 56 px / 700 / -1.0 | Título del juego en el hero |
| `displayCompact` | 40 px / 700 / -0.8 | Mismo título en ventanas < 700 px de alto |
| `dialogTitle` | 32 px / 700 / -0.5 | Título en el diálogo |
| `body` | 17 px / 400 / 0 / line-height 1.4 | Descripción (≤ 48 ch, 3 líneas) |
| `meta` | 16 px / 500 / 0 | Línea de datos (tiempo, última sesión, tienda) |
| `label` | 13 px / 600 / +1.2 / MAYÚSCULAS | "RECIENTES", cabeceras de estadística |
| `chip` | 13 px / 500 / 0 | Chips de género |
| `stat` | 22 px / 700 / -0.3 | Valor de estadística en el diálogo |

## Espaciado

Rejilla de 8 px. Escala: 4, 8, 12, 16, 24, 32, 48, 64.
Margen seguro TV: 64 px izquierda/derecha, 40 px arriba/abajo.
Ancho de la columna de lectura: 46 % del ancho, máximo 640 px.
Chips de 28 px de alto, máximo 4 por fila. Rail de 64 px.
El layout se activa en horizontal cuando el dispositivo es TV o el ancho
es ≥ 960 px; el resto de formatos conserva el Classic anterior.
Los TV reportan 960 × 540 px lógicos (DPR 2), así que en TV rige la escala
compacta (`displayCompact`, arte 4:1); la escala completa es para ventanas
de escritorio ≥ 700 px lógicos de alto.

## Radios

| Token | Valor | Uso |
|---|---|---|
| `radiusChip` | 8 | Chips, botones secundarios |
| `radiusCard` | 10 | Pósters |
| `radiusDialog` | 16 | Diálogo |
| `radiusFull` | 999 | Píldora de sesión activa |

## Elevación

Nivel 0 en todo. Único relieve permitido: anillo de foco de 3 px con 2 px de
separación: `accent` en pósters, `accentLight` en botones y rail (sobre el
botón primario relleno de `accent` el anillo `accent` desaparecía). El diálogo se separa del fondo con un scrim
`bg @ 72 %`, no con sombra.

## Movimiento

| Token | Valor | Uso |
|---|---|---|
| `curve` | Cubic(0.2, 0, 0, 1) | Todo |
| `focus` | 130 ms | Escala y anillo de póster / botón |
| `backdrop` | 220 ms | Crossfade del fondo (ya lo aplica `GameBackdropArt`) |
| `dialogIn` | 250 ms | Fade + desplazamiento 12 px |
| `dialogOut` | 180 ms | Solo fade |
| `focusScale` | 1.06 | Póster o botón con foco |

Con `reduceMotion` activo todas las duraciones pasan a 0 y la escala a 1.0.

## Componentes base

- **Rail izquierdo** (64 px): iconos 24 px, `textFaint` en reposo,
  `accentLight` + anillo con foco. Orden: atrás, buscar, cuadrícula, filtros
  inteligentes, ajustes de presentación.
- **Columna de lectura**: título `display`, meta `meta`, chips (máx. 4),
  descripción `body`, etiqueta `label` de la fila.
- **Póster**: radio `radiusCard`, sin etiqueta sobrepuesta cuando la fila está
  enfocada (el título ya vive en la columna), anillo al foco.
- **Botón primario**: fondo `accent`, texto blanco 16 px / 700, alto 48,
  radio `radiusChip`.
- **Botón secundario**: borde `line` 1 px, texto `text`, mismo alto.
- **Chip**: borde `line`, texto `chip`, alto 28, padding 12 h.
- **Estadística**: etiqueta `label` + valor `stat`.

## Diálogo del juego

Ancho 62 % (máx. 880 px), alto máximo pantalla − 2 × 40 px. Arte 21:9 arriba
(4:1, padding 16 y descripción de 3 líneas en compacto; caché 1280 px) con
degradado hacia `surface`
y el título sobrepuesto. Debajo: chips, descripción (4 líneas), tres
estadísticas (tiempo jugado, última sesión, logros Steam solo cuando el
juego tiene `steamAppId` y hay credenciales) y barra inferior con
Jugar (autofoco, X), Detalles (Y), Más (rueda dentada → hoja de acciones).
Atrás/B cierra.

## Datos disponibles

- Tiempo jugado: suma de sesiones locales (`SessionHistoryService`), o el
  valor de Playnite si es mayor.
- Última sesión: fin de la última sesión local; si no hay, `lastPlayed`.
- Logros: `AchievementProgress` de Steam en caché del launcher.
- No hay desarrollador, editor ni fecha de lanzamiento en `NvApp`; no se
  inventan.
