# AGENTS

Guia operativa para futuras sesiones de Codex sobre `ApSwitcher`.

## Objetivo del proyecto

`ApSwitcher` es una app ligera de macOS que replica el flujo de `Alt+Tab` de Windows usando `Option+Tab`, pero cambia entre ventanas individuales y no entre apps.

## Estado actual

- App empaquetada como Swift Package, sin proyecto `.xcodeproj`.
- El bundle de salida vive en `dist/ApSwitcher.app`.
- El identificador estable es `com.iyubinest.apswitcher`.
- La firma usada desde shell hoy es `Apple Development: iyubinest@hotmail.com (H6Y8QWKATB)`.
- `Screen Recording` es requisito efectivo para miniaturas.
- `Accessibility` es requisito efectivo para hotkey global y focus de ventanas.
- La arquitectura actual ya separa una capa pura de sesión (`SwitcherSession.swift`) de los adaptadores sensibles de macOS.

## Mapa del repo

- `Sources/ApSwitcher/AppDelegate.swift`: arranque, polling de permisos, wiring general.
- `Sources/ApSwitcher/AppSwitcherController.swift`: flujo principal del switcher, overlay, selección, previews, failsafe.
- `Sources/ApSwitcher/WindowCatalogService.swift`: catálogo de ventanas vía AX + CGWindowList.
- `Sources/ApSwitcher/WindowPreviewProvider.swift`: miniaturas con `ScreenCaptureKit`.
- `Sources/ApSwitcher/GlobalHotkeyMonitor.swift`: `CGEventTap` para `Option+Tab`, flechas, escape, enter.
- `Sources/ApSwitcher/OverlayWindowController.swift`: panel flotante y cálculo de tamaño.
- `Sources/ApSwitcher/SwitcherOverlayView.swift`: UI SwiftUI del overlay.
- `Sources/ApSwitcher/WindowUsageTracker.swift`: MRU por ventana mediante polling del focused window.
- `Sources/ApSwitcher/WindowSwitchingLogic.swift`: lógica pura de orden y navegación.
- `Sources/ApSwitcher/SwitcherSession.swift`: puertos/adaptadores y fábrica pura de sesión del switcher.
- `Sources/ApSwitcher/*PermissionController.swift`: wrappers de permisos.
- `scripts/build_app.sh`: empaquetado y firma.
- `Tests/ApSwitcherTests`: tests puros; priorizar este enfoque antes de tocar runtime.

## Archivos sensibles

Evitar cambios innecesarios en estos archivos salvo que el problema lo requiera de forma directa:

- `AppDelegate.swift`
- `GlobalHotkeyMonitor.swift`
- `WindowCatalogService.swift`
- `WindowPreviewProvider.swift`
- `scripts/build_app.sh`

Motivo:

- TCC y permisos de macOS son frágiles entre builds.
- `CGEventTap`, AX y `ScreenCaptureKit` son difíciles de validar por unit test.
- Cambios pequeños pueden romper hotkeys, focus o prompts del sistema.

## Estrategia de tests

Priorizar tests sobre lógica pura o controladores con dependencias inyectadas:

- `WindowSwitchingLogic`
- `WindowUsageTracker`
- value types como `WindowFrame` y `WindowIdentity`
- `SwitcherSessionFactory`
- `SwitcherFooterMessageResolver`

No introducir mocks grandes del sistema ni tests frágiles sobre:

- `AXUIElement`
- `CGEventTap`
- `NSPanel`
- `ScreenCaptureKit`
- TCC

Si se necesita más cobertura sobre comportamiento sensible, primero extraer funciones puras o pequeños adaptadores testeables, sin reescribir la arquitectura completa en la misma sesión.

## Dirección arquitectónica

La dirección correcta para seguir aumentando cobertura es:

1. mantener `AX`, TCC, `ScreenCaptureKit`, `NSPanel` y `CGEventTap` como adaptadores finos
2. mover decisiones y composición a fábricas/reducers puros
3. inyectar protocolos en controladores para poder probar orquestación sin tocar macOS real

Evitar el patrón opuesto:

- mezclar más lógica de negocio dentro de `AppDelegate`
- mezclar más decisiones dentro de `WindowCatalogService`
- crear mocks complejos de APIs del sistema antes de extraer capas puras

## Comandos útiles

Desarrollo:

```bash
swift run ApSwitcher
```

Build:

```bash
swift build
```

Tests:

```bash
swift test
```

Empaquetado:

```bash
./scripts/build_app.sh
```

Abrir la app empaquetada:

```bash
open -n /Users/cristian/repos/iyubinest/ApSwitcher/dist/ApSwitcher.app
```

Reiniciar la app:

```bash
pkill -x ApSwitcher || true
open -n /Users/cristian/repos/iyubinest/ApSwitcher/dist/ApSwitcher.app
```

## Logs útiles

Logs propios de la app:

```bash
/usr/bin/log show --last 10m --style compact --predicate 'subsystem == "com.iyubinest.apswitcher"'
```

Logs de TCC relevantes:

```bash
/usr/bin/log show --last 10m --style compact --predicate 'process == "tccd" AND eventMessage CONTAINS[c] "com.iyubinest.apswitcher"'
```

## Troubleshooting conocido

### Miniaturas no aparecen

Señal actual más importante:

- Si el log dice `loadPreviewsIfNeeded skipped because Screen Recording is not granted`, el problema es TCC, no `ScreenCaptureKit`.

Pasos:

1. `tccutil reset ScreenCapture com.iyubinest.apswitcher`
2. reiniciar la app
3. aceptar el prompt de `Screen Recording`
4. cerrar y abrir de nuevo la app si macOS lo requiere

### El prompt de permisos reaparece entre builds

Normalmente indica uno de estos dos problemas:

- cambió la identidad efectiva del bundle
- TCC conserva una autorización asociada a un requirement anterior

Validar:

```bash
codesign -dv --verbose=4 /Users/cristian/repos/iyubinest/ApSwitcher/dist/ApSwitcher.app 2>&1 | sed -n '1,40p'
```

### El borde del primer item se corta

El ajuste está en `SwitcherOverlayView.swift`, no en `OverlayWindowController.swift`.

## Restricciones de entorno

- Este directorio no está bajo un repo git activo en esta sesión. No dependas de `git status` o `git diff`.
- `dist/ApSwitcher.app` es output generado; no editar archivos dentro del bundle manualmente.
- Si tocas firma, permisos o TCC, recompila y vuelve a abrir el bundle desde `dist/ApSwitcher.app`, no el binario interno directo.

## Checklist de cierre recomendado

Antes de dar por terminada una sesión de cambios:

1. correr `swift build`
2. correr `swift test`
3. si hubo cambios funcionales, correr `./scripts/build_app.sh`
4. si hubo cambios visuales o de permisos, reiniciar `dist/ApSwitcher.app`
5. si hubo problemas con miniaturas, revisar logs antes de seguir cambiando código
