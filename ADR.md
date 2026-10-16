# ADR-001: Bloomary — Cross-Platform App Architecture

- Status: Accepted
- Date: 2026-08-30
- Scope: all Bloomary client apps (iOS: `bloomary/ios`, macOS: `bloomary/desktop`)

This ADR is the standing architecture reference for Bloomary clients. Consult it
before any refactor, port, or new-platform app. It records the decision, the
structural rules, and the invariants that must survive any refactoring.

## Decision

Client apps are **SwiftUI, one native app per Apple platform**, sharing an
identical architecture. No cross-platform UI framework (Electron/Tauri/React
Native) — those force a rewrite and lose native text editing, keychain, and
web-auth behavior. Code is **copied and adapted** between platform projects, not
shared by reference, so each app can evolve independently. Extracting a shared
SwiftPM package is an allowed future step if drift becomes painful.

## Architecture: feature-sliced modules (FSD equivalent)

FSD is a React-ecosystem methodology; this is its Swift equivalent. Every client
app uses the same three-layer structure:

```
Application/   composition root: app entry, DI container, config, root navigation
Features/      independent feature modules: <Feature>/{UI,Model,API,Storage}
Shared/        cross-feature code: UI style, network helpers, observability
```

FSD layer mapping: `app` → `Application`, `pages/widgets/features/entities` →
`Features/<Name>`, `shared` → `Shared`.

### Rules (must hold after any refactor)

1. **One-way dependencies**: `Application → Features → Shared`. Features never
   import each other; Shared imports nothing from the app.
2. **Composition root**: all wiring happens in `AppContainer` (Application/DI).
   Features receive dependencies, never construct siblings.
3. **MVVM inside features**: SwiftUI views + `@MainActor ObservableObject`
   stores + Foundation services. TCA/VIPER rejected — boilerplate exceeds the
   app's complexity.
4. **Feature folder layout**: `UI/` (views), `Model/` (types, stores),
   `API/` (network services), `Storage/` (persistence). Not all are required.
5. **Platform ports** keep feature names, file responsibilities, and behavior
   identical; only platform-boundary code changes (see Porting map).

## Invariants (do not change without a new ADR)

These are the contract between clients and the backend, and between app versions
and their stored user data:

- **API endpoints** (base `https://api.bloomary.life`):
  - `GET  /api/linkedin/cli/start` → `{authUrl, state, redirectUri, pollUrl}`
  - `GET  /api/linkedin/cli/result?state=…&wait=2` → `{status, token?, error?…}`,
    statuses `done`/`pending`/`error`
  - `GET  /api/linkedin/callback` (intercepted redirect completion)
  - `POST /api/linkedin/disconnect` `{linkedInId}`
  - `POST /api/account/delete` `{linkedInId}`
  - `POST /api/linkedin/post` multipart: `accessToken`, `memberId`, `commentary`
  - `POST /api/feedback` JSON `{name, linkedInId, email, title, message, attachments[]}`
- **Error contract**: error bodies are `{error, errorDescription?}`; clients
  surface `errorDescription ?? error`.
- **Storage**: drafts in UserDefaults as JSON, key `<draftsKey>.<ownerID|"signed-out">`,
  `draftsKey = bloomary_drafts`, max 15 drafts, newest first. LinkedIn token in
  Keychain, service `com.dailymind.bloomary.desktop.linkedin`, account
  `bloomary_linkedin_token`; account deletion also removes synchronizable items.
- **JSON coding**: ISO-8601 date strategies (`JSONDecoder/Encoder.app`).
- **Auth flow**: start → `ASWebAuthenticationSession` (callback scheme
  `bloomary`) → optional intercepted-callback completion → poll result up to
  45 rounds × `wait=2`. Ephemeral web session once after account deletion.
- **Editor formatting**: plain text only, via Unicode transforms —
  bold/italic = Mathematical Alphanumeric Symbols (digits mapped for bold),
  strikethrough/underline = combining marks U+0336/U+0332, code = backtick wrap,
  clear = strip all of the above, bullets = `- ` prefix, numbered = `N. ` prefix.
- **Telemetry events** (TelemetryDeck, namespace `eu.dailymind`): `app_opened`,
  `insight_opened`, `editor_started`, `draft_saved`, `linkedin_connect_started`,
  `linkedin_connected`, `account_deleted`, `post_started`, `post_succeeded`,
  `post_failed`, `feedback_opened`, `feedback_sent`.
- **Style**: ink `0.067/0.071/0.059`, muted = ink 58%, paper `0.949/0.941/0.910`,
  panel `1.0/0.992/0.969`, coral `1.0/0.373/0.239`, lime `0.788/0.973/0.416`;
  primary button = lime fill, secondary = panel fill + ink 20% stroke, 8pt
  radius. Light mode only.

## Porting map (platform-boundary substitutions)

| iOS | macOS |
|---|---|
| `UITextView` via `UIViewRepresentable` | `NSTextView` via `NSViewRepresentable` |
| `UIApplication.open` | `NSWorkspace.shared.open` |
| Bottom `TabView` | `NavigationSplitView` sidebar, same sections |
| `PhotosPicker` | `PhotosPicker` (macOS 13+), else `NSOpenPanel` |
| `ASWebAuthenticationSession` | unchanged |
| Keychain, UserDefaults, URLSession | unchanged |
| Sentry watchdog-termination flag | omit (iOS-only) |

When adding a third platform: copy the feature set, apply this map extended with
the new platform's rows, keep every invariant above.

## Adding a feature (any platform)

1. New folder `Features/<Name>/` with `UI/Model/API/Storage` as needed.
2. Dependencies injected from `AppContainer`; no imports of other features.
3. Shared code goes to `Shared/` only when used by 2+ features.
4. Mirror the feature in the other platform app(s) in the same structure.
5. Add/extend Swift Testing suites mirroring the iOS test set.

## Consequences

- Per-platform codebases drift manually until a shared package is extracted.
- Backend contract and storage format changes require coordinated client updates
  and a new ADR.
- Refactors may reorganize inside layers but must preserve the dependency rule,
  the invariants, and observable behavior.
