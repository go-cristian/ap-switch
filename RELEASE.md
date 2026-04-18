# Release Automation

Este repo publica un `.dmg` instalable mediante GitHub Actions cuando haces push de un tag `vX.Y.Z`.

## Flujo

1. crear un tag como `v1.0.0`
2. hacer push del tag
3. GitHub Actions:
   - corre `swift test`
   - construye `ApSwitcher.app`
   - firma la app con `Developer ID Application`
   - genera `dist/release/ApSwitcher-X.Y.Z.dmg`
   - notariza app y dmg con Apple
   - adjunta el `.dmg` al GitHub Release

Workflow:

- [.github/workflows/release.yml](/Users/cristian/repos/iyubinest/ApSwitcher/.github/workflows/release.yml)

Script principal:

- [build_release_dmg.sh](/Users/cristian/repos/iyubinest/ApSwitcher/scripts/build_release_dmg.sh)

## Secrets requeridos en GitHub

Agregar estos secrets en el repo:

- `MACOS_DEVELOPER_ID_APPLICATION`
  - debe ser del team `3EUA8SZ453`
  - valor ejemplo: `Developer ID Application: Cristian Gomez (3EUA8SZ453)`
- `MACOS_DEVELOPER_ID_P12_BASE64`
  - contenido base64 del `.p12` del certificado `Developer ID Application`
- `MACOS_DEVELOPER_ID_P12_PASSWORD`
  - password del `.p12`
- `APPLE_NOTARY_KEY_ID`
  - key id de App Store Connect API key
- `APPLE_NOTARY_ISSUER_ID`
  - issuer id de App Store Connect API key
- `APPLE_NOTARY_API_KEY`
  - contenido completo del archivo `.p8`

## Generar el secret del certificado

Exporta el certificado `Developer ID Application` a `.p12` y luego:

```bash
base64 -i developer-id-application.p12 | pbcopy
```

Pega ese valor en `MACOS_DEVELOPER_ID_P12_BASE64`.

## Generar una release

```bash
git tag v1.0.0
git push origin v1.0.0
```

## Notas

- Este flujo no usa `Apple Development`; para distribución real usa `Developer ID Application`.
- El workflow valida que la app quede firmada con el team `3EUA8SZ453`.
- No uses certificados de otros teams aunque existan en el keychain o en otras máquinas.
- `.signing/` permanece fuera del repo y no debe commitearse.
- Si cambias la firma o el bundle id, revisa también TCC local para pruebas manuales.
