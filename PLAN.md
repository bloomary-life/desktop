# PLAN: Bloomary Desktop (macOS)

Implementation plan for the macOS app in `bloomary/desktop/`. Goal: **exactly
the same functionality as the iOS app** (`bloomary/ios`). Architecture rules and
invariants live in [ADR.md](ADR.md); this file is the build checklist.

Source of truth: iOS Swift sources (`Application/`, `Features/`, `Shared/` —
25 files) + `BloomaryTests/` (5 suites). iOS project is not modified.

## Target structure

```
bloomary/desktop/
├── ADR.md                            # architecture reference (done)
├── PLAN.md                           # this file
├── Bloomary Desktop.xcodeproj       # new project, macOS 14+ deployment target
├── Application/
│   ├── App/BloomaryDesktopApp.swift
│   ├── DI/AppContainer.swift
│   ├── Config/{AppConfiguration.swift, AppConfiguration.plist}
│   └── Navigation/MainSplitView.swift
├── Features/
│   ├── Insights/UI/InsightsView.swift
│   ├── Drafts/UI/DraftsView.swift
│   ├── Drafts/Model/{Draft.swift, DraftStore.swift}
│   ├── Drafts/Storage/DraftRepository.swift
│   ├── Editor/UI/{EditorView.swift, RichTextEditor.swift}
│   ├── LinkedInAuth/UI/LinkedInProfilePhoto.swift
│   ├── LinkedInAuth/Model/{LinkedInModels.swift, LinkedInSessionStore.swift}
│   ├── LinkedInAuth/API/LinkedInAuthService.swift
│   ├── LinkedInAuth/Storage/AuthTokenStore.swift
│   ├── LinkedInPost/API/{LinkedInPostService.swift, MultipartFormDataBuilder.swift}
│   ├── Feedback/UI/FeedbackView.swift
│   ├── Feedback/API/FeedbackService.swift
│   └── Account/UI/AccountSettingsView.swift
├── Shared/
│   ├── UI/AppStyle.swift
│   ├── Network/Coding.swift
│   └── Observability/{AppTelemetry.swift, CrashReporter.swift}
└── Bloomary DesktopTests/           # Swift Testing, ports of the 5 iOS suites
```

## Configuration (copy values from iOS)

`AppConfiguration.plist`: api.baseURL `https://api.bloomary.life`,
linkedIn.callbackURLScheme `bloomary`, storage.draftsKey `bloomary_drafts`,
storage.linkedInTokenKey `bloomary_linkedin_token`, observability (sentryDSN,
sentryEnvironment `production`, sentryTracesSampleRate 0.1, telemetryDeckAppID
`5BC98248-6BB2-4B83-AB26-308C92836215`, telemetryDeckNamespace `eu.dailymind`).
Observability section optional → disabled. Missing/invalid plist → fatalError.

`Info.plist`: display name "Bloomary", URL type with scheme `bloomary`
(CFBundleURLName `com.dailymind.bloomary.desktop`), `ITSAppUsesNonExemptEncryption=false`,
category productivity. No `LSRequiresIPhoneOS`. macOS sandbox: outgoing network,
user-selected file read (for feedback attachments); app group not needed.

## Functional spec (mirrors iOS exactly)

### 1. App shell — `BloomaryDesktopApp`, `AppContainer`, `MainSplitView`

- Launch sequence: `CrashReporter.start()` → `AppConfiguration.load()` →
  `AppTelemetry.start(configuration:)` → track `app_opened` → build container.
- Container wires: `UserDefaultsDraftRepository(storage.draftsKey)`,
  `AuthTokenStore(storage.linkedInTokenKey)`, `LinkedInAuthService(baseURL,
  callbackURLScheme, tokenStore)`, `LinkedInPostService(baseURL)`,
  `FeedbackService(baseURL)`, `DraftStore(repository, telemetry)`,
  `LinkedInSessionStore(tokenStore)`. Stores injected as environment objects.
- Root: `NavigationSplitView` with sidebar listing the same 4 sections in the
  same order — **Insights, Drafts, Editor, Settings** — same SF Symbols
  (`chart.line.uptrend.xyaxis`, `doc.text`, `square.and.pencil`, `gearshape`).
  Default selection = **Editor**. Selecting Editor without a draft-open intent
  calls `draftStore.startNewPost()` (iOS `opensDraftInEditor` logic).
- `.tint(AppStyle.lime)`, `.preferredColorScheme(.light)`.
- Overlay: floating draggable ladybug button — 52×52 coral circle, white
  `ladybug` SF Symbol 20pt semibold, default position (x: 44, y: max(92,
  82% of height)), drag clamped 34pt from window edges, accessibility label
  "Send feedback"; tap → feedback sheet + `feedback_opened`.
- Overlay: "Posted to LinkedIn" toast — top center, capsule, panel bg 96%,
  subheadline semibold ink, shadow, appears 1.6s (fade+move), shown after
  successful post; selection switches to Insights.
- On appear and on `memberID` change: `draftStore.setOwnerID(memberID)`.

### 2. Insights — `InsightsView`

- Caption "Public LinkedIn signals", title "People turn their lived work into
  visible opportunity." (title2 semibold).
- The same 6 static cards, data verbatim from iOS:
  1. `$2M revenue` — Christian Krause / Quota League
  2. `$100K+ MRR pipeline` — Alyona Mysko
  3. `600+ leads` — Jim Taylor
  4. `2x in 60 days` — Lauren Tickner
  5. `3x client income` — Trisha Paul
  6. `7 inbound leads/week` — Rita Kerola
  (summaries and LinkedIn activity URLs copied from `InsightsView.swift`)
- Card: coral caption topline, ink headline title, muted subheadline summary,
  panel bg, 8pt radius. Tap → `NSWorkspace.shared.open(url)`; on success track
  `insight_opened`.

### 3. Drafts — `DraftsView`, `DraftStore`, `DraftRepository`, `Draft`

- Caption "Saved locally. Max 15 drafts.", title "Drafts".
- Empty: `ContentUnavailableView("No drafts", systemImage: "doc.text",
  description: "Saved drafts will appear here.")`.
- List: single panel card (8pt radius), rows separated by insets dividers.
  Row = title (first line of body, trimmed, max 72 chars, else "Untitled
  draft", headline ink), body preview (subheadline muted, 3 lines), updatedAt
  (`.formatted(date: .abbreviated, time: .shortened)`, caption muted), ✕ delete
  button (32×32, muted, accessibility "Delete draft").
- Tap row → `draftStore.openDraft(draft)` + switch to Editor.
- `DraftStore` (verbatim logic): placeholder `"Write a LinkedIn post..."`;
  `saveCurrentDraft` trims, empty → status "Draft is empty"; unchanged → status
  "Draft saved" without persisting; else update existing (new updatedAt) or
  prepend new draft, cap 15, persist, track `draft_saved`, status "Draft saved".
- `saveOpenedDraftAndClearEditor`, `openDraft`, `deleteDraft`,
  `deletePostedDraftIfSaved` (removes the draft whose id was captured before
  the property is nilled), `deleteAccountData(ownerID:)` clears
  owner scope + `signed-out` scope, `setOwnerID` reloads and starts new post.
- `UserDefaultsDraftRepository`: JSON via `JSONEncoder/Decoder.app` (ISO-8601
  dates), key `<draftsKey>.<ownerID ?? "signed-out">`.

### 4. Editor — `EditorView`, `RichTextEditor`

- Caption "Saved locally"; header row: back chevron (28×28, "Back to drafts")
  → switch to Drafts; title "Write your post".
- Editor card (panel bg, 8pt radius): toolbar row + text area.
- Toolbar (44pt height, white bg, bottom hairline ink 12%): text buttons
  **B** (bold weight) **I** (italic) **S** (strikethrough) **U** (underline)
  **`<>`** **T/**, vertical divider, icon buttons `list.bullet`, `list.number`.
  Buttons 44×44, ink 72%.
- Commands (Unicode transforms, same as iOS):
  - bold: offset ranges A–Z +0x1D5D4, a–z +0x1D5EE, 0–9 +0x1D7EC
  - italic: A–Z +0x1D608, a–z +0x1D622 (no digits)
  - strikethrough / underline: append combining U+0336 / U+0332 to each char
  - code: wrap selection in backticks
  - clear: strip backticks, combining marks, and map Mathematical Alphanumeric
    Symbols back to ASCII (ranges 0x1D5D4–0x1D63B, 0x1D7EC–0x1D7F5)
  - bullets: prefix selected lines with `- `; numbered: `1. `, `2. `, …
- `RichTextEditor`: **NSTextView via NSViewRepresentable**, plain-text binding,
  body font, ink color, word wrap, no rich-text attributes, min height 260,
  padding 12 (+36 trailing). First edit → track `editor_started`.
- Clear button (✕, 32×32, top-right inside editor card): calls
  `saveOpenedDraftAndClearEditor()`; hidden and disabled when text is empty.
- Preview card (white bg, 8pt radius, ink 12% stroke): if connected — profile
  photo 48 (circle, async load, `Bloomary/1.0` User-Agent, 12s timeout,
  `returnCacheDataElseLoad`, blue #0A66C2 "in" fallback), name (headline),
  displayHeadline ?? "Now" (subheadline muted); else "Connect LinkedIn to
  preview your profile." Body: editor text, or "Preview appears here." if blank.
- Bottom action bar (paper bg, top hairline): "Save draft" (secondary) →
  `saveCurrentDraft()` + switch to Drafts; "Post to LinkedIn" / "Posting..."
  (primary, disabled while posting).
- Post flow: track `post_started` → if not connected, run sign-in
  (`linkedin_connect_started` / `linkedin_connected`) →
  `postService.publish(text:credential:)` → `deletePostedDraftIfSaved()` →
  status "Posted to LinkedIn", track `post_succeeded`, toast + Insights switch →
  open `https://www.linkedin.com/in/me/recent-activity/all/`. On error: status =
  error description, track `post_failed`.

### 5. LinkedIn auth — `LinkedInAuthService`, `LinkedInModels`,
`LinkedInSessionStore`, `AuthTokenStore`, `LinkedInProfilePhoto`

- Sign-in flow (identical to iOS, see ADR invariants): cli/start →
  `ASWebAuthenticationSession` (presentation anchor = key window; ephemeral
  session once after account deletion) → intercepted `/api/linkedin/callback`
  completion → poll cli/result 45× `wait=2` → save token to Keychain.
  Errors: invalidStartURL, missingWindow, cancelled, timedOut, server(message)
  with the same user-facing strings.
- Models: `LinkedInProfile` (memberId, name, pictureUrl, email, headline,
  localizedHeadline; `displayHeadline` = trimmed localizedHeadline else trimmed
  headline else nil), `LinkedInToken` (accessToken, idToken?, tokenType?,
  scope?, expiresIn?, profile, connectedAt). CodingKeys snake/camel mapping as
  iOS.
- `LinkedInSessionStore`: `isConnected` = non-empty accessToken + memberID,
  `postCredential`, `setToken` (clears status, persists), `disconnect`,
  `deleteAccountData` (incl. synchronizable Keychain items), `statusMessage`.
- `AuthTokenStore`: Keychain generic password, service
  `com.dailymind.bloomary.desktop.linkedin`, update-or-add on save.

### 6. Posting — `LinkedInPostService`, `MultipartFormDataBuilder`

- `POST /api/linkedin/post`, multipart boundary `Boundary-<UUID>`, fields
  `accessToken`, `memberId`, `commentary` (trimmed). Builder format:
  `--boundary\r\nContent-Disposition: form-data; name="k"\r\n\r\nv\r\n` …
  `--boundary--\r\n`.
- Errors: empty → "Post is empty."; missing credential → "Connect LinkedIn
  first."; non-2xx → server message from `{error, errorDescription}` else
  "LinkedIn post failed."

### 7. Feedback — `FeedbackView`, `FeedbackService`

- Sheet (`NavigationStack`, title "Feedback", Close top-right). Also reachable
  from Settings.
- Welcome panel: "Welcome" + the iOS copy verbatim ("We're open to your
  thoughts…").
- Form: Title (`TextField`, roundedBorder), message (`TextEditor` min height
  180, white bg, 8pt radius, ink 12% stroke), "Attach images"
  (`photo.on.rectangle.angled`, secondary style, up to 5 images via
  `PhotosPicker`; each loaded as Data → base64, filename `feedback-N.jpg`),
  attachment count caption ("N image(s) attached"), status message,
  "Send feedback" / "Sending..." primary button.
- Send: empty trimmed message → "Feedback message is empty.";
  `POST /api/feedback` JSON `{name, linkedInId, email, title, message,
  attachments:[{filename, content}]}`; identity from LinkedIn profile (empty
  strings when signed out). Success → "Sent. Confirmation was emailed to you.",
  clear form, track `feedback_sent`; failure → error description.
- Links: "Talk instead" → `https://calendly.com/dailymind/20min`;
  "Privacy policy" → `https://bloomary.life/privacy/`.

### 8. Settings / Account — `AccountSettingsView` (+ `AccountDetailView`)

- Title "Settings".
- Signed out: "Connect LinkedIn" / "Connecting..." primary button → sign-in
  flow; errors → session statusMessage.
- Signed in: Community link card (`person.2`, "Community", panel bg, ink 16%
  stroke) → `https://t.me/+NDQcpuABme9iYTU0`; coral "Send feedback" button
  (`ladybug`, white headline) → feedback sheet + `feedback_opened`; toolbar ☰
  button (24pt in 52×52 panel circle, "Account") → `AccountDetailView`.
- Account detail: title "Account"; profile card (photo 56, name title3
  semibold, headline muted, "Registered \<connectedAt, numeric date\>" caption
  muted); "Log out" / "Logging out..." (secondary) → `POST disconnect` → clear
  token, status "Logged out.", dismiss; bottom bar destructive "Delete
  account" / "Deleting..." → confirmation dialog "Delete account?" with the iOS
  message verbatim ("This deletes your LinkedIn connection, local drafts, and
  local authorization token. Support, legal, and security records may be
  retained where required.") → `POST /api/account/delete` →
  `draftStore.deleteAccountData`, `sessionStore.deleteAccountData`,
  `requireEphemeralSignInOnce()`, status "Account deleted.", track
  `account_deleted`, dismiss.

### 9. Shared

- `AppStyle`: palette + `PrimaryButtonStyle` / `SecondaryButtonStyle` exactly as
  iOS (see ADR invariants); `nsInk` replaces `uiInk`.
- `Coding`: `JSONDecoder/Encoder.app` with ISO-8601 date strategies.
- `AppTelemetry`: TelemetryDeck, start only when appID non-empty, random
  default user UUID, no session signals; same 12 events (ADR).
- `CrashReporter`: Sentry, start only when DSN non-empty, environment, traces
  sample rate, crash handler, app-hang tracking, auto performance tracing,
  `sendDefaultPii=false`; omit iOS-only watchdog flag.

## Tests (port the 5 iOS suites, Swift Testing)

Same framework (`Testing`, `@Test`/`#expect`), same coverage:

1. `AppConfigurationTests` — plist decoding, defaults, invalid/missing values.
2. `DraftStoreTests` — empty draft not persisted, trim+persist+telemetry,
   update-in-place, save-and-clear, delete, cap/scoping behavior, with an
   `InMemoryDraftRepository` test double.
3. `LinkedInModelsTests` — decoding, CodingKeys mapping, displayHeadline rules.
4. `LinkedInSessionStoreTests` — isConnected, setToken/disconnect/delete
   against a fake token store.
5. `MultipartFormDataBuilderTests` — exact body bytes/boundary format.

## Build phases

1. **Scaffold** — Xcode macOS project (SwiftUI, Swift Testing), folder
   structure per above, config plist + Info.plist, AppStyle, Coding. Compiles,
   launches to empty split view.
2. **Shared + models** — Draft, LinkedIn models, stores, repositories,
   Keychain store, telemetry/crash wiring. Port all 5 test suites here; green.
3. **Auth + services** — LinkedInAuthService, PostService + multipart builder,
   FeedbackService.
4. **Editor** — NSTextView RichTextEditor with all 8 commands, toolbar,
   preview, action bar, full post flow.
5. **Remaining views** — Drafts, Insights, Settings/Account, Feedback, floating
   button, toast, MainSplitView wiring.
6. **Parity verification** — run test suite; then manual side-by-side
   walkthrough with the iOS app covering: launch events, all 4 sections, draft
   CRUD + cap + owner scoping, all 8 format commands, preview states, sign-in,
   post success/failure, feedback with 0/5 attachments, logout, account
   deletion, offline error messages.

## Out of scope

- Any change to `bloomary/ios/**` (hard constraint).
- Backend changes; shared SwiftPM extraction; Windows/Linux; Catalyst.
- New features, redesign, dark mode, localization. Replicate iOS behavior
  as-is; log any suspected iOS bugs in `bloomary/wiki/` instead of fixing here.
