# UI-2: Direction B "Aurora", Palettes and Live Surfaces

**Owner:** UI Designer #2 · **Date:** 2026-11-07 · **Status:** proposal for review
**Sources:** Apple HIG *Live Activities* (rev. Oct 2026), ActivityKit *Creating custom views for Live Activities*, WWDC25 *Icon Composer*. All contrast ratios were computed (WCAG 2.x).

---

## 1. Direction B: "Aurora / Luminous"

**Concept.** Time is light. The app looks like the sky at the hour you open it: soft colour fields drift behind the task you're doing *now*, glass controls float above them, and everything else stays calm and bright. Finishing things feels good, not clinical. **Mood:** airy · warm · alive · gentle precision.

- Light-first porcelain surfaces. Dark mode is an ink-violet night sky, not grey.
- **One** living element: a time-of-day aurora field behind the current-task card. It shows the time of day and the task state (§2.6).
- Soft radii (cards 28 pt, capsule controls) and layered glass (iOS 26 Liquid Glass; `.ultraThinMaterial` on iOS 17–25).
- A violet "now" accent that never collides with the green/amber/red status colours.

### B vs A: a frank comparison

| | A "Instrument / Chronograph" | B "Aurora / Luminous" |
|---|---|---|
| First impression | Precise, pro, serious | Friendly, fresh, emotionally warm |
| Timer legibility | Excellent: dark, high contrast, tabular | Good. Needs discipline so gradients never sit under small text |
| Battery (OLED) | Best: dark-first, mostly black pixels | Light-first costs more on OLED; ambient motion costs a little |
| Fit with system surfaces | Native: Dynamic Island and Always-On are black | Needs translation: aurora becomes accents on black |
| Distinctiveness | Risk of looking like every dark timer/dev tool | Ownable. Few planners feel like *time of day* |
| Risk | Cold or stressful over long sessions; sterile screenshots | Reads as a wellness app; gradients can muddy hierarchy |

### Recommendation: hybrid "Chronograph bones, Aurora light"

1. **From A:** grid, density, type hierarchy, tabular numerals, tick-mark ring, minute ruler, black-native system surfaces. A's dark mode is the *hero* appearance (marketing, icon, StandBy).
2. **From B:** the aurora field in exactly four places (current-task card, widget backgrounds, the Lock Screen Live Activity wash, the icon), the violet "now" accent, glass controls, warm copy and celebrations.
3. **Appearance:** follow the system setting. Light mode is a first-class peer (B's porcelain), not an inverted dark mode.
4. **Rule:** if a colour field doesn't show *time* or *state*, remove it. Lists, the calendar grid and AI chat stay neutral.
5. **Palette:** **Aurora** (§2.1). Solstice and Lagoon are alternates or future user themes.

---

## 2. Colour palettes

**Principles:**
- All palettes share the same semantic roles, so swapping a theme means swapping one token table.
- **Category colours are shared** (user data must not change hue with the theme).
- Status is **never colour-only**: always icon + label.
- Light-mode status colours are text-safe (≥ 4.5:1).

### 2.1 Aurora (recommended): cool porcelain / ink-violet night

| Token | Light | Dark |
|---|---|---|
| `bg` | `#F5F5FA` | `#0A0B11` |
| `surface` (cards) | `#FFFFFF` | `#15161F` |
| `surface2` (grouped, inputs, raised) | `#ECECF3` | `#1F202C` |
| `separator` | `#DEDEE8` | `#2A2B39` |
| `text1` | `#15141C` | `#F4F3FA` |
| `text2` | `#4F4D5E` | `#B5B3C7` |
| `text3` | `#67657A` | `#8E8CA3` |
| `now` (accent) | `#5B3DF5` | `#9483FF` |
| `onNow` | `#FFFFFF` | `#0A0B11` |
| `nowSoft` (tint fill) | `#ECE8FF` | `#231D4D` |
| `success` | `#177A45` | `#3DD68C` |
| `warning` (ending soon) | `#965700` | `#FFB547` |
| `warningRing` (graphics only) | `#C97700` | `#FFB547` |
| `danger` (overrun, destructive) | `#C92A37` | `#FF6166` |

### 2.2 Solstice: warm cream / ember night (most "optimistic")

| Token | Light | Dark |
|---|---|---|
| `bg` | `#FBF7F1` | `#120E0B` |
| `surface` | `#FFFFFF` | `#1E1915` |
| `surface2` | `#F3ECE2` | `#2A231D` |
| `separator` | `#E7DED2` | `#3A3028` |
| `text1` / `text2` / `text3` | `#1E1813` / `#5B5148` / `#75695D` | `#FBF4EC` / `#CBBDAD` / `#9C8F80` |
| `now` (fill) | `#F0592A` | `#FF7A4D` |
| `nowText` (links, labels) | `#B93D0B` | `#FF7A4D` |
| `onNow` | `#1E1813` (dark label on coral) | `#120E0B` |
| `nowSoft` | `#FFE6DB` | `#3A1D12` |
| `success` | `#277A3C` | `#5DD47F` |
| `warning` / `warningRing` | `#9C5C00` / `#C97700` | `#FFC04D` |
| `danger` | `#C2185B` (raspberry) | `#FF5C93` |

*Why raspberry:* for people with red-green colour blindness, a coral "now" next to a true red is hard to tell apart. Magenta-red carries blue, so it stays separable.

### 2.3 Lagoon: fresh mineral / deep-sea night

| Token | Light | Dark |
|---|---|---|
| `bg` | `#F1F7F7` | `#061214` |
| `surface` | `#FFFFFF` | `#0E1D20` |
| `surface2` | `#E4EEEE` | `#17292D` |
| `separator` | `#D2E1E1` | `#22383C` |
| `text1` / `text2` / `text3` | `#0E1A1C` / `#44585B` / `#5A6F73` | `#EDF7F7` / `#A8BFC2` / `#7C9599` |
| `now` | `#00707F` | `#3DD8E5` |
| `onNow` | `#FFFFFF` | `#061214` |
| `nowSoft` | `#D9F0F2` | `#0B3338` |
| `success` | `#3A7A18` (yellow-green, kept clear of teal) | `#A3E05F` |
| `warning` / `warningRing` | `#965900` / `#C97700` | `#FFBF4D` |
| `danger` | `#C42E45` | `#FF6B7E` |

### 2.4 Category palette (shared by all three)

| # | Name (default use) | Light | Dark |
|---|---|---|---|
| 1 | Indigo (Deep work) | `#4C5BD4` | `#8B96FF` |
| 2 | Sky (Meetings) | `#1A7FD1` | `#5CB8FF` |
| 3 | Teal (Learning) | `#0E8C80` | `#3FD4C2` |
| 4 | Green (Health) | `#2E8F47` | `#66D682` |
| 5 | Amber (Errands) | `#B87A00` | `#FFC53D` |
| 6 | Coral (Social) | `#E0560F` | `#FF8A4C` |
| 7 | Rose (Personal) | `#D2336D` | `#FF78A9` |
| 8 | Plum (Creative) | `#9437B0` | `#D48BFF` |

Categories appear as dots, bars, rings and tinted fills (14% light / 22% dark behind `text1`), never as text colour. Dark variants double as Dynamic Island colours (≥ 7.9:1 on black).

### 2.5 Contrast notes (computed)

- **Aurora light:** `text1` 16.8, `text2` 7.6, `text3` 5.2, `now` 5.6, `onNow/now` 6.1, `success` 5.0, `warning` 5.3, `danger` 5.0 (on `bg`). **Aurora dark:** `text1` 17.8, `text2` 9.6, `text3` 6.0, `now` 6.5, statuses 6.7–11.2. All pass AA.
- **Solstice:** coral `#F0592A` is only **3.2:1** on cream, so it is a fill with a dark label (5.2:1). Text uses `nowText` (5.3:1).
- **Lagoon light:** `text3` and `success` dip to ~4.5 on `surface2`; keep them off it for small text.
- **Categories (light):** 3.3–6.1:1 on `bg`, which passes WCAG 1.4.11 for non-text UI.
- **On aurora gradients:** `text1` ≥ 11.3, `text2` ≥ 5.6. `now` drops to 4.1–4.5, so use it there only for large numerals or rings.
- **Lock Screen LA, worst wallpaper:** `text1` ≥ 10, `text2` ≥ 5.4. Status colours drop to 3.6–4.4, so use them only on ≥ 24 pt numerals and graphics.

### 2.6 Time-of-day ambient gradients

Four stops each, mapped onto a 3×3 `MeshGradient` (stop 0 top-leading, 1 top-trailing, 2 centre/bottom-trailing, 3 bottom-leading).

| Phase (default window) | Light stops | Dark stops |
|---|---|---|
| **Dawn** 05:00–09:00 | `#FFE4D4` `#FFD3DE` `#E6DDFF` `#FFF5E3` | `#2B1B3E` `#46223A` `#3B2A20` `#12131D` |
| **Day** 09:00–16:30 | `#DCEBFF` `#E2F6F2` `#FFF5D9` `#F0EDFF` | `#0F2A45` `#0D3638` `#1E2050` `#0B0C12` |
| **Dusk** 16:30–20:30 | `#FFDAC4` `#F8CBE1` `#DCCFFF` `#FFE9CF` | `#3A1D47` `#552338` `#47290F` `#140F1C` |
| **Night** 20:30–05:00 | `#DDE1FF` `#E7DCFF` `#D3E4F4` `#F1EFFA` | `#0B1131` `#1B1347` `#06292E` `#08090F` |

**Rendering rules (cheap by construction):**
- **Where:** only behind the current-task card, clipped to it.
- **Mesh:** iOS 18+ uses a 3×3 `MeshGradient`. Corners are fixed; the centre and edge midpoints drift on sine curves (amplitude ≤ 0.06, period ~20 s). iOS 17 uses two static `RadialGradient`s over a `LinearGradient`.
- **Frame rate:** `TimelineView(.animation(minimumInterval: 1/15, paused: !ambientActive))`. Phase colours are recomputed once a minute, with a 30-min blend at each phase boundary.
- **Paused when:** the card is off-screen, the app is not active, Reduce Motion or Low Power Mode is on, `thermalState ≥ .serious`, or the task is paused. The fallback is the same mesh, frozen. Never animate `blur`.
- **State modulation:** in the last 5 min, `warning` blends into stop 2 at 35%. Paused sets saturation to 0.35 and freezes the field. Overrun blends `danger` into stop 2 at 25%. With no current task, the field drops to 50% opacity.
- **iOS 26:** the play/pause/complete controls are `.glassEffect(.regular.interactive())` in one `GlassEffectContainer`, so the aurora refracts through them. Never stack glass on glass.

---

## 3. Live Activity: Lock Screen

**One activity per run of back-to-back tasks**, following the HIG's single-activity guidance. It starts when a task starts. On Complete, it rolls into *Up next* if the next task begins within 30 min; otherwise it ends with `dismissalPolicy: .after(.now + 5 min)`. It always ends within 8 h.

```
┌─────────────────────────────────────────────────┐ 371×144 pt (393-pt phones) / 408×144 (430-pt)
│ ▍● Write launch brief                until 2:58 │ 17 semibold text1 · 13 medium text2
│                                                 │
│   47:12                           (⏸)    (✓)    │ 44 pt rounded semibold, tabular · 44 pt buttons
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━░░░░▒▒▒    │ 6 pt capsule; last 5-min zone marked amber
│ Next 3:00 · Design review                       │ 13 medium text2
└─────────────────────────────────────────────────┘ 14 pt standard margins
```

- **Countdown:** `Text(timerInterval: start...end, pauseTime: pausedAt, countsDown: true)` with `.monospacedDigit()`, so the activity needs no per-second updates.
- **Progress:** `ProgressView(timerInterval:countsDown: false)` in the category colour. A `warningRing` overlay at 70% marks the last 5 min, drawn above the bar, so the fill "enters amber" with no update (verify on device).
- **Background:** `activityBackgroundTint` `#FFFFFF @ 0.92` / `#0A0B11 @ 0.86`, plus a static time-of-day wash (dark stops at 30%, leading 40%). When `isLuminanceReduced`, drop the wash.
- **Buttons:** `LiveActivityIntent`s that run without opening the app. `TogglePauseIntent` is an outlined circle; `CompleteTaskIntent` is a filled `now` circle with a checkmark. They sit ≥ 16 pt apart and differ in shape and colour, which balances the HIG's preference for one control against the brief. **Cancel stays in-app** (destructive, with Undo).
- **Privacy:** the "Hide titles on Lock Screen" setting shows the category name instead.

| State | Changes from running |
|---|---|
| **Up next** (≤ 5 min before) | Eyebrow "UP NEXT", countdown to start (`now` colour), single **Start** button; height 120 pt |
| **Running** | As drawn |
| **Paused** | "Paused" chip, digits frozen in `text2`, bar static (`ProgressView(value:)`), ⏸ becomes ▶ |
| **Overrun** | `staleDate = plannedEnd`, so the system re-renders with `context.isStale` and needs no app wake. Shows "+" `Text(plannedEnd, style: .timer)` (counts up) in `danger`, label "Over time", buttons **+10 min** · **Complete** |
| **Done** (dismissing) | ✓ "Done · 58 min", next task line, no buttons |

**Updates:** the app or intents push an update on every user action. If the backend that proxies OpenAI is available, it also sends ActivityKit pushes: priority 5 at T-5 (amber digits) and priority 10 **with alert** at T-0. In that case, skip the local notification for the same moment. **Watch and CarPlay:** `.supplementalActivityFamilies([.small])` shows ring + countdown + title, with no buttons (CarPlay disables them).

---

## 4. Dynamic Island

The background is always black. `keylineTint(categoryDark)`. Everything links to Home with the current task expanded.

| Region | Running | Paused | Overrun | Up next |
|---|---|---|---|---|
| **Compact leading** (≤ 52×36.67 pt) | 18 pt `ProgressView(timerInterval:)` circular ring, 2.5 pt stroke, category colour | Static ring at 60%, 8 pt `pause.fill` inside | Full ring in `danger` | `clock` glyph in `now` |
| **Compact trailing** | `Text(timerInterval:)` 15 pt rounded semibold tabular, category colour, `.frame(maxWidth: 46)` to stop width jitter | Static "12:04" at 60% white | "+" `Text(end, style: .timer)` in `danger` | Countdown to start in `now` |
| **Limited width** (28 pt circle) | Leading ring only; trailing left empty so the system hides it | Same | Same | Same |
| **Minimal** (36.67–45 pt) | 20 pt ring + 6 pt category dot centre (live progress, per HIG) | Ring + `pause.fill` | `danger` ring + `exclamationmark` | `now` ring empty |
| **Expanded leading** | 40 pt ring (4 pt stroke) with category SF Symbol 16 pt | Dimmed | `danger` | Hollow `now` ring |
| **Expanded trailing** | Countdown 30 pt semibold white + "ends 2:58" 12 pt @ 60% | Frozen digits @ 60% | "+4:12" `danger` + "over" | "in 4:12" |
| **Expanded center** | Title 16 pt semibold (1 line) + "Deep work · 60 min" 12 pt category colour | + "Paused" | + "Over time" | "Up next · 3:00" |
| **Expanded bottom** | "Next 3:00 · Design review" 13 pt @ 60% · Spacer · ⏸ 36 pt (white 16% fill) · ✓ 36 pt (`now` fill, ink glyph) | ▶ · ✓ | **+10** · ✓ | **Start** capsule |

Expanded height is ≤ 150 pt, with content snug to the TrueDepth camera. Transitions use only `.numericText(countsDown: true)` and opacity.

---

## 5. Widgets

| Family | Content | Interaction |
|---|---|---|
| **systemSmall** | 4 pt category bar · "NOW" eyebrow · title (2 lines, 15 semibold) · countdown 28 pt · linear timer progress. Idle: "Next · 3:00", title, countdown to start | One `Button(intent:)`: **Start** (idle) or **Complete** (running) |
| **systemMedium** | Left 55%: as small. Right 45%: **Last** (✓, title, "1:00–1:55") and **Next ×2** (time, dot, title), mirroring Home | Pause/Resume + Complete |
| **accessoryCircular** | Timer-driven ring + category SF Symbol. Idle: next start "3:00" | None (opens Home) |
| **accessoryRectangular** | L1 `●` `47:12` bold + "left" · L2 title · L3 "Next 3:00 Design review" | None |
| **accessoryInline** | "Write brief · until 2:58" (static end time, never ticks) / "Next 3:00 · Design review" | None |

- **Background:** `containerBackground(for: .widget)` uses the *static* gradient for the entry's day phase.
- **Accented, clear and tinted modes** (`widgetRenderingMode != .fullColor`): drop the gradient and apply `widgetAccentable()` to the ring and countdown.
- **Refresh strategy:** one timeline per day. Entries go at each task's notice time, start and end, plus the 4 phase boundaries (≈ 40 entries for 12 tasks). Policy is `.after(lastEntry)`. The timer views tick by themselves, so there are **no per-minute entries**. Call `reloadTimelines(ofKind:)` only on edits, AI changes, and start/pause/complete. Set `TimelineEntryRelevance` high from T-5 to the task's end, for the Smart Stack.

---

## 6. Notifications

**Style:** the title is the task title as the user wrote it, the subtitle is time and duration, and the body is one short sentence. **No app-inserted emoji** (VoiceOver reads them aloud), though a user's own emoji is kept. No guilt language; state facts neutrally ("Over by 10 min"). Action buttons get SF Symbol icons.

| Moment | Title | Subtitle | Body | Actions | Level |
|---|---|---|---|---|---|
| T-5 (custom lead) | Write launch brief | 2:00–3:00 PM · 60 min | Starts in 5 min. | Start now · Snooze 5 min · Skip | `.timeSensitive` |
| Start time, not started | Write launch brief | Scheduled 2:00 PM | Ready when you are. Starting runs a 60-min timer. | Start · Skip | `.active` |
| Time's up (only if no LA push alert) | Time's up | Write launch brief | Next: Design review at 3:00. | Complete · +10 min | `.timeSensitive` |
| Overrun +10 | Still on Write launch brief? | Over by 10 min | Design review started at 3:00. | Complete · +10 min | `.active` |
| AI changed the plan | Assistant updated today | 2 changes | Moved Gym to 6:30 PM and added Call Sam at 5:00. | Review | `.passive` |

**Grouping:** task notifications use `threadIdentifier = "plan-yyyy-MM-dd"` (one stack per day); the assistant uses `"assistant"`. Remove a task's pending and delivered notifications as soon as it starts, completes or is edited. Relevance score: 1.0 for T-5, 0.6 for overrun, 0.2 for AI.

---

## 7. Micro-interactions and celebrations

**Motion tokens:** `tap` 0.12 s scale 0.96 · `quick` `.snappy(duration: 0.18)` · `base` `.snappy(duration: 0.25)` · `move` `.spring(response: 0.32, dampingFraction: 0.86)` · `celebrate` ≤ 0.55 s total. Nothing user-triggered runs longer than 600 ms.

| Moment | Motion (cheap primitives only) | Total | Haptic (`.sensoryFeedback`) | Reduce Motion |
|---|---|---|---|---|
| **Start task** | ▶ → ⏸ `symbolEffect(.replace)`; digits roll in via `.numericText(countsDown:)`; ring draws 0 → full with `move`; aurora fades from 60% to 100% | 350 ms | `.start` | Crossfade 200 ms |
| **Pause / resume** | Symbol replace; digits fade to `text2`; aurora desaturates and freezes | 250 ms | `.selection` | Same, no saturation tween |
| **Last minute (T-60 s)** | Ring and digits crossfade to `warning`; one "breath" (ring scale 1 → 1.04 → 1); no repeating pulse | 300 ms | `.warning` ×1 | Colour change only |
| **Overrun (T-0)** | Digits flip to "+0:00" counting up in `danger`; ring starts a thin second lap; chips "+5 / +10 / Complete" slide up 12 pt | 400 ms | `.error` ×1 (gentle) | Fade chips in |
| **Complete** | ✓ `symbolEffect(.bounce)`; ring fills to 100%; one-shot radial bloom in the category colour (scale 0.6 → 1.4, opacity 0.5 → 0); card slides out, next task slides into "Now" via `matchedGeometryEffect`; day-progress counter ticks | 550 ms | `.success` | No scale/bloom; 200 ms crossfade |
| **Cancel** | Card scales to 0.98 + fades; Undo toast for 4 s (no confirmation alert) | 220 ms | `.impact(weight: .light)` | Fade |

**Cost rules:** animate only opacity, scale, offset, symbol effects and numeric text. No particle emitters, and no animated blur or shadow radius. The bloom is one `RadialGradient` layer.

---

## 8. App icon: "Daybreak Ring"

**Glyph:** a thick open ring (a countdown arc, or a sun clearing the horizon) with a bright "now" dot. No clock hands, which are a cliché and collide with the Clock app. The ring repeats in the Dynamic Island, Live Activity, widgets and Home, so the brand reads everywhere.

- **Canvas:** 1024×1024 Icon Composer `.icon`; the system masks the shape.
- **Background group:** ink `#0C0D18` with a radial horizon glow `#3A1F6B` rising from the bottom centre (radius 70%).
- **Ring group:** outer Ø 620, stroke 128, round caps. The ring starts at 12 o'clock and sweeps 306° clockwise, leaving a 54° gap at 10–12 o'clock ("time remaining"). Angular gradient: `#8B6CFF` → `#E45BCF` → `#FF7A55` → `#FFC44D`. Liquid Glass and specular on.
- **Dot group:** `#FFFFFF`, Ø 104, at the trailing cap. Glass on, high specular.
- **Variants:**
  - *Default:* as above.
  - *Dark:* background `#000000`→`#0B0C14`, glow at 40%, dot `#FFF4E0`.
  - *Clear* (iOS 26): from the mono layer, a frosted ring and a white dot.
  - *Tinted* (iOS 18 + 26): a grayscale ring ramp `#8C8C8C`→`#FFFFFF` that keeps the direction of progress, white dot, no background.
  - *iOS 17/18:* asset-catalog PNGs for Any/Dark/Tinted. Check iOS 18 tinted separately.
- **Small sizes:** at 29 and 40 pt the gap and dot must still read. If not, widen the gap to 60° and the dot to Ø 120.

---

## 9. Swift token sketch (Aurora + time-of-day stops)

```swift
import SwiftUI

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
extension Color { // trait-resolved light/dark pair (app, widgets, Live Activities)
    init(_ light: UInt32, _ dark: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

enum Aurora {
    static let bg          = Color(0xF5F5FA, 0x0A0B11)
    static let surface     = Color(0xFFFFFF, 0x15161F)
    static let surface2    = Color(0xECECF3, 0x1F202C)
    static let separator   = Color(0xDEDEE8, 0x2A2B39)
    static let text1       = Color(0x15141C, 0xF4F3FA)
    static let text2       = Color(0x4F4D5E, 0xB5B3C7)
    static let text3       = Color(0x67657A, 0x8E8CA3)
    static let now         = Color(0x5B3DF5, 0x9483FF)
    static let onNow       = Color(0xFFFFFF, 0x0A0B11)
    static let nowSoft     = Color(0xECE8FF, 0x231D4D)
    static let success     = Color(0x177A45, 0x3DD68C)
    static let warning     = Color(0x965700, 0xFFB547)
    static let warningRing = Color(0xC97700, 0xFFB547)
    static let danger      = Color(0xC92A37, 0xFF6166)
    static let categories: [Color] = [
        Color(0x4C5BD4, 0x8B96FF), Color(0x1A7FD1, 0x5CB8FF), Color(0x0E8C80, 0x3FD4C2), Color(0x2E8F47, 0x66D682),
        Color(0xB87A00, 0xFFC53D), Color(0xE0560F, 0xFF8A4C), Color(0xD2336D, 0xFF78A9), Color(0x9437B0, 0xD48BFF)]
}

enum DayPhase: CaseIterable {
    case dawn, day, dusk, night
    static func at(_ date: Date, calendar: Calendar = .current) -> DayPhase {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        switch (c.hour ?? 0) * 60 + (c.minute ?? 0) {
        case 300..<540:  return .dawn    // 05:00–09:00
        case 540..<990:  return .day     // 09:00–16:30
        case 990..<1230: return .dusk    // 16:30–20:30
        default:         return .night
        }
    }
    func stops(dark: Bool) -> [Color] { // TL, TR, centre/BR, BL
        let hex: [UInt32] = switch (self, dark) {
        case (.dawn, false):  [0xFFE4D4, 0xFFD3DE, 0xE6DDFF, 0xFFF5E3]
        case (.day, false):   [0xDCEBFF, 0xE2F6F2, 0xFFF5D9, 0xF0EDFF]
        case (.dusk, false):  [0xFFDAC4, 0xF8CBE1, 0xDCCFFF, 0xFFE9CF]
        case (.night, false): [0xDDE1FF, 0xE7DCFF, 0xD3E4F4, 0xF1EFFA]
        case (.dawn, true):   [0x2B1B3E, 0x46223A, 0x3B2A20, 0x12131D]
        case (.day, true):    [0x0F2A45, 0x0D3638, 0x1E2050, 0x0B0C12]
        case (.dusk, true):   [0x3A1D47, 0x552338, 0x47290F, 0x140F1C]
        case (.night, true):  [0x0B1131, 0x1B1347, 0x06292E, 0x08090F]
        }
        return hex.map { Color(uiColor: UIColor(hex: $0)) }
    }
}
```

---

## Hand-offs and items to verify

- **Engineering, please confirm:** that a `LiveActivityIntent` can roll the activity while the app is in the background; how the amber overlay renders; the push budget; and the mesh's energy cost at 15 fps (measure in Instruments).
- **Designer A:** align on shared structure (ring geometry, type scale, ruler). I propose A's type system, with SF Pro Rounded only for the hero timer.
- **PM:** confirm the overrun "+10 min" extend action, and the pre-start "Up next" activity (which needs push-to-start or the app in the foreground).
