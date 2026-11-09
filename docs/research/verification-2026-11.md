# Verification pass — 2026-11-09

Scope: facts that earlier research could not check because sites were unreachable. They feed code defaults for Dayflight's on-device OpenAI assistant (Chat Completions, streaming, tools) and its iOS 26 surfaces.

**Method and status**

- **Section A (OpenAI): verified.** All pages were fetched live through Firecrawl on 2026-11-09 from developers.openai.com: model pages, deprecations, the GPT-6 guide, the reasoning guide, the prompt-caching guide, and the Chat Completions and Models API reference.
- **Section B (Apple, App Store, GitHub Actions): NOT verified.** Both Firecrawl servers reported *"Insufficient credits"* (daily MCP allowance exhausted; resets 2026-11-10 07:33 UTC) on the first Apple request, so no Apple, App Store or GitHub page was fetched. The values in section B come from training knowledge (cutoff June 2026). Each is marked **UNVERIFIED** and should be re-checked at the URL listed before it becomes a hard dependency.

Confidence key: **High** = quoted from the primary source today · **Medium** = inferred from primary-source wording, or several consistent primary statements · **Low / UNVERIFIED** = not fetched; from memory.

---

## A. OpenAI

### A1. Current text model IDs, tiers and Chat Completions + tools support

| Claim | Verified value | Source | Confidence |
|---|---|---|---|
| Is there a "GPT-6 Luna"? Exact API id | Yes. `model` = **`gpt-6-luna`** (single snapshot `gpt-6-luna`; no dated snapshot). "Our most efficient model for focused, high-volume tasks." 1,050,000 context, 128,000 max output, knowledge cutoff May 18, 2026. | https://developers.openai.com/api/docs/models/gpt-6-luna | High |
| Current GPT-6 family IDs | `gpt-6-astra` (top), `gpt-6.1-sol`, `gpt-6.1-terra`, `gpt-6-sol`, `gpt-6-luna` | https://developers.openai.com/api/docs/guides/latest-model.md ; https://developers.openai.com/api/docs/models/all | High |
| Other current text IDs (in the Chat Completions `model` enum, not deprecated) | `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna`, `gpt-5.5`, `gpt-5.5-2026-04-23`, `gpt-5.4`, `gpt-5.4-mini`, `gpt-5.4-mini-2026-03-17`, `gpt-5.2`, `gpt-5.2-2025-12-11`, `gpt-5.2-pro` | https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create | High |
| Tier mapping of the 5.6 names | `gpt-5.6-terra` "roughly corresponds to the mini model tier"; `gpt-5.6-luna` "roughly corresponds to the nano model tier" | https://developers.openai.com/api/docs/models/gpt-5.6-terra.md ; …/gpt-5.6-luna | High |
| Cheapest class with function calling | `gpt-6-luna` ($0.10 / $0.50), then `gpt-5.6-luna` and `gpt-5.4-nano` ($0.20 in; nano is deprecated), then `gpt-5.4-mini` ($0.75 / $4.50) | model pages (see A3) | High |
| **GPT-6 Luna / GPT-6 Sol on Chat Completions with tools** | **"Chat Completions supports function calling only with `reasoning_effort` set to `none`."** Use Responses for reasoning together with tools. | https://developers.openai.com/api/docs/models/gpt-6-luna ; https://developers.openai.com/api/docs/models/gpt-6-sol.md ; latest-model guide ("GPT-6 Sol and GPT-6 Luna support function calling in Chat Completions only with `reasoning_effort: "none"`") | High |
| **GPT-6 Astra / GPT-6.1 Sol / GPT-6.1 Terra on Chat Completions with tools** | **Not supported.** "GPT-6 Astra, GPT-6.1 Sol, and GPT-6.1 Terra support Chat Completions, but tool calling requires Responses." The reasoning guide adds: "Chat Completions does not support function calling with GPT-6 Astra or GPT-6.1 Sol." | latest-model guide; https://developers.openai.com/api/docs/guides/reasoning.md | High |
| GPT-5.6 Luna / Terra on Chat Completions with tools | Endpoint `v1/chat/completions`: Supported; features include `streaming` and `function_calling`. Unlike the GPT-6 pages, there is **no** "reasoning_effort none only" restriction. The GPT-6.1 Terra guide says "When migrating from GPT-5.6 Terra … If your application calls tools through Chat Completions, migrate those requests to the Responses API", which implies 5.6 Terra does tools on Chat Completions today. | gpt-5.6-luna / gpt-5.6-terra model pages; latest-model guide | Medium (no explicit "works at any effort" sentence) |
| GPT-5.4 Mini on Chat Completions with tools | Chat Completions Supported; streaming and function_calling supported; reasoning default **`none`** | https://developers.openai.com/api/docs/models/gpt-5.4-mini.md | High |
| Streaming | "Streaming: Supported" on the `gpt-6-luna`, `gpt-6-sol`, `gpt-5.6-luna`, `gpt-5.6-terra` and `gpt-5.4-mini` pages | model pages | High |
| `reasoning_effort` per model | `gpt-6-luna`, `gpt-6-sol`, `gpt-6.1-terra`, `gpt-5.6-*`: `none`, `low`, `medium` (default), `high`, `xhigh`, `max`. `gpt-6-astra`: no `none` (HTTP 400). `gpt-6.1-sol`: `low`…`max`, no `none`/`minimal`. `gpt-5.4-mini`: `none` (default), `low`, `medium`, `high`, `xhigh`. **No current small model lists `minimal`.** Guide: "If your existing request uses `minimal`, start with `low`." | model pages; latest-model guide; reasoning guide | High |
| Is `gpt-4o-mini` still in the enum? | Yes, but marked "**Deprecated.** Announced shutdown date: 2027-01-14" (alias and `gpt-4o-mini-2024-07-18`) | Chat Completions reference (model enum) | High |

### A2. Deprecations (official page)

| Model | Shutdown date | Official recommended replacement | Source | Confidence |
|---|---|---|---|---|
| `gpt-5` / `gpt-5-2025-08-07` | **Dec 11, 2026** (announced 2026-06-11) | `gpt-5.6-sol` | https://developers.openai.com/api/docs/deprecations | High |
| `gpt-5-mini` / `gpt-5-mini-2025-08-07` | **Dec 11, 2026** (32 days from today) | `gpt-5.6-terra` | same | High |
| `gpt-5-nano` / `gpt-5-nano-2025-08-07` | **Dec 11, 2026** | `gpt-5.6-luna` | same | High |
| `gpt-4.1-mini` / `gpt-4.1-mini-2025-04-14` | **January 14, 2027** (announced 2026-10-14) | `gpt-6-luna` | same | High |
| `gpt-4o-mini` / `gpt-4o-mini-2024-07-18` | **January 14, 2027** | `gpt-6-luna` | same; the reference marks the alias deprecated with the same date | High |
| (related) `gpt-4.1` and `gpt-4o` snapshots | January 14, 2027 | `gpt-6-luna` | same | High |
| (related) `gpt-5.4-nano`, `gpt-5.1` | Apr 1, 2027 | `gpt-6-luna` / `gpt-6-sol` | same | High |
| (related) `gpt-4.1-nano`, `o4-mini`, `o3-mini`, `o1` | already shut down Oct 23, 2026 | `gpt-5.6-luna` / `gpt-5.6-terra` / `gpt-5.6-sol` | same | High |
| (related) `o3` | Dec 11, 2026 | `gpt-5.6-sol` | same | High |
| Notice policy | GA models get at least 6 months' notice; specialized variants at least 3 months; `preview` models can go with about 2 weeks' notice | same | High |

**Every model in Dayflight's current `modelPresets` is deprecated**, and the default (`gpt-5-mini`) stops working on **2026-12-11**.

### A3. Pricing (Standard tier, per 1M text tokens, from the model pages)

| Model | Input | Cached input | Cache write | Output | Source | Confidence |
|---|---|---|---|---|---|---|
| `gpt-6-luna` | $0.10 | $0.01 | $0.125 | $0.50 | https://developers.openai.com/api/docs/models/gpt-6-luna | High |
| `gpt-5.6-luna` | $0.20 | $0.02 | 1.25× input ($0.25) | $1.20 | https://developers.openai.com/api/docs/models/gpt-5.6-luna | High |
| `gpt-5.4-mini` | $0.75 | $0.075 | n/a (no write charge before 5.6) | $4.50 | https://developers.openai.com/api/docs/models/gpt-5.4-mini.md | High |
| `gpt-5.6-terra` | $2.00 | $0.20 | 1.25× input ($2.50) | $12.00 | https://developers.openai.com/api/docs/models/gpt-5.6-terra.md | High |
| `gpt-6-sol` | $2.00 | $0.20 | $2.50 | $10.00 | https://developers.openai.com/api/docs/models/gpt-6-sol.md | High |
| `gpt-5.6-sol` (comparison) | $4.00 | $0.40 | — | $20.00 | quick-comparison table on the gpt-5.6-terra page | High |

Notes (High): prompts over 272K input tokens cost 2× input and 1.5× output. Batch and Flex are 50%; Fast is 2×; regional processing adds 10%. The pricing page itself (https://developers.openai.com/api/docs/pricing) is client-rendered and the query returned nothing, so the model pages are the price source.

### A4. Chat Completions parameters for reasoning models

| Claim | Verified value | Source | Confidence |
|---|---|---|---|
| `reasoning_effort` enum | `"none"`, `"minimal"`, `"low"`, `"medium"`, `"high"`, `"xhigh"`, `"max"`; default `"medium"`. "Not all reasoning models support every value." | Chat Completions reference | High |
| `max_completion_tokens` vs `max_tokens` | `max_completion_tokens` is "an upper bound … including visible output tokens and reasoning tokens". `max_tokens` is "**Deprecated** … in favor of `max_completion_tokens`, and is not compatible with o-series models." | Chat Completions reference | High |
| `temperature` | Range 0–2, default 1. GPT-6 guide: "When reasoning effort is not `none`, remove `temperature`, `top_p`, and `top_logprobs`. For Chat Completions, also remove `logprobs`." So temperature is only valid at `none`. | reference; latest-model guide | High |
| `stream_options.include_usage` | Supported. "An additional chunk will be streamed before the `data: [DONE]` message … `choices` … always an empty array." Other chunks carry `usage: null`. If the stream is interrupted the usage chunk may not arrive. Only set it with `stream: true`. | Chat Completions reference | High |
| `parallel_tool_calls` | `optional boolean (default: true)`. Setting `false` "ensures exactly zero or one tool is called". | reference; https://developers.openai.com/api/docs/guides/function-calling.md | High |
| `developer` vs `system` role | Developer message: "With o1 models and newer, `developer` messages replace the previous `system` messages." System message: "With o1 models and newer, use `developer` messages for this purpose instead." | Chat Completions reference | High |
| `strict` tool schemas | "Chat Completions requests remain non-strict by default." Recommended: `strict: true` with `additionalProperties: false` and every property `required`. | function-calling guide | High |
| Prompt caching: automatic? | "Prompt caching is enabled by default for supported OpenAI models." Chat Completions `prompt_cache_options` is "Supported for `gpt-5.6` and later models. By default, OpenAI automatically chooses one implicit cache breakpoint." `mode` defaults to `implicit`; `ttl` is `"30m"` (only value on Chat Completions). | https://developers.openai.com/api/docs/guides/prompt-caching.md ; reference | High |
| Minimum cacheable prefix | **1,024 visible input tokens for GPT-5.6 and later.** For earlier models it "varies by request settings". Hidden OpenAI system tokens don't count. | prompt-caching guide | High |
| Where implicit breakpoints land (5.6+) | At the end of the latest eligible message (user messages; the last tool response in a run; the last developer message in the *initial* run of developer messages). Lookup also tries up to 20 earlier eligible message endings. | prompt-caching guide | High |
| Cache billing (5.6+) | Read = 0.1× input (0.05× for 6.1 Sol / 6.1 Terra). Write = 1.25× input for 30m. Earlier models have no write charge. Usage reports `prompt_tokens_details.cached_tokens` and `cache_write_tokens`. | prompt-caching guide; reference (usage schema) | High |
| `prompt_cache_key` / `prompt_cache_retention` | `prompt_cache_key`: optional on 5.6+ (routing is automatic); still useful before 5.6. `prompt_cache_retention` is **Deprecated** ("Use `prompt_cache_options.ttl` instead"). | reference; prompt-caching guide | High |

### A5. Is Chat Completions deprecated?

| Claim | Verified value | Source | Confidence |
|---|---|---|---|
| Status | **Not deprecated, and no shutdown date.** Quote: "While Chat Completions remains supported, Responses is recommended for all new projects." Also: "Chat Completions remains supported, so you can migrate one user flow at a time." It is absent from the deprecations page. The reference opens with "Starting a new project? We recommend trying Responses". | https://developers.openai.com/api/docs/guides/migrate-to-responses.md ; deprecations page | High |
| Practical catch | New features are increasingly Responses-only. Reasoning with tools on GPT-6, `configuration_update`, 12h cache TTL, and `reasoning.mode: pro` all require Responses. "Reasoning models work better with the Responses API." | reasoning guide; latest-model guide | High |
| Assistants API | Shut down Aug 26, 2026 (not used by Dayflight) | deprecations page | High |

### A6. `GET /v1/models`

| Claim | Verified value | Source | Confidence |
|---|---|---|---|
| Response shape | `{object:"list", data:[{id, created, object:"model", owned_by, shutdown_date}]}`. `shutdown_date` is "optional string or null" (`YYYY-MM-DD`). The deprecations page recommends checking it to "monitor model shutdowns programmatically". | https://developers.openai.com/api/reference/resources/models/methods/list ; deprecations page | High |
| Does it list `gpt-6-luna` etc.? | It "Lists the currently available models" **for the calling org**. Access is not guaranteed by tier: "Meeting a usage-tier threshold doesn't grant access to every model. If a documented model is missing from Playground or `GET /v1/models`, or a request returns `model_not_found` …". The 5.6 Luna page has the same caveat. Free tier: "Not supported" on the GPT-6 Luna rate-limit table. Not tested live (no API key in this environment). | https://developers.openai.com/api/docs/guides/rate-limits.md ; model pages | Medium |

---

## B. Apple (iOS 26 SDK), App Store, CI — **UNVERIFIED**

> Firecrawl credits ran out before any page in this section could be fetched. Everything below is from training knowledge (cutoff June 2026). Re-verify at the listed URL.

### B7. Liquid Glass SwiftUI API

| Claim | Best-known value | Re-check at | Confidence |
|---|---|---|---|
| `glassEffect` signature | `func glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape()) -> some View`, iOS 26.0. The `isEnabled:` parameter appeared in early betas but is believed absent from the shipping `glassEffect(_:in:)`. Dayflight's `Theme.swift:268` call `glassEffect(glass.interactive(interactive), in: shape)` matches. | https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:) | UNVERIFIED / Medium |
| `Glass` type | `struct Glass`: `static var regular`, `static var clear`, `static var identity`; `func tint(_ color: Color?) -> Glass` (optional `Color?`); `func interactive(_ isEnabled: Bool = true) -> Glass` | https://developer.apple.com/documentation/swiftui/glass | UNVERIFIED / Medium |
| `GlassEffectContainer` | `GlassEffectContainer(spacing: CGFloat? = nil) { … }`, iOS 26.0 | https://developer.apple.com/documentation/swiftui/glasseffectcontainer | UNVERIFIED / Medium |
| `glassEffectID` | `func glassEffectID(_ id: (some Hashable & Sendable)?, in namespace: Namespace.ID) -> some View`; related `glassEffectUnion(id:namespace:)`, `glassEffectTransition(_:)` | https://developer.apple.com/documentation/swiftui/view/glasseffectid(_:in:) | UNVERIFIED / Medium |
| Button styles | `.buttonStyle(.glass)` (`GlassButtonStyle`) and `.buttonStyle(.glassProminent)` (`GlassProminentButtonStyle`), iOS 26.0 | https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glass | UNVERIFIED / Medium |

### B8. Tab bar accessory and minimize

| Claim | Best-known value | Re-check at | Confidence |
|---|---|---|---|
| `tabViewBottomAccessory(content:)` | iOS 26.0: `func tabViewBottomAccessory<Content: View>(@ViewBuilder content: () -> Content) -> some View` | https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(content:) | UNVERIFIED / Medium |
| `tabViewBottomAccessory(isEnabled:content:)` | Added in **iOS 26.1** so the accessory can be hidden (returning an empty view from `content:` still shows an empty capsule on 26.0) | https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(isenabled:content:) | UNVERIFIED / Low–Medium |
| Placement | `@Environment(\.tabViewBottomAccessoryPlacement)` → `.inline` (tab bar minimized) / `.expanded` | https://developer.apple.com/documentation/swiftui/tabviewbottomaccessoryplacement | UNVERIFIED / Medium |
| `tabBarMinimizeBehavior` | `func tabBarMinimizeBehavior(_ behavior: TabBarMinimizeBehavior)`; values `.automatic`, `.onScrollDown`, `.onScrollUp`, `.never`; iOS 26.0 (iPhone only in effect) | https://developer.apple.com/documentation/swiftui/view/tabbarminimizebehavior(_:) | UNVERIFIED / Medium |

### B9. ActivityKit

| Claim | Best-known value | Re-check at | Confidence |
|---|---|---|---|
| Max duration | Active for up to **8 hours**, then ended by the system. An ended activity stays on the Lock Screen for up to **4 more hours** (12 h total). | https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities | UNVERIFIED / Medium–High |
| `staleDate` / `isStale` | When `staleDate` passes, the system re-renders with `context.isStale == true` and does not wake the app. Setting `staleDate: nil` means never stale. | https://developer.apple.com/documentation/activitykit/activitycontent/staledate | UNVERIFIED / Medium–High |
| `Activity.request` in background | Normally foreground only (else `ActivityAuthorizationError` / visibility error). Exceptions: push-to-start (iOS 17.2+), and a `LiveActivityIntent` running in the app process, which Apple allows to start or modify activities while the app is in the background. | https://developer.apple.com/documentation/activitykit/activity/request(attributes:content:pushtype:) ; https://developer.apple.com/documentation/appintents/liveactivityintent | UNVERIFIED / Medium |
| Local update budget | No documented hard per-hour cap for local `activity.update(_:)` while the app runs; the push budget applies to APNs priority-10 updates. Content-state payload ≤ **4 KB**. | ActivityKit docs | UNVERIFIED / Medium |

### B10. Which process runs `perform()`

| Claim | Best-known value | Re-check at | Confidence |
|---|---|---|---|
| Widget/Live Activity `Button(intent:)` with `LiveActivityIntent` | Runs in the **app process**; the system launches or wakes the app in the background. The intent type must be compiled into both targets. This matches the comment at `Shared/TaskActivity.swift:62`. | https://developer.apple.com/documentation/appintents/liveactivityintent | UNVERIFIED / Medium–High |
| Plain `AppIntent` from a widget button | Runs in the **widget extension process**, unless `openAppWhenRun` / `supportedModes` (iOS 26) asks for the app, or it is an `AudioPlaybackIntent` / `LiveActivityIntent` | https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities | UNVERIFIED / Medium |

### B11. Control Center controls (iOS 18)

| Claim | Best-known value | Re-check at | Confidence |
|---|---|---|---|
| Minimal control | `struct StartNextControl: ControlWidget { var body: some ControlWidgetConfiguration { StaticControlConfiguration(kind: "…start-next") { ControlWidgetButton(action: StartNextBlockIntent()) { Label("Start next", systemImage: "play.fill") } }.displayName("Start next block") } }` in the widget bundle | https://developer.apple.com/documentation/widgetkit/controlwidget | UNVERIFIED / Medium |
| Opening the app | A control only foregrounds the app if its intent asks: conform to `OpenIntent` (needs a `target` parameter), set `static let openAppWhenRun = true` (superseded by `static let supportedModes: IntentModes = .foreground` in iOS 26), or use `OpenURLIntent` for a deep link. A `LiveActivityIntent` runs in the background without opening the app. | https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system | UNVERIFIED / Medium |

### B12. Notifications

| Claim | Best-known value | Re-check at | Confidence |
|---|---|---|---|
| 64 pending local notifications | "The system keeps the soonest-firing 64 notifications (with automatically rescheduled notifications counting as a single notification) and discards the rest." This sentence is from Apple's archived *Local and Remote Notification Programming Guide*; current `UNUserNotificationCenter` docs don't restate it but the behaviour persists. | https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/SchedulingandHandlingLocalNotifications.html | UNVERIFIED / Medium |
| Time Sensitive | Needs the **Time Sensitive Notifications** capability (entitlement `com.apple.developer.usernotifications.time-sensitive` = true) plus `content.interruptionLevel = .timeSensitive`. No Apple approval needed (unlike Critical Alerts). Users can turn it off per app (`UNNotificationSettings.timeSensitiveSetting`). | https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/timesensitive | UNVERIFIED / Medium–High |

### B13. App Store requirements

| Claim | Best-known value | Re-check at | Confidence |
|---|---|---|---|
| iOS 26 SDK required for uploads | Apple's "Upcoming SDK minimum requirements" notice: from **April 2026** (believed April 28, 2026), iOS/iPadOS apps uploaded to App Store Connect must be built with the **iOS 26 SDK (Xcode 26)** or later. If correct, this is already in force. | https://developer.apple.com/news/upcoming-requirements/ | UNVERIFIED / Medium |
| `CA92.1` (UserDefaults) | Read and write data that is only accessible to the app itself | https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api | UNVERIFIED / High (stable since 2024) |
| `1C8F.1` (UserDefaults) | Read and write data accessible to apps, app extensions and App Clips that are members of the **same App Group** as the app. Dayflight's app and widget manifests declare both codes, which is correct for an App Group suite. | same | UNVERIFIED / High |

### B14. GitHub Actions macOS runners

| Claim | Best-known value | Re-check at | Confidence |
|---|---|---|---|
| Labels | `macos-15` (arm64; `-intel` and `-large` variants), `macos-26` (arm64; preview in late 2025, GA expected in 2026), `macos-14` (being retired). `macos-latest` pointed at `macos-15`, with a migration to `macos-26` announced. | https://github.com/actions/runner-images#available-images | UNVERIFIED / Low |
| Xcode on images | `macos-26`: Xcode 26.x is default, with iOS 26.x simulator runtimes. `macos-15`: Xcode 16.x default, plus Xcode 26.x installed side by side (images keep only a few runtimes). Dayflight's CI already picks the newest `/Applications/Xcode_*.app`. | https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md ; …/macos-15-arm64-Readme.md | UNVERIFIED / Low |

---

## Code changes recommended

**OpenAI assistant (verified; do these before 2026-12-11)**

1. **`PlannerSettings.swift` – default model.** Set `AssistantSettings.defaultModel = "gpt-6-luna"`. It is the cheapest current model ($0.10 / $0.50 per 1M), OpenAI's named replacement for `gpt-4o-mini` and `gpt-4.1-mini`, not deprecated, and has a May 2026 knowledge cutoff. On Chat Completions with tools it must run with `reasoning_effort: "none"` (see 3).
2. **`modelPresets`.** Replace the list with `["gpt-6-luna", "gpt-5.6-luna", "gpt-5.4-mini", "gpt-6-sol", "gpt-5.6-terra"]`. Every current preset (`gpt-5-mini`, `gpt-5`, `gpt-5-nano`, `gpt-4.1-mini`, `gpt-4o-mini`) is deprecated; the first three shut down 2026-12-11, the last two 2027-01-14. Do **not** offer `gpt-6-astra`, `gpt-6.1-sol` or `gpt-6.1-terra`: Chat Completions does not support tool calling on them.
3. **Per-model capability table** (new `ModelCapabilities`, in place of the prefix-only `isReasoningModel`):
   - `gpt-6-luna`, `gpt-6-sol`: tools require `reasoning_effort = "none"`. Always send `"none"` and disable the effort picker.
   - `gpt-5.6-luna`, `gpt-5.6-terra`, `gpt-5.6-sol`: efforts `none, low, medium, high, xhigh, max`; default `low` for this assistant.
   - `gpt-5.4-mini`: efforts `none, low, medium, high, xhigh`; API default `none`.
   - `gpt-6-astra`, `gpt-6.1-*`: `supportsChatCompletionsTools = false`. Refuse with a clear message, or route through a future Responses client.
   - Unknown or third-party ids: omit `reasoning_effort`.
4. **Reasoning-effort picker values** (`SettingsView.swift:128`). Use `["none", "low", "medium", "high"]`, filtered by the model's capabilities. Drop `"minimal"`: no current small model supports it.
5. **Migrate stored settings** in `AssistantSettings.init(from:)`:
   - Map `reasoningEffort == "minimal"` to `"low"` (OpenAI: "If your existing request uses `minimal`, start with `low`").
   - Map a stored `model` in {`gpt-5`, `gpt-5-mini`, `gpt-5-nano`, `gpt-4.1-mini`, `gpt-4o-mini`, `gpt-4.1-nano`, `o4-mini`, `o3-mini`} to `defaultModel`. OpenAI's own replacement for `gpt-5-mini` is `gpt-5.6-terra`, which costs 8× more per output token ($2 / $12), so `gpt-6-luna` is the cost-equivalent choice.
6. **Fix the retry-on-400 path** (`AssistantSession.unsupportedParameter` / `dropParam`). For `gpt-6-luna` / `gpt-6-sol`, an error mentioning `reasoning_effort` must be retried with `reasoning_effort: "none"`, **not** by dropping the parameter. Omitting it means the API default `"medium"`, which still fails with tools.
7. **`chooseFallback(from:unavailable:)`.** Its "small, newest major version" scoring now picks `gpt-6-luna` first, which is fine only if 3 and 6 are in place. Also exclude ids whose `/v1/models` entry has a non-null `shutdown_date` in the past or within 30 days: decode `shutdown_date` in `listModels`.
8. **Keep `max_completion_tokens`** (3000 is fine; it includes reasoning tokens). Never send `max_tokens`, which is deprecated.
9. **Keep `stream: true` + `stream_options: {"include_usage": true}`.** Handle a missing final usage chunk on interrupted streams.
10. **Leave `parallel_tool_calls` unset** (default `true`), or set it to `false` for one call per turn. Consider adding `"strict": true` to each `ToolDefinition`, with `additionalProperties: false` and all fields `required`; Chat Completions is non-strict by default.
11. **Message role.** For `endpoint.isOpenAI`, send the static prompt as role **`developer`** instead of `system` ("With o1 models and newer, use `developer` messages"). Keep `system` for OpenAI-compatible local servers.
12. **Prompt caching** (automatic on 5.6+; nothing to enable).
    - Make sure the static developer prompt plus tool schemas reach **≥ 1,024 tokens**, or caching never triggers on 5.6+ models. The guide's break-even analysis favours padding with useful stable instructions once the prefix is above about 221 tokens and reused about 10 or more times.
    - Keep the per-turn CONTEXT message *after* the static block, as the code already does.
    - Don't send `prompt_cache_retention` (deprecated). `prompt_cache_key` is optional.
13. **`TokenUsage`.** Also decode `prompt_tokens_details.cache_write_tokens`. On 5.6+ models writes are billed at 1.25× input, so any cost display must count them.
14. **Temperature.** Don't add `temperature`/`top_p`. They are only allowed at `reasoning_effort: "none"`.
15. **Medium-term.** Chat Completions is supported with no shutdown date, but reasoning with tools on the GPT-6 family needs the **Responses API** (`/v1/responses`). Plan a Responses transport if the assistant needs reasoning on current-generation models.
16. **Docs.** Update `docs/ARCHITECTURE.md` §Assistant (lines ~346–359) and the Settings copy to the new defaults.

**Apple / CI (UNVERIFIED; re-check before relying on them)**

17. Mini-player: use `tabViewBottomAccessory { … }` behind `if #available(iOS 26, *)`. To hide it when no timer runs, use `tabViewBottomAccessory(isEnabled: timer.isRunning) { … }` behind `if #available(iOS 26.1, *)`; on 26.0, conditionally attach the modifier instead of returning an empty view. Read `\.tabViewBottomAccessoryPlacement` for the compact `.inline` layout. Add `.tabBarMinimizeBehavior(.onScrollDown)` on iOS 26.
18. Keep the `Glass` call shape `glassEffect(_:in:)`, with no `isEnabled:` parameter on `glassEffect`; pass `nil` to `tint(_:)` for none. Use `.buttonStyle(.glass)` / `.glassProminent` for system buttons on 26.
19. Keep Live Activity buttons and Control Center controls on `LiveActivityIntent` (runs in the app process, can start or update activities from the background). Add `supportedModes = .foreground` (26) / `openAppWhenRun` (18–25) only for an intent that must open the app, such as "Open Now".
20. Plan for the 8 h Live Activity cap: blocks longer than about 7.5 h should end and restart the activity on the next user action. Keep `staleDate = plannedEnd`.
21. Keep `NotificationPlanner` under 64 pending requests, with headroom (e.g. ≤ 60). Make sure the App target's entitlements include `com.apple.developer.usernotifications.time-sensitive`.
22. CI: switch `runs-on: macos-15` to `macos-26` (or pin `Xcode_26.x`) so the build uses the iOS 26 SDK that App Store uploads now require. Keep the "newest Xcode" and simulator-picking steps.

*Firecrawl note: Your Firecrawl credits ran out. Daily MCP credits refresh in 23h 50m. Add credits or upgrade to keep going: https://www.firecrawl.dev/billing/s/EFJTYyvf9pEiXLAjmQPEWlygBi5mAcZHBy8NSHcBZp0*

---

## Addendum (2026-11-09, lead engineer): Section B items re-checked via web search

Firecrawl credits ran out before section B. These four items were re-checked with a regular web search against Apple and GitHub sources:

| Claim | Verified value | Source | Confidence |
|---|---|---|---|
| `Glass.tint(_:)` parameter type | Takes **`Color?`** (pass `nil` for no tint) | [Apple: Glass.tint(_:)](https://developer.apple.com/documentation/swiftui/glass/tint(_:)) | High |
| `tabViewBottomAccessory` | `tabViewBottomAccessory(content:)` from iOS 26.0. An `isEnabled:` overload exists for 26.1+, but Apple forum threads, including a DTS reply, report it as laggy or buggy on 26.1 and needing Xcode 26.2+. **Decision:** keep Dayflight's own overlay mini-player. | [Apple doc](https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(content:)), [forum 806373](https://developer.apple.com/forums/thread/806373), [forum 803404](https://developer.apple.com/forums/thread/803404) | Medium-high |
| Which process runs an interactive widget / Live Activity `Button(intent:)` | A **`LiveActivityIntent`** (or one with `openAppWhenRun`) runs in the **app process**. A plain `AppIntent` runs in the widget extension. **Decision:** widget Start/Pause/Complete buttons use LiveActivityIntents. | [Apple: Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities) | High |
| GitHub-hosted macOS 26 runners | `macos-26` (arm64) has been generally available since 2026-02-26, with the Xcode 26.x line (26.0.1 → 26.4+) | [GitHub changelog](https://github.blog/changelog/2026-02-26-macos-26-is-now-generally-available-for-github-hosted-runners/) | High |

Still unverified, to re-check once Firecrawl credits reset: the 8 h ActivityKit cap wording, the iOS 26 SDK upload-requirement date, the exact privacy-manifest reason-code wording, and `ControlWidget` details.
