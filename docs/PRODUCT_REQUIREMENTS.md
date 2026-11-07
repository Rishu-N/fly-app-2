# Dayflight — Final Product Requirements (v1.0)

> Synthesised from the six research tracks in `docs/research/` (UX ×2, UI ×2, BA ×2).
> Where tracks disagreed, the decision and the reason are recorded here. This document is the
> input to `docs/ARCHITECTURE.md` and to the implementation.

**Working name: Dayflight** (BA‑1's top pick; fits the "fly" codename. Trademark check still pending.)
**One-liner:** *The planner that starts when you do.*

---

## 1. Product pillars

1. **The task is the timer.** Starting a task runs a countdown for its **planned duration** from the
   moment of the tap, whatever the clock says. 2:00–3:00 started at 1:58 → ends 2:58; started at 2:10 → ends 3:10.
2. **One glance = what now, how long, what next.** Home shows Last · **Now (expanded)** · Next · Next.
3. **The plan never moves without a tap.** Drift is shown, and fixing it is a single tap with Undo.
4. **An assistant that asks before acting.** It asks clarifying questions, and every change it proposes
   is previewed as a review card. Nothing is applied until the user taps Apply, and every applied set can be undone.
5. **Fast, cheap, private.** Native SwiftUI. Zero background CPU while a timer runs. No account and no app server.
   The OpenAI key stays in the Keychain.

## 2. Platform & scope decisions

| Decision | Choice | Why |
|---|---|---|
| Minimum iOS | **iOS 18.0**; Liquid Glass on **iOS 26** via `#available` | MeshGradient, `Tab` API, zoom transitions; iOS 26 glass where available. iOS 18 is a reasonable floor for a new app in late 2026. |
| Devices | iPhone only (portrait) | Scope. iPad/Watch in v2. |
| Data | On-device, App Group container, no backend | Privacy, cost, reliability. iCloud sync in v1.1. |
| Calendar import (EventKit) | **v1.1** | Keeps v1 focused on the wedge (BA‑2 lists it as Should). |
| Inbox/unscheduled tab | **Not in v1** | UX‑2 suggested it; UX‑1 keeps three tabs. The wedge is the scheduled day. |
| Monetisation | Not implemented in v1 code; plan per BA‑1 (Free + Pro $6.99/mo or $39.99/yr) | Ship the experience first. |

## 3. Information architecture

- **Tabs (3):** `Now` (`timer`) · `Plan` (`calendar.day.timeline.left`) · `Assistant` (`sparkles`, always last).
- **Settings:** gear button on Now → sheet.
- **Quick capture:** floating **+** on Now and Plan, plus pull-down on Now.
- **Mini-player:** while a timer runs, a compact pill above the tab bar on Plan and Assistant (iOS 26 `tabViewBottomAccessory`; overlay on iOS 18–25).

## 4. Home — "The Now Lens" (UX‑1, adopted)

Layout, top to bottom: header (date, day-progress hairline, drift chip, gear) → **Last lane** (52 pt) →
**Lens** (flexible, about 55% of the screen) → **Next 1** (68 pt) → **Next 2** (52 pt) → tail ("+4 later").

**Focus rule** (what the lens shows, in order):
1. A running, paused or overtime task. It is **never displaced**.
2. A planned task whose window contains now (**Due/Late**), or that starts within the lead time (**Ready**).
3. A **Gap** slab counting down to the next task, with "Start next now" and "Fill gap".
4. **End of day** summary, or **Empty** ("Your day is open").

**Lens contents:** category dot, planned window and state label · title (2 lines) · notes/checklist
(up to 3 items, checkable) · **hero timer** (bezel ring with 60 ticks + condensed monospaced digits; tap to
toggle remaining ↔ "ends at") · control cluster:

| State | Controls |
|---|---|
| Ready / Due / Late | **Start** (full width), Skip, ⋯ (Mark done, Edit) |
| Running | **Pause**, **Complete**, +5, ⋯ (Cancel, Edit) |
| Paused | **Resume**, Complete, ⋯ (Cancel) |
| Overtime | **Complete** (prominent), +5, +15 |
| Gap | Start next now, Fill gap |

- **Cancel** is never next to Complete. It lives in ⋯ or the swipe-left tray, with no dialog and an Undo toast.
- **Swipe right** on the lens = Complete. **Swipe left** = the Later tray (+5, +15, Skip, Cancel).
- **Conveyor moment** on Complete, Cancel or Skip: the lens shrinks into Last, Next 1 grows into the lens and Next 2 slides up. About 440 ms, with a `.success` haptic. Undo reverses it.
- **Drift chip & collision badge:** "you'll be 4m late" → Push next / Shift rest of day / Ignore (one undoable change).

## 5. Timer & lifecycle rules (UX‑2 edge-case table + BA‑2 state machine)

- **Stored status:** planned · running · paused · completed · cancelled · skipped. **Derived phase:** upcoming, due, missed, overrun.
- **Timer is derived from timestamps:** `startedAt`, `pausedAt`, `pausedTotal`, `targetDuration` (+ extensions), `endedAt`. It never ticks in state, so it survives kills, reboots and suspension.
- **Early or late start** → full planned duration from the tap. The plan is untouched, and drift is shown.
- **One timer at a time.** Starting B while A is active asks: **Complete A & start B** (default) · **Cancel A & start B** · Keep A.
- **Pause** freezes remaining time, and the "ends at" time slides later.
- **Overrun:** digits count up with "+", the ring turns amber, and there are +5/+15 buttons and one nudge notification at +10 min. **Never auto-completes** unless Settings › Auto-complete is on.
- **+5 in overtime** adds 5 minutes beyond the time already elapsed.
- **Missed** (window passed, never started): shown kindly as "Didn't start", with Reschedule.
- **Skip** (not started) and **Cancel** (started, abandoned) are both undoable. **Delete** is separate (edit sheet / long-press).
- **Recurring tasks:** daily, weekdays, or weekly on chosen days. Occurrences are materialised for a 14-day window; deleting one occurrence excludes that day; editing a series changes future, not-started occurrences.
- **Time-zone change:** blocks keep their absolute instants; the day index is rebuilt.

## 6. Notifications (UX‑2 + UI‑2 copy)

| Type | When | Title / body | Actions | Level |
|---|---|---|---|---|
| Lead reminder | start − lead (default **5 min**; global + per task; 0 = at start) | "{title} in 5 min" / "2:00–3:00 · 60m" | **Start now** · Snooze 5 min · Skip | Time Sensitive (setting) |
| Time's up | timer reaches zero | "Time's up · {title}" | **Complete** · +5 min | Time Sensitive |
| Overrun nudge | 10 min after zero, once | "Still on {title}?" | Complete · +5 min | Active |
| Assistant ready | AI reply finishes while backgrounded | "Your plan is ready to review" | (opens Assistant) | Passive |

- **Rolling window:** at most 56 lead reminders across 7 days (iOS caps pending notifications at 64). It is re-synced on launch, on any change, on a day or time-zone change, and on foreground.
- **Minimal diff:** request IDs are content-addressed, so editing one task touches about two requests.
- **Per-day thread grouping.** Lead reminders for a task are removed when it starts, is edited or completes.
- **Actions run in the background** (Snooze, Skip, Complete, +5). **Start now** opens the app so the Live Activity can start.

## 7. Live Activity, Dynamic Island, widgets (UI‑2)

- **Live Activity** starts when a task starts and is updated only on user actions (start, pause, resume, extend). Countdown via `Text(timerInterval:countsDown:)`, progress via `ProgressView(timerInterval:)`, so there are no per-second updates. `staleDate` = projected end, so overtime renders without waking the app.
- **Lock Screen buttons** are App Intents: **Pause/Resume** and **Complete**. Cancel stays in the app.
- **Dynamic Island:** compact = progress ring + countdown in the category colour; minimal = ring; expanded = title, countdown, ends-at, next task, Pause/Complete.
- **Widgets:** Small (now/next + countdown), Medium (Now + Last + Next ×2), Lock Screen circular, rectangular and inline. Timeline entries only at task boundaries; reloaded only on edits.

## 8. Quick capture (UX‑1 §5)

One line, parsed locally and deterministically, with live chips: `gym 6:30pm 45m #health`, `standup 9-9:15`,
`deep work 90m` (lands in the first free slot), `call mum tomorrow 7pm`. A bare hour resolves to the next
upcoming occurrence. Return adds the block and keeps the field open for rapid entry.

## 9. Plan tab

- **Day timeline:** hour grid, now-line, blocks tinted by category (14% light / 22% dark fill + 3 pt bar), plan-vs-actual for finished blocks, dashed "Free 45m" gaps. Tap a block → edit sheet. Long-press → context menu (Start now, Duplicate, Move to tomorrow, Delete).
- **Week strip** on top to switch days, with a density dot per day.
- **Edit sheet:** title, start, duration (chips 15/25/30/45/60/90 + stepper), category, reminder (default / custom / off), repeat, notes, checklist.

## 10. Assistant tab (BA‑2 §5 + UX‑2 §6)

- **Transport:** OpenAI Chat Completions with streaming, function calling and the user's key. The base URL is configurable, so OpenAI-compatible local servers (Ollama, LM Studio) also work.
- **Model:** free text with a picker **populated live from `GET /models`**. Default `gpt-5-mini`. ⚠️ BA‑1 reports OpenAI retires `gpt-5-mini`/`nano` on **2026‑12‑11** and `gpt-4o-mini`/`gpt-4.1-mini` on **2027‑01‑14**. If the server says the model doesn't exist, the app **auto-falls back** to an available model from the live list and tells the user.
- **Tools:** `list_tasks`, `find_free_slots`, `create_tasks`, `update_tasks`, `shift_tasks`, `delete_tasks`, `ask_user`.
  - Write tools only **stage** a change set, shown as a review card with Add/Move/Edit/Remove rows and per-row checkboxes, plus **Apply** / **Discard**.
  - Applied sets are undoable (one entry per set).
  - The outcome ("applied 3/4") is reported back to the model on the next turn.
- **Clarifying questions:** `ask_user` renders option chips plus "Just decide for me" and free text. Typing while a question is open answers it.
- **Templates (12):** Plan my day, Running late, Quick add, Break it down, Find free time, Move tasks, Clear a block, Daily review, Weekly planning, Build a routine, Focus sprints, Prep for an event. Shown as a chip rail; each opens a small fill-in form.
- **Context control:**
  - The prompt carries today only, plus the active task. Anything else is fetched via `list_tasks` (≤ 14 days per call).
  - Earlier turns are compacted, with tool payloads dropped.
  - The static system prompt comes first so the provider can cache it.
  - At most 6 round trips per message.
- **Runs locally in the background:** the request runs on the device and survives tab switches. When backgrounded, a background-task assertion lets it finish, then a local notification is posted. Changes are **never applied in the background**.
- **Privacy:**
  - A one-time consent sheet appears before the first request (App Review 5.1.2(i)).
  - Notes are not sent unless toggled on.
  - The key is stored in the Keychain (`AfterFirstUnlockThisDeviceOnly`) and only its last 4 characters are ever shown.
  - Chats are stored on the device, with a Clear button.
  - The assistant can **never** start, pause or complete timers.

## 11. Visual system — "Chronograph bones, Aurora light" (UI‑2 hybrid)

- **Structure from UI‑1:** 4 pt grid, condensed monospaced timer digits, uppercase expanded "bezel" eyebrows (NOW · NEXT · ENDS 2:58), tick-mark ring, solid card controls, glass only on the floating layer.
- **Light from UI‑2:** a time-of-day **aurora field** (MeshGradient, dawn/day/dusk/night) behind the lens **only**. It is cheap: ≤ 15 fps, frozen when paused, off-screen, under Reduce Motion or in Low Power Mode. It also blends warning or danger as the timer runs low or over.
- **Themes ("dials"):** **Aurora** (default, violet now `#5B3DF5` / `#9483FF`), **Lume** (cyan `#00748C` / `#3DE3F5`), **Ember** (signal orange `#BA3C04` / `#FF6A2B`). The app follows the system light/dark setting.
- **Category colours** are shared across themes (UI‑2 set, with Slate replacing Plum to stay clear of the violet accent): focus Indigo, meeting Sky, learning Teal, health Green, admin Amber, social Coral, personal Rose, rest Slate.
- **Semantics:** the accent appears only on live things. Success = complete. Warning = ending soon or overrun. Danger = destructive only. Status always pairs a glyph with a word.
- **Motion tokens** (everything ≤ 350 ms except the conveyor):
  - `micro` `.snappy(0.15)`
  - `snappy` `.snappy(0.25)`
  - `bouncy` `.spring(0.32, 0.72)`
  - `glide` `.spring(0.35, 0.86)`
  - `conveyor` `.spring(0.36, 0.86)`
  - Reduce Motion falls back to 200 ms fades.
- **Haptics** via `.sensoryFeedback`: start = impact medium, complete = success, cancel/skip = impact light, overrun = warning, pause = selection.

## 12. Settings (defaults in bold)

- **Reminders:** enabled **on**; default lead **5 min**; Time Sensitive **on**; notify at timer end **on**.
- **Planning:** default duration **30 min**; day window **07:00–22:00**; auto-complete at zero **off**.
- **Feel:** theme **Aurora**; haptics **on**; ambient aurora **on**; Live Activities **on**.
- **Assistant:**
  - OpenAI key (Keychain)
  - model **gpt-5-mini** (with live list)
  - base URL **https://api.openai.com/v1**
  - reasoning effort **low**
  - share notes **off**
  - clear history
- **Check my reminders** diagnostic: permission state, time-sensitive state, and the number of reminders scheduled.

## 13. Non-functional budgets (BA‑2 §2.8, owned by the tech lead)

- Cold launch to interactive Now in **< 1 s**; day query **< 10 ms**; scrolling at **120 fps** on ProMotion; memory **< 100 MB**.
- **Zero** timers firing while a task runs in the background. The system renders countdowns.
- Disk writes are debounced (about 350 ms), touch only the changed month file, and are atomic.
- The notification resync diff applies only the minimal adds and removes.
- AI defaults: about 8k input tokens max per request, and an output cap.

## 14. Out of scope for v1 (roadmap)

- **v1.1:** iCloud sync; EventKit overlay; Insights/stats; Siri and Shortcuts quick add; Control Center control; custom templates; widget buttons.
- **v2.0:** Apple Watch; iPad and Mac; two-way calendar sync; on-device Apple Foundation Models option.
