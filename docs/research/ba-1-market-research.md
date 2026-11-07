# BA-1: Market & Competitive Research. Minute-by-minute planner + AI assistant (codename "Fly")

*Author: Business Analyst #1. Date: 2026-11-07.*
*Notes on the evidence: App Store ratings and in-app purchase prices are US storefront snapshots from Nov 2026. Third-party pricing sources often disagree; where they do I give a range. I could not open Reddit directly, so user quotes come mainly from App Store reviews. OpenAI prices come from OpenAI's developer docs as cached on 2026-11-07; openai.com itself is blocked from this environment.*

---

## TL;DR

- **The category is proven, and timers are the weak spot.** Structured (4.8★, 169K ratings) and Tiimo (iPhone App of the Year 2025) show people pay for visual planning. Their reviews keep naming three gaps: the plan doesn't adapt when you drift, notifications are weak, and timers are tied to the clock instead of to the moment you actually start.
- **Expensive AI planners are disliked on iPhone.** Motion charges **$44.99/mo or $294.99/yr** in-app, holds 4.1★, and reviewers complain about no widgets, weak notifications, and an AI that "dumps tasks into available timeslots."
- **Positioning:** *"the planner that starts when you do."* Execution comes first: a live countdown for each block, one-tap reflow when you're late, and an AI that **proposes a change and waits for approval.** **Wedge feature:** Live Block + Reflow.
- **Pricing:** a generous free tier, **Pro at $6.99/mo or $39.99/yr**, and later **Pro + AI at $9.99/mo or $79.99/yr** with bundled credits. A typical AI edit costs about **$0.0013 on GPT-6 Luna**.
- **Watch items.** `gpt-5-mini`/`gpt-5-nano` shut down **Dec 11, 2026**, and BYOK (bring your own key) has drawn **3.1.1** rejections from App Review.
- **Top names:** **Dayflight** and **Glidepath**. *Nowline* and *Tempo* are already taken in this category.

---

## 1. Market context

**Spending is rising, and AI is driving it.** In 2025, consumers spent more on non-game apps than on games for the first time: **$85.5B, up 21% YoY**. Generative-AI apps alone approached about $5B ([Sensor Tower](https://sensortower.com/press/press-release-boosted-by-gen-ai-services-consumers-spent-more-money-in-apps-than-games-for-first-time), [TechCrunch](https://techcrunch.com/2026/01/21/consumers-spent-more-on-mobile-apps-than-games-in-2025-driven-by-ai-app-adoption/)). Appfigures names productivity among the categories leading growth ([WebProNews](https://www.webpronews.com/global-mobile-app-downloads-drop-2-7-in-2025-spending-surges-21-6)). I found no credible, sourced size for the time-blocking segment itself.

**ADHD and time blindness is a large segment that pays.** The CDC estimates that **6.0% of US adults (about 15.5M) have a current ADHD diagnosis**, about 56% of them diagnosed as adults ([HealthDay](https://www.healthday.com/healthpro-news/neurology/155-million-adults-had-current-adhd-diagnosis-in-2023), [CHADD](https://chadd.org/about-adhd/general-prevalence-adults/)). Tiimo reported **500K+ users and about 50K paying** in 2024 ([Tech.eu](https://tech.eu/2024/08/28/neurodivergent-focused-app-tiimo-secures-16m-in-funding-round/)). It then won **iPhone App of the Year 2025** ([App Store](https://apps.apple.com/us/app/tiimo-to-do-list-planner/id1480220328)), so Apple's editors clearly favour this category.

**Trends, 2024–2026:**
1. **AI scheduling agents are spreading.** Dropbox bought Reclaim in 2024 ([TechCrunch](https://techcrunch.com/2024/08/22/dropbox-acquires-index-ventures-backed-ai-scheduling-tool-reclaim-ai/)). Gemini now schedules and resolves conflicts across Workspace ([Google, Sep 2026](https://workspaceupdates.googleblog.com/2026/09/create-content-schedule-events-and-coordinate-tasks-across-Workspace-regardless-of-what-app-you-are-in.html)). ChatGPT can create and edit iCloud Calendar events as of Oct 27, 2026 ([Digital Trends](https://www.digitaltrends.com/computing/chatgpt-finally-gets-the-icloud-mail-and-calendar-plugins-users-have-been-waiting-for/)). Every planner now advertises AI.
2. **The OS is absorbing basic entry.** iOS 27 adds natural-language entry in Calendar and Reminders, gives Siri full calendar access, and turns screenshots into events ([MacRumors](https://www.macrumors.com/2026/06/08/ios-27-calendar-reminders/)). *Getting events in is commoditised; the value is now in running and adapting the plan.*
3. **Ambient surfaces are maturing.** iOS 27 brings Live Activities in landscape Dynamic Island, full-screen widgets, and real-time widget updates ([iClarified](https://www.iclarified.com/101152/here-are-the-263-new-features-revealed-in-apples-massive-wwdc-2026-slide)). Structured and Llama Life already ship Live Activities.
4. **On-device AI is available to apps.** Apple's Foundation Models framework, from iOS 26, gives apps a free on-device LLM with tool calling ([overview](https://blakecrosley.com/blog/apple-foundation-models-framework)).
5. **Visual timers for ADHD are an established need.** The App Store has many single-purpose "time blindness" timers, but few connect a timer to a real calendar.

---

## 2. Competitor matrix

Abbreviations: LA = Live Activity. "?" = not verified. US prices, 2026.

| App | Core idea | Minute-level? | Focus timer? | AI | LA | Platforms | Price | Strengths | Weaknesses (reviews) |
|---|---|---|---|---|---|---|---|---|---|
| **Structured** | Visual timeline planner | Yes (5–15-min steps) | Pomodoro | Drafts a plan from plain English; Siri | Yes | Apple, Android, web | Free; Pro $6.99/mo, $29.99/yr, $99.99 lifetime ([App Store](https://apps.apple.com/us/app/structured-daily-planner-todo/id1499198946)) | 4.8★ / 169K; polished; cheap | Overlaps fixed by hand; AI draft can't be edited before commit; dragging feels fiddly |
| **Tiimo** | Visual planner for neurodivergent users | Yes, plus untimed | Countdown | AI Co-Planner (brain dump → plan) | ? (Lock Screen timer widgets) | iOS/Watch, Android, web | Pro $12/mo, $54/yr ([App Store](https://apps.apple.com/us/app/tiimo-to-do-list-planner/id1480220328)) | App of the Year; ADHD trust | Weak notifications; timers auto-start at clock time; bugs after updates |
| **Sunsama** | Guided daily planning ritual | Timeboxing | Focus mode | Limited | ? | Web, desktop, mobile | ~$17–20/mo annual; no free plan ([Morgen](https://www.morgen.so/blog-posts/sunsama-pricing), [Carly](https://www.usecarly.com/blog/sunsama-review/)) | Calm workflow | Expensive; mobile is secondary |
| **Motion** | AI auto-scheduler | Auto-placed | No | Auto-scheduling, daily agenda | No | Web, desktop, mobile | iOS $44.99/mo, $294.99/yr ([App Store](https://apps.apple.com/us/app/motion-tasks-ai-scheduling/id1580440623)); web ~$19–29/mo annual ([Morgen](https://morgen.so/blog-posts/motion-pricing)) | "Reshuffles your entire day" ([Motion](https://usemotion.com/calendar)) | No widgets; few notifications; unpredictable placement; 4.1★ |
| **Reclaim** (Dropbox) | AI that protects time for habits and tasks | Calendar blocks | No | Auto-scheduling | No | Web, via your calendar app | Free; Starter ~$10/mo ([SchedulingKit](https://schedulingkit.com/pricing-guides/reclaim-ai-pricing)) | Set-and-forget | Not built for running the day on a phone |
| **Akiflow** | Universal inbox + time blocking | Yes | No | Aki assistant | ? | Desktop, web, mobile | $34/mo or ~$19/mo annual ([Morgen](https://www.morgen.so/blog-posts/akiflow-pricing)) | Fast capture | Mobile "laggy and glitchy" (React Native) ([Carly](https://www.usecarly.com/blog/akiflow-review/)) |
| **Amie / Notion Calendar** | Calendar with to-dos (Amie) or Notion databases (Notion) | Yes | No | Amie: AI meeting notes; Notion: none | ? | Amie Mac/iOS; Notion all | Amie ~$20/mo annual ([Ellie](https://ellieplanner.com/productivity-copilot/amie-app-pricing)); Notion free ([AISO](https://aisotools.com/blog/notion-calendar-review-2026)) | Design; free (Notion) | Amie has moved to meeting notes ([Nocal](https://nocal.app/alternatives/amie)); Notion requires Notion |
| **Fantastical** | Power-user calendar | Event-level | No | Natural-language parsing | ? | Apple (+Win) | ~$4.75/mo annual ([Morgen](https://morgen.so/blog-posts/fantastical-pricing)) | Best parsing and polish | Doesn't help you run the day |
| **Llama Life** | One task at a time, each with a countdown | Yes (per-task minutes) | Per-task countdown + overtime | Emoji matching | Yes | iPhone, Android, web | $6/mo, $39/yr ([App Store](https://apps.apple.com/us/app/adhd-organizer-llama-life/id6454469750)) | **Closest timer model** | No calendar anchoring; buggy; hard paywall |
| **Routine** | Calendar + tasks + notes | Yes | ? | v2.0 voice, agents | ? | Desktop, web, iOS | Free core; ~$5–8/mo ([Ellie](https://ellieplanner.com/productivity-copilot/routine-app-pricing)) | All-in-one | 3.6★ on iOS |
| **Todoist** | Task manager | Due times and durations | No | AI assist | No | All | Pro $5/mo annual ([Routine](https://routine.co/blog/posts/todoist-pricing)) | Everywhere | Not time-blocking |
| **Things 3** | Elegant Apple task manager | Reminder times | No | None | No | Apple | $9.99 one-time on iPhone ([Toolradar](https://toolradar.com/tools/things-3/pricing)) | Design | No time blocking or AI |
| **Apple Calendar/Reminders** (iOS 27) | Built-in default | Event times | No | Natural-language entry, Siri | System | Apple | Free | On every iPhone | No timers, no replanning |
| **Google Calendar** (Gemini) | Built-in default | Event times | No | Suggested times, cross-app scheduling | No | All | Free | Huge reach | Built for meetings |

Adjacent focus tools: **Flow** ($2.99/mo, $17.99/yr, $39.99 lifetime; [App Store](https://apps.apple.com/app/id1423210932)) and **Opal** ($19.99/mo, $99.99/yr; [Autonomous](https://www.autonomous.ai/ourblog/opal-app-review)). Both offer timers or blocking without a plan behind them.

**Takeaway:** no app combines (a) a **start-anchored** live countdown on the Lock Screen and in Dynamic Island, (b) **calendar-aware reflow when you drift**, and (c) an **AI that asks before it changes anything**. Structured is the closest overall, and Llama Life is the closest on the timer model.

---

## 3. User pain points

1. **The plan doesn't adapt when you drift.** *"Have everything bump forward accordingly, rather than having to hand slide it to eliminate overlaps"* ([Structured](https://apps.apple.com/us/app/structured-daily-planner-todo/id1499198946)). *"No way to snooze a task or have it roll into the following day"* ([Tiimo](https://apps.apple.com/us/app/tiimo-to-do-list-planner/id1480220328)).
2. **The opposite problem: AI moves things without asking.** Motion keeps a help article titled *"Tasks Not Scheduling Where You Expect?"* ([Motion help](https://help.usemotion.com/tasks-events-and-auto-scheduling-101/tasks-not-scheduling-where-you-expect-heres-whats-actually-happening)). Reviewers write: *"The AI just dumps tasks into available timeslots"* and *"my entire calendar deleted unprompted"* ([Motion](https://apps.apple.com/us/app/motion-tasks-ai-scheduling/id1580440623)).
3. **Notifications are too weak, unreliable, or stale.** *"The quick ding isn't enough to get my attention and move on to the next task."* *"When I complete a task early, I'll still get a reminder"* ([Tiimo](https://apps.apple.com/us/app/tiimo-to-do-list-planner/id1480220328)). Motion: *"little to no notifications and zero customisability."* Structured shipped a fix for missing notifications ([changelog](https://feedback.structured.app/changelog/structured-423-bug-fixes)).
4. **Timers are tied to the clock, not to the person.** *"Tasks that were scheduled for a time would automatically start a timer at that time whether I wanted it to or not"* ([Tiimo](https://apps.apple.com/us/app/tiimo-to-do-list-planner/id1480220328)). Llama Life users asked for *"the timer… to show and continue running in the Lock Screen"* ([Llama Life](https://apps.apple.com/us/app/adhd-organizer-llama-life/id6454469750)). **The client's start-anchored timer fills exactly this gap.**
5. **Entering and editing tasks takes too many taps.** *"Too many… clicks involved in creating a task"*; tasks *"don't seem to 'stick'"*; users want drag-to-resize ([Structured](https://apps.apple.com/us/app/structured-daily-planner-todo/id1499198946)).
6. **AI output is hard to control or too literal.** *"No option to edit what AI came up with without first adding the events to your day"* (Structured). Tiimo's AI is *"making tasks for exactly what I say"* when the user needed the work broken down. Good conversational AI does get praised: Akiflow's assistant *"feels like I'm talking to a person"* ([Carly](https://www.usecarly.com/blog/akiflow-review/)).
7. **Poor quality and paywall surprises.** Akiflow's mobile app is *"laggy and glitchy"*. Llama Life users *"can't use it AT ALL without a paid subscription."* Users also ask for *"2-way sync with Apple Calendar/Google Calendar"* (Tiimo).

---

## 4. Personas

**P1: Maya, 29, product manager with ADHD (primary)**
- *Goals:* start on time, notice time passing, get through transitions.
- *Frustrations:* hyperfocus makes her late; one "ding" is too weak; apps that make her feel guilty for being behind.
- *Where the app wins:* At 1:58 she taps **Start** on "Write spec (2:00–3:00)", and Dynamic Island counts down 60:00 to 2:58. At 2:53 she gets a strong haptic and the Live Activity changes colour. She taps **+10** on the Lock Screen and gets *"Push 'Standup prep' and 'Email' by 10 min?"* One tap fixes it.

**P2: Dev, 36, freelance designer**
- *Goals:* minute-level client blocks; planned versus actual time; keep the 5 pm gym slot.
- *Frustrations:* call overruns wreck the afternoon; Motion is too expensive and unpredictable.
- *Where the app wins:* He types into the AI tab: *"I'm 20 late, keep gym, shorten what's flexible."* It asks *"Shorten Invoicing from 30 to 15 min, or move it to tomorrow?"*, shows a before/after diff, and applies it on **Approve**.

**P3: Sofia, 23, medical student**
- *Goals:* long study blocks with Pomodoro cycles inside; cheap; StandBy on her desk.
- *Frustrations:* her timer app and planner app don't share state.
- *Where the app wins:* A 2-hour "Pharm review" block runs as a Live Activity with a 25/5 cycle inside it. Completing it updates the Home cards automatically.

**P4: Priya, 41, working parent**
- *Goals:* tight logistics; reliable 5-minute heads-ups; shared family calendar.
- *Frustrations:* typing on the go; reminders that fire after the task is done.
- *Where the app wins:* She dictates *"Dentist Thursday after school, soccer moved to 5."* The AI asks *"Which child? How long?"* and writes to her iCloud family calendar.

---

## 5. Positioning

**Positioning statement:** *For people who plan by the minute and keep slipping behind, [Name] is the iPhone planner that starts when you do. Every block becomes a live countdown, your day reflows in one tap when life runs late, and an AI co-pilot changes nothing without asking.*

**Differentiators:**
1. **Start-anchored timers.** The countdown runs for the planned duration from the moment you start (start at 1:58, end at 2:58). This contrasts with Tiimo's clock-triggered timers and Structured's clock-bound blocks.
2. **Drift-aware reflow, always with consent.** The app offers to shift, compress or skip upcoming tasks and never changes the plan silently (unlike Motion).
3. **"Now / Last / Next 2" home plus an interactive Live Activity.** The Home screen works like a departures board. Pause, add time or complete from the Lock Screen or Dynamic Island.
4. **An AI that asks first.** Clarifying questions, a diff preview, one-tap undo, and templates such as "I'm running late", "Fit in…" and "Plan my morning".
5. **Native, private and affordable.** SwiftUI (Akiflow's top complaint is React Native). No account and no server. A fraction of Motion's price.

**Wedge feature for launch:** **Live Block + Reflow.** It can be demoed in 10 seconds, it fills the most-cited review gap, and iOS 27's AI does nothing similar. The AI tab amplifies it (*"I'm 20 late, fix my afternoon"*) but should not lead the marketing, because "AI planner" is now a crowded claim.

---

## 6. Monetization & pricing

**Competitor price bands (annual-equivalent per month):**
- *Budget, around $3–4:* Structured ($29.99/yr), Llama Life ($39/yr), Flow.
- *Mid, around $4.50–5:* Tiimo ($54/yr), Todoist, Fantastical.
- *Premium AI, $17–25:* Sunsama, Akiflow, Motion (Motion's iOS in-app price works out to $24.58/mo).

| Tier | Price | Contents |
|---|---|---|
| **Free** | $0 | The full wedge: unlimited tasks, start-anchored timer, Live Activity, notifications with a custom lead time, Calendar/Reminders sync, Home screen, 2 widgets. |
| **Pro** | **$6.99/mo · $39.99/yr** (7-day trial on annual); launch-only Founders lifetime at $99 | Smart reflow rules, multi-stage alerts, routines and templates, planned-vs-actual analytics, Pomodoro inside blocks, all widgets, Watch, themes, **AI via BYOK** |
| **Pro + AI** (v1.x) | **$9.99/mo · $79.99/yr** | Pro plus bundled AI with fair use (for example, 500 small-model actions and 50 "deep plans" a month). No API key needed. |

**Rationale:** $39.99/yr sits above Structured and below Tiimo, justified by the timer, reflow and native AI, and it avoids the hard-paywall backlash Llama Life gets. Pro + AI undercuts Motion, Sunsama and Akiflow by roughly 3–4×.

**BYOK versus bundled AI:**
- BYOK costs us nothing in AI and needs no backend, so it suits v1 and power users. Its downsides are consumer onboarding (an OpenAI account plus API billing) and App Review risk (see §8).
- Bundled credits are the mass-market path and need a thin proxy. A managed iOS AI proxy such as [AIProxy](https://aiproxy.com/), with App Attest and StoreKit checks, avoids running our own servers.
- Optional: use Apple's on-device Foundation Models for free natural-language quick-add. This departs from the "OpenAI only" brief, so the client must decide.

**Unit economics, from [OpenAI pricing](https://developers.openai.com/api/docs/pricing) as of 2026-11-07, per 1M tokens:**
- **GPT-6 Luna:** $0.10 in, $0.50 out ("most efficient… high-volume", supports function calling; [models](https://developers.openai.com/api/docs/models)).
- **GPT-6.1 Terra:** $1 in, $5 out.
- **GPT-6.1 Sol:** $2 in, $10 out.
- Cache writes are now billed (Luna: $0.125 for a 30-minute write), so occasional phone usage gains little from caching.

A typical calendar edit is about 7.5K input tokens (system prompt and tool schemas around 2K, roughly 3 days of events around 1K, history, two model calls in the tool loop) and about 1K output tokens:

| Model | Per request | Typical user (90/mo) | Heavy user (450/mo) |
|---|---|---|---|
| Luna | ~$0.00125 | ~$0.11 | ~$0.56 |
| Terra | ~$0.0125 | ~$1.13 | ~$5.63 |
| Sol | ~$0.025 | ~$2.25 | ~$11.25 |

- **Voice input** adds about $0.001 per 15-second clip (`gpt-transcribe`, $0.0045/min).
- **Default to Luna** and escalate to Terra only for "plan my week" requests. The blended cost is under $2 per heavy user per month.
- **Margin check:** Pro + AI nets about $8.49 after Apple's 15% Small Business rate ([RevenueCat](https://www.revenuecat.com/blog/engineering/small-business-program)), a gross margin above 75%.
- **BYOK marketing line:** "typical use costs pennies a month."

---

## 7. Naming

These were quick App Store and web checks in Nov 2026. Run trademark (USPTO/EUIPO), domain and handle checks before committing.

| # | Name | Rationale | Conflicts found |
|---|---|---|---|
| ★1 | **Dayflight** | Your day as a flight plan: what's boarding next, in flight now, landed. Fits the "Fly" codename and the departures-board Home screen. | No app named Dayflight found. Sounds like "Daylight"; aviation focus timers exist ([Plane Focus](https://apps.apple.com/ae/app/plane-focus-flight-timer/id6757431152), [Focus Flight](https://lifestack.ai/blog/focus-flight-app)). **Low.** |
| ★2 | **Glidepath** | The path that lands you on time; suggests gentle correction when you drift. | Tiny "Glidepaths" (finance) and an ASTB test-prep app; also an investing term. **Low in Productivity.** |
| 3 | **Takt** | From "takt time", the beat of work. Short and modern. | Small Productivity apps ("Takt – Time Tracking", "Takt: Recurring Task Tracker"). **Medium**: needs a suffix. |
| 4 | **Segue** | Smooth transitions, the core ADHD pain. | "Segue: Stage Timer" (no ratings); pronunciation ambiguous. **Low–Medium.** |
| 5 | **Flyday** | Codename pun: fly through your day. | Flyday travel app ([App Store](https://apps.apple.com/us/app/id1683507477)). **Medium.** |
| 6 | **Blocktime** | Aviation "block time" (gate-to-gate duration) plus time blocking. | Pilot logbooks ([Blocktime](https://apps.apple.com/de/app/blocktime/id1501011792)); too descriptive to trademark easily. **Medium.** |
| 7 | **Contrail** | The trail behind you, like the "Last task" card. | Travel and flight-tracker apps ([App Store](https://apps.apple.com/qa/app/contrail/id6752272792)). **Low–Medium.** |
| 8 | **Kairos** | Greek for "the right moment". | Kairos Calendar in Productivity ([App Store](https://apps.apple.com/us/app/id443777187)). **High.** |
| 9 | **Nowline** | The "now" line on a timeline. | **Taken in this exact space**: an Android time-blocker ([Play](https://play.google.com/store/apps/details?id=com.nowline)), a macOS menu-bar time-blocker ([macmenubar](https://macmenubar.app/app/nowline)), and an AI planner ([nowline.org](https://www.nowline.org/)). **Avoid.** |
| 10 | **Tempo** | The rhythm of your day. | "Tempo: ADHD Calendar & Planner" is live ([App Store](https://apps.apple.com/us/app/tempo-adhd-calendar-planner/id6762128596)). **Avoid.** |

Also rejected: Daybeat (an existing GTD app), Pacely (an existing energy planner), Flightline (pilot logbooks, plus a "Flowline" planner).

---

## 8. Go-to-market and key risks

**Go-to-market:**
- **Community beta.** Run a TestFlight beta with ADHD communities, coaches and creators. They are the category's loudest reviewers, and they pay.
- **Aim for Apple featuring.** Use every system surface: interactive Live Activities, widgets, App Intents and Siri, StandBy, Watch Smart Stack, and Liquid Glass. Submit the featuring nomination 6–8 weeks before launch.
- **Lead with a 10-second hero video:** "Tap Start → Dynamic Island countdown → 'Running 7 min late, shift 3 tasks?'" for TikTok, Reels and Shorts.
- **Indie press:** MacStories, 9to5Mac's indie spotlight, The Sweet Setup, and Product Hunt.
- **App Store search terms:** "time blocking", "ADHD planner", "visual timer", "pomodoro".
- **Launch offers:** a Founders lifetime deal and month-for-month referrals.

**Key risks:**

| Risk | Detail | Mitigation |
|---|---|---|
| **App Review: BYOK** | A BYOK app was rejected under **3.1.1** because it "uses API keys to unlock or enable functionality" ([Apple forums](https://developer.apple.com/forums/thread/763884)). Others are live ([Geeps](https://apps.apple.com/dk/app/id6476961115), [opchat](https://apps.apple.com/us/app/id6761932211)), so enforcement is inconsistent. | Make the core app fully useful without AI. Sell paid features only through in-app purchase. Say "connect your OpenAI account", never "unlock". Give App Review a demo key or demo mode (2.1). Ship the in-app-purchase AI tier soon after launch. |
| **App Review: privacy** | **5.1.2(i)**: apps must "clearly disclose where personal data will be shared with… third-party AI, and obtain explicit permission" ([Guidelines, Oct 16, 2026](https://developer.apple.com/app-store/review/guidelines/)). | A consent screen before the first AI call; send the minimum calendar context. OpenAI API data is not used for training by default and is kept up to 30 days for abuse monitoring ([OpenAI](https://developers.openai.com/api/docs/guides/your-data)). |
| **Model churn** | `gpt-5-mini`/`nano` retire Dec 11, 2026; `gpt-4o-mini`/`gpt-4.1-mini` retire Jan 14, 2027; the Assistants API is gone ([deprecations](https://developers.openai.com/api/docs/deprecations)). | Use the Responses API; load the model ID from remote config (static JSON on a CDN) with a fallback chain. |
| **Platform: Sherlocking** | iOS 27, ChatGPT and Gemini now create calendar events directly. | Compete on execution (timers, reflow); also be a Siri and App Intents target. |
| **Platform limits** | Live Activities last about 8 hours, plus up to 4 hours on the Lock Screen ([guide](https://newly.app/guides/ios-live-activities)). Apps can have at most **64 pending local notifications** ([Apple forums](https://developer.apple.com/forums/thread/811171)), which a dense schedule with 5-minute alerts can hit. | Use system-rendered timer text; schedule notifications on a rolling window. These need feasibility work in the feature plan. |
| **AI trust** | One wrong bulk edit destroys trust (Motion's "deleted unprompted"). | Approve-before-apply, undo, an AI change log, no bulk deletes without confirmation. |
| **Copycats** | Structured (169K ratings) could copy start-anchored timers. | Speed on reflow and AI quality; planned-vs-actual habit loops; design that is hard to copy. |
| **Notification fatigue** | Complaints run both ways: too weak and too many. | Per-task alert styles; escalate only for "anchor" tasks; quiet automatically during Focus modes. |
