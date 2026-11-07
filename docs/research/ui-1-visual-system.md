# UI-1 — Visual Direction A: "Chronograph"

> Proposal by UI Designer #1. A complete, SwiftUI-ready visual system for the minute-by-minute time-blocking app. Direction A is **dark-first, exact, luminous**: a black watch dial, white indices, and **one lume-coloured hand that always means "now"**. Everything here is specified so it can be implemented in SwiftUI (iOS 17+), with iOS 26 Liquid Glass where it is available.

---

## 1. Concept & mood

**The phone is a chronograph.** The Home screen is a dial. Time that has passed is quiet graphite, time still to come is crisp white type, and the single luminous accent (the lume) marks the present moment: the timer ring, the now-line on the Day timeline, the Dynamic Island, and the Start button. Nothing else gets that colour. Because the accent is rare, the eye always finds "now" in under a second.

The ring changes colour temperature as time runs out. While there is time it is **cool** (lume cyan). When the task is ending soon it turns **warm** (amber), and when it overruns it shows an amber **overrun lap**. Users can read the state of the clock at a glance without reading the digits.

- **Three adjectives:** *Precise · Luminous · Taut*
- **References:** dive and chronograph dials (BGW9 lume, minute-track bezels), glass-cockpit avionics (the cyan "selected/active" value), Apple Watch Ultra complications, Teenage Engineering-style labelling.
- **It should never look like:**
  - a skeuomorphic watch: no brushed steel, bevels, gold, Roman numerals or fake screws;
  - neon cyberpunk: no glows on everything and no gradients across the UI (the glow is reserved for the lume dot);
  - a pastel or beige planner, or a gamified one: no confetti, mascots or streak flames;
  - a stock-blue Reminders clone;
  - a dashboard of colours: the accent appears in at most 1–3 places per screen.

Direction A owns **dark, exact and quiet with one vivid signal**. If Direction B goes light, soft or warm, the two will separate clearly.

---

## 2. Colour palettes

All three palettes share the same token names, so switching between them only changes values. Dark is the design source of truth; light is a "silver dial" rendition with the same hierarchy. Contrast ratios below are WCAG 2.x values I calculated for these exact hex pairs.

**Semantic rules (all palettes)**
- `accent` means **now / live** only: the timer ring while running, the now-line, the live dot, the Start button and Live Activity tint. Tab selection, links and the AI send button stay monochrome (`textPrimary`).
- `success` means **complete**, `warning` means **ending soon and overrun**, and `danger` means **cancel / destructive** only. Overrun is deliberately *not* red: it is a state, not an error.
- State is never signalled by colour alone. Every state also has a glyph or a sign: `checkmark`, `!`, `+02:14`.

### 2.1 Palette A1 — **"Lume"** (recommended)
Graphite dial with BGW9-style ice-cyan lume. In light mode the accent becomes a deep petrol-teal, like a petrol-blue dial.

| Token | Light | Dark |
|---|---|---|
| background | `#F3F4F6` | `#060708` |
| surface1 (cards) | `#FFFFFF` | `#111316` |
| surface2 (controls, chips) | `#E8EAEE` | `#1A1D21` |
| separator (hairline) | `#D3D7DD` | `#2A2E35` |
| ringTrack | `#E1E4E8` | `#1E2227` |
| textPrimary | `#0B0D10` | `#F4F6F8` |
| textSecondary | `#4A515B` | `#A3AAB4` |
| textTertiary | `#686F7A` | `#7C838E` |
| **accent ("now")** | **`#00748C`** | **`#3DE3F5`** |
| accentOn | `#FFFFFF` | `#00242B` |
| success | `#127A3A` | `#3DDC84` |
| successOn | `#FFFFFF` | `#002611` |
| warning | `#A35C00` | `#FFB020` |
| warningOn | `#FFFFFF` | `#2B1A00` |
| danger | `#CC1D35` | `#FF4D5E` |
| dangerOn | `#FFFFFF` | `#2A0006` |

**Increase Contrast variants** (asset-catalog "High Contrast" slots):

| Token | Light | Dark |
|---|---|---|
| textSecondary | `#353B44` | `#C3C9D1` |
| textTertiary | `#4A515B` | `#A3AAB4` |
| accent | `#005A6D` | `#7DF0FF` |
| separator | `#A9AFB8` | `#3E444D` |

**WCAG contrast — Lume**

| Pair | Dark | Light |
|---|---|---|
| textPrimary / background | 18.6 | 17.7 |
| textPrimary / surface1 | 17.2 | 19.5 |
| textSecondary / surface1 | 7.9 | 8.0 |
| textSecondary / surface2 | 7.2 | 6.7 |
| textTertiary / background | 5.3 | 4.6 |
| textTertiary / surface1 | 4.9 | 5.1 |
| accent / background | 13.0 | 4.9 |
| accent / surface1 | 12.0 | 5.4 |
| accentOn / accent | 10.5 | 5.4 |
| accent / ringTrack (graphic, needs ≥ 3) | 10.3 | 4.3 |
| success / surface1 | 10.4 | 5.0 |
| successOn / success | 9.2 | 5.4 |
| warning / surface1 | 10.2 | 5.1 |
| danger / surface1 | 5.7 | 5.5 |
| accent on black (Dynamic Island) | 13.5 | — |

Every text pair meets AA (4.5) except textTertiary on dark surface2 (4.4). Tertiary text is therefore never placed on surface2.

### 2.2 Palette A2 — **"Tachymeter"**
A warm carbon dial with a **signal-orange** seconds hand, the classic chronograph hand. It is more energetic and urgent. To stay distinct from the orange accent, warning moves to yellow and danger moves to raspberry.

| Token | Light | Dark |
|---|---|---|
| background | `#F5F2EE` | `#0B0A09` |
| surface1 | `#FFFFFF` | `#161412` |
| surface2 | `#EBE6E0` | `#201D1A` |
| separator | `#D8D1C9` | `#302B27` |
| ringTrack | `#E6E0D9` | `#241F1B` |
| textPrimary | `#14110E` | `#F7F3EE` |
| textSecondary | `#57504A` | `#B1A99F` |
| textTertiary | `#726A62` | `#857D74` |
| **accent** | **`#BA3C04`** | **`#FF6A2B`** |
| accentOn | `#FFFFFF` | `#1F0A00` |
| success / successOn | `#1C7D45` / `#FFFFFF` | `#4BD68A` / `#00230F` |
| warning / warningOn | `#8A6400` / `#FFFFFF` | `#FFD23F` / `#2A2000` |
| danger / dangerOn | `#C4164C` / `#FFFFFF` | `#FF4577` / `#2A0010` |

Contrast, dark: textPrimary/bg 17.9, textSecondary/bg 8.5, textTertiary/surface1 4.5, accent/bg 6.9, accentOn/accent 6.7, danger/surface1 5.6. Contrast, light: textPrimary/bg 16.9, textSecondary/bg 7.1, textTertiary/bg 4.8, accent/bg 5.0, white/accent 5.6, success/bg 4.6, warning/bg 4.8. *Caveat:* the "cool → hot" ring logic is weaker here, because the accent is already warm.

### 2.3 Palette A3 — **"Abyss"**
A diver's midnight-navy dial with an **ultraviolet** hand. It is the most "tech" of the three and ties in naturally with the AI tab.

| Token | Light | Dark |
|---|---|---|
| background | `#F3F4F9` | `#05070E` |
| surface1 | `#FFFFFF` | `#0E1220` |
| surface2 | `#E7E9F2` | `#171C2E` |
| separator | `#D2D6E3` | `#262C42` |
| ringTrack | `#E0E3EE` | `#1A2033` |
| textPrimary | `#0A0D1A` | `#EEF1FA` |
| textSecondary | `#4A5068` | `#9CA4BD` |
| textTertiary | `#686E89` | `#737B99` |
| **accent** | **`#5A3FE0`** | **`#9D8DFF`** |
| accentOn | `#FFFFFF` | `#120A3A` |
| success / successOn | `#0F7A4B` / `#FFFFFF` | `#3FDDA0` / `#002618` |
| warning / warningOn | `#9E5A00` / `#FFFFFF` | `#FFB547` / `#2A1800` |
| danger / dangerOn | `#C81E44` / `#FFFFFF` | `#FF5A78` / `#2A0010` |

Contrast, dark: textPrimary/bg 17.8, textSecondary/bg 8.1, textTertiary/bg 4.8 (4.46 on surface1), accent/bg 7.4, accentOn/accent 6.8, danger/bg 6.7. Contrast, light: textPrimary/bg 17.6, textTertiary/bg 4.6, accent/bg 5.9, white/accent 6.5, success/bg 4.9.

### 2.4 Category palette (8 task colours, shared by all three palettes)
Category colours are **index marks**, never large fills. They appear as a 3 pt leading bar, an 8 pt dot, or a 14 % tint behind `textPrimary` on Day-view blocks. They never carry text on their own, so the requirement is the WCAG non-text threshold of ≥ 3:1. The text on a tinted block stays `textPrimary`; for example, text on a 14 % azure tint measures 13.4:1 in dark mode.

| # | Name | Dark | Light | vs dark surface1 | vs light bg |
|---|---|---|---|---|---|
| 1 | Rose | `#FF6F91` | `#C92D57` | 7.0 | 4.8 |
| 2 | Brass | `#E6CC4A` | `#866F00` | 11.6 | 4.5 |
| 3 | Moss | `#9BD65A` | `#4A8516` | 10.8 | 4.1 |
| 4 | Jade | `#3FD49B` | `#06855A` | 9.8 | 4.2 |
| 5 | Azure | `#5FA8FF` | `#1D62D6` | 7.6 | 5.1 |
| 6 | Plum | `#C68BFF` | `#7F3ECC` | 7.6 | 5.5 |
| 7 | Orchid | `#F27AD0` | `#AC2E8C` | 7.5 | 5.4 |
| 8 | Slate | `#A3ACB9` | `#5B6472` | 8.1 | 5.4 |

There is a deliberate gap in hue around each accent. In **Abyss**, Plum sits too close to the UV accent, so swap it for **Clay** (`#D9A27A` dark, 8.4; `#9A5B2E` light, 4.9). Lume cyan sits about 30° away from both Jade and Azure, and its chroma differs, so no swap is needed.

### 2.5 Recommendation
**Ship "Lume" (A1).** Cyan is the hue furthest from the green, amber and red semantic colours, so complete, ending soon and cancel stay unambiguous. It reads as "light emitted from a dark dial", which is the brand idea itself. It gives the highest accent contrast on black (13:1), which matters most in the Dynamic Island and Always-On, and it carries the "cool → hot" timer story. Tachymeter and Abyss can ship later as user-selectable "dials" (themes) at no extra engineering cost.

---

## 3. Typography

| Family | Use |
|---|---|
| **SF Pro, `.condensed` width** | Timer digits. The tall, narrow, instrument-like figures fit a ring. |
| **SF Pro (default width)** | All UI text: titles, body, rows. |
| **SF Pro, `.expanded` width, uppercase, tracked** | "Bezel" eyebrows: NOW, NEXT, ENDS 14:58, PAUSED. This is the signature detail. |
| **SF Mono** | Day-timeline hour ticks and AI-template tokens only: tiny technical labels. |
| *Not used* | SF Pro Rounded (too soft for the instrument) and New York (the serif warmth belongs to another direction). |

Every numeral that changes uses `.monospacedDigit()`, so digits never jitter.

| Token | Spec | Dynamic Type |
|---|---|---|
| `timerXL` | 68 pt, Light, condensed, mono digits, tracking −1 (MM:SS) | `@ScaledMetric(relativeTo: .largeTitle)`, capped at `.accessibility1` |
| `timerXLHours` | 54 pt, same style (H:MM:SS) | same |
| `timerM` (Live Activity, accessory) | 34 pt, Regular, condensed, mono digits | `.title` |
| `timerS` (Dynamic Island compact, rows) | 15 pt, Semibold, mono digits | fixed in the Island, `.subheadline` in rows |
| `cardTitle` | 28 pt, Semibold, tracking −0.4, max 2 lines | `.title` |
| `screenTitle` | 34 pt, Bold | `.largeTitle` |
| `rowTitle` | 17 pt, Semibold, 1 line | `.headline` |
| `body` | 17 pt, Regular | `.body` |
| `timeLabel` | 15 pt, Medium, mono digits ("15:00", "14:00–15:00") | `.subheadline` |
| `meta` | 13 pt, Regular, textSecondary | `.footnote` |
| `eyebrow` | 11 pt, Semibold, expanded, uppercase, tracking +1.0 | `.caption2` |
| `caption` | 12 pt, Regular | `.caption` |
| `tick` | SF Mono 11 pt, Medium, textTertiary | `.caption2` |

**Dynamic Type behaviour.** Build fonts relative to text styles, for example `.system(.title, weight: .semibold)`, or with `@ScaledMetric` for the timer. At accessibility sizes (`dynamicTypeSize.isAccessibilitySize`), the hero card switches to **digits-only mode**: the ring is hidden, digits span the full width with `.minimumScaleFactor(0.6)`, and the controls stack vertically as full-width 56 pt buttons. With *Bold Text* turned on, the timer moves from Light to Medium automatically, because it uses system weights.

---

## 4. Layout & shape

**Spacing scale (4 pt grid):** `2 · 4 · 8 · 12 · 16 · 20 · 24 · 32 · 40 · 56`. Screen margin is **20**, card padding is **20**, the gap between rows is **8**, and the gap between sections is **16**.

**Radii** (always `style: .continuous`): `xs 6` (index bars, ticks), `s 10` (Day-view blocks, tags), `m 16` (inputs), `row 20` (compact rows), `l 24` (AI change cards, sheet content), `hero 32` (current-task card), `pill` = `Capsule`. On iOS 26, the hero card can use `ConcentricRectangle`, so its corners stay concentric with the display; the fallback is `RoundedRectangle(cornerRadius: 32, style: .continuous)`.

**Elevation.** Dark mode has **no drop shadows**: depth comes from surface steps (bg → surface1 → surface2) plus a 1 pt inner hairline (`strokeBorder`, white at 6 %). The hero card adds a static *specular top edge*: a 1 pt stroke with a `LinearGradient` from white 14 % at the top to clear at 40 %. It reads like the edge of a watch crystal. Light mode uses two static shadows: `(0,1) blur 2 @ 6 %` and `(0,12) blur 32 @ 6 %`. Never put a shadow on a view that animates continuously.

**Home: reference iPhone 17 (402 × 874 pt).** Layout is chronological from top to bottom, like turning a crown: **Last → Now → Next ×2**.

1. **Toolbar** (system, 44 pt). Left: eyebrow `SAT · 7 NOV`. Right: glass toolbar buttons `plus` and `person.crop.circle`.
2. **Last row**, 52 pt, "ghost" style: no fill, 1 pt `separator` stroke, radius 20. Leading status glyph, 17 pt: `checkmark.circle.fill` in success, `xmark.circle` in textTertiary for cancelled, or `exclamationmark.circle` in warning for overran. Title 15 Medium in textSecondary, `13:00–13:58` in mono textTertiary. Trailing actual duration (`58m`), or `+6m` in warning.
3. **Hero card ("Now")**: width 362 (20 pt margins), padding 20, radius 32, surface1, about 442 pt tall with a one-line title. The parts stack as follows:
   - Eyebrow row (16 pt): 6 pt accent live dot, then `NOW · 14:00–15:00`, then a 3 × 14 pt category tick. Trailing `60 MIN` in textTertiary.
   - 10 pt gap, then the title (`cardTitle`, up to 2 lines).
   - 6 pt gap, then the meta row (13 pt symbols `mappin`, `checklist`, `note.text` plus `meta` text: "Studio · 2/5 subtasks").
   - 16 pt gap, then the **dial block**: 228 × 228, centred, containing the ring and digits (see §5).
   - 16 pt gap, then the **control row**: 56 pt tall. Cancel (56 circle), 12 pt gap, Pause/Play (56 circle), 12 pt gap, then Complete (a capsule that fills the remaining **186 pt**).
4. **NEXT** eyebrow (textTertiary), then **two next rows**: 64 pt, surface1, radius 20, horizontal padding 16. Each row has a 3 × 28 pt category bar, a 48 pt time column (`15:00` timeLabel over `30m` caption in textTertiary), the title (`rowTitle`) plus an optional 13 pt location line, and on the trailing edge a chip: `in 12m` (24 pt capsule, surface2, 13 Medium mono digits). The first next row also shows `bell.fill` (12 pt, textTertiary) when an alert is scheduled. Swipe actions are Start now (accent) and Snooze 5 (surface2).
5. **Tab bar** (system glass): Now `timer`, Day `calendar.day.timeline.left`, Tasks `checklist`, Assistant `sparkles`. The selected tint is **textPrimary**, not the accent.

**Small screens and empty state.** Home is a `ScrollView`. Below a height of 750 pt the dial shrinks to 184 pt and the digits to 56 pt. When nothing is running, the hero card becomes **"Free until 15:00"** with a textTertiary ring counting down the gap and a filled accent **Start next early** button.

**Day timeline (for consistency).** Default scale 1.2 pt per minute (72 pt per hour); pinch to zoom between 0.6 and 4 pt per minute. Hour ticks use SF Mono 11 in a 44 pt gutter. Blocks have a radius of 10, a 14 % category tint, a 3 pt category bar and a 13 Semibold title, with a minimum height of 22 pt. Dragging snaps to 5 minutes, with `.sensoryFeedback(.selection)` on each snap. The **now-line** is a 1 pt accent rule with an 8 pt dot and a time pill (accent fill, accentOn, 11 pt mono semibold) and updates once a minute. The running block gets a 1.5 pt accent stroke.

---

## 5. The timer visual: **Bezel ring + condensed digits**

**Choice:** a thin **ring with a 60-tick minute bezel**, with large condensed digits in the centre. I rejected the alternatives. A bar wastes the hero space and reads as a download. A liquid fill is expensive (animated shapes and masks every frame) and reads as playful. Digits alone lose the at-a-glance proportion.

**Geometry (228 × 228 block).**
- Track: a circle of 200 pt diameter measured at the stroke centre, 10 pt stroke, `ringTrack`.
- Progress: 10 pt stroke with `lineCap: .round`, drawn as `trim(from: elapsedFraction, to: 1)` and rotated −90°. The leading edge moves **clockwise like a watch hand**, eating the remaining arc.
- Lume head: a 12 pt circle at the leading edge, filled with the progress colour, with a 4 pt `accentOn` centre. Its "glow" is a static `RadialGradient` circle 28 pt across (accent 35 % → clear). It is **not** a blur or shadow.
- Bezel: 60 ticks between radius 108 and 112 (minor ticks: 1 pt, textTertiary at 40 %). Every 5th tick is major (1.5 × 6 pt, textSecondary). On a task shorter than an hour, the ticks map to the planned duration.
- Inside the ring: `timerXL` digits (MM:SS, or H:MM:SS at 54 pt), with the `ENDS 14:58` eyebrow 6 pt below in textSecondary.

**States and colour.**

| State | Ring | Digits | Eyebrow |
|---|---|---|---|
| Running | `accent` | textPrimary | `NOW` + accent dot |
| Ending soon (≤ alert lead time, default 5 min, or ≤ 10 %) | crossfade to `warning` over 250 ms, with one `.warning` haptic | textPrimary | `ENDING SOON` in warning, `!` glyph |
| Last 60 s | `warning` | `warning` | — |
| **Overrun** | track tinted warning 20 %; a 4 pt **overrun lap** ring inside it (r = 88) grows clockwise at 1 revolution per 10 min | `+02:14` in warning, counting up | `OVERRUN` |
| Paused | progress becomes textSecondary | textSecondary | `PAUSED` |
| Completed | ring fills to 360° in `success` (250 ms), then hands off | — | — |

**Rendering cheaply (1 Hz model, no per-frame work in `body`).**
- Digits: use **`Text(timerInterval: start...end, pauseTime: pausedAt, countsDown: true)`**. The system ticks the digits itself, so `body` is never re-run for them. The same text view works in widgets and Live Activities. For overrun, switch to `Text(end, style: .timer)`, which counts up once `end` has passed. Schedule that switch with a `TimelineView(.explicit([end]))` or a single `Task.sleep`; do not poll.
- Ring: wrap **only the progress arc** in `TimelineView(.periodic(from: start, by: 1))`. Between ticks, apply `.animation(.linear(duration: 1), value: fraction)`. That re-evaluates state once a second and costs one cheap path interpolation per frame, so the sweep looks continuous. Under Low Power Mode, Reduce Motion, or `context.cadence != .live` (Always-On), drop the interpolation and step once a minute, hiding seconds.
- The bezel ticks are a **separate, static `Canvas`** outside the `TimelineView`, so they are drawn once and cached.
- Never apply `shadow`, `blur`, or `glassEffect` to the moving arc.
- Live Activity and Dynamic Island: `ProgressView(timerInterval:countsDown:)` with `.progressViewStyle(.circular)` and the accent tint. The system animates it, and `Text(timerInterval:)` supplies the digits. Compact layout: 8 pt category dot plus ring on the leading side, `timerS` digits in accent on the trailing side (frame max 52 pt). Minimal layout: ring only.

```swift
ZStack {
    BezelTicks()                                   // static Canvas — never invalidated
    Circle().stroke(Tok.ringTrack, lineWidth: 10)
    TimelineView(.periodic(from: start, by: 1)) { ctx in
        let now = pausedAt ?? ctx.date
        let f = min(1, max(0, now.timeIntervalSince(start) / end.timeIntervalSince(start)))
        Circle().trim(from: f, to: 1)
            .stroke(ringColor(remaining: end.timeIntervalSince(now)),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .animation(pausedAt == nil && !reduceMotion ? Motion.tick : nil, value: f)
    }
    Text(timerInterval: start...end, pauseTime: pausedAt, countsDown: true)
        .font(TypeRamp.timerXL).monospacedDigit()
}
.frame(width: 228, height: 228)
```

---

## 6. Buttons & controls

The hero card is **content layer**, so its controls are **solid**, not glass. Glass belongs to the floating layer (see §8).

| Control | Size and shape | Fill | Glyph and label | Feedback |
|---|---|---|---|---|
| **Complete** (primary) | 56 pt capsule, fills the rest of the row (186 pt) | `success` | `checkmark` 17 Bold + "Complete" 17 Semibold, in `successOn` | `.sensoryFeedback(.success)`, `.symbolEffect(.bounce)` on the check |
| **Start** (primary, when not running) | 56 pt capsule | `accent` | `play.fill` + "Start" in `accentOn` | `.impact(weight: .medium)` |
| **Pause / Play** (secondary) | 56 pt circle | `surface2` + 1 pt hairline | `pause.fill` ↔ `play.fill`, 22 pt, textPrimary; when paused, Play glyph is `accent` | `.contentTransition(.symbolEffect(.replace))` (`.replace.magic(fallback: .downUp)` on iOS 18+), `.impact(weight: .light)` |
| **Cancel** (destructive) | 56 pt circle | `surface2` | `xmark` 20 Semibold in `danger` | **Hold 0.5 s to cancel.** A 2 pt danger ring fills around the button. A plain tap shows a "Hold to cancel" hint. No modal is needed. |
| Snooze / Extend | 36 pt capsule chip | surface2 | `plus` + "5 min" (`timeLabel`) | `.contentTransition(.numericText())` |

**Pressed state** (one custom `ButtonStyle` for all): scale 0.96 and brightness −0.06 in light or +0.06 in dark, animated with `Motion.micro`. Disabled state: 40 % opacity, no hit-testing. Minimum hit target is 44 pt; visual targets are 56 pt.

**Undo.** After Complete or Cancel, a glass toast appears for 4 s above the tab bar: "Completed · Undo", with `arrow.uturn.backward`.

**SF Symbols vocabulary:** `checkmark`, `play.fill`, `pause.fill`, `xmark`, `plus`, `forward.end.fill` (skip), `arrow.uturn.backward`, `bell.fill` / `bell.badge`, `timer`, `calendar.day.timeline.left`, `checklist`, `sparkles`, `mic.fill`, `arrow.up`, `wand.and.stars`, `target`, `arrow.right.to.line`. Symbol weight follows the adjacent text weight.

**AI assistant controls.**
- Composer: a floating glass capsule with a minimum height of 52 pt that grows to 5 lines.
- Send button: a 36 pt circle in **textPrimary** with `arrow.up` in the `background` colour, enabled only when there is text. The same slot shows `mic.fill` when the field is empty.
- Prompt templates: horizontally scrolling **solid** surface2 chips, 36 pt tall, 15 Medium, each with a 13 pt leading symbol. Examples: "Plan my afternoon", "Shift everything after 3 pm by 30 min", "Block 90 min focus", "Add a reminder". Tapping a chip fills the composer with highlighted placeholder tokens (SF Mono) and does not send it.
- Clarifying questions: assistant text on the background, with no bubble, followed by outline quick-reply chips.
- **Change cards** (surface1, radius 24): show a mini timeline diff. Added blocks have a dashed 1 pt outline in their category colour plus `plus`. Moved blocks show a 30 % ghost at the old slot and a solid block at the new one. Removed blocks have textTertiary strikethrough plus `minus`. Actions: **Apply** (a textPrimary-filled pill with the label in the bg colour) and **Edit** (surface2).

---

## 7. Motion tokens

All values are SwiftUI springs. Every common transition settles in **≤ 350 ms**. The only exception is `tick`, which is continuous interpolation rather than a transition.

| Token | SwiftUI | ≈ spring(response, damping) | Use |
|---|---|---|---|
| `micro` | `.snappy(duration: 0.15)` | 0.15, 1.0 | press states, toggles, chip selection |
| `snappy` | `.snappy(duration: 0.25)` | 0.25, 0.86 | default state changes, colour crossfades, row insert/remove, toast |
| `bouncy` | `.bouncy(duration: 0.32, extraBounce: 0.08)` | 0.32, 0.72 | Next → Now promotion, complete check, AI change card appearing |
| `glide` | `.smooth(duration: 0.35)` | 0.35, 1.0 | glass morphs, ring draw-on, sheet content, tab-accessory expand |
| `tick` | `.linear(duration: 1.0)` | — | ring progress between 1 Hz updates only |

**Signature choreography: Complete** (settles in about 360 ms).
- 0 ms: haptic; the check bounces; the ring fills to 360° in success (`snappy`).
- 60 ms: card content lifts by −16 pt and fades.
- The first next row morphs into the hero card with `matchedGeometryEffect` (`bouncy`), and its ring draws on with trim 0 → 1 (`glide`).
- The finished task collapses into the Last row (`snappy`).
- No confetti.

**Numeric and symbol effects.**
- `.contentTransition(.numericText(countsDown: true))` on relative chips ("in 12m"), duration steppers and the "ENDS 14:58" label when a pause shifts it. Do not apply it to `Text(timerInterval:)`, which updates itself.
- `.symbolEffect(.bounce, value:)` on the complete check and on the bell when an alert is scheduled.
- `.symbolEffect(.wiggle)` on the bell at "ending soon" (iOS 18+; fall back to bounce).
- `.symbolEffect(.drawOn)` for the success check on iOS 26.
- `.symbolEffect(.variableColor.iterative)` on `ellipsis` while the AI is thinking. This is the only continuous symbol effect, and only while a request is in flight.

**Reduce Motion:** replace offsets, scales and morphs with ≤ 150 ms opacity crossfades, and turn off the `tick` interpolation.

---

## 8. Liquid Glass usage rules

Apple's guidance is that Liquid Glass belongs to the **navigation and control layer that floats above content**. It should be used sparingly, with colour applied to at most one prominent control. Direction A follows this strictly; the instrument look depends on solid, precise surfaces.

**Glass: yes (floating layer only).**
- **Tab bar**: system-provided. Add `.tabBarMinimizeBehavior(.onScrollDown)` on Day and Assistant.
- **Mini-timer accessory**: `.tabViewBottomAccessory { }` on iOS 26, shown on every tab except Now, like Music's "now playing". It contains an 8 pt category dot, the task title, `Text(timerInterval:)` in `timerS`, and a Pause button. Read `tabViewBottomAccessoryPlacement` to show the compact version when the tab bar is minimised. Tapping it jumps to Now.
- **Toolbar buttons** (`plus`, profile): system glass. The **Day-view quick-add button** is a 56 pt glass circle in a `GlassEffectContainer` that morphs into a quick-add field through `glassEffectID` (`glide`).
- **AI composer** and its mic and send buttons: one `GlassEffectContainer(spacing: 8)`.
- **Undo toast**, sheets, menus and popovers: system glass.
- Variant: `.regular` everywhere, with `.interactive()` only on tappable glass. `.clear` is never used, because the app has no media backgrounds. A tint goes on at most **one** glass control per screen: the AI send button when it has text, tinted textPrimary.
- Use `.scrollEdgeEffectStyle(.soft, for: .top)` on scrolling screens, so content dissolves under the toolbar.

**Solid surfaces: always.** The hero card, Last and Next rows, the timer ring, Day-timeline blocks, AI messages, change cards and template chips. **Never glass on glass**: for example, no glass button on a glass sheet; use solid surface2 there.

**Performance rules.**
- Glass shapes change only on discrete events, never every frame.
- Keep grouped glass in a single container rather than many separate glass views.
- Inside glass, content updates step at 1 Hz without interpolation: the accessory's digits are `Text(timerInterval:)`, which is effectively free.
- Never put a `TimelineView`-driven animating shape under or inside glass.

**Fallback for iOS 17–25.**
- Floating controls: `.background(.regularMaterial, in: Capsule())`, a 0.5 pt white-12 % hairline, and one static shadow.
- Tab bar: the standard material `TabView`.
- Mini timer: a `.safeAreaInset(edge: .bottom)` material capsule placed above the tab bar.
- With `accessibilityReduceTransparency` turned on, swap the materials for solid `surface2`; system glass adapts on its own.

---

## 9. Swift token sketch (Lume)

```swift
import SwiftUI

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    /// Dynamic light/dark colour with optional Increase-Contrast variants (works in widgets too).
    static func dyn(_ light: UInt32, _ dark: UInt32, hcL: UInt32? = nil, hcD: UInt32? = nil) -> Color {
        Color(uiColor: UIColor { t in
            let hc = t.accessibilityContrast == .high
            if t.userInterfaceStyle == .dark { return UIColor(hex: hc ? (hcD ?? dark) : dark) }
            return UIColor(hex: hc ? (hcL ?? light) : light)
        })
    }
}

/// Palette A1 "Lume". (Production: mirror these into an asset catalog with High Contrast slots.)
enum Tok {
    static let bg        = Color.dyn(0xF3F4F6, 0x060708)
    static let surface1  = Color.dyn(0xFFFFFF, 0x111316)
    static let surface2  = Color.dyn(0xE8EAEE, 0x1A1D21)
    static let separator = Color.dyn(0xD3D7DD, 0x2A2E35, hcL: 0xA9AFB8, hcD: 0x3E444D)
    static let ringTrack = Color.dyn(0xE1E4E8, 0x1E2227)
    static let text1     = Color.dyn(0x0B0D10, 0xF4F6F8)
    static let text2     = Color.dyn(0x4A515B, 0xA3AAB4, hcL: 0x353B44, hcD: 0xC3C9D1)
    static let text3     = Color.dyn(0x686F7A, 0x7C838E, hcL: 0x4A515B, hcD: 0xA3AAB4)
    static let accent    = Color.dyn(0x00748C, 0x3DE3F5, hcL: 0x005A6D, hcD: 0x7DF0FF)  // "now" only
    static let accentOn  = Color.dyn(0xFFFFFF, 0x00242B)
    static let success   = Color.dyn(0x127A3A, 0x3DDC84)
    static let successOn = Color.dyn(0xFFFFFF, 0x002611)
    static let warning   = Color.dyn(0xA35C00, 0xFFB020)                              // ending soon + overrun
    static let danger    = Color.dyn(0xCC1D35, 0xFF4D5E)                              // cancel only
    static let category: [Color] = [
        .dyn(0xC92D57, 0xFF6F91), .dyn(0x866F00, 0xE6CC4A), .dyn(0x4A8516, 0x9BD65A), .dyn(0x06855A, 0x3FD49B),
        .dyn(0x1D62D6, 0x5FA8FF), .dyn(0x7F3ECC, 0xC68BFF), .dyn(0xAC2E8C, 0xF27AD0), .dyn(0x5B6472, 0xA3ACB9),
    ]
}

enum TypeRamp {
    static let timerXL   = Font.system(size: 68, weight: .light).width(.condensed).monospacedDigit()
    static let cardTitle = Font.system(.title, weight: .semibold)
    static let rowTitle  = Font.system(.headline, weight: .semibold)
    static let timeLabel = Font.system(.subheadline, weight: .medium).monospacedDigit()
    static let eyebrow   = Font.system(.caption2, weight: .semibold).width(.expanded)  // + .textCase(.uppercase).tracking(1)
    static let tick      = Font.system(.caption2, design: .monospaced, weight: .medium)
}

enum Motion {
    static let micro  = Animation.snappy(duration: 0.15)
    static let snappy = Animation.snappy(duration: 0.25)
    static let bouncy = Animation.bouncy(duration: 0.32, extraBounce: 0.08)
    static let glide  = Animation.smooth(duration: 0.35)
    static let tick   = Animation.linear(duration: 1.0)
    static func a11y(_ a: Animation, reduceMotion: Bool) -> Animation { reduceMotion ? .easeOut(duration: 0.15) : a }
}

extension View {
    /// Floating-layer glass with an iOS 17–25 material fallback. Never use on content-layer cards.
    @ViewBuilder func floatingGlass<S: Shape>(_ shape: S, interactive: Bool = true) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.interactive(interactive), in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 0.5))
        }
    }
}
```

(`TypeRamp.timerXL` should be scaled with `@ScaledMetric(relativeTo: .largeTitle) var timerSize = 68` at the call site.)

---

## 10. Hand-off checklist

- [ ] The accent appears only on now/live elements; audit each screen for ≤ 3 occurrences.
- [ ] Every state carries a glyph or sign in addition to colour (Differentiate Without Color).
- [ ] The timer body re-renders at ≤ 1 Hz; profile with Instruments' SwiftUI template to confirm no per-frame `body` calls.
- [ ] No glass in the content layer, no glass on glass, and no shadows or blur on animating views.
- [ ] Test light, dark, Increase Contrast, Reduce Transparency, Reduce Motion and AX5 Dynamic Type.
- [ ] Live Activity, Dynamic Island and widgets use dark tokens (the Island is always black) and `widgetAccentable()` on the ring for tinted Home Screen modes.
