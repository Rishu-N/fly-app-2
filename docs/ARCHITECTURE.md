# Dayflight — Architecture & Tech-Lead Review (v1.0)

> Owner: tech lead. Inputs: `docs/PRODUCT_REQUIREMENTS.md` (authoritative), `docs/research/*`, and the code as of 2026‑11‑07 (`PlannerCore/`, `App/`, `Shared/`).
> Where this document and the code disagree, the code must change. §11 lists every change, prioritised.

## 0. Engineering principles

1. **Derive, never tick.** All time-dependent state is a pure function of stored timestamps and `now`. The app arms exactly one wake-up, at the next schedule boundary, and the system renders countdowns. No `Timer`, no per-second state, no polling.
2. **One writer.** Only the app process writes the data files. Widgets read a pre-reduced snapshot. `LiveActivityIntent.perform()` and notification actions run inside the app process. Nothing in the widget extension mutates data.
3. **Reconcile, don't replay.** Notifications, the Live Activity and widgets each have one `reconcile` function that diffs *desired* against *actual* state. Every trigger calls that same function: launch, edit, action, day change and foreground. Missed events therefore heal themselves.
4. **Debounce I/O, never correctness.** Disk, widget and notification work for plan edits is debounced. Anything a suspended process could get wrong is applied right away, and every background entry point awaits it before returning. Examples are the time's-up alert after a pause, and Live Activity state.
5. **Values across boundaries.** Only `Sendable` value types cross actor boundaries: `PlanTask` slices, `NotificationSpec`, `WidgetSnapshot`, `ChatRequest`. Inject `now` and the `Calendar` everywhere; core logic never calls `Date()` or `.current`.

## 1. Module & folder layout

```
project.yml / Dayflight.xcodeproj (Xcode 16 synchronized folders; build with Xcode 26 SDK, see P1-17)
Config/            Base.xcconfig (APP_BUNDLE_ID, DAYFLIGHT_APP flag for the app target only)
PlannerCore/       Swift package. Foundation + Observation only. Linux-testable.
  Model/           PlanTask, TimerSession, TaskSeries/RepeatRule, DayKey/MonthKey, PlannerSettings, TaskCategory
  Engine/          TaskTransitions, ScheduleEngine (snapshot + nextBoundary), ScheduleMath, RecurrenceExpander
  Notifications/   NotificationPlanner (desired specs + diff, pure)
  Parsing/         QuickAddParser
  Store/           TaskStore (@MainActor @Observable), ChangeSet/UndoEntry/StoreChange, JSONFilePersistence (actor)
  Assistant/       wire types, ChatTransport/OpenAIHTTPTransport, SSE, StreamAccumulator, AssistantTool,
                   ToolExecutor, SystemPrompt, PromptTemplate, AssistantSession (agent loop)
  Widget/          NEW WidgetTimeline: entry dates + per-entry NowSnapshot (shared by app tests and widget)
  Util/            NEW StableHash (FNV-1a 64; never `hashValue`), DeterministicID (UUID from seriesID+day)
Shared/            compiled into App and Widgets
  AppGroup.swift   group id, container/file URLs, defaults suite, WidgetSnapshot, DeepLink
  TaskActivity.swift  TaskActivityAttributes + ContentState, LiveActivityIntents (perform under #if DAYFLIGHT_APP)
  Theme.swift      DialTheme/Palette, category colours, DayPhase stops, TypeRamp, Motion, floatingGlass
App/
  DayflightApp.swift (TO ADD)  @main, @UIApplicationDelegateAdaptor, scenePhase → AppModel
  AppDelegate.swift  (TO ADD)  touches AppModel.shared in didFinishLaunching (installs UN delegate in time)
  AppModel.swift     composition root + entry points (UI, intents, notification actions, deep links)
  EffectsCoordinator.swift (TO ADD; extract from AppModel)  StoreChange fan-out, debouncers, settle()
  ClockMonitor.swift (TO ADD; extract)  day / time-zone / significant-time events
  Services/  NotificationScheduler, LiveActivityController, WidgetSnapshotWriter, AssistantService,
             SettingsStore + KeychainStore, Haptics, BackgroundAssertion (TO ADD)
  Features/  Now/ (NowModel, Lens, HeroTimer, TimerRing, AuroraField, Lanes, DriftChip), Plan/ (PlanModel,
             DayTimeline, BlockView, WeekStrip, EditSheet), Assistant/ (Chat, ProposalCard, AskUserChips,
             TemplateRail), QuickAdd/, Settings/ (incl. ReminderDiagnostics), Common/ (MiniPlayer, UndoToast)
Widgets/           DayflightWidgetsBundle, TaskLiveActivity (+ DynamicIsland), NowWidget (small/medium),
                   AccessoryWidgets (circular/rectangular/inline), NowTimelineProvider
```

**Responsibilities**

| Type | Isolation | Responsibility |
|---|---|---|
| `TaskStore` | `@MainActor @Observable` | Single source of truth. Owns the day index, undo and debounced persistence, and emits `StoreChange`. |
| `JSONFilePersistence` | actor | Month-partitioned JSON. Encode and decode run off main. Writes are atomic. |
| `ScheduleEngine` / `ScheduleMath` / `NotificationPlanner` / `WidgetTimeline` | pure (nonisolated) | All derivations. Home and the widgets share the same functions. |
| `AppModel` | `@MainActor` | Composition root. Hosts entry points: `perform`, `handleIntent`, `handleNotificationAction`, `open(url)`. Owns UI routing state only. |
| `EffectsCoordinator` | `@MainActor` | Turns `StoreChange` and settings changes into effects. `settle()` runs all pending effects now and awaits them. |
| `NotificationScheduler` | `@MainActor` class (awaits XPC) | Builds the desired specs, diffs them against pending requests, and holds snoozes and the last applied ID set. |
| `LiveActivityController` | `@MainActor` | Keeps `Activity<TaskActivityAttributes>` reconciled with the active task. |
| `WidgetSnapshotWriter` | `@MainActor` (IO detached) | Builds the snapshot, compares stable hashes, writes atomically and reloads timeline kinds. |
| `SettingsStore` | `@MainActor @Observable` | `PlannerSettings` stored as one JSON blob in App Group defaults. Emits changes to the coordinator. |
| `KeychainStore` | static, called off main | Holds the API key with `AfterFirstUnlockThisDeviceOnly`. Exposes only the last 4 characters for display. |
| `AssistantService` | `@MainActor @Observable`, **lazy** | Hosts `AssistantSession`. Persists the transcript, holds the background assertion and posts the "ready" notification. |
| `NowModel` | `@MainActor @Observable` | `snapshot: NowSnapshot` plus a single boundary wake-up. |

**Entitlements / plist:**
- App Groups (app and widget).
- Time Sensitive Notifications.
- `NSSupportsLiveActivities`.
- `NSAllowsLocalNetworking` and `NSLocalNetworkUsageDescription`, for Ollama or LM Studio over plain `http` on the LAN.
- `PrivacyInfo.xcprivacy`, declaring UserDefaults with reason `1C8F.1` (App Group).

Data files must use `completeFileProtectionUntilFirstUserAuthentication`, never `.complete`. Lock-screen intents read and write them while the device is locked.

## 2. Runtime object graph & lifecycle

```
                       AppModel.shared  (@MainActor, created by AppDelegate.didFinishLaunching)
   ┌───────────────┬──────────────┬────────────┴───────────┬──────────────────────┐
SettingsStore   KeychainStore   TaskStore ──onChange──▶ EffectsCoordinator ◀── ClockMonitor
   │ changes ──────────────────────│──────────────────────▶ │ immediate          │ debounced / settle()
   │                     JSONFilePersistence (actor)        ├─▶ NowModel          ├─▶ NotificationScheduler
   │                                                        └─▶ LiveActivityCtl   └─▶ WidgetSnapshotWriter
AssistantService (lazy, first Assistant tab) ─▶ AssistantSession ─▶ OpenAIHTTPTransport (URLSession)
                                                     └─▶ ToolExecutor (@MainActor; reads TaskStore, stages Proposal)
UN delegate (AppModel ext.) · LiveActivityIntents · deep links ──▶ AppModel entry points ──▶ TaskStore
```

**Construction** (no I/O in `init`; < 5 ms):

```swift
@MainActor final class AppModel {
  static let shared = AppModel()
  let settings = SettingsStore()                       // one defaults read (tiny)
  let store = TaskStore(persistence: JSONFilePersistence(directory: AppGroup.dataDirectory),
                        calendar: .current)            // snapshot calendar, replaced only via setCalendar
  let notifications = NotificationScheduler(); let liveActivities = LiveActivityController()
  let widgets = WidgetSnapshotWriter()
  lazy var effects = EffectsCoordinator(store: store, settings: settings, notifications: notifications,
                                        liveActivities: liveActivities, widgets: widgets)
  private(set) lazy var assistant = AssistantService(store: store, settingsStore: settings, notifications: notifications)
  private init() {
    store.onChange = { [unowned self] in effects.handle($0) }
    settings.onChange = { [unowned self] old, new in effects.settingsChanged(old, new) }
    UNUserNotificationCenter.current().delegate = self
    Task(priority: .userInitiated) { await store.bootstrap(); effects.storeLoaded() }
  }
}
```

**Cold launch (foreground)**
1. `AppDelegate.application(_:didFinishLaunchingWithOptions:)` touches `AppModel.shared`. That sets the UN delegate before launch completes (Apple requirement), starts `bootstrap`, and registers categories (fire-and-forget).
2. The first frame renders Now with a placeholder of identical layout (no spinner). `bootstrap` loads the current and next month first (≈ 10–20 ms), then the rest.
3. `effects.storeLoaded()` runs these steps in order:
   - `liveActivities.reconcile()` adopts `Activity.activities`.
   - `store.autoCompleteIfNeeded`.
   - `NowModel.refresh()`.
   - The widget write is hash-checked, so usually no reload happens.
   - The notification resync is deferred about 1 s after the first frame, at `.utility`.

   **No effect may run before `isLoaded`** (P1-14).
4. Keychain reads, the `/models` fetch and the transcript all wait until the Assistant tab is opened.

**Background launch (notification action or LiveActivityIntent).** The same `AppModel.shared` path runs. `AssistantService` is not created.

```swift
func handleIntent(_ a: TimerIntentAction, taskID: String) async {
  await BackgroundAssertion.run("intent") {
    await store.waitUntilLoaded()                 // memoised bootstrap (P0-3)
    guard let task = validated(taskID, expecting: a) else { return }
    try? store.perform(action(for: a, task), on: task.id)
    await effects.settle()                        // flush disk + LA update + notification diff + widget (P0-8)
  }
}
```

"Start now" is a `.foreground` action. The state change happens in `didReceive`, but `Activity.request` waits for `scenePhase == .active`; the controller retries a pending start then.

**scenePhase**
- **`.active`:**
  - `clock.check()` catches day or time-zone changes missed while suspended.
  - `NowModel.refresh()` re-arms the boundary.
  - `liveActivities.reconcile()` handles a pending start and the 7 h restart.
  - Notification resync, with a full diff against pending requests.
  - `refreshAuthorization()` for the permission banner.
- **`.background`:** cancel the boundary task, then `BackgroundAssertion.run { await effects.settle() }`. `settle()` includes `store.flushNow()` and awaits the in-flight write. The assertion has an expiration handler.
- **`.inactive`:** no work. It flickers whenever Control Center is pulled down.

**Day and time changes (`ClockMonitor`).** It observes `.NSCalendarDayChanged`, `UIApplication.significantTimeChangeNotification` and `.NSSystemTimeZoneDidChange`, and compares the stored `(DayKey, TimeZone.identifier)` to decide what happened.
- **Day changed:** `store.materializeRecurrences(now:)`, then `NowModel.refresh()`, then a full notification resync (the horizon moved), then a widget write (the window moved).
- **Time zone changed:** `store.setCalendar(.current)`, which rebuilds the index, re-materialises and emits `.reload` (P1-3). Then everything in "day changed". Instants are unchanged (PRD §5), so timers and the Live Activity are untouched.

## 3. Data flow & side-effect orchestration

`StoreChange` gains two fields: `days: Set<DayKey>` and `activeChanged: Bool` (P2). With them the coordinator can skip work cheaply.

| Effect | Trigger | Timing | Redundancy guard |
|---|---|---|---|
| `NowModel.refresh` | change touching today±1, or `activeChanged` | immediate | assign only if `NowSnapshot !=` old |
| Live Activity | `.timer`, `activeChanged`, or a change to the next task | immediate (`await` in background) | `ContentState` equality with the last pushed state (needs P1-12) |
| Notifications, timer-related | `.timer` | immediate: remove delivered and pending notifications for the task, then diff | — |
| Notifications, full diff | `.schedule`, `.reload`, reminder settings | debounce 300 ms, coalescing | desired ID set equals last applied → skip `pendingNotificationRequests` |
| Widget snapshot + `reloadTimelines(ofKind:)` | change in [now−18 h, end of tomorrow], or the active task, or theme | debounce 1 s | stable hash of the payload (excluding `generatedAt`) equals the persisted hash → no write, no reload |
| Disk flush | every commit | 350 ms inside the store | only dirty, loaded months |

Bulk operations produce one `ChangeSet`, which means one `StoreChange` and one run of each effect. Bulk operations are assistant Apply, Shift rest of day and series edits. `settle()` cancels the debouncers, runs their work now and awaits all of it. It is used by every background entry point, by `.background`, and after notification actions.

## 4. Concurrency model

- **`@MainActor`:**
  - Types: `TaskStore`, `AppModel`, `EffectsCoordinator`, `SettingsStore`, the controllers, feature models, `AssistantSession` (UI state) and `ToolExecutor`.
  - Main-actor work must stay at **O(day)**: index lookups, the snapshot (≤ 3 days), quick-add parsing, tool execution (≤ 14 cached day lookups) and notification planning (≤ 7 days, < 1 ms).
  - Never on main: JSON over 10 KB, file I/O, synchronous Keychain reads or blocking XPC.
- **Actors / off-main:**
  - `JSONFilePersistence`.
  - Transport tasks: SSE decoding runs in the `AsyncThrowingStream` producer `Task`, which is nonisolated.
  - Detached `.utility` writes for the widget snapshot and the transcript.
  - Keychain reads (`KeychainStore` called through a nonisolated async wrapper).
- **Sendable discipline:**
  - Pass `[PlanTask]` slices, not the store.
  - `UNNotificationResponse` and `userInfo` are not `Sendable`. Extract strings in the `nonisolated` delegate method before hopping to main (the existing code does this ✓).
  - ActivityKit calls happen from main. Under Swift 6.2 toolchains (`nonisolated(nonsending)` by default), mark CPU-bound helpers `@concurrent`.
- **Cancellation:**
  - Each assistant turn is one `Task` owned by `AssistantSession`. Stop, Clear, a key change or a new send cancels it.
  - `onTermination` cancels the URLSession task. The loop checks `Task.isCancelled` between rounds and closes dangling tool calls (✓ `rollBackDanglingToolCalls`).
  - Tab switches never cancel.
  - Debouncers and the boundary wake-up are single replaceable Tasks.
- **Priorities:** bootstrap `.userInitiated`; launch resync and widget writes `.utility`; writes awaited by `settle()` inherit the caller's priority.

## 5. Timer rendering strategy

| Surface | Running | Paused | Overtime |
|---|---|---|---|
| Hero digits | `Text(timerInterval: s.displayInterval, countsDown: true)` `.monospacedDigit()` | same with `pauseTime: s.pausedAt` (correct only after P1-12) | `"+"` + `Text(timerInterval: end...end+24h, countsDown: false)` |
| "Ends at" | static `Text(end, format: .dateTime.hour().minute())` | recomputed on pause/resume | — |
| Bezel ring | 60 ticks drawn once in a `Canvas`. Only the arc sits inside `TimelineView(.periodic(from: start, by: clamp(duration/720, 1 s, 10 s)))`, with no implicit animation | static arc | full amber arc, static |
| Relative labels ("in 12 min") | `Text(date, style: .relative)` / `.timer`, which the system updates | — | — |
| Drift chip (when paused, overtime or due), Plan now-line | its own `TimelineView(.everyMinute)` | | |
| Live Activity / Island / widgets | `Text(timerInterval:)`, `ProgressView(timerInterval:)` | `ProgressView(value:)` plus static digits | `staleDate = end` → `context.isStale` flips to the overtime face with no app wake |

The ring's `TimelineView` exists only while the task is running, the scene is `.active` and the view is on screen (`onAppear`/`onDisappear`).

**Home boundary wake-up.** `NowModel.refresh(now:)` computes the snapshot and calls `ScheduleEngine.nextBoundary`. It then arms one `Task.sleep(for: boundary − now, tolerance: .milliseconds(200))` that calls `refresh` again. It is re-armed on relevant store changes, on `.active` and on clock events, and cancelled in the background.

After P1-4, `nextBoundary` covers every input the snapshot depends on:
- starts and ends
- `start − lead` ("Ready")
- `projectedEnd − 5 min` (warning zone)
- `projectedEnd`
- `next.start − 6 h` (gap window)
- `previous.end + 18 h`
- local midnight

The 60‑second cap in `AppModel.armBoundaryTimer` goes away (P1-16).

**Aurora.** It renders as `TimelineView(.animation(minimumInterval: 1/15, paused: !live))`, where `live` requires all of these:
- the ambient setting is on
- the scene is `.active` and the view is visible
- Reduce Motion is off
- Low Power Mode is off
- the thermal state is below `.serious`

The warning or danger blend is a discrete input that changes only at boundaries. Mesh points and colours are precomputed static arrays (P2).

## 6. Notifications

**Categories and actions** (registered once per launch):

| Category | Actions | Options |
|---|---|---|
| `TASK_LEAD` | `TASK_START` "Start now" · `TASK_SNOOZE` "Snooze 5 min" · `TASK_SKIP` "Skip" | Start = `.foreground`; others background |
| `TASK_TIMER` | `TASK_COMPLETE` "Complete" · `TASK_EXTEND5` "+5 min" | background |
| `ASSISTANT` | none; tapping deep-links to Assistant | — |

**Identifiers and payload**
- IDs follow `kind.<taskID>.<epoch>.<h8>`, where `h8` is an FNV-1a hash of kind, title, body and interruption level (P1-6).
- Owned prefixes: `lead.`, `snooze.`, `timer.`, `nudge.` and `sentinel.`.
- `userInfo = {taskID, kind, startEpoch}` is used for routing and stale-action guards.

**Interruption levels:**
- Lead reminder: `.timeSensitive` when the setting and the entitlement both allow it, otherwise `.active`.
- Time's up: always `.timeSensitive`.
- Nudge: `.active`.
- Assistant: `.passive`.

**Triggers:**
- Lead reminders use `UNCalendarNotificationTrigger` with `DateComponents.timeZone` set, which pins an absolute instant (P1-8).
- Timer ends use `UNTimeIntervalNotificationTrigger`.

**Background handling:** every action starts with `await store.waitUntilLoaded()`, then validates the action, and ends with `await effects.settle()`.

| Action | Effect |
|---|---|
| Start now (foreground) | `start(task)`. A conflict opens the T5 dialog in-app. The Live Activity starts once the scene is `.active`. |
| Snooze 5 | `notifications.snooze(task)`. The snooze is stored in the scheduler state and emitted by the planner (P1-7). The delivered lead is removed. |
| Skip | `perform(.skip)` → resync |
| Complete | `perform(.complete)` → Live Activity ends with a "Done" card (`.after(+2 min)`) → resync |
| +5 min | `perform(.extend(5))`, with the overtime rule from P0-7 → Live Activity update (new `staleDate`) → new time's-up |

**Stale-action guard:** ignore the action if the task is missing, its status doesn't fit the action, or its `start` no longer matches the payload's `startEpoch`.

**Rolling window (≤ 64):**
- ≤ 56 lead reminders and snoozes within 7 days
- 2 timer notifications (end and nudge)
- 1 assistant
- 1 sentinel ("Open Dayflight to keep reminders coming", 1 min after the last lead in the window)

That leaves 4 slots of headroom.

**Resync runs on:**
- launch (deferred)
- foreground
- schedule changes (debounced)
- timer actions (immediate)
- notification actions (awaited)
- day, time-zone and significant time changes
- reminder settings changes
- permission becoming granted

**Delivered cleanup:** when a task starts, is skipped or edited, completes or is deleted, remove its delivered `lead.`/`snooze.` notifications. On complete or cancel, also remove `timer.` and `nudge.` (the existing `clear(taskID:)` does this ✓).

**Foreground on Now:** `willPresent` returns `[.list]` and the lens plays a haptic instead (✓).

**Diagnostics:** "Check my reminders" shows authorization, the Time Sensitive setting, and pending counts per prefix.

## 7. Live Activity

**Schema** (existing `TaskActivityAttributes`, kept tiny at ≈ 250 B): attributes `startedAt`. `ContentState` holds:
- `taskID`, `title`, `category`, `theme`
- `timerStart` = `startedAt + pausedTotal`
- `timerEnd` = `timerStart + target`
- `pausedRemaining?`
- `nextTitle?`, `nextStart?`
- `completed`

**Fix needed:** both bounds must be independent of `now` (P1-12). Then equality dedupe works while paused.

| Event | Action |
|---|---|
| start (foreground) | `Activity.request(content: .init(state, staleDate: timerEnd, relevanceScore: 100), pushType: nil)` |
| start (background, or the request throws) | mark `pendingStart`; retry on `.active`. The timer, the notifications and the widget still work. |
| pause / resume / +5 / next task changed | `await activity.update(...)`. When paused, `staleDate = nil`. |
| complete | end with the `completed` state, `dismissalPolicy: .after(now + 2 min)` |
| cancel / delete / active task gone | `end(nil, .immediate)` |
| user dismissed it (`activityStateUpdates == .dismissed`) | don't recreate it for this task (P2) |
| age > 7 h on `.active` | end, then request a new one. Tasks with more than 8 h remaining get no activity. |

**Reconcile** runs on launch, after every relevant change and on `.active`:
1. End every activity whose `taskID` differs from the active task, and any duplicates.
2. Adopt the matching activity.
3. Update it if its state differs.
4. Request one if missing and allowed.

## 8. Widgets

**Snapshot.** The file is `AppGroup.widgetSnapshotURL`, about 5–15 KB:

```
WidgetSnapshot { version, generatedAt, theme, defaultLeadMinutes, tasks: [PlanTask] }
```

Rules for `tasks`:
- It covers [now − 18 h, end of tomorrow] plus the active task.
- `notes` and `checklist` are stripped (P1-15).
- `updatedAt` and `createdAt` are zeroed, so edits nobody can see don't change the hash.
- Keys are encoded `.sortedKeys`.

**Hash.** FNV-1a 64 over the encoded bytes with `generatedAt` excluded, persisted in App Group defaults. Write and `reloadTimelines(ofKind:)` (Now and Accessory kinds) only when the hash changed.

**Timeline.** `NowTimelineProvider` reads the snapshot (≈ 1 ms). `WidgetTimeline.entryDates` starts at now and iterates `ScheduleEngine.nextBoundary` until the end of tomorrow, capped at 40 entries; each entry gets `ScheduleEngine.snapshot`. The policy is `.atEnd`. There are no per-minute entries: the timer views tick on their own.

`TimelineEntryRelevance` is high from T−5 until the task ends.

**Reload policy:** only on hash change. WidgetKit doesn't count reloads made while the app is in the foreground. Reloads from background intents do count, which is why the hash is persisted.

## 9. Assistant runtime

**Request** (existing `AssistantSession.buildRequest`):
- The system message is the byte-stable `SystemPrompt.staticPart`.
- Then come compacted earlier turns: user text and assistant prose only, tool payloads dropped, last 10 turns (✓).
- Then a **CONTEXT** message (now, time zone, clock style, day window, defaults, active row, today's rows). It is placed immediately before the newest user turn, not inside the system message (P1-19). Use the `system` role for non-OpenAI servers.
- Finally the current turn verbatim.
- Tools and `staticPart` form a cacheable prefix of about 1.9k tokens. Send `prompt_cache_key` (a stable per-install value) only to `api.openai.com`.

**Budgets:**
- About 8k input tokens. Estimate with `utf8.count / 4 × 1.1`. Trim the oldest turns first, then truncate tool results over 2k tokens with "truncated — narrow the range".
- Output: `max_completion_tokens` of 3000 for reasoning models (reasoning tokens count against it), 800 otherwise.
- At most 6 rounds per user message (`maxRounds`). At most 50 items per write call (schema) and 100 per proposal.
- `ask_user` ends the turn in a waiting state. The answer goes back as that tool call's result.

**Streaming:**
- SSE is decoded in the transport task.
- Deltas are coalesced and published to `streamingText` at ≤ 25 Hz (✓ 40 ms).
- The streaming bubble is plain `Text`. Markdown is parsed once, when the turn completes.

**Backgrounding:** `beginBackgroundTask("assistant-request")` brackets every turn. The `defer`-based `onTurnFinished` guarantees it ends (✓). On expiry: stop, keep the partial text, and show "Interrupted · Retry". When a turn finishes in the background with something to review, post a `.passive` "Your plan is ready to review". Changes are **never** applied in the background. An optional iOS 26 upgrade is `BGContinuedProcessingTask` for long turns.

**Model fallback:** on `modelNotFound`, fetch `/models` (cached for 24 h, per base URL) and run `chooseFallback`, which prefers chat-capable `*-mini` models. Retry once. Then show "Using X because Y isn't available". Keep the configured model separate from the effective one (P2).

**Unsupported parameters:** `reasoning_effort`, `max_completion_tokens` and `stream_options` are dropped per model and the request retried (✓).

**Errors:**

| Error | Behaviour |
|---|---|
| `missingAPIKey`, `invalidBaseURL`, `unauthorized`, `quotaExceeded` | not retryable; deep-link to Settings |
| `rateLimited(retryAfter)`, `network`, `badResponse`, `server ≥ 500` | one retry with backoff (honour `Retry-After` ≤ 10 s); a Retry chip after that |
| `cancelled` | "Stopped." |
| `context_length_exceeded` | compact harder and retry once |

**Tokens:** `stream_options.include_usage` provides usage, which is summed per conversation and per month (`UsageLedger`, shown in Settings).

**Privacy:**
- A consent sheet (`consentGiven`) appears before the first request.
- Notes are sent only with `shareNotes`.
- Titles are sanitised, and tool text is treated as data (stated in the prompt).
- There are no timer tools.
- The key lives only in the Keychain and is never logged.
- The session is `ephemeral`: no URL cache.
- The transcript lives in app-private Application Support (not the App Group). It is capped and deleted by Clear.

## 10. Performance budgets

| Budget | How it is met | How it is measured |
|---|---|---|
| Cold launch to an interactive Now < 1 s | No I/O in `init`; static-linked PlannerCore; current month loaded first; Assistant, transcript, Keychain and `/models` lazy; notification resync deferred; placeholder with identical layout | Instruments **App Launch**; `XCTApplicationLaunchMetric`; MetricKit `MXAppLaunchMetric` |
| Day query < 10 ms (target < 0.1 ms) | `idsByDay` + per-day sorted cache; `activeTaskID` cached (P1-1); `tasks(in:)` = ≤ 15 cached lookups | `os_signpost` "dayQuery" + **Time Profiler**; Linux perf test with 5k tasks |
| 120 fps scrolling | per-day observable columns (P1-2); hour grid drawn in one `Canvas`; blocks in a custom `Layout`, `ForEach(tasks, id: \.id)`; now-line and ring isolated in their own `TimelineView`; no `GeometryReader` per row | **SwiftUI** instrument (Xcode 26) + **Animation Hitches** on ProMotion hardware |
| Memory < 100 MB | 2–3 MB of tasks; `LazyVStack` chat; transcript capped; static palettes and colours; widget extension < 30 MB (snapshot only) | **Allocations** / **Leaks** after 30 min of chat + plan scrolling |
| Battery: zero background CPU while a timer runs | system-rendered timers; Live Activity updates only on actions; no BG refresh tasks; everything cancelled in `.background`; no foreground polling (P1-16) | **Power Profiler** / Energy Log, device locked for 30 min with a running timer: no app CPU samples |
| Disk | 350 ms debounce, only dirty and loaded months, atomic | **File Activity** |

**SwiftUI rules**

1. **Narrow observation.** Views read the smallest observable they need:
   - a `DayColumn`, not `TaskStore.tasksByID`
   - `NowModel.snapshot`, not `AppModel.clockTick`

   Pass value types to leaf views, and never pass the store.
2. **`Equatable` leaf views** (`BlockView`, `LaneRow`, `ProposalRow`) with `.equatable()` where the inputs are cheap to compare.
3. **No `AnyView`.** Use `@ViewBuilder` or enums instead.
4. **Stable identities.** Always `id: \.id`, never indices. Never `.id(UUID())`, and never change `.id` to force refresh.
5. **No heavy work in `body`.** No sorting or filtering. No formatter creation: use cached `Date.FormatStyle` / `static let`. No Keychain or defaults reads. `TaskCategory.color` must be a cached static, not built per access (P2).
6. **`drawingGroup()` only where Instruments shows a win** (candidate: the 60-tick bezel, if the `Canvas` is ever not enough). `MeshGradient` is already GPU-backed.
7. **Animation.** `.contentTransition(.numericText())` only for discrete changes. Use `.task(id:)` for async work tied to the view. Haptics via `.sensoryFeedback`. The conveyor uses `.geometryGroup()` to avoid layout thrash.
8. **Aurora ≤ 15 fps,** paused when invisible, backgrounded, or under Reduce Motion, Low Power Mode or thermal pressure.

## 11. Tech-lead review of the existing code

Severity scale:
- **P0** — data loss, a broken core flow, or a PRD violation on a primary path. Fix before any UI work builds on it.
- **P1** — correctness or performance issues that users or the battery will notice. Fix before beta.
- **P2** — polish and API shape.

Line numbers refer to the files as of 2026‑11‑07. Resolved since first read: `PlanTask.expectedEnd` now clamps to `now` during overrun (PlanTask.swift:121–125), which fixes drift and free slots in overtime. The quick-add parser no longer reads "answer 3 emails" as 3 o'clock.

### P0

**P0-1 — The month partition depends on the device time zone, so tasks can silently vanish from disk.**
- Where: `TaskStore.commit` (TaskStore.swift:381–404) and `writeDirty` (360–377) partition by `MonthKey(task.start, calendar)` and by `idsByDay` day keys, which come from the local calendar. `rebuildIndex` (419–425) re-buckets after a time-zone change.
- How it fails:
  1. A task at Nov 30 23:30 New York lives in `tasks-2026-11.json`.
  2. In London it re-indexes to December.
  3. The next edit to any November task rewrites November *without* it, while December isn't dirty. The task is now in no file.
  4. If the task itself is edited instead, both files hold copies, and `bootstrap` (68) keeps an arbitrary one, depending on task-group order.
- Fix:
  - Make the storage partition time-zone-independent: the UTC month of `start`, from a fixed `Calendar(identifier: .gregorian)` set to UTC. Keep it separate from the display day index.
  - On load, dedupe by `id`, keeping the newest `updatedAt`, and mark both months dirty to heal.

**P0-2 — Months that are unloaded, partially loaded or failed to load get overwritten with partial data.**
- Where:
  - Mutations aren't gated on `isLoaded` (`add`/`update`/`apply`/`perform`, 169–271), and the 350 ms flush then writes whatever is in memory.
  - A commit that touches a month never loaded, such as moving or creating a task more than 2 months back, marks it dirty (387–398).
  - `ensureLoaded` marks months loaded *before* awaiting the read (99), and treats read errors as empty (102).
  - `bootstrap` turns any decode error into an empty month with `try?` (62).
  - `saveTasks([])` then *deletes* the file (Persistence.swift:61–64).
- Effect: one corrupt record, or one early edit, wipes a month.
- Fix:
  - `writeDirty` writes only months in `loadedMonths`.
  - `commit` loads the target month first, or persistence does read-merge-write for unloaded months.
  - Public mutators assert `isLoaded`; entry points `await waitUntilLoaded()`.
  - Decode per element (`[Lossy<PlanTask>]`). On a file-level failure, quarantine (`tasks-YYYY-MM.corrupt-<ts>.json`), mark the month read-only and surface an error.

**P0-3 — `bootstrap` isn't memoised.**
- Where: two concurrent calls both pass `guard !isLoaded` (TaskStore.swift:54). The second overwrites in-memory state with disk state (68), discarding anything done in between, such as a lock-screen Pause handled right after the first load. `waitUntilLoaded` (84–87) hangs forever if `bootstrap` is never called in that process.
- Fix:
  ```swift
  private var loadTask: Task<Void, Never>?
  public func bootstrap() async { await (loadTask ?? { let t = Task { await load() }; loadTask = t; return t }()).value }
  public func waitUntilLoaded() async { await bootstrap() }
  ```

**P0-4 — The day cache defeats Observation, so Plan views stop updating.**
- Where: `tasks(on:)` (TaskStore.swift:117–122) returns from the `@ObservationIgnored` `dayCache` without touching any observed property. A view whose `body` hits the cache registers no dependency and never refreshes again. A second view of the same day is dead from its first render, and any view becomes dead after a re-render caused by another day's edit. Home only works by accident, because `activeTask` reads `tasksByID`.
- Fix:
  - Minimum: read `revision` (`_ = revision`) at the top of `tasks(on:)`.
  - Proper fix: P1-2.
  - Add a `withObservationTracking` regression test.

**P0-5 — Lead reminders re-fire on every resync inside the lead window.**
- Where: NotificationPlanner.swift:96–101 sets `fire = now + 1`, and line 108 embeds the fire time in the ID. Once the normal reminder is delivered, any resync during the window (an edit, a foreground, a timer action) sees no pending request with the new ID and schedules another one. The copy then says "in 5 min" when fewer minutes remain. The existing test `testInsideLeadWindowFiresSoon` pins this behaviour.
- Fix:
  - IDs independent of `now`: `lead.<task>.<startEpoch>.<h8>`.
  - Pass the delivered IDs into `plan`, and never emit a lead whose `lead.<task>.<startEpoch>` prefix has been delivered.
  - Emit an in-window catch-up only for tasks created or edited since the last sync, with an accurate "starts in N min" title.

**P0-6 — Stale whole-record writes clobber timer state.**
- Where:
  - `TaskStore.update(_:)` (176–184), `apply(_:)` (204–223) and `undo` (227–237) write full `PlanTask` copies taken earlier.
  - `ToolExecutor.apply` uses the `item.after` snapshot taken at staging time (ToolExecutor.swift:241–244).
  - `AppModel`'s toast Undo calls `store.update(before)` (AppModel.swift:238–244).
- Failure cases:
  - An edit sheet is open while a lock-screen Pause runs; Save resurrects `.running` and loses the pause.
  - The assistant proposes moving task X, the user starts X, then taps Apply. X is reset to `.planned` with `session = nil`, leaving the Live Activity and time's-up orphaned. This breaks "the assistant can never start, pause or complete timers".
- Fix:
  - Split plan fields from execution fields: `update(id:, plan: (inout PlanFields) -> Void)` never touches `status` or `session`.
  - `ChangeSet` carries field patches plus `baseUpdatedAt`. `apply` rebases onto the current record and skips rows whose task is no longer `.planned` (for moves and deletes) or changed since staging. The outcome is reported as "applied 3/4".
  - Undo uses the same check.

**P0-7 — "+5 min" in overtime doesn't add time beyond what has elapsed.**
- Where: TaskTransitions.swift:61–62 → TimerSession.swift:96–100 just adds to `targetDuration`.
- Effect: at 12 min over, +5 leaves the task 7 min over. The nudge's "+5 min" is a visible no-op, and no new time's-up is scheduled, because the planner skips `end <= now` (NotificationPlanner.swift:59). This violates PRD §5.
- Fix:
  ```swift
  targetDuration = remaining(at: now) < 0 ? elapsed(at: now) + seconds : targetDuration + seconds
  ```
  `extend` needs `now`. Update `testOverrunAndExtend`: extending by 10 at 10:35 must give an end of 10:45.

**P0-8 (App) — Background entry points return before their side effects run.**
- Where:
  - `handleIntent` (AppModel.swift:323–335) and `handleNotificationAction` (377–398) await only `store.flushNow()`.
  - The notification diff is a 150/600 ms sleeping Task (NotificationScheduler.swift:65–72, via AppModel.swift:159).
  - The Live Activity update is a fire-and-forget `Task` (LiveActivityController.swift:40).
  - The widget write sleeps 1 s (WidgetSnapshotWriter.swift:12–18).
- Effect: once `perform()` or `didReceive` returns, the process can be suspended. After a lock-screen **Pause**, the old time's-up still fires. After **+5**, it fires early. After **Complete**, the nudge fires, and the Live Activity or widget may show stale state.
- The `.background` handler (108–117) has the same problem: it skips the notification diff, and calls `endBackgroundTask` before the detached widget write finishes, with no expiration handler.
- Fix:
  - Add `EffectsCoordinator.settle()`, which cancels the debouncers and awaits the flush, `await activity.update/end`, the notification diff and the widget write.
  - Every background entry point and `.background` call it inside a `BackgroundAssertion` that has an expiration handler.

### P1

**P1-1 — `activeTask` costs O(n) and the single-active invariant is unenforced.**
- Where: `activeTask` scans every task (TaskStore.swift:148–150). It is called from `perform`, `tasksAround`, `autoCompleteIfNeeded`, `AppModel.syncSideEffects` and the mini-player. Its result is undefined when two tasks are active, and `add`/`apply` accept tasks with any status (169–223).
- Fix:
  - Keep an observed `activeTaskID` in `commit`.
  - Assert at most one active task.
  - Force `status = .planned, session = nil` for assistant and quick-add creations.

**P1-2 — Observation is coarse.**
- Where: `tasksByID` is a single observed property (22). Any mutation, even a checklist tick, invalidates every day view, the week strip and Home. `AppModel.clockTick` (52, 147, 201) invalidates every clock-reading view on every change and every minute.
- Fix:
  - Per-day `@Observable final class DayColumn { private(set) var tasks: [PlanTask]; var count: Int }`, vended by `store.column(for:)` and updated only for touched days.
  - Observed `activeTask` / `activeTaskID`.
  - Replace `clockTick` with `NowModel.snapshot`.
  - Stop exposing `tasksByID` publicly.

**P1-3 — The day index uses recomputed keys and the autoupdating calendar.**
- Where: `index`/`unindex` recompute `DayKey(task.start, calendar)` (406–418) with `.autoupdatingCurrent` (44), and `calendar` is a public `var` (29). After a time-zone change, `unindex` computes a different day, leaving ghost IDs and stale caches, so a task shows on two days. `AppModel.timeZoneChanged` (130–134) only works because it rebuilds afterwards; any commit in between corrupts the index.
- Fix:
  - Store `dayByID: [UUID: DayKey]` and unindex by the stored key.
  - Use a snapshot `Calendar`.
  - Add `setCalendar(_:)`, which rebuilds the index, re-materialises and emits `.reload`.
  - Make `calendar` `private(set)`.

**P1-4 — `nextBoundary` misses boundaries.**
- Where: NowSnapshot.swift:119–137 ignores the 6 h gap flip (56), the 18 h expiry of `previous` (78), local midnight (`missedCount`, `isDate(inSameDayAs:)`), `start − lead` ("Ready") and the T−5 warning edge.
- Effect: `AppModel.armBoundaryTimer` (179–204) patches this by hand, adding per-task lead edges and a 60 s cap (see P1-16).
- Fix:
  - Add these boundaries to `nextBoundary(after:tasks:leadDefault:calendar:)`.
  - Better: return `(NowSnapshot, nextBoundary)` from one `evaluate` call, so both use the same slice.
  - Add a property test: sampling between consecutive boundaries must yield identical snapshots.

**P1-5 — The focus rule is incomplete.**
- Where: `NowSnapshot.Focus` (6–15) has no **Ready** state (starts within the lead time), no End-of-day vs Empty distinction, and no `laterCount` for "+4 later". With an active task, the upcoming filter (87) hides a due task that started before the active one.
- Fix: add `.ready(PlanTask)`, `.endOfDay(done:total:)` / `.empty` and `laterCount`. Include overlapping due tasks in `upcoming`.

**P1-6 — Notification IDs aren't content-addressed.**
- Where: IDs encode only the fire time (NotificationPlanner.swift:61, 74, 108). Renaming a task or toggling Time Sensitive never updates the pending request.
- Fix: append an 8-hex FNV-1a hash of kind, title, body and level. Never use `hashValue`, which is seeded per process. Route by `userInfo` (the app already does ✓) and drop `taskID(fromNotificationID:)`.

**P1-7 — Snooze has no model.**
- Where: `NotificationScheduler.snooze` (114–126) adds `snooze.<id>`, which the diff doesn't own. Only timer actions clear it (129–131), so a snoozed reminder still fires after the task is edited, moved or deleted. It also doesn't count toward the 64 budget.
- Fix: `NotificationPlanner.plan(..., snoozes: [UUID: Date])` emits snoozes inside the budget. Persist snoozes in the scheduler state (App Group defaults) and drop them on start, skip or edit. Add `snooze.` to the owned prefixes.

**P1-8 (App) — Lead-reminder triggers float with the time zone.**
- Where: `UNCalendarNotificationTrigger` is built from `Calendar.current.dateComponents` without `timeZone` (NotificationScheduler.swift:104–107). It fires at the old *wall-clock* time in the new zone. Because the ID (fire epoch) doesn't change, the resync after a time-zone change never replaces it. This contradicts PRD §5 ("absolute instants").
- Fix: `calendar.dateComponents(in: calendar.timeZone, from: fire)`, which sets `timeZone`, or an interval trigger.

**P1-9 — Recurring occurrences get random UUIDs.**
- Where: `makeOccurrence` assigns random IDs (Recurrence.swift:119). `updateSeries` deletes and recreates up to 14 tasks (TaskStore.swift:292–300), so every series edit churns all their reminders and widgets, and the change can't be undone as one step.
- Fix:
  - Deterministic ID = hash(seriesID, day) with the UUID version bits set.
  - `updateSeries` patches future planned occurrences in place, in one `ChangeSet` (undoable) and one `StoreChange`.

**P1-10 — Undo plumbing.**
- Where:
  - The store makes only Skip and Cancel undoable (TaskStore.swift:265–268), but the PRD requires Undo for Complete too. The task auto-resolved in a start conflict isn't captured either.
  - The app works around this with stale `store.update(before)` (P0-6).
  - Delete and Shift toasts call `store.undo()` (AppModel.swift:257, 263), which pops *whatever is last*. A notification action or intent in the 4.5 s toast window makes Undo revert the wrong change.
- Fix: `perform` records one undo entry with all its upserts and returns its ID. Toasts call `store.undo(entryID)`.

**P1-11 — `flushNow` doesn't await an in-flight write, and write errors are swallowed.**
- Where: if the debounced flush is already inside `writeDirty`, `flushNow` (344–348) finds nothing dirty and returns at once. `try?` on save (374, 376) drops the dirty marks forever.
- Fix:
  - A serial writer: chain each write's `Task` on the previous one, and have `flushNow` await the tail.
  - Re-insert months on failure and log.
  - A per-month generation counter, so an older payload never lands after a newer one.

**P1-12 — `displayInterval` folds the current pause into the lower bound.**
- Where: TimerSession.swift:77–81. With `pauseTime: pausedAt`, any state rebuilt after the pause instant shows the remaining time plus the time since pausing. Examples: launch reconciliation, a widget entry, `ContentState.init` (TaskActivity.swift:39–48). It also makes `ContentState` depend on `now`, so equality dedupe fails while paused.
- Fix: use `pausedTotal` only. Then `lower...upper` + `pauseTime: pausedAt` is correct at any `now`. Build the paused `ContentState` from `pausedAt`, not `now`.

**P1-13 — Quick-add date resolution.**
- Ambiguous ranges resolve the end on the next day (QuickAddParser.swift:157–164). `standup 9-9:15` typed after 09:15 starts at 21:00 and ends the next day at 09:15, giving 12 h 15 m. "focus from 9 to 11" at 13:00 gives 14 h. These are PRD examples.
- Explicit "today"/"tonight" turns off next-upcoming resolution (`preferFuture: dayOffset == nil`, line 158), and `tonight` is a no-op (79), so "tonight 8" gives 08:00.
- Fix:
  - When the start is ambiguous, resolve the end as the first h or h+12 after the start.
  - Use `preferFuture` when the offset is 0.
  - `tonight` forces pm for 1–11.
  - Cap durations at 12 h.

**P1-14 (App) — The effects pipeline has gaps.**
- `.active` (98–107) and the first `syncSideEffects` can run before `bootstrap` finishes. The 150 ms resync then diffs an empty store, removing every pending notification, and the widget writes an empty snapshot; both are later re-added or reloaded.
- `SettingsStore` changes trigger nothing (SettingsStore.swift:11–13). Turning reminders off, changing the default lead or turning Live Activities off has no effect until some later store change. `Haptics.enabled` is read only at init (AppModel.swift:65).
- Fix: gate all effects on `store.isLoaded`, and route settings diffs to `EffectsCoordinator.settingsChanged(old:new:)`.

**P1-15 (App) — Widget reloads are budget-hungry.**
- Where: `WidgetSnapshotWriter` hashes with the per-process `Hasher` over full `PlanTask`s, including notes, checklist and `updatedAt` (WidgetSnapshotWriter.swift:21–28; AppModel.swift:168–175). `lastHash` is in-memory only, so the first write in every process reloads: every launch and every lock-screen intent. It also calls `reloadAllTimelines()` (33).
- Fix: strip unrendered fields, use a stable FNV hash persisted in App Group defaults, and call `reloadTimelines(ofKind:)`.

**P1-16 (App) — The app polls in the foreground.**
- Where: `armBoundaryTimer` always adds `now + 60 s` (AppModel.swift:185). It then bumps the global `clockTick` (201), re-rendering every clock-dependent view each minute. It also re-computes boundaries on every store change.
- Fix: P1-4 boundaries, system-updating `Text(date, style:)` for relative labels, and a scoped `TimelineView(.everyMinute)` for the drift chip and the now-line.

**P1-17 (App) — Build risk: the Liquid Glass APIs don't exist in the Xcode 16 SDK.**
- Where: `floatingGlass` uses `glassEffect`/`Glass` (Theme.swift:262–271), as will `tabViewBottomAccessory`. `#available` is a runtime check, so this fails to *compile* with the iOS 18 SDK.
- Fix: declare Xcode 26 as the build toolchain (the App Store has required the iOS 26 SDK since April 2026), *or* wrap the code in `#if compiler(>=6.2)`. Keep the project file in the Xcode 16 synchronized-folder format.

**P1-18 (App) — Launch and background-launch cost.**
- Where: `AppModel.init` builds `AssistantService` eagerly (AppModel.swift:64). That decodes the whole transcript (up to 300 items and 200 wire messages) synchronously on main (AssistantService.swift:30–33), on every launch including lock-screen intent launches. The transcript also lives in the App Group container (21–23).
- Fix: create `AssistantService` lazily, load the transcript async on first open, and move it to app-private Application Support.
- Related: the UN delegate is installed only when something first touches `AppModel.shared` (68). The `@main` App and AppDelegate don't exist yet; `didFinishLaunching` **must** touch it, or background notification actions can be lost.

**P1-19 (Assistant) — The dynamic CONTEXT sits inside the system message.**
- Where: `SystemPrompt.build` appends it (SystemPrompt.swift:53–75; AssistantSession.swift:416–420). "Now:" changes every minute and the rows change with edits, so the prefix diverges right after `staticPart` and no history is ever cache-hit.
- Fix: keep the system message static and insert CONTEXT as its own message right before the latest user turn. This makes tools, the static prompt and the history a stable, cacheable prefix.

### P2

1. **`DayKey`:** `DayKey(string:)` accepts "2026-02-31" (DayKey.swift:21–27). `startDate` should use `startOfDay` (36–38). Replace `String(format:)` in `description` (29–31) with manual padding.
2. **Calendar defaults:** remove the `calendar: = .current` defaults from the engine APIs. Affected: DayKey; `ScheduleEngine.snapshot` (NowSnapshot.swift:40); `NotificationPlanner.plan` (50); `QuickAddParser` (32); `AppModel.selectedPlanDay` (50).
3. **`chronological` allocates:** it builds two `uuidString`s per comparison (NowSnapshot.swift:139–143). Compare `uuid` bytes instead.
4. **Colour lookups allocate:**
   - `TaskCategory.paletteIndex` allocates `allCases` and couples colour to enum order (TaskCategory.swift:45).
   - `TaskCategory.color` and `DayPhase.stops` build new colours on every access (Theme.swift), and the aurora calls them per frame. Use `static let` tables.
   - Verify that closure-based dynamic `UIColor`s render correctly in widgets and Live Activities across an appearance change. Asset-catalog colours are the safe path.
5. **DST-gap fallbacks to midnight:** Recurrence.swift:117, `QuickAddParser.resolve`, `LocalTimeCodec.parse`. Use `date(from:)` with `.nextTime` semantics.
6. **Recurrence data:** `.weekly(days: [])` never matches (Recurrence.swift:14). `excludedDays` grows without bound (74); prune entries older than 60 days.
7. **Series edge cases:**
   - `endSeries` (TaskStore.swift:303–310) lets any later full materialisation bring back today's remaining occurrence.
   - Undoing an occurrence delete doesn't un-exclude its day (190–196).
   - `removeSeries` (313–323) deletes past *missed* history and isn't undoable.
8. **`ScheduleMath`:** `roundUp` ignores the calendar, which breaks :30-offset zones with 30/60-min steps (ScheduleMath.swift:69–74). `shift` has no upper bound.
9. **Store API gaps:**
   - Unknown IDs throw `.notAllowed(from: .planned, ...)` (TaskStore.swift:256); add `.taskNotFound`.
   - Editing a running task's duration doesn't update `session.targetDuration`.
   - Durations aren't validated to 1–720 in `commit`.
10. **Planner wording:** the planner ignores `autoCompleteWhenTimerEnds`, so the nudge and copy are wrong when it's on. Time's-up being Time Sensitive shouldn't follow the lead toggle (NotificationPlanner.swift:68).
11. **Persistence efficiency:**
    - `writeDirty` scans all of `idsByDay` per month (369); keep `idsByMonth`.
    - The bootstrap task group gives no parallelism, because loads serialise on the actor (60–65).
    - `PlanTask.session` decode failure drops the whole file (PlanTask.swift:162; Persistence.swift:54–55).
    - Set the file-protection class explicitly.
12. **`StoreChange` / undo API:** add `days` and `activeChanged`; document that `onChange` has a single owner; `UndoEntry.date` should take an injected `now` (TaskStore.swift:427–430).
13. **`requireApproval`** (PlannerSettings.swift:67) contradicts pillar 4. Remove it.
14. **QuickAdd polish:** `CharacterSet` and the weekday table are rebuilt per token, on every keystroke (lines 60, 208, 225, 288, 298, 352–358); hoist them to `static let`. `midnight` and `12` after noon resolve to the past. Weekday abbreviations collide with words ("sat", "wed", "sun").
15. **Live Activity:** it recreates the activity after a user dismissal, contradicting UX-2 (LiveActivityController.swift:36–59). Add the 7 h restart and the 8 h guard. Observe `activityStateUpdates`.
16. **Intents:** set `static let isDiscoverable = false`. Set `DAYFLIGHT_APP` only in the app target's `SWIFT_ACTIVE_COMPILATION_CONDITIONS`. Add a stale-action guard using `startEpoch`.
17. **`AppGroup`:** `containerURL` and `identifier` are recomputed on every access (an entitlement lookup); make them `static let`. The silent fallback to private storage (AppGroup.swift:19–25) hides misprovisioning and strands data later; `assertionFailure` in DEBUG.
18. **Keychain on main:** `SecItemCopyMatching` runs on main, and `hasKey`/`maskedKey` hit the Keychain on every access (AssistantService.swift:49; SettingsStore.swift:43–89). Cache them.
19. **Assistant:** `onModelFallback` permanently overwrites the user's model (AssistantService.swift:45); keep configured and effective models separately. `refreshModels` has no cache. `OpenAIHTTPTransport` can be plain `Sendable` (ChatTransport.swift:70). `compact` has no token budget. `ToolExecutor.apply` creates series outside the undoable `ChangeSet` (ToolExecutor.swift:249).
20. **Snooze write:** `snooze` uses fire-and-forget `center.add` in a background path; await it.
21. **Quick-add cost:** `quickAdd` builds a `DateFormatter` per call, and `lastDuration` scans every task (AppModel.swift:283, 303–309).

## 12. Testing strategy

**PlannerCore (`swift test` on Linux; XCTest exists, Swift Testing is fine for new suites).** Inject `now` and the `Calendar` everywhere.

- **Timer math:** pause/resume/extend and overtime extend (P0-7); `displayInterval` invariance under `now` (P1-12).
- **Transitions:** an exhaustive action × status table.
- **`ScheduleEngine`:** focus rules including Ready, End-of-day and Empty, plus the **boundary property test** (random days; snapshots identical between consecutive `nextBoundary`s).
- **`ScheduleMath`:** free slots including overtime.
- **Recurrence:**
  - deterministic IDs and idempotent materialisation
  - DST (America/New_York 2026‑03‑08, Europe/London 2026‑03‑29, America/Santiago midnight DST)
  - Asia/Kolkata and Asia/Kathmandu offsets
- **`NotificationPlanner`:**
  - budget and horizon
  - **idempotence**: plan at t and at t+Δ with the first set delivered → no new lead (P0-5)
  - a rename changes the ID; editing one task changes ≤ 2 operations
  - snoozes stay inside the budget
- **`QuickAddParser`:** table tests at 08:00, 13:00 and 22:00, including every PRD example.
- **`TaskStore` (with `InMemoryPersistence`):**
  - time-zone switch doesn't lose data (P0-1)
  - unloaded and corrupt months are never overwritten (P0-2)
  - concurrent bootstrap (P0-3)
  - `withObservationTracking` fires for cached days (P0-4)
  - stale rebase (P0-6)
  - undo by entry ID
  - single-active invariant
- **Assistant:**
  - SSE fragments
  - tool-call delta accumulation
  - the HTTP error mapping
  - context budget
  - a byte-stability snapshot of `staticPart` and the tool schema (cache guard)
  - scripted `ChatTransport`: 6-round limit, `ask_user`, cancellation mid-stream, fallback
- **`WidgetTimeline`:** ≤ 40 entries, ending at the end of tomorrow.

**Device-only tests (manual checklist, iOS 18 and iOS 26 devices):**
- **Live Activity:**
  - start, pause, resume, +5, complete
  - `isStale` overtime face with the app killed
  - lock-screen buttons with the app killed **and the device locked** (file protection)
  - 8 h limit (a 9 h task)
  - respect for user dismissal
  - Dynamic Island compact, minimal and expanded; StandBy
- **Notifications:**
  - every action with the app killed: Snooze, Skip, Complete, +5 in background; Start now in foreground (deferred Live Activity start)
  - a lock-screen Pause must cancel the time's-up (P0-8)
  - the 64-cap with 200 tasks
  - the Time Sensitive entitlement on and off
  - delivered cleanup
- **Clock and time zone:** a manual time-zone change mid-day (reminder instants unchanged), midnight in the foreground and while suspended, DST weekend.
- **Widgets:** reloads only on content change (count them in the Console); appearance switch.
- **Assistant:** Ollama or LM Studio over LAN (local-network prompt, ATS); backgrounding mid-stream (ready notification; nothing applied); airplane mode → Retry.
- **Accessibility and power:** Reduce Motion, Low Power Mode and thermal throttling freeze the aurora.

**Pre-release performance checklist**
1. **App Launch** template: cold launch < 1 s on the oldest supported device (iPhone XS / A12) with 5k tasks and a full transcript; first frame without transcript or Keychain work.
2. **Time Profiler:** quick-add parse per keystroke < 1 ms, `snapshot` < 0.5 ms, `tasks(on:)` < 0.1 ms, notification resync < 50 ms wall time.
3. **SwiftUI** instrument (Xcode 26) plus **Animation Hitches:**
   - Plan horizontal paging and vertical scroll at 120 Hz with no hitches above 1 frame
   - conveyor animation
   - no view-body update storms on a checklist tick (P1-2)
4. **Allocations / Leaks:** < 100 MB after 30 min of mixed use; widget extension < 30 MB.
5. **Power Profiler / Energy Log:** device locked for 30 min with a running timer shows zero app CPU wakes; Now on screen with no running timer shows no periodic wakes (P1-16); aurora ≤ 15 fps.
6. **File Activity:** one month file per edit burst, none while idle.
7. **Network:** one HTTP/2 connection per turn, `cached_tokens > 0` from the second turn on (P1-19).
8. In code: `os_signpost` intervals `bootstrap`, `snapshot`, `notifResync`, `widgetWrite`, `agentRound`. In production: MetricKit (`MXAppLaunchMetric`, `MXCPUMetric`, hang diagnostics).
