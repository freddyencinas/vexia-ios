# Vexia iOS (native SwiftUI)

Native personal finance app for **iOS 27**, built with **Clean Architecture + MVVM**.
Tracks income, expenses, transfers and currency exchange, stock and crypto investments, budgets,
and includes an AI assistant (voice/receipt capture and budget planning chat).

## Requirements
- Xcode 27+, iOS 27 SDK (deployment target 27.0), Swift 6 (default actor isolation = MainActor).
- Open `Vexia.xcodeproj` (synchronized folders: new files are added to the target automatically).
- No third-party dependencies.
- Backend: production by default (`https://api.vexia.app`, MCP `https://copilot.vexia.app`).
  For a local backend, change the URLs in the app: Ajustes → Servidor (UI is in Spanish).
  The LLM API key is entered in Ajustes → Inteligencia artificial.

## Layers (dependencies point inward)

```
Presentation (SwiftUI Views + @Observable ViewModels)
        │ uses
Domain (Entities, Repository protocols, UseCases, AI ports)   ← no SwiftUI/URLSession/SDKs
        ▲ implements
Data (Remote repositories, JSON→Entity mappers, AI adapters, Local storage)
        │
Core (APIClient, JSON, Keychain, Formatters, Design tokens, DI container)
```

| Folder | Contents |
|---|---|
| `Domain/Entities` | `Transaction`, `Account`, `Budget`, `DashboardOverview`, … (plain structs) |
| `Domain/Repositories` | protocols `AuthRepository`, `TransactionsRepository`, `BudgetAgent`, `GoogleIdentityProvider`, … |
| `Domain/UseCases` | business rules: `SaveTransactionUseCase`, `RestoreSessionUseCase`, `ClassifyTransactionUseCase`, `GoogleLoginUseCase`, `PINHasher` |
| `Domain/AI` | **AI ports**: `LLMProvider`, `SpeechTranscriber`, `PromptRepository`, `VexiaResult` |
| `Data/DTOs/Mappers.swift` | JSON → Domain mappers (tolerant to camelCase/snake_case and legacy keys) |
| `Data/Repositories` | REST API repositories + local settings (UserDefaults/Keychain) |
| `Data/Remote` | `GoogleOAuthProvider` (OAuth 2.0 + PKCE via `ASWebAuthenticationSession`, no SDK) |
| `Data/AI` | adapters: `CloudflareLLMProvider`, `AppleFoundationModelsProvider`, `FallbackLLMProvider`, `AppleSpeechTranscriber` |
| `Core/DI/AppContainer.swift` | composition root: the only place that knows concrete implementations |
| `Presentation/<Feature>` | `XViewModel.swift` + `XView.swift` per feature |

## Key flows
| Flow | Where |
|---|---|
| Session restore (splash → lock / main / login) | `RestoreSessionUseCase` + `SessionViewModel` + `RootView` |
| Token refresh (single in-flight refresh) | `Core/Networking/APIClient.swift` |
| Google Sign-In | `GoogleIdentityProvider` → `GoogleOAuthProvider` → `GoogleLoginUseCase` → `POST /auth/google` |
| Transaction save routing | `SaveTransactionUseCase`: same-currency transfer → `/transfers`; FX and income/expense → `/transactions` |
| Per-transaction exchange rates | `LoadTransactionRatesUseCase` + `RatesStrip` (tap = "this time only" / "save", long press = refresh) |
| Voice / receipt → transaction | `ClassifyTransactionUseCase` + `VexiaCaptureViewModel` |
| AI prompts (remote with 24 h cache, embedded fallback) | `RemotePromptRepository` + `Resources/Prompts/*.txt` |
| Budget planning chat (A2UI widgets) | `BudgetAgent` / `HTTPBudgetAgent` + `AgentWidgetView` |
| Main navigation | `MainTabView` (iOS 27 `TabView`, `Tab(role: .prominent)`, `tabViewBottomAccessory`) |

## Pluggable AI
Use cases depend only on `LLMProvider`. Default chain: Cloudflare Workers AI (text + vision)
→ Apple Foundation Models on-device (text). Switching provider = new class in `Data/AI` + 1 line in `AppContainer`.

## Design and dark mode
Tokens live in `Core/Design/Theme.swift` (`VexiaColor`), all light/dark adaptive.
- `brandBlue` = text/icons/tint; `brandFill` = solid surfaces carrying white content.
- Backend colors (`Color(hexString:)`) are automatically lightened in dark mode when too dark.
- Avoid fixed `Color(hex:)` in views except on surfaces that don't change with the mode (brand gradient).

## Localization
Spanish (development language) and English via a String Catalog (`Vexia/Resources/Localizable.xcstrings`).
- Spanish literals are the keys: `Text("Gasto")` is localized as-is; strings built outside SwiftUI views use `String(localized:)`.
- Language = the per-app language in iOS Settings (Ajustes → Idioma opens it). UI, AI prompts, dictation and `Accept-Language` follow it.
- Money keeps the regional format ("Bs 1.539,00") in both languages; dates and month names follow the app language.
- A test fails if any catalog key lacks an English translation.

## Tests
```bash
xcodebuild -project Vexia.xcodeproj -scheme Vexia \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -parallel-testing-enabled NO test
```
Swift Testing: AI parser, prompts, use cases with mocks, mappers, PIN hashing,
Google Sign-In (PKCE), bar metrics, adaptive colors (resolved off the main thread), quantity formatting.

## Configuration and secrets
- No secrets in the source. The Google iOS OAuth client ID is public by design (PKCE, no client secret).
- The LLM API key is entered by the user (Ajustes → Inteligencia artificial) and stored in the Keychain.
- Session tokens are stored in the Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
- `.gitignore` excludes `xcuserdata/`, build output, signing profiles/certificates and secret files (`.env`, `Secrets.xcconfig`, `GoogleService-Info.plist`).

## Roadmap
- Chat WebSocket, complex A2UI widgets (BudgetProposalCard/BudgetSetupCard),
  full budget editing, receipt share extension,
  more languages.
