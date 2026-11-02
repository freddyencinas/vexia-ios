# CLAUDE.md

Guía para Claude Code en `vexia-ios` (app nativa SwiftUI de Vexia). Responder al usuario en español; código y comentarios en inglés.

## Reglas del usuario
- NUNCA hacer push a GitHub. Commit solo si el usuario lo pide.
- La app apunta a **producción** por defecto (`https://api.vexia.app`, MCP `https://copilot.vexia.app`). Cualquier acción que escriba datos (guardar tasa, crear transacción, etc.) en el simulador afecta datos reales: no hacerlo sin permiso.
- No iniciar sesión ni aprobar pantallas de Google/Face ID en nombre del usuario.
- No agregar secretos al código. Claves de usuario → Keychain; config secreta futura → `Secrets.xcconfig` (ignorado por git).
- Existe una app Flutter hermana (`../finance-app`) con la misma lógica: un fix aquí debe considerar el mismo fix allá (y viceversa). No mencionar Flutter en comentarios del código ni en el README (repo independiente).
- Cambios de backend van en `../backend` (Cloudflare Workers + Hono); deploy solo con autorización explícita.

## Stack
- Xcode 27, iOS 27 SDK (deployment target 27.0), Swift 6 con `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` y `SWIFT_APPROACHABLE_CONCURRENCY`.
- SwiftUI + `@Observable`, Liquid Glass (`glassEffect`, `.buttonStyle(.glass)`), `TabView` con `Tab(role: .prominent)`.
- Sin dependencias externas (no SPM/CocoaPods). Google Sign-In = OAuth 2.0 + PKCE con `ASWebAuthenticationSession`.
- Proyecto con carpetas sincronizadas: archivos nuevos en `Vexia/` o `VexiaTests/` se agregan solos al target.

## Comandos
```bash
# Tests (Swift Testing)
xcodebuild -project Vexia.xcodeproj -scheme Vexia \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -parallel-testing-enabled NO test

# Build + instalar en simulador
xcodebuild -project Vexia.xcodeproj -scheme Vexia -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath /tmp/vexia-dd build
xcrun simctl install booted /tmp/vexia-dd/Build/Products/Debug-iphonesimulator/Vexia.app
xcrun simctl launch booted com.vexia.finance.ios

# Modo oscuro / claro del simulador
xcrun simctl ui booted appearance dark   # o light
```
Correr los tests después de cada cambio. Verificación visual: Maestro (`~/.maestro/bin/maestro test flow.yaml`) en el simulador.

### Código muerto (Periphery, equivalente a knip)
```bash
periphery scan --strict -- -destination 'generic/platform=iOS Simulator'   # config en .periphery.yml
```
- Correrlo antes de cada versión (TestFlight/App Store) o tras cambios grandes. Debe salir "No unused code detected".
- Sin uso de verdad → borrarlo. Funcionalidad pendiente → conservar con `// periphery:ignore - pending: <qué falta>`.
- Propiedades de entidades mapeadas desde la API pero aún no mostradas se conservan (`retain_assign_only_properties`).

## Idiomas (String Catalog)
- `Vexia/Resources/Localizable.xcstrings`: español = idioma base (las claves son el texto en español), inglés traducido.
- Literales en APIs SwiftUI (`Text`, `Button`, `Label`, `navigationTitle`…) ya se localizan. Strings fuera de la vista (ViewModels, `enum` `title`, errores, ternarios) → `String(localized: "…")`. Helpers propios que reciben literales → parámetro `LocalizedStringKey`.
- No localizar: códigos/keys de API, prompts de IA, logs, datos del backend.
- Idioma = idioma por app de iOS (`SettingsRepository.language` lee `Bundle.main.preferredLocalizations`); no hay selector propio.
- Al agregar textos: compilar en Xcode (agrega las claves al catálogo) y traducir al inglés; `catalogIsFullyTranslatedToEnglish` falla si falta alguna.

## Arquitectura (Clean Architecture + MVVM, dependencias hacia adentro)
```
Presentation  (Views + @Observable ViewModels por feature)
   │ usa
Domain        (Entities, protocolos de Repositories, UseCases, puertos de IA) — sin SwiftUI/URLSession
   ▲ implementa
Data          (Remote/Local repositories, Mappers JSON→Entity, adaptadores IA, GoogleOAuthProvider)
Core          (APIClient, JSON, Keychain, Formatters, Design tokens, AppContainer)
```
- `Core/DI/AppContainer.swift` es el único composition root: solo ahí se instancian implementaciones concretas.
- Nuevas capacidades externas = protocolo en `Domain` + adaptador en `Data` + 1 línea en `AppContainer` + mock en `VexiaTests/Mocks.swift`.
- `Data/DTOs/Mappers.swift`: los fallbacks de keys (camelCase/snake_case, nombres legacy) son intencionales. No “limpiarlos” sin revisar el backend.
- `APIClient`: refresh de token único en vuelo; keys Keychain `access_token`, `refresh_token`, `user_id`.

## Gotchas
- **Aislamiento MainActor por defecto**: closures que el sistema ejecuta fuera del main thread deben ser `nonisolated`/`@Sendable`. Ej.: los providers dinámicos de `UIColor` en `Theme.swift` (SwiftUI resuelve colores en su hilo de render → crash `_dispatch_assert_queue_fail` si no). Hay test de regresión.
- **Colores**: usar tokens `VexiaColor` (adaptativos). `brandBlue` para texto/íconos; `brandFill` para fondos con texto blanco. `Color(hex:)` fijo solo sobre superficies que no cambian con el modo (p. ej. `heroGradient`). Colores del backend con `Color(hexString:)` (se aclaran en oscuro).
- **Barras de progreso**: usar `BarMetrics.width(total, fraction)` (evita anchos negativos/NaN). No nombrar tipos `Layout` (choca con SwiftUI).
- **Cantidades**: `Fmt.quantity(_:crypto:)` para acciones/cripto; nunca redondear a entero.
- **Info.plist generado** (`INFOPLIST_KEY_*` en el pbxproj): no admite keys custom como `GIDClientID`; el client ID de Google va en `AppConfig.googleIOSClientID`.
- `/crypto/pnl` devuelve IDs (UUID) de exchange en vez de nombres; el ViewModel los filtra. Fix real pendiente en backend.
- Tab bar se minimiza al hacer scroll: en Maestro, relanzar la app antes de tocar tabs.
