# UX-1: Core Interaction Paradigm, "The Now Lens"

**Owner:** UX Designer #1 · **Scope:** paradigm, Home/Now, task lifecycle, gestures, quick capture, motion, how Day and Week relate to Home.
**Out of scope (UX-2):** onboarding, deep edge cases, the accessibility deep-dive, AI chat UX.

**Ground rules this doc assumes**
- The timer is **duration-based**: Start means the planned duration begins now (start a 2:00–3:00 task at 1:58 → it ends at 2:58).
- **One running task at a time.**
- **Plan and reality are separate.** Planned times never change on their own; actual times are recorded; the difference ("drift") is always visible and fixable in one tap.

---

## 1. Three paradigm concepts

### A. The Now Lens (fixed focal point, time flows through it)
Home is an instrument, not a list you scroll. A focal **lens** sits at a fixed position on screen, and time moves through it like film through a projector gate. Whatever is under the lens (a task, a free gap, the end of the day) is magnified into a live control surface. Everything else shrinks with distance: the last task above, the next two below, the rest folded into a tail. "Now" is always in the same place under your thumb. Completing a task advances the film one frame (the **conveyor**). Dragging the rail scrubs ahead to preview and springs back. Pinching closed relaxes the magnification into a linear Day timeline, then a Week.
**Why it's new:** calendars are documents you navigate; this presents the present. It applies fisheye focus+context to time, and the timer lives *inside* the magnified object instead of on a separate screen.

### B. Orbit (the day as a dial)
The next 3 hours (zoomable to 12) wrap around a ring. Tasks are arcs, and a sweeping hand eats the current arc, so the arc itself is the timer. Drag an arc's ends to resize it or rotate it to reschedule. The center holds the countdown and controls.
**Why it's new:** clock, schedule and pomodoro become one analog, gestural object, a natural fit for the Watch and the Dynamic Island.
**Cost:** text on curves, minute precision, short blocks, overlapping arcs and VoiceOver order all get hard.

### C. The Deck (one card face-up)
Each block is a physical card. Only the Now card is face-up, with the next cards stacked behind it in Z and the last task in a discard pile on top. Swipe right to complete or left to defer, and the next card rises.
**Why it's new:** the day becomes tactile, one thing at a time.
**Cost:** it hides time. Gaps, overlaps, "how long until" and drift become invisible, and a deck implies order rather than clock time.

### Decision: **A, the Now Lens**, with two borrowings
1. **The brief already describes a fisheye** (last, expanded current, next two). The Lens makes it a system, not "a list with one big row".
2. **Minute precision needs linear, legible time labels.** Lens rows stay rectilinear; Orbit fails here.
3. **It keeps time context** (gaps, drift, collisions), which the Deck hides.
4. **One spatial model across Now, Day and Week** via semantic zoom: fewer concepts to learn.
5. **Cheap and battery-friendly:** Home is a fixed layout of 5 slots, with no scrolling list, no 3D and one 1 Hz tick.
6. **VoiceOver order matches time order.**

**Borrowed from Deck:** swipe the lens slab to complete it (as an accelerator), and the "one thing at a time" emphasis.
**Borrowed from Orbit:** the object itself *drains*. A small drain ring is used on compact surfaces (Dynamic Island, widget, mini-player).

---

## 2. Home / Now screen spec

### 2.1 Layout, top to bottom (reference: 6.1"/6.3" iPhone, about 852 pt tall)

| Zone | Height | Content |
|---|---|---|
| **Z0 Header** | 44 pt | "Sat, Nov 7" over a 2 pt **day-progress hairline** (one segment per block: filled = done, tinted = current, outlined = future). Trailing: **drift chip** ("On time", amber "+6m", teal "−3m") and settings. |
| **Z1 Last lane** | 52 pt | Most recent finished, cancelled or skipped task today, at 60% opacity: status glyph (✓ / ✕ / ↷), one-line title, actual vs planned ("52m of 60m"). Hidden if none, and the lens grows upward. |
| **Z2 The Lens** | flexible, ≥ 340 pt (about 55%) | Liquid Glass slab, 32 pt corner radius. The task color fills the **remaining** portion (the drain). Contents below; states in §2.2. |
| **Z3 Next 1** | 68 pt | Monospaced start time ("3:00"), title, duration, "in 12m", collision badge when needed. |
| **Z4 Next 2** | 52 pt | Same, smaller, at 80% opacity. |
| **Z5 Tail** | 32 pt | "+4 later · last ends 9:40 PM" with a grabber. Pull up to open Day. |
| **Bottom** | system | Tab bar **Now · Plan · Assistant**, plus a floating glass **+** (capture). |

**Inside the lens, top to bottom:**
1. Color dot, planned window ("2:00–3:00 PM") and state label ("Running", "Starts in 4:12", "Late 3m").
2. Title (title2 bold, up to 2 lines), then a row of meta chips (location, "Join" link, tag).
3. Notes or checklist, up to 3 lines or items, checkable in place. "Show all" expands the lens to full height.
4. **Hero timer** (76 pt SF Rounded, monospaced digits) with "ends 2:58 PM · started 1:58" under it. Tapping the digits swaps remaining time ↔ ends-at clock.
5. **Control cluster**: 56 pt capsules in a `GlassEffectContainer`, deliberately at about 65–72% of screen height (the one-handed thumb zone).

### 2.2 What goes in the lens: the focus rule
Check these in order:
1. A **Running, Paused or Overtime** task.
2. A task with planned start ≤ now + lead time (lead time = the notification lead, default 5 min) that hasn't been started or dismissed. It shows as **Ready** before its start and **Late** after.
3. Otherwise, if a future task exists today, a **Gap** object covering now → next start.
4. Otherwise, **End of day** if any tasks existed today, or **Empty** if none did.

A running task is **never displaced**. If Next 1's start arrives while you're in overtime, Next 1 shows a collision badge and the lens doesn't move.

| State | Lens shows | Controls | Last / Next lanes |
|---|---|---|---|
| **Empty** (nothing today) | Clear glass slab: "Your day is open" and a sample: *"deep work 9:30 90m"* | **Add block** (primary), Ask Assistant | Next lanes show tomorrow's first two, labelled "Tomorrow" |
| **Ready** (≤ lead time before start) | "Starts in 4:12" (counts down to clock time). Hero shows the static "60:00": what will run. | Full-width **Start**; Skip, ⋯ | Normal |
| **Late** (start passed, not started) | Amber "Late 3m". Hero still "60:00" (full duration, per the brief), with "Full 60m · ends 3:03". | **Start**, Skip. In ⋯: *Shorten to fit* (runs only what's left of the planned window) | Next 1 shows a projected collision |
| **Running** | Countdown digits, draining tint | **Pause**, **Complete**, small **+5**, ⋯ (Cancel, Edit, Move) | Drift shown on Next 1 |
| **Paused** | Digits frozen at 50% opacity; "Paused · 2:13" counts up; static diagonal hatch over the fill (no pulsing) | **Resume** (morphs from Pause), Complete, ⋯ | Drift chip keeps growing |
| **Overtime** | "+3:41" counting up; slab tint goes warm with a static hatch | **Complete** (larger), **+5**, **+15** | Next 1 shows the collision ("You're 4m into Email") |
| **Gap** | "Free" slab: no tint, dotted glass outline. Hero counts down to the next task ("23:10 until Email triage · 3:30"). | **Start Email now** (early, full duration), **Fill gap** (capture prefilled with "23m") | Next 1 is the task the gap ends at. At ≤ lead time, the conveyor advances it into **Ready**. |
| **End of day** | Summary slab: "Done 7/9 · focused 5h12m · avg drift +4m" | **Review missed (2)**, **Plan tomorrow** | Next lanes show tomorrow's first two |

If a Late task's planned end passes without a start, it becomes **Missed**. It drops into the Last lane with a "Reschedule" affordance, and the lens advances.

### 2.3 Drift and collisions
- **Drift** = projected end of the focus task − its planned end, shown in the header chip.
- If the projected end passes Next 1's planned start, Next 1 says *"3:00 · you'll be 4m late"*.
- Tapping the chip or badge opens a 3-row glass menu (not a sheet):
  - **Push next 4m**
  - **Ripple the day**: shifts every *flexible* block after this one. *Fixed* blocks (meetings, pinned items) never move, and the ripple stops at the first gap that absorbs it.
  - **Ignore**
- New times preview in the lanes with a numeric roll before you commit, and undo is offered as a toast.

### 2.4 The conveyor moment
The conveyor is triggered by complete, cancel, skip, Gap→Ready, Late→Missed, and scrub preview. Timeline for **Complete**, with t = 0 at touch-up:

| t (ms) | What happens |
|---|---|
| 0 | `.success` haptic. Complete glyph → checkmark (`.contentTransition(.symbolEffect(.replace))`, 140 ms). |
| 60 | Lens interior fades out with blur 0→6 (120 ms ease-out). Hero digits collapse into "✓ 52m". |
| 100 | **The slab shrinks into the Last lane** (`matchedGeometryEffect` id `task.<id>`, conveyor spring). The old Last row rises 24 pt and fades (160 ms ease-in): it falls off the top. |
| 140 | **Next 1 grows into the lens.** Its tint sweeps in from the leading edge (240 ms ease-out); label, title, hero and controls stagger in 30 ms apart. |
| 170 | Next 2 slides up to Next 1. A new Next 2 rises from the Tail (+20 pt offset, fade in, 220 ms). |
| ≈440 | Settled. New controls are hit-testable from about 200 ms (once 60% opaque). |

- If the new focus is a Gap, the lens morphs into the Free slab instead.
- **Undo** (toast, 5 s) plays the conveyor in reverse at 0.85× duration.

---

## 3. Task lifecycle (user POV)

`Scheduled → Ready → (Late) → Running ⇄ Paused → (Overtime) → Completed | Cancelled`, plus `Ready/Late → Skipped` and `Late → Missed`.

| Action | Available in | Timer effect | Schedule effect |
|---|---|---|---|
| **Start** | Ready, Late, any future task ("Start now" in peek), Gap ("Start next now") | remaining = planned duration; `endsAt = now + duration` | None. Drift is computed. |
| **Pause** | Running, Overtime | Frozen. "ends at" slides forward live. | Drift grows |
| **Resume** | Paused | Continues from the frozen remaining time | — |
| **Complete** | Running, Paused, Overtime. Ready/Late via ⋯ "Mark done" | Stops. Records worked time = elapsed − paused. | Conveyor |
| **Cancel** | Running, Paused, Overtime | Stops. Partial time is recorded, and the task shows struck through in Last. | Conveyor + undo toast |
| **Skip** | Ready, Late, future tasks | None | Marked skipped. Optional "Move to…" (next gap / tomorrow / unscheduled). |
| **+5** (long-press for +1/+10/+15/+30; or drag the digits ±1 min) | Running, Paused, Overtime | Running/Paused: added to remaining. **Overtime: resets to 5:00 from now** (overtime is absorbed into actual time). | Drift updates |
| **Start next early** | Long-press Complete (Running), Gap, Next 1 peek | Current task completes. The next one runs its **full** duration from now. | Conveyor, then an immediate Start morph |
| **Shorten to fit** | Late | duration = planned end − now | — |

**One-timer rule.** Starting a task while another is running doesn't open a modal. The Start capsule splits for 3 s into **"Complete current & start"** and **"Pause current & start"**. A task paused this way waits in Next 1 as "Paused · Resume". The running task always owns the lens.

**Timer model for builders.** Derive the timer purely from timestamps (`startedAt`, `pausedIntervals`, `plannedDuration`, `extensions`). Nothing ticks in state, so it survives app kills, and the Live Activity, widgets and notifications share one `endsAt`.

**Notifications.** The pre-alert (default 5 min, set globally or per task) opens straight into **Ready**, and its **Start** action runs the same logic via an App Intent. At `endsAt`, "Time's up" offers **Complete** and **+5**.

---

## 4. Gesture vocabulary

Tiers: **P** = primary (always has a visible button, taught on first use) · **A** = accelerator (one-time hints) · **X** = expert (tips). Haptics per §6.

| Gesture | Where | Result | Tier |
|---|---|---|---|
| Tap | Lens buttons | Start / Pause / Resume / Complete / +5 | P |
| Tap | Hero digits | Toggle remaining ↔ ends-at clock | P |
| Tap | Next row | **Peek**: expands in place (about 160 pt) with notes, Start now, Skip | P |
| Tap | Last row | Details; **Reopen** within 10 min | P |
| Tap | Drift chip / collision badge | Push / Ripple / Ignore | P |
| Tap **+**, or **pull down** from header/Last/lens top | Home | Quick capture | P |
| Swipe **right** on lens (≥ 35% width or > 600 pt/s) | Running, Paused, Overtime | **Complete** (checkmark revealed behind the slab) | A |
| Swipe **left** on lens | Any task state | "Later" tray: +5, +15, next gap, tomorrow, Skip, Cancel (red, last) | A |
| Swipe right / left on a Next row | Next lanes | Start now / Skip or Move | A |
| Long-press | Any row or the lens | Context menu: Edit, Duplicate, Pin as fixed, Move to tomorrow, Delete | A |
| Long-press **Complete** (0.4 s radial fill) | Lens | **Complete & start next** | A |
| Long-press **+5** | Lens | +1 / +10 / +15 / +30 picker | A |
| Drag **up** from Next/Tail | Home | **Scrub preview**: each 56 pt shifts focus one block ahead; the lens reads "Preview · 3:30 PM" with only Start now enabled. Release → back to Now. | A |
| Pinch closed, or pull up on Tail | Home | Zoom out to **Day** (Plan tab) | A |
| Vertical drag on hero digits | Running, Paused | ±1 min per 12 pt | X |
| Long-press + drag a block | Day / Week | Reschedule with **5-min snap**. Slide the finger > 60 pt sideways for **1-min precision** (scrubbing-speed pattern) with a time bubble. Dwell 400 ms on a neighbor for **push mode** (neighbors shove instead of overlapping). | X |
| Drag a block's top / bottom edge | Day | Change start / duration | X |
| Long-press empty time + drag down | Day | **Draw a block**; opens capture prefilled | X |

**Conflict rules**
- The lens owns horizontal drags.
- Pull-down capture only starts above the lens controls, moving downward.
- Scrub only starts below the lens, moving upward.
- Looking *back* is a tap on Last, not a scrub, to keep it simple.

---

## 5. Quick capture

**Entry points:** pull-down on Home, the **+** button, a "Quick Add" App Intent (Control Center control, Action button, Siri), and the Assistant tab for anything multi-step.

### The surface
- A glass capsule field morphs in at the top from **+** or the pulled header, with the keyboard up immediately.
- Under it, a **landing strip** (a one-row mini timeline, ±3 h) shows where the block will land and its neighbors.
- Values parse inline as **tokens** while you type: `[Gym] [6:30 PM] [45m] [🔔 5m]`. The parser is deterministic and on-device (`NSDataDetector` plus a small grammar, debounced 80 ms, no network or LLM).
- Tapping a token opens a horizontal scrub wheel without dismissing the keyboard.

### Grammar (examples to support at launch)
| Input | Result |
|---|---|
| `gym 6:30 45m` | Gym, at the next future 6:30 (PM if 6:30 AM has passed), 45 min |
| `deep work 90m` | No time given, so it goes in the **first free gap ≥ 90 min** ("Next free: 4:10 PM") |
| `email now 20m` | Saves and **starts immediately** |
| `standup tmrw 9:15 15m !10` | Tomorrow, with a 10-min alert (`!N` = alert lead) |
| `read after lunch 30m` | Anchored after the block titled "lunch" |

Also support ranges (`18:00-18:20`), repeats (`every weekday`) and color tags (`#health`).

**Defaults:** duration is 30 min (a setting), or learned from the last block with the same title. The alert uses the global lead time.

### Slotting
- **Collisions:** the strip outlines an overlap in red and offers **Keep overlap** (default, since it's what you typed), **Push later blocks**, or **Next free slot**.
- **Return** saves and keeps the field open for the next line (brain-dump mode, with a "3 added" counter). Swipe down or tap outside to close.
- **Landing:** if the destination is visible on Home, the rail **opens a gap** and the title token flies in (`matchedGeometryEffect`) with a small overshoot. Landing in the current Gap **splits** the Free slab (Free 23m → Task 15m + Free 8m). Landing later sends the token into the Tail, whose counter rolls ("+5 later").

---

## 6. Motion choreography

### Motion tokens (define once, use everywhere)
```swift
enum Motion {
  static let tap      = Animation.snappy(duration: 0.18)
  static let morph    = Animation.spring(response: 0.30, dampingFraction: 0.80)
  static let expand   = Animation.spring(response: 0.32, dampingFraction: 0.78) // tiny overshoot
  static let conveyor = Animation.spring(response: 0.36, dampingFraction: 0.86)
  static let snapBack = Animation.spring(response: 0.30, dampingFraction: 0.90)
  static let drag     = Animation.interactiveSpring(response: 0.22, dampingFraction: 0.86)
  static let zoom     = Animation.spring(response: 0.40, dampingFraction: 0.88)
  static let fadeOut  = Animation.easeOut(duration: 0.16)
}
```

| Transition | Motion | Target duration | Details | Haptic |
|---|---|---|---|---|
| **Start** (Ready→Running) | `morph` | 280 ms | Start capsule **splits** into [Pause][Complete] + a +5 bubble: `glassEffectID` in a `GlassEffectContainer(spacing: 12)` on iOS 26, `matchedGeometryEffect` on `.ultraThinMaterial` capsules on iOS 17–25. Drain fill appears at 100%. | `.start` |
| **Pause / Resume** | `tap` | 180 ms | Glyph swaps via `.contentTransition(.symbolEffect(.replace.downUp))`; digits to 0.5/1.0 opacity; hatch fades (200 ms). | `.impact(flexibility: .soft, intensity: 0.6)` / `.impact(flexibility: .solid, intensity: 0.7)` |
| **Timer tick** | `.snappy(duration: 0.2)` | 200 ms/s | `.contentTransition(.numericText(countsDown: true))`: only changed digits roll. The fill steps per tick without animation (sub-point moves are invisible), so nothing renders continuously. | none |
| **+5** | `.snappy(duration: 0.22)` | 220 ms | Digits roll up (`countsDown: false`); a ghost "+5" floats up 14 pt and fades (240 ms); fill extends with `morph`. | `.increase` |
| **Overtime entry** | `.easeInOut(duration: 0.26)` | 260 ms | Tint crossfades; "0:00"→"+0:01" via numericText; one `keyframeAnimator` nudge (scale 1→1.015→1, 220 ms). | `.warning` |
| **Complete (conveyor)** | `conveyor` + staggers | ≈440 ms total, feels like 300 | See §2.4 | `.success` |
| **Cancel** | `.spring(response: 0.26, dampingFraction: 0.92)` | 220 ms + conveyor | Slab slides 40 pt leading, desaturates and fades; then the conveyor. Undo toast enters in 200 ms. | `.stop` |
| **Swipe-to-complete** | `drag` while tracking | — | 1:1 tracking, 0.55 rubber-band past the threshold, checkmark scales 0.6→1 at it. Released past it, the slab carries on 24 pt and compresses into Last (conveyor variant, no bounce-back); below it → `snapBack`. | threshold `.impact(weight: .medium)`, commit `.success` |
| **Peek a Next row** | `expand` | 300 ms | Row height animates, neighbors reflow, title is matched. | `.selection` |
| **Pull-to-capture** | `drag` → `morph` | 300 ms after release | Rubber-band follows the finger; detent at 72 pt. Released past it, the field expands with the keyboard; below it → `snapBack`. | detent `.impact(weight: .light)` |
| **Capture landing** | `conveyor`, drop `.spring(response: 0.30, dampingFraction: 0.70)` | 320 ms | Neighbors part, then the token lands. | `.impact(weight: .light)` |
| **Scrub step** | conveyor at 0.6× | ≈240 ms per step | Same view IDs as Complete; release reverses with `snapBack`. | `.selection` per step |
| **Now → Day** (pinch) | gesture-driven → `zoom` | 320 ms finish | `MagnifyGesture` progress 0…1, commit at 0.3. The lens compresses into a mini-timeline (220 ms), then the tab switches to Day already scrolled to now, with the current block glowing once. | `.impact(weight: .light)` on commit |
| **Day ↔ Week** | `zoom` | 340 ms | `matchedGeometryEffect` per visible block (≤ about 40). | `.impact(weight: .light)` |
| **Drag-reschedule** (Day/Week) | lift `.spring(response: 0.22, dampingFraction: 0.70)`; reflow `.snappy(duration: 0.22)`; drop `.spring(response: 0.24, dampingFraction: 0.80)` | 160 ms lift, 240 ms drop | Lifted block scales to 1.04 with a 12 pt shadow; neighbors reflow live. | lift `.impact(weight: .medium)`, snap `.selection` (≥ 40 ms apart), precision mode `.impact(flexibility: .rigid)`, drop `.impact(weight: .light)` |
| **Ripple apply** | `conveyor`, 18 ms stagger per block | ≤ 350 ms | Times roll with numericText. | `.levelChange` |
| **Mini-player appears** (other tabs) | `.smooth(duration: 0.25)` | 250 ms | iOS 26: `tabViewBottomAccessory`. iOS 17–25: a `safeAreaInset(edge: .bottom)` capsule. | none |

**Other gesture haptics:** tap digits / long-press +5 → `.selection`; lens swipe-left and Next-row swipes → `.impact(weight: .light)`; long-press Complete → `.start`; dragging the digits → `.increase` / `.decrease` per minute.

### Timer digits
- Font `.system(size: 76, weight: .semibold, design: .rounded).monospacedDigit()`. Format `M:SS`, or `H:MM:SS` at ≥ 1 h.
- In the app, drive the hero with `TimelineView(.periodic(from: startedAt, by: 1))` scoped to **the digits and fill only**, not the whole Home.
- On the Live Activity, widgets and mini-player, use `Text(timerInterval:countsDown:)` and `ProgressView(timerInterval:)`, which the system updates at no app cost.

### Matched-geometry plan
- One `@Namespace var rail` on Home, with IDs `task.<id>` (slab/row frames), `title.<id>` (titles glide instead of crossfading) and `hero.<id>` (digits ↔ "✓ 52m").
- Controls use `glassEffectID("primary" | "secondary" | "plus5")`.
- One source per ID at a time, ≤ 8 matched elements on Home, and no matched geometry across tabs (the pinch handoff fakes it).

### Rules
- **Every animation is interruptible and retargetable.** Input is never blocked for more than 120 ms.
- **No idle or looping animations** (no breathing, no shimmer). Paused and overtime use static treatments to save battery.
- **Reduce Motion:** 150 ms crossfades replace movement, digits use `.contentTransition(.identity)`, haptics stay.
- **Low Power Mode:** no per-tick digit animation and no interactive glass highlight. Updates stay at 1 Hz.
- **Haptic budget:** none on ticks, at most one per user action (snap ticks are throttled).

---

## 7. Other screens in the paradigm

**Tabs:** **Now · Plan · Assistant**, plus a floating **+**.
- The Now tab never scrolls. Browsing and heavy editing happen in Plan.
- On Plan and Assistant, the running task follows you as a **mini-player** (drain ring, title, countdown, Pause/Complete). Tapping it returns to Now.

### Day view (Plan, zoom level 1)
- **Layout:** linear vertical timeline, default 1 h = 72 pt, pinchable from 40 to 240 pt/h; pinching closed past 40 pt/h continues into Week. Ruler ticks go from 15 min to 5 min (≥ 160 pt/h) to 1 min (240 pt/h).
- **Now line** is pinned, with a small lens notch. **The current block is the same object as on Home**: drain fill, live digits, tappable controls.
- **Plan vs actual:** past blocks show the plan at 40% opacity, with a solid **actual bar** on the leading edge from actual start to end. Early starts, late starts and overruns read at a glance.
- **Gaps** are dashed **"Free 45m"** capsules. Tapping one opens capture prefilled with that slot.
- **Navigation:** a week-day strip on top (swipe to change day). When you scroll away, a **Now** pill appears: first tap scrolls back to now, a second tap returns to the Now tab.

### Week view (Plan, zoom level 2)
- 7 columns with 6:00–24:00 fitted vertically, no scrolling by default.
- **The lens returns, horizontally:** the focused day's column is magnified to about 44% width with titles. The other six are thin **density strips** (colored segments only). Tap or swipe horizontally to move focus (`.selection`).
- Long-press and drag moves a block across days. Tapping the focused column's header zooms into Day.

### How they relate
Now (zoom 0) ⇄ Day (zoom 1) ⇄ Week (zoom 2), by pinch or a Day/Week toggle in Plan. Blocks keep the same identity, colors and long-press/drag grammar at every level.

### Beyond the app: the same object everywhere
- **Dynamic Island:** compact = drain ring + countdown. Expanded = title + Pause / Complete / +5 (`LiveActivityIntent`).
- **Lock Screen Live Activity:** a mini lens (Last · Current · Next 1).
- **Widgets:** small = current task + countdown; medium = lens + next 2. Start/Complete via `Button(intent:)`.

---

## 8. What makes this a new paradigm (do not lose these)

- **Now has a fixed address.** Time flows through a stationary lens, so the user never scrolls to find the present.
- **The task *is* the timer.** The slab itself drains; it is not a card with a timer widget on it.
- **Duration-relative, with plan and reality both visible.** Start means the full duration begins. Drift is always shown, and one tap pushes or ripples the plan. Planned times never change silently.
- **The conveyor ritual.** Completing physically advances the day in about 400 ms with a success haptic. Fast and satisfying, never slow.
- **Gaps are first-class objects.** Free time sits in the lens with its own countdown, "start next now" and "fill gap".
- **One object everywhere.** Lens, mini-player, Dynamic Island, Lock Screen and widget share one visual (drain + digits) and the same three verbs: Pause, Complete, +5.
- **Semantic zoom with one metaphor.** Now → Day → Week by pinch, with a magnified focus repeated at every level.
- **Capture in one line, landing where you can see it.** Tokens parse while you type, and the block physically drops into the rail.
