# Dayflight

**The planner that starts when you do.** A native iPhone calendar + reminders app for
minute-by-minute time-blocking, with a pomodoro-style timer on every block and an on-device
OpenAI assistant that plans with you.

- **The task is the timer.** Tap Start and the block's full planned duration counts down from
  that moment, whatever the clock says. A 2:00–3:00 block started at 1:58 ends at 2:58.
- **Home = the Now Lens.** The last block sits compressed at the top, the current block is
  magnified in the middle (timer ring, Pause/Play, Complete, Cancel, +5) and the next two blocks
  follow. When you complete a block, the next one slides up into the lens.
- **Reminders** fire 5 minutes before a block by default. You can change that globally or per
  block, and Start, Snooze or Skip right from the notification.
- **Live Activity + Dynamic Island** show the running block, with Pause and Complete buttons on
  the Lock Screen.
- **Assistant tab.** It runs on your device with your OpenAI key and has no server of its own. It
  adds and moves blocks, asks clarifying questions, and comes with 12 prompt templates. Every
  change is shown as a review card, and nothing changes until you tap **Apply**. Every applied
  change can be undone.
- **Plan tab.** A day timeline (drag a block to move it, with a 5-minute snap) and a **week
  overview** zoom level.
- **Apple Calendar overlay.** Optional and read-only. Your events show as busy time, and quick add
  and the assistant plan around them. Event titles are only shared with the assistant if you turn
  that on.
- **Insights.** Focused vs planned time, on-time starts, start drift, completion rate,
  focus by category, and your streak.
- **Everywhere on the system:**
  - Siri/Shortcuts: "Add a block", "Start my next block", "I'm done", "What's next".
  - A Control Center / Action button control for quick add.
  - Start, Pause and Complete buttons on the Home Screen widget.

---

## Open & run

Requirements: **Xcode 26** (iOS 26 SDK) recommended, or Xcode 16 or newer. The deployment target
is **iOS 18.0**. On iOS 26 the app uses Liquid Glass; earlier versions fall back to materials.

1. Open `Config/Base.xcconfig` and set:
   - `APP_BUNDLE_ID` to a reverse-DNS id you own (the widget becomes `<id>.widgets` and the App
     Group becomes `group.<id>`)
   - `DEVELOPMENT_TEAM` to your Team ID (or pick a team in Signing & Capabilities)
2. Open `Dayflight.xcodeproj`, select the **Dayflight** scheme and run it on an iPhone or a
   simulator.
   - Alternative: `brew install xcodegen && xcodegen generate` regenerates the project from
     `project.yml`.
3. Optional: in the app, go to **Settings › Assistant** and paste an OpenAI API key. It is stored
   in the Keychain on this device only.
   - Any OpenAI-compatible server works too, for example a local Ollama at
     `http://192.168.x.x:11434/v1`.

Capabilities used: **App Groups** (shares data with the widget) and **Time Sensitive
Notifications**. Both need a paid Apple Developer team. With a free personal team, delete both
entitlements in `Config/*.entitlements`: the app still runs, but widgets won't see your data.

Core logic tests (any machine with Swift 6, Linux included):

```bash
cd PlannerCore && swift test     # 150+ tests
```

> **OpenAI models (verified 2026-11-09 on developers.openai.com, see
> `docs/research/verification-2026-11.md`).** The default is **`gpt-6-luna`**, OpenAI's cheapest
> current model at $0.10 / $0.50 per 1M tokens.
> - **Effort:** On Chat Completions, `gpt-6-luna` and `gpt-6-sol` can only call tools with
>   `reasoning_effort: "none"`. The app handles this per model (`ModelCapabilities`), and Settings
>   only offers efforts the model accepts.
> - **Retirements:** `gpt-5-mini`/`gpt-5`/`gpt-5-nano` shut down on **2026-12-11** and
>   `gpt-4.1-mini`/`gpt-4o-mini` on **2027-01-14**. Saved settings using those models migrate
>   automatically.
> - **Picker and fallback:** The picker is filled from your account's live `GET /models` list. If a
>   model is retired or about to be (its `shutdown_date`), the assistant switches to an available
>   tool-capable model and tells you.

---

## Project layout

```
PlannerCore/            Swift package: all domain logic, no UI frameworks, Linux-testable (Swift 6)
  Model/                PlanTask, TimerSession (timestamps, never ticks), Recurrence, Settings, StableHash
  Engine/               NowSnapshot (focus rule), TaskTransitions (state machine), ScheduleMath
  Notifications/        NotificationPlanner — 64-cap rolling window, content-addressed ids, minimal diff
  Parsing/              QuickAddParser — "gym 6:30pm 45m #health", "standup 9-9:15", "call mum tomorrow 7pm"
  Store/                TaskStore (@Observable), UTC-month-partitioned JSON, undoable ChangeSets
  Assistant/            OpenAI Chat Completions streaming client, tools, agent loop, prompts, 12 templates
App/                    The iPhone app (SwiftUI)
  AppModel.swift        Composition root: side-effect fan-out, settle(), notification + intent handling
  Services/             NotificationScheduler, LiveActivityController, WidgetSnapshotWriter,
                        AssistantService, SettingsStore/Keychain, Haptics
  Features/Now/         Now Lens: LensCard, TimerDial (bezel ring), AuroraField (time-of-day mesh)
  Features/Plan/        Week strip, day timeline (drag to reschedule, 5-min snap), editor
  Features/Assistant/   Chat, clarifying-question chips, proposal review cards, template forms
  Features/…            Quick capture, Settings (incl. "Check my reminders"), Onboarding
Shared/                 Compiled into app + widget: theme tokens, Live Activity attributes + intents
Widgets/                Live Activity, Dynamic Island, Home/Lock Screen widgets
Config/                 xcconfig, Info.plists, entitlements
docs/                   Research, final requirements, architecture + tech-lead review
```

## How it was designed

Seven agents worked in parallel and in sequence. Their full outputs are in `docs/`:

| Role | Output |
|---|---|
| UX #1: interaction paradigm | `docs/research/ux-1-interaction-paradigm.md`: "The Now Lens", gestures, the conveyor motion |
| UX #2: flows & edge cases | `docs/research/ux-2-flows-and-edge-cases.md`: IA, notifications, a 21-rule edge-case table, assistant UX |
| UI #1: visual system | `docs/research/ui-1-visual-system.md`: "Chronograph", the Lume/Tachymeter/Abyss palettes, type, motion |
| UI #2: palettes & live surfaces | `docs/research/ui-2-palettes-and-live-surfaces.md`: "Aurora", Live Activity, Island, widgets, icon |
| BA #1: market research | `docs/research/ba-1-market-research.md`: competitors, personas, pricing, naming |
| BA #2: product plan | `docs/research/ba-2-product-plan.md`: feature catalog, user stories, AI tool spec, templates |
| Technical architect / tech lead | `docs/ARCHITECTURE.md`: architecture, performance budgets, code review (P0/P1/P2) |

These were combined into **`docs/PRODUCT_REQUIREMENTS.md`**, which is the authoritative v1.0
spec. Key decisions:

- **Visual direction: "Chronograph bones, Aurora light".** Precise instrument typography (condensed
  monospaced digits, uppercase eyebrows, a tick-mark ring) plus a time-of-day aurora field behind
  the current block only. There are three selectable themes: **Aurora** (default, violet), **Lume**
  (cyan) and **Ember** (orange).
- **One timer at a time.** Starting another block asks you to complete or cancel the current one.
  Overtime counts up and never completes itself unless you turn that on.
- **The plan never moves without a tap.** A drift chip offers "Push next" or "Shift rest of day",
  each with Undo.
- **The assistant only proposes.** Write tools stage a change set, you review and apply it, and an
  applied set is one Undo. The assistant can never start, pause or complete a timer.

## Performance & battery

- **No ticking timers.** Countdowns are rendered by the system (`Text(timerInterval:)`,
  `ProgressView(timerInterval:)`) in the app, the Live Activity and widgets. While a block runs in
  the background the app uses **zero CPU**: the Live Activity counts down by itself, and its
  `staleDate` switches it to the overtime view.
- **Home re-renders only at schedule boundaries.** These are a block starting or ending, the
  timer reaching zero, or the lead time starting. In the foreground there is also one tick per
  minute for labels like "in 12m". The ring updates at 1 Hz inside a scoped `TimelineView`.
- **Storage:**
  - Data is held in memory as value types.
  - Day queries use an index, so they cost O(that day's tasks).
  - Writes are debounced, serialised and atomic, run off the main thread, and touch only the
    changed month's file.
  - Files are partitioned by UTC month, so a time-zone change can't move a task between files.
- **Notifications** use a diff: editing one block touches about two system requests, and the
  rolling window stays under iOS's 64-pending limit.
- **Widgets** reload only when the rendered content's stable hash changes.
- **Aurora field:** a 3×3 MeshGradient at ≤ 15 fps. It is paused when off-screen, when the block
  is paused, under Reduce Motion or Low Power Mode, and when the device is hot.
- **Assistant:**
  - A static, cacheable system prompt.
  - Only today's schedule is sent up front; anything else is fetched through tools.
  - Earlier turns are compacted.
  - At most 6 round trips per message.
  - Streaming with cancellation.

## Testing & CI

Every push runs `.github/workflows/ci.yml`:

- **Linux:** `swift test` for PlannerCore. The suite includes property and fuzz tests, a scripted
  conversation for each of the 12 assistant templates, adversarial and prompt-injection tests,
  and real HTTP tests against a mock OpenAI server.
- **macOS 26 (Xcode 26):**
  - PlannerCore tests again, which covers the Darwin streaming path.
  - A full build of the app and widget extension for the iOS simulator.
  - UI tests that drive the Now (running, paused, overrun, gap, empty), quick add, Plan (day and
    week), Insights, Assistant and Settings screens in light and dark mode.
  - Screenshots exported as the `screenshots` artifact, plus a text layout audit (clipping,
    overlap, small tap targets) printed in the log.

UI-test mode: launch with `-UITests -UITestsScenario running|paused|overrun|gap|empty`
(add `-UITestsDark` for dark mode) for deterministic in-memory data.

## Status & next steps

- PlannerCore tests pass on Linux and macOS. The iOS app, widgets and UI tests **build and pass in
  CI on Xcode 26 / `macos-26`**.
- Things that can only be checked on a real device:
  - Live Activity buttons while the phone is locked
  - notification actions when the app has been killed
  - time-sensitive delivery
  - the battery cost of the aurora (measure with Instruments)
- **Roadmap:**
  - Next: iCloud sync, custom templates, and a Responses API transport so GPT-6 models can reason
    while using tools.
  - Later: Apple Watch, iPad/Mac, an on-device model option.
