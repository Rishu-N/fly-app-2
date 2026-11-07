# UX-2: Flows, Notifications and Edge Cases

*Lens: robustness, clarity and ease of use. Home choreography and the visual paradigm belong to UX-1. Copy uses the working name "Fly".*

## 0. Rules everything below follows

1. **One running timer at a time.** Starting a second timer always resolves the first one.
2. **Never move the plan silently.** Early starts, late starts and overruns change the *actual* times. The *planned* times change only when the user taps something.
3. **Undo beats confirm.** Destructive actions run immediately and show a 5-second undo toast.
4. **Notifications are a budget.** Each block gets one heads-up. Alerts that collide are merged, and nothing fires while the user is already looking at the screen.
5. **Store timestamps, not running counters.** Timer state is `startedAt`, `pausedAt` and `pausedTotal`, and everything else is recomputed from those.

**Terms.** A *block* has a start and a duration. A *reminder* is a 0-minute item with a Done checkbox and no timer. A block's status is one of: Planned, Running, Paused, Overtime, Completed, Skipped, Cancelled or Missed.

---

## 1. Information architecture

| # | Tab | SF Symbol | Purpose |
|---|---|---|---|
| 1 | **Now** | `timer` | Home: the current block, the last block and the next two |
| 2 | **Plan** | `calendar.day.timeline.left` | Day timeline (default), week strip, search |
| 3 | **Inbox** | `tray` | Items with no time yet and undated reminders, dragged into Plan when ready |
| 4 | **Assistant** | `sparkles` | AI chat and templates (always the last tab) |

- **Settings is a gear** in the Now and Plan nav bars. It opens as a sheet with its own `NavigationStack`. It doesn't get a tab.
- **Skip the iOS 26 `Tab(role: .search)`.** It would take the trailing slot that the Assistant needs. Search goes in Plan's toolbar instead.
- **Running mini-player.** While a timer runs on any tab other than Now, a pill sits above the tab bar: `● Deep work · 23:10 ⏸`. On iOS 26 it uses `tabViewBottomAccessory`; on iOS 17–18 it's a custom overlay. Tapping the pill jumps to Now, and its pause button works in place.
- **Plan navigation.** Swipe sideways to change days. Tap the week strip to jump. A "Today" button appears whenever the user is away from today. Long-press empty time to create a block.

| Interaction | Presentation |
|---|---|
| Quick add | Sheet at `.medium` with the keyboard up; drag to `.large` for the full editor |
| Tap a block | Sheet at `.medium` with details and actions (Start, Edit, Skip, Duplicate, Delete); editing expands it to `.large`, never a push |
| Repeat scope, conflict choices | `confirmationDialog` |
| Settings | Sheet, with pushes inside it |
| Day review | Push from Plan |
| Assistant change set with more than 3 changes | Full sheet showing a before/after timeline |

---

## 2. Onboarding (4 screens, under 60 seconds, no account)

1. **Value.** "Plan by the minute. Start when you're ready."
   - A 3-second loop shows the rule: a 2:00–3:00 block, Start tapped at 1:58, timer ends at 2:58.
   - Subline: "Your timer runs for the time you planned, whenever you start."
2. **Heads-up.** "How early should we nudge you?"
   - Chips: None · At start · 2 · **5** · 10 · 15 min. The toggle "Nudge me if I haven't started" is on.
   - The primary button, **Turn on reminders**, brings up the system prompt. The user has just picked a lead time, so they know why we're asking.
   - "Not now" is fine: the app still works with in-app banners and the Live Activity.
3. **Your day.**
   - **Try a sample day:** five short blocks starting at the next 5-minute mark, so Now is live immediately. A "Clear sample day" chip stays visible.
   - **Start empty.**
   - Optionally, if EventKit ships, **Show my calendar events** as fixed blocks. Calendar permission is requested only when this is picked.
4. **Assistant (skippable).** "Bring your own OpenAI key."
   - A paste field with a Paste button, plus a "Where do I get one?" link.
   - Privacy line: "Stored in your Keychain. Requests go straight from your phone to OpenAI. Fly runs no servers."
   - One cheap request validates the key and shows a ✓. **Skip for now** is as prominent as Continue.

There's no tour. Tips appear in context, at most one per session.

---

## 3. Create and edit a block

**Target: under 5 seconds.** Tap **+**, type "Gym 6pm 45m", press Return. That's it.

- **Quick add focuses the title field.** Typing is parsed locally (`NSDataDetector` plus a small grammar) into tappable chips, e.g. **6:00 PM** and **45 min**.
- **Defaults when nothing is typed:**
  - *Start:* the next free slot. That's the end of the last block that ends after now, or now rounded up to 5 minutes.
  - *Duration:* the last duration used for this title, otherwise the category default, otherwise 30 minutes.
- **Return saves.** A "Saved · Undo" toast follows. Autocomplete on past titles brings back their category, duration and checklist.
- **Other paths:** long-press in Plan and drag to resize (snaps to 5 minutes), drag from Inbox, Duplicate, or the "Add block" App Intent (Siri, Control Center, app-icon quick action).

| Field | Default | Notes |
|---|---|---|
| Title | — | The only required field |
| Start | Next free slot | 1-minute precision, with −5/+5 chips |
| Duration ↔ End | 30 min | Chips: 15 · 25 · 30 · 45 · 60 · 90 · Custom. Changing End adjusts the duration and keeps the start fixed. Always shown as "2:00–2:45 · 45 min" |
| Category | Last used | 8 presets, each a color plus an SF Symbol glyph |
| Heads-up | Default (5 min) | Per-block override: None, At start, or N minutes |
| Repeat | Never | Daily, Weekdays, Weekly on [day], Every N days, Custom |
| Checklist | — | Can be ticked from the running card; ticking every item does not auto-complete the block |
| Notes | — | Plain text; links are detected |
| Flexible | Off | Lets "Shift rest of day" and the Assistant move this block |

**Validation warns but never blocks.** An overlap shows "Overlaps Lunch 12:30–1:00 · [Move after]". A start in the past shows "This is in the past · Log as done?"

---

## 4. Notification UX

### Templates

| Type | Fires | Title / Body | Actions | Level |
|---|---|---|---|---|
| Heads-up | Start − lead | **Deep work in 5 min**<br>2:00–3:00 · 60 min. Your timer starts when you tap Start. | **Start now** · Snooze 5 min · Skip | Time-sensitive |
| Not started | Start + 5 min, once | **Deep work was due at 2:00**<br>Start now and you still get the full 60 min. | **Start** · Skip · Reschedule… | Active |
| Time's up | Timer end | **Time's up: Deep work**<br>60 min done. Up next: Lunch at 3:00. | **Complete** · +5 min · +15 min | Time-sensitive |
| Time's up + next block (merged) | Timer end, when the next block starts within the lead window | **Time's up: Deep work**<br>Lunch starts at 3:00. | **Complete & start Lunch** · +5 min · Complete | Time-sensitive |
| Overtime | End + 10 min, once | **Still on Deep work?**<br>You're 10 min over. | **Complete** · Keep going | Active |
| Paused | Pause + 15 min, once | **Deep work is paused**<br>24 min left. | **Resume** · Complete | Passive |
| Next block while one runs | Next start − lead | **Lunch at 3:00**<br>Deep work has 12 min left. | **Complete & start Lunch** · Keep going | Time-sensitive |
| Assistant done | Reply finishes in background | **Your plan is ready**<br>3 changes to review. | Opens the Assistant | Passive |

**What each action does.** Everything except Reschedule runs in the background without opening the app.

- **Start now** starts the timer from the tap, schedules Time's up, and updates the Live Activity.
- **Snooze** re-alerts in 5 minutes without moving the plan. If the start has passed, the copy becomes "started 2 min ago".
- **Skip** marks this occurrence Skipped (restorable). **+5 / +15** extends the duration and reschedules Time's up.
- **Complete & start X** does both in one tap. It's the most common transition in a day.

### Avoiding notification spam

- **Merge** alerts that fall within 2 minutes of each other.
- **Stay quiet on Now.** If the Now tab is on screen, `willPresent` drops the banner and the card animates with a haptic instead.
- **Clean up.** Starting, skipping or editing a block removes its pending alerts immediately.
- **Follow-ups fire at most once per block.** Group by day with `threadIdentifier = "day-2026-11-07"`.
- **Quiet hours** (off by default) downgrade alerts to passive.
- **Ease off when ignored.** After 3 ignored heads-ups in a row, one card asks "Too many nudges? [Fewer] [Keep]". Fewer means heads-ups only for blocks of 25 minutes or more.

### The 64-pending limit

iOS keeps only the 64 soonest pending requests per app and silently drops the rest. Repeating triggers can't skip single occurrences either. So:

- **Rolling window of at most 55 requests:**
  - up to 40 heads-ups
  - "Not started" follow-ups for the next 10 blocks only
  - 4 slots reserved for the running block
  - 1 sentinel
- **Expand repeating blocks into individual occurrences.** Never use repeating triggers.
- **Top up the window** on every foreground, every edit, every notification-action callback, `BGAppRefreshTask`, and `significantTimeChangeNotification`.
- **Sentinel.** One minute after the last heads-up in the window, schedule "Open Fly to keep your reminders coming." Each top-up pushes it later, so it only fires if the app hasn't run for days.
- **Triggers.** Heads-ups use `UNCalendarNotificationTrigger` (wall clock). Timer ends use `UNTimeIntervalNotificationTrigger`, so durations survive clock changes.
- **`.timeSensitive`** (requires the capability) is only for heads-ups and Time's up. These are the alerts that should break through Focus and Scheduled Summary. A Settings toggle downgrades them to active.

### Live Activity and Dynamic Island

- **One activity, reused** through states by updating it: Up next → Running → Paused/Overtime → Up next.
- **Running uses `Text(timerInterval:countsDown:)`.** It ticks with zero updates.
- **`staleDate` is set to the timer end.** When `context.isStale` is true, the view shows "Time's up · +mm:ss" counting up via `Text(end, style: .timer)`. It flips to overtime without the app running.
- **Buttons (`LiveActivityIntent`):**
  - Running: Pause/Resume and **Complete**
  - Up next: **Start**
  - Overtime: **Complete** and +5
  - **No Cancel on the Lock Screen**, because it's too easy to hit by accident.
- **Dynamic Island:**
  - Compact: category glyph with a progress ring on the left, mm:ss remaining on the right (`monospacedDigit`).
  - Minimal: just the ring.
  - Expanded: title, time remaining, "Next: Lunch 3:00", and two buttons.
- **No server means no push-to-start.** A local start needs the app in the foreground (engineering: verify `LiveActivityStartingIntent` for widget and Control buttons).
  - Start the "Up next" activity whenever the app is foregrounded with a block less than 60 minutes away.
  - If a background "Start now" finds no activity, the timer and Time's up still work, and the activity appears at the next foreground.
- **8-hour cap.** Recreate the activity on foreground after 7 hours. Blocks longer than 8 hours (e.g. sleep) don't get one by default.
- **Respect dismissal.** If the user swipes the activity away, don't recreate it until the next block starts.

---

## 5. Edge cases: one rule each

| Situation | Rule | UI feedback |
|---|---|---|
| **Early start** (planned 2:00, started 1:58) | Planned duration from the tap, so it ends at 2:58. The plan stays 2:00–3:00; the actual time is logged. More than 60 minutes early asks first | "Started 2 min early". Timeline draws the actual block over a faint planned outline |
| **Late start** (started 2:10) | Full duration from the tap, so it ends at 3:10. Never shift other blocks automatically | "Runs into Lunch by 10 min · [Shift rest of day +10m]" |
| **Starting B while A runs** | If A is in overtime, it completes automatically. Otherwise, ask | [Complete A & start B] (default) · [Pause A & start B] · [Cancel]. Auto-completion shows "Completed Deep work · Undo" |
| **Paused past the next block's start** | A stays paused. B becomes the current block | Pill: "⏸ Deep work · 24m left [Resume]". Long-press → "Finish later" puts the remainder into the next free gap |
| **Paused until the day ends** | At day end (default 4:00 AM) the block becomes **Unfinished**, with time spent logged | Listed under "Needs attention" in Day review, with Reschedule |
| **Timer overrun** | **Never auto-complete silently.** The timer counts up as Overtime. Time's up fires once, and the nudge fires once at +10 min | "+03:12" with a striped bar and the word "Over". Buttons: Complete, +5. The Live Activity flips via `isStale` |
| **Finishing early** | The actual end is logged, and the rest of the slot becomes free time | "Done 8 min early · Free until 3:00" · [Start Lunch early] [Take a break] [Add a block] |
| **Skip vs. Cancel vs. Delete** | *Skip*: not doing it (before it starts). *Cancel*: stop a running block, time spent logged. *Delete*: remove from the plan (editor only) | 5-second undo on each. Skipped and cancelled blocks stay on the timeline, greyed and struck through |
| **Restoring** | Same day: Skipped → [Restore], back to Planned (or Missed if its time has passed). Cancelled → [Resume] the remaining time, or [Reschedule]. Past days are read-only | Actions live in the block sheet |
| **Missed (never started)** | Becomes Missed once the planned end passes. One "Not started" nudge at +5 min. No shaming | "Last" row: "Didn't start: Gym · [Reschedule]". Also listed in Day review |
| **Overlapping blocks** | Allowed, with a warning. If nothing runs, the earlier one is current and the other is next, tagged. Same-minute heads-ups merge | Amber stripe plus "Overlaps Lunch" text, never color alone |
| **Back-to-back** (A ends 3:00, B starts 3:00) | If A is running on time, B's heads-up is folded into A's Time's up | One alert: "Complete & start Lunch". The Live Activity moves straight to B |
| **Gaps** | Gaps of 10 minutes or more are shown as free time. Shorter gaps are hidden | "25 min free" row between upcoming blocks; tapping it opens quick add with the gap pre-filled |
| **Crossing midnight** | Stored as an absolute start plus a duration. The block belongs to the day it starts on, using the "Day starts at" setting | "→ 12:30 AM" with a stub on the next day. The timer is unaffected |
| **Repeating blocks** | Each occurrence has its own status and timer. Edits ask "This one / This and future / All". Skipping one occurrence never changes the series | "Repeats weekdays" badge, plus a dot on occurrences that were edited |
| **Editing a running block's duration** | End = `startedAt` + new duration + `pausedTotal`. If the new duration is shorter than the time already spent, the block goes to Overtime | +5/−5 chips on the card. When shortening past elapsed time: "That's less than you've spent. Complete now?" |
| **Editing a running block's start** | Only the plan moves. The actual start and the timer stay as they are | "Plan moved · timer unchanged" |
| **App killed or phone rebooted** | Rebuild from timestamps; pending notifications survive reboot. On launch, recreate the Live Activity and top up the window | Nothing visible. A timer that ended meanwhile opens in Overtime |
| **Time zone change / DST** | Blocks keep their local wall-clock times by default. Running timers are duration-based and don't change. A start that lands in a DST gap moves forward | Banner: "You're on Pacific Time. Your plan kept its local times. [Keep] [Keep Paris times]" |
| **Reminder (0 min)** | No timer and no Start button. Gets a heads-up only if the user sets one | A slim row with a Done checkbox |
| **Notifications denied** | Everything else still works through in-app banners and the Live Activity | Banner on Now, at most once a week: "Reminders are off. [Turn on]" |

---

## 6. AI assistant UX

**Layout:**
- **Nav bar:** model menu ("Fast" / "Smart") and a new-chat button.
- **Context chip** under the title: "Sees: Today + 7 days · notes off". Tapping it changes the scope, so the user always knows what gets sent.
- **Messages:** user bubbles, full-width assistant text, change cards inline.
- **Composer:** templates button (`square.grid.2x2`), text field (keyboard dictation), and Send, which becomes **Stop** while streaming.

**Template gallery.** An empty chat shows a 2-column grid of cards. Once a chat is going, templates appear as chips above the composer. A template drops text into the composer with tappable **slot tokens**, e.g. "Fit `[task]` in before `[time]`".

| Template | What it does |
|---|---|
| **Plan my day** | Builds today from Inbox, routines and open time |
| **Fit this in** | Finds the best slot, moving Flexible blocks if needed |
| **I'm running late** | "I'm 30 min behind": reshuffles the rest of today |
| **Brain dump → blocks** | Turns a messy list into timed, sized blocks |
| **Break it down** | Splits a big task into sequenced blocks with checklists |
| **Protect focus time** | Reserves deep-work blocks around fixed events this week |
| **Build a routine** | Creates a repeating morning or evening routine |
| **Clear my evening** | Moves or skips everything after a chosen time |
| **Week preview** | Summarises the week and flags overloaded days |
| **Review my day** | What got done, what slipped, and suggestions for tomorrow |

**Clarifying questions** are a tool call: `ask_user(question, options[], multiSelect)`. Using a tool call instead of free text means the chips always render.
- The UI shows the question, 2–5 answer chips, **"Just decide for me"**, and **"Other…"**, which focuses the composer.
- A tapped chip is posted as the user's reply.
- At most 2 questions per turn. Chips already answered go inactive.

**Proposed changes are never applied without review.** `propose_changes([...])` renders a change-set card:

```
3 changes to Today                       [mini before/after strip]
＋ Add     Email triage  4:00–4:20 PM                        [✓]
✎ Move    Gym  6:00 → 6:30 PM (old time struck through)     [✓]
－ Remove  Admin  5:00–5:25 PM                               [✓]
⚠ Gym now overlaps Dinner by 10 min
[ Apply 3 changes ]   Edit…   Discard
```

- **Rows are labelled with a glyph and a word,** never color alone. Each row has a checkbox so changes can be applied one at a time. Tapping a row opens the normal editor, pre-filled.
- **Apply** plays a success haptic, and the card changes to "Applied ✓ · **Undo**". Undo stays available for the whole chat and reverts the full set.
- **Removals and edits to the running block** are always explicit rows. The Assistant can never start, pause or complete a timer.
- **More than 3 changes** offers "Review on timeline".

**Streaming:**
1. Thinking dots.
2. One tool-status line, e.g. "Looking at Thursday…".
3. The reply text streams in.
4. A skeleton card fills in, with a light haptic when it's ready.

If the user leaves mid-reply, a background task finishes it (about 30 seconds of runtime) and sends "Your plan is ready". Nothing is applied in the background.

| Error | Copy | Action |
|---|---|---|
| No key | "The assistant runs on your own OpenAI key." | [Add key]. Templates stay visible but greyed out |
| 401 | "OpenAI didn't accept this key." | [Update key] |
| No credit | "Your OpenAI account is out of credit." | [Open OpenAI billing] |
| 429 | "OpenAI is busy for this key. Retrying in 20s…" | Retries automatically with a countdown; [Cancel] |
| Offline | "You're offline. This will send when you're back." | Message stays queued; [Send now] |
| Bad tool output | (retries silently once) "I couldn't build those changes. Try rephrasing?" | [Retry] |

**Privacy sheet (first visit), "What the assistant sees":**
- Titles and times for blocks in the range you choose.
- Notes stay **off** unless you turn them on.
- Requests go straight from this iPhone to OpenAI on your key.
- Chats stay on this device.

Keychain storage is `AfterFirstUnlockThisDeviceOnly`: usable in the background, never synced. Settings shows the month's estimated usage.

---

## 7. Haptics and sound

Use `.sensoryFeedback`. Apple documents `.start`, `.stop`, `.increase` and `.decrease` as watchOS-oriented, so iPhone uses impact and notification styles.

| Action | Feedback |
|---|---|
| Start a block | `.impact(weight: .medium)` |
| Pause / Resume / Undo | `.impact(flexibility: .soft)` |
| Complete; apply changes | `.success` |
| Cancel a block; overlap warning (once per edit) | `.warning` |
| Timer ends with the app in foreground | Core Haptics, 3 short pulses |
| ±5 min, chips, pickers, 5-minute drag snaps (at most once per 80 ms) | `.selection` |
| Drop a block; change set ready | `.impact(weight: .light)` |
| Delete or skip (with undo toast) | `.impact(flexibility: .rigid)` |
| Assistant error | `.error` |

**Sound:**
- No UI sounds in the app.
- Two notification sounds, each under 1 second: a soft tone for heads-ups and a distinct two-note chime for Time's up. Both can be changed, and there's a "Haptic only" option.
- Respect the silent switch.
- Never a ticking sound.

---

## 8. Accessibility

- **Dynamic Type on the Home card.** From `.accessibility1` up, use `ViewThatFits` to switch from side-by-side to stacked.
  - Icon-only buttons become full-width labelled buttons.
  - Notes and the checklist fold behind "Details".
  - Timer digits scale up to `.accessibility3` and use `.monospacedDigit()`.
  - Times never truncate. Titles wrap to 2 lines.
- **VoiceOver.**
  - The timer reads label "Deep work, running" and value "23 minutes left of 60, ends 2:58 PM". The value updates once a minute, not every second.
  - Announcements at 5 minutes left and at Time's up. Overtime reads as "3 minutes over".
  - Custom actions on the card: Pause, Complete, Add 5 minutes, Cancel.
  - Upcoming rows read like "Next: Lunch, 3:00 to 3:30 PM, 30 minutes". Gaps read "25 minutes free".
- **Reduce Motion.** Springs and scaling become 150 ms crossfades. The progress ring steps instead of sweeping. No parallax. Reduce Transparency switches Liquid Glass to opaque materials.
- **Color-blind safety.** Each category is a color plus a glyph. Each status is a shape plus a word:
  - Running: filled dot
  - Paused: ⏸
  - Overtime: "+" and stripes
  - Missed: dashed outline
  - Cancelled: strikethrough
  - Done: ✓

  Validate the palette for protanopia and deuteranopia, and support Increase Contrast.
- **Tap targets.** At least 44×44 pt everywhere, and at least 60 pt for the primary timer controls. **Cancel never sits next to Complete**; it goes in a `…` menu. Controls stay in the lower half of the screen, and Voice Control names match the visible labels.

---

## 9. Settings (defaults in bold)

| Group | Setting | Default |
|---|---|---|
| **Reminders** | Heads-up | **5 min** |
| | Nudge if not started | **On, at +5 min** |
| | Time's up | **On** |
| | Overtime nudge | **Once, at +10** |
| | Time-sensitive | **On** |
| | Sounds | **Chime** (or Haptic only) |
| | Quiet hours | **Off** |
| | Check my reminders | — |
| **Timer** | Starting while another runs | **Ask** |
| | Auto-complete overtime | **Never** (starting another block completes it) |
| | Show seconds | **On** |
| | Keep screen awake on Now | **Off** |
| **Schedule** | Default duration | **30 min** |
| | Snap to | **5 min** (1 / 15) |
| | Day starts at | **4:00 AM** |
| | Week starts | **System** |
| | When I run over | **Offer to shift** (or Never) |
| | After travel | **Keep local times** |
| **Live Activity & Widgets** | Live Activity | **On** |
| | "Up next" before start | **On, 60 min** |
| | Dynamic Island shows | **Time left** (or Title) |
| **Assistant** | OpenAI key | **Not set** |
| | Model | **Fast** |
| | Can see | **Today + 7 days** |
| | Include notes | **Off** |
| | History | **30 days** |
| | Usage this month; Delete all chats | — |
| **Calendars** (if EventKit ships) | Show events | **Off** |
| **Appearance** | Theme | **System** |
| | App icon | — |
| | Haptics | **On** |
| **Data** | Export (ICS/CSV); Clear sample day; Erase all | — |
| **About** | Privacy, Help, Version | — |

**"Check my reminders"** turns the top planner-app complaint ("it didn't notify me") into a self-check. It verifies notification permission, time-sensitive alerts, any active Focus, Scheduled Summary and Background App Refresh. Each failed check gets a fix button, and the screen shows "37 reminders scheduled through Tue 9:40 AM".

---

## 10. Empty and zero states

| Where | Copy | Actions |
|---|---|---|
| Now, nothing planned | **Nothing planned yet.** Try "Deep work 9am 90m". | [Add block] [Plan with Assistant] |
| Now, in a gap | **Free until 3:00.** Up next: Lunch. | [Start Lunch early] [Add a block] |
| Now, day finished | **That's a wrap.** 6 of 7 blocks done · 5h 40m focused. | [Plan tomorrow] [Review day] |
| Now, nothing has ended yet today | The "Last" row is hidden (no placeholder) | — |
| Plan, empty day | **An open day.** Press and hold any time to add a block. | [Add block] |
| Inbox, empty | **Inbox zero.** Capture anything here and drop it into your day later. | [Add item] |
| Assistant, no key | **Your assistant runs on your own OpenAI key.** It stays private, on this device. | [Add key] |
| Assistant, new chat | **What should we plan?** | Template grid |
| Notifications off | **Reminders are off.** You won't get heads-ups. | [Turn on] [Not now] |

**Tone:** short, kind and factual. Say "Didn't start", never "Failed". No streak guilt.
