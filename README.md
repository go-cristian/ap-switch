# ApSwitcher

App ligera para macOS que replica el flujo de `Alt+Tab` de Windows con `Option+Tab`, pero cambiando entre ventanas individuales en vez de apps.

## Qué hace

- Corre como app de barra de menú.
- Escucha `Option+Tab` globalmente.
- Muestra un overlay centrado con todas las ventanas top-level detectables.
- Usa orden reciente de uso por ventana para que el primer salto vaya a la ventana anterior.
- Activa la ventana seleccionada al soltar `Option`.
- Soporta `Option+Shift+Tab` para navegar en reversa.
- Soporta flechas izquierda/derecha y arriba/abajo para mover la selección mientras el overlay está abierto.
- Intenta mostrar miniaturas reales con `ScreenCaptureKit` cuando `Screen Recording` está concedido.
- Permite salir desde el icono de barra de menú o con `Control+Option+Q`.

## Por qué no `Command+Tab`

Apple documenta `Command+Tab` como un atajo reservado del sistema para moverse entre apps abiertas y explícitamente indica que no se debe sobrescribir. Para un comportamiento confiable, la app usa `Option+Tab`.

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

La ruta sensible de runtime de macOS (`Accessibility`, `Screen Recording`, `AXUIElement`, `CGEventTap`, `NSPanel`, `ScreenCaptureKit`) no se cubre por unit test directo.

## Troubleshooting rápido

Si no salen miniaturas:

1. abre la app
2. prueba `Option+Tab`
3. revisa el log:

```bash
/usr/bin/log show --last 10m --style compact --predicate 'subsystem == "com.iyubinest.apswitcher"'
```

Si el log dice `Screen Recording is not granted`, resetea TCC y vuelve a autorizar:

```bash
tccutil reset ScreenCapture com.iyubinest.apswitcher
```

Luego reinicia la app y vuelve a aceptar `Screen Recording`.

## Empaquetar como `.app`

```bash
./scripts/build_app.sh
```

Esto genera:

```text
dist/ApSwitcher.app
```

Luego puedes abrirla con:

```bash
open dist/ApSwitcher.app
```
