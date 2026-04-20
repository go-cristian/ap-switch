# ApSwitcher

App ligera para macOS que replica el flujo de `Alt+Tab` de Windows con `Cmd+Tab`, pero cambiando entre ventanas individuales en vez de apps.

## Qué hace

- Corre como app de barra de menú.
- Escucha `Cmd+Tab` globalmente.
- Muestra un overlay centrado con todas las ventanas top-level detectables.
- Usa orden reciente de uso por ventana para que el primer salto vaya a la ventana anterior.
- Prioriza ventanas del escritorio actual cuando ya existen allí.
- Reconcila la lista a los `100ms` de abrir el switcher para absorber cambios rápidos entre escritorios.
- Evita mejor las colisiones cuando hay ventanas casi idénticas del mismo app en escritorios distintos.
- Activa la ventana seleccionada al soltar `Command`.
- Soporta `Cmd+Shift+Tab` para navegar en reversa.
- Soporta flechas izquierda/derecha y arriba/abajo para mover la selección mientras el overlay está abierto.
- Intenta mostrar miniaturas reales con `ScreenCaptureKit` cuando `Screen Recording` está concedido.
- Permite salir desde el icono de barra de menú o con `Control+Option+Q`.

## Notas sobre `Cmd+Tab`

Esta versión usa `Cmd+Tab` como atajo principal. Eso no es una ruta oficialmente soportada por Apple, así que puede ser más frágil frente a cambios de macOS que el resto de la app.

Fuentes oficiales:

- [Other System and Application Shortcuts](https://developer.apple.com/library/archive/documentation/IDEs/Conceptual/xcode_help-command_shortcuts/SystemAndOther/SystemAndOther.html)
- [Accessibility Keyboard Shortcuts](https://developer.apple.com/library/archive/documentation/Accessibility/Conceptual/AccessibilityMacOSX/OSXAXKeyboardShortcuts.html)

## Requisitos

- macOS 13 o superior
- Xcode Command Line Tools
- Permiso de `Accessibility` para detectar el atajo global y enfocar ventanas
- Permiso de `Screen Recording` si quieres miniaturas de otras ventanas

## Ejecutar en desarrollo

```bash
swift run ApSwitcher
```

## Salir de la app

- Menú de barra de menú: `Cerrar`
- Atajo de emergencia: `Control+Option+Q`

## Tests

```bash
swift test
```

Se usa `Swift Testing` para validar la lógica pura de orden MRU y navegación del selector.

Cobertura actual:

- `WindowSwitchingLogic`
- `WindowUsageTracker`
- `WindowFrame` y `WindowIdentity`
- `SwitcherSessionFactory`

La ruta sensible de runtime de macOS (`Accessibility`, `Screen Recording`, `AXUIElement`, `CGEventTap`, `NSPanel`, `ScreenCaptureKit`) no se cubre por unit test directo.

## Troubleshooting rápido

Si no salen miniaturas:

1. abre la app
2. prueba `Cmd+Tab`
3. revisa el log:

```bash
/usr/bin/log show --last 10m --style compact --predicate 'subsystem == "dev.cgomez.apswitcher"'
```

Si el log dice `Screen Recording is not granted`, resetea TCC y vuelve a autorizar:

```bash
tccutil reset ScreenCapture dev.cgomez.apswitcher
```

Luego reinicia la app y vuelve a aceptar `Screen Recording`.

Si al cambiar muy rápido de escritorio el switcher muestra referencias viejas:

1. mantén `Command` presionado una fracción de segundo más
2. deja que la reconciliación a `100ms` reconstruya la lista
3. si sigue fallando, revisa el log del subsystem `dev.cgomez.apswitcher`

## Empaquetar como `.app`

```bash
./scripts/build_app.sh
```

Esto genera:

```text
dist/ApSwitcher.app
```

Instalación recomendada para pruebas manuales:

```bash
./scripts/install_app.sh
```

Esto reinstala la copia empaquetada en:

```text
/Applications/ApSwitcher.app
```

Y la vuelve a abrir desde esa ubicación estable, que se comporta mejor con TCC y Launch Services.

Si necesitas forzar una prueba limpia de permisos:

```bash
./scripts/install_app.sh --reset-permissions
```

## Release `.dmg`

Hay automatización para publicar un `.dmg` instalable en GitHub cuando haces push de un tag `vX.Y.Z`.
Usar solo certificados del team `3EUA8SZ453`.

Documentación:

- [RELEASE.md](/Users/cristian/repos/iyubinest/ApSwitcher/RELEASE.md)

Script de release:

```bash
./scripts/build_release_dmg.sh
```
