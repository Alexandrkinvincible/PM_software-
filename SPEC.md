# PM Controller — SPEC

**Name:** PM Controller. Locked. Bundle identifier `com.apexmech.pmcontroller`.
**Owner:** Apex Plumbing and Mechanical Services SC. Alex Kulikov, principal.
**Standing:** Apex owns the software outright — see `LICENSE`, and the copyright header on
every source file. PCM is a pilot customer, not a co-owner. Apex owns the product; a customer
owns its own records. That split belongs in writing before any customer data is entered.
**Pilot customer:** Paulson Cheek Mechanical (PCM).
**Client platform:** native iOS / iPadOS (SwiftUI). **Tablet first.** See §9.

This file is authoritative. Where an instruction conflicts with it, the conflict is raised
rather than guessed at. Decisions land here as they are made; `docs/DECISIONS.md` records
what was assumed and why.

---

## 1. Purpose

Commercial mechanical crews already track tasks in Fieldwire, but nobody can answer, on demand:

- How many man-hours did we burn vs. earn, by system and area?
- How much of that was rework, and how much was our own error found after sign-off?
- What did we get paid extra for, and what are we doing on an unapproved promise?
- Are we ahead or behind the GC's schedule, and when we were blocked, who blocked us?

This app makes those numbers a by-product of work the crew already does: assign a task, clock
in on it, photograph it, close it out. No separate reporting step.

---

## 2. Non-negotiable principles

These drive the data model. Do not violate them for convenience.

1. **Six core statuses are locked in the database.** They cannot be renamed, reordered or
   deleted by any role. Every report reads core status, never a column name.
2. **Custom board columns map to exactly one core status.** Flexibility on the board,
   untouched reporting underneath.
3. **Hours are per person, never typed at task level.** The Lead sets start/end and selects the
   crew present; the system writes one `time_entries` row per person. Task hours are always a SUM.
4. **Change-order hours never count against the base estimate.** Work nobody estimated must not
   make the crew look slow.
5. **Review rework and discovered defects are different things.** Rework is caught before
   sign-off. A defect is found after. Tracked separately.
6. **History is never rewritten.** An Accomplished task stays Accomplished; a later defect links
   back to it.
7. **Every progress-page number is a stored filter, not a computed blob.** Clicking any figure
   returns the ticket list behind it. Build this way from Phase 1 — retrofitting drill-down is
   expensive.
8. **Row-level security in the database, not the UI.** A Foreman querying directly must not see
   another Foreman's receipts.
9. **Deactivate, never delete users.** Historical tasks and time rows must keep resolving to a
   real person.

---

## 3. Roles & access

No self-registration. An admin creates a user by email + role + project assignment; credentials
are issued and the password must be changed at first login.

| Role | Admin | Create / assign | Kick to Rework | Approve Accomplished | Approve CO | Material page |
|---|---|---|---|---|---|---|
| Manager | Yes | Yes | Yes | Yes | Yes | Full table, all projects |
| PM | No | Yes | Yes | Yes | Yes | Full table (own projects) |
| Assistant PM | No | Yes | Yes | No | No | Full table (own projects) |
| Supervisor | No | Yes | Yes | Yes | No | Own uploads only |
| Assistant Super | No | Yes | Yes | Yes | No | Own uploads only |
| Foreman | No | Assign to Leads | Yes | No | No | Own uploads only |
| Lead | No | No | No | No | No | No access |

- Assistant Super is a full clone of Supervisor.
- Assistant PM is a PM minus the two actions with money or finality attached: final sign-off and
  change-order approval. Full material cost visibility is retained.
- Roles are assigned **per project**: the same person can be Super on one job and Foreman on another.

---

## 4. Status flow

```
OPEN → ASSIGNED → IN PROGRESS → REWORK ⇄ REVIEW → ACCOMPLISHED
```

| Transition | Who | What happens |
|---|---|---|
| Create → Open | PM, Asst PM, Super, Asst Super, Foreman | Task created against project, area, system. Est. hours + est. quantity set. |
| Open → Assigned | PM, Asst PM, Super, Asst Super | Assigned to a Foreman, who re-assigns to a Lead. |
| Assigned → In Progress | Lead | Lead sets start time and selects crew present. One time row opens per person. |
| In Progress → Review | Lead | End time, quantity installed, photos, description. Time rows close. |
| Review → Rework | PM, Asst PM, Super, Asst Super, Foreman | Reason required, punch photos optional. Writes a `rework_items` row. Push notification fires to the assigned Lead immediately. |
| Rework → In Progress | Lead | New session. All hours from here are flagged `is_rework`. |
| Rework → Review | Lead | Resubmitted with corrective photos. Loop repeats if rejected again. |
| Review → Accomplished | PM, Super, Asst Super, Manager only | Locked to final data. Searchable by date, name, area, system, rework count. |

Rework ⇄ Review loops as many times as needed. Every kick-back writes its own row, so repeat
rejections become a visible number (`rework_count`).

### 4a. Custom columns

Each project defines its own board columns, but every custom column maps to exactly one locked
core status. Cards move freely between custom columns inside the same core status; crossing a
core status boundary still fires the same role gates and writes to `task_events`.

| Example custom column | Maps to | Effect |
|---|---|---|
| Waiting on GC / other trade | In Progress | Sets blocked flag; starts the blocked-days clock, attributed to the responsible trade |
| Material on order | In Progress | Blocked flag; blocked reason = material |
| Ready for inspection | Review | Sits in Review; no hours accrue |
| Punch list | Rework | Hours flagged rework automatically |

---

## 5. Data model

Implemented in `supabase/migrations/0001_schema.sql`. Policies in `0002_rls.sql`.

`users` · `companies` · `projects` · `project_members` · `board_columns` · `tasks` · `task_crew` ·
`time_entries` · `task_media` · `rework_items` · `notifications` · `schedule_baselines` ·
`blocked_periods` · `material_categories` · `receipts` · `receipt_lines` · `task_events` ·
`saved_filters`

Fixed lists, never free text:

- **Root cause:** layout error · dimension misread · coordination miss · spec change · damage by others
- **Cost class:** base · change order · our cost
- **Work class:** first-time · review rework · discovered defect
- **Cost responsibility:** our cost · GC/owner · other trade
- **Blocked party:** GC · other trade · material · owner · us
- **Material categories:** Pipe & fittings · Valves & specialties · Hangers & supports ·
  Fixtures & trim · Insulation · Hardware & fasteners · Consumables · Tools · Equipment rental ·
  Freight & delivery · Other (a table, not an enum, because the PM may edit it; constrained by
  foreign key so it can never become free text)

`task_events` records every status change with no exceptions. The audit trail is the product.

---

## 6. Material page (separate from tasks)

- Upload a photo or PDF; extraction pulls vendor, date, invoice number, and line items.
- Each line auto-categorised. Low confidence → Needs Review queue, never a silent guess.
- Duplicate detection on vendor + date + total — the same receipt gets photographed by two
  people constantly.
- Fast manual-correction screen. Thermal-paper OCR is unreliable; corrections are routine, not
  exceptional.
- Optional project / area / cost-class tag per receipt. No task link.
- Views: totals by category, vendor, month, project — all drillable to line level.
- Price history per item across vendors over time.

---

## 7. Progress page (read-only, every number clickable)

- Hours earned vs. burned by area and system — base contract only
- Change orders: approved value and hours; unapproved CO hours with aging
- Rework %: rework hours ÷ total, trended weekly, by system
- Kick-back count: tasks rejected more than once, reasons grouped
- Discovered defects: count, hours, cost, days-after-sign-off, root cause grouped
- Schedule variance vs. current GC baseline and vs. original baseline
- Blocked days by responsible party
- In-house vs. contractor split: hours and dollars
- Cost to complete
- Aging: tasks in Review, in Rework, In Progress past estimate

Every figure links to its ticket list — task, area, system, lead, hours, work class, cost class,
each row opening the ticket.

---

## 8. Reporting culture rules (build these in, not just policy)

1. Defects are logged by whoever finds them, not whoever caused them.
2. Defect rate is never displayed as a metric on any individual's page. Report by system, area
   and phase — never a leaderboard by Lead.
3. Logging a defect is a record, not a trigger. Conversations come from monthly patterns.
4. Rework reasons describe the condition, not the person.

---

## 9. Stack

**Changed from the original spec.** The original called for a React mobile-first PWA. The client
is now a **native iOS app**. Nothing else moved: the backend, the schema, the policies and every
principle above are unchanged, because they never depended on the client.

- **Supabase** — Postgres, auth, row-level security, storage for photos and receipts.
  Unchanged from the original spec.
- **SwiftUI, iOS/iPadOS 18 and newer**, one binary for both. **Tablet is the design target**;
  the phone layout follows from it by size class. A tablet rotates freely; a phone stays
  portrait, because that one is used one-handed on a ladder.

  A deployment target is a *minimum*, not a maximum: an 18.0 floor runs on 18, 26 and everything
  after. **There is no iOS 19–25** — Apple switched to year-based numbering in 2025 and went
  from 18 straight to 26. 18 is the 2024 release, and the floor is set there deliberately: it
  keeps `@Observable`, `#Preview` and the modern SwiftUI surface rather than writing to an older
  dialect. See `docs/DECISIONS.md` A5.
- **supabase-swift** for auth, PostgREST and storage. The app ships the anon key only; every
  query carries the signed-in user's JWT, so the policies in `0002_rls.sql` are what decides.
- **Supabase Edge Functions** for anything needing the service-role key. Today that is one
  function: `admin-create-user`.
- **SwiftData** for the offline queue (Phase 3+). A close-out written with no signal is held
  locally and replayed; it is never lost.
- **APNs** via Supabase for rework notifications. This is the reason for the platform change:
  the original plan flagged web push on crew phones as a live risk, and on iOS it is the one
  delivery path that is not a gamble. SMS stays available as a fallback.

Why native rather than the PWA, in one line each:

| Requirement (from the original plan) | PWA on iOS | Native |
|---|---|---|
| Rework notification must reach the Lead with the app closed | Fragile; needs the app added to the Home Screen first | APNs, reliable |
| Close-out under 60 seconds, camera one tap | File-picker detour | Direct camera |
| Offline tolerance — a close-out with no signal must not be lost | Storage evicted under pressure | SwiftData, survives |
| Crews shoot 12 MP images all day | JS-side compression | Hardware pipeline |

The cost of the change is honest: no Android, and App Store review on every release. Accepted
deliberately.

**What it does not cost.** The $99/yr Apple Developer Program is needed only to put the app on
*other people's* devices — TestFlight or the App Store. It is not needed to build, to run in a
Simulator, or to install on a device you own yourself (a free Apple ID signs for 7 days at a
time). The real prerequisite is a Mac, and even that is partly covered: CI builds the app on a
macOS runner and publishes screenshots of it running on an iPad as an artifact of every run
(§14), so the work is visible before anyone buys anything.

---

## 10. Build constraints

- **Tablet layout first**, phone second, laptop later. Desktop is out of scope for v1.
- **Task close-out must take under 60 seconds.** Crew pre-selected, camera one tap, quantity one
  field. If it takes longer, it will not happen in the field.
- **Offline tolerance** — a close-out on a job with no signal must not be lost.
- Photo compression on upload — crews shoot 12 MP images all day.
- No direct editing of hours anywhere. Only start/end times and crew selection.
- Core statuses enforced by DB constraint, not hidden UI.
- CSV export from every table. Nothing trapped.

---

## 11. Out of scope for v1

No scheduling engine, no invoicing, no payroll export, no Fieldwire API integration, no Android.
Those are Phase 10+, only if the pilot earns them.

---

## 12. Phase plan

| Phase | Deliverable | Done when |
|---|---|---|
| 0 | Plan, model, flow, checklist | Package issued |
| 1 | Schema + admin user setup + auth + RLS | Admin creates a Lead by email; that Lead sees only his project and no material page |
| 2 | Task board, columns, role-gated transitions | A Lead cannot move a task to Accomplished |
| 3 | Time capture — crew selection, per-person rows | One session with 3 crew writes 3 rows |
| 4 | Photos, description, quantity at close-out | Task closes with a photo from a phone in the field |
| 5 | Review gate + Rework column + push notifications | Rejected task lands in Rework and the Lead's phone buzzes |
| 6a | Cost class + change orders; custom board columns | CO hours excluded from base earned value |
| 6b | Schedule fields, GC baselines, blocked periods | Blocked days attribute to a named party |
| 6c | Work class + discovered defects with source-task links | A defect ticket links back to an Accomplished task |
| 6d | Material page — upload, extraction, categories, price history | A photographed receipt lands categorised, duplicates caught |
| 7 | Progress page, every number drillable | Clicking any figure returns its ticket list; numbers reconcile to a hand-check of one week |
| 8 | Pilot on a fresh PCM job — Alex + Leads | Two full weeks run without paper backup |
| 9 | Closeout package — results, improvements, business case | Final PDF issued |

---

## 13. Open questions

- Burdened rates: real figures from PCM, or placeholder multipliers until shared.
- Does the GC issue a schedule that can be imported, or are milestone dates entered by hand per area?
- Will PCM share estimated hours per system, or only total contract hours?
- Should Supervisor have wider material visibility than Foreman?
- Written sign-off from PCM ownership before any PCM data lives in a system you own; data
  ownership if the relationship ends.
- Which iPads and iPhones do the crews actually carry? The floor is iOS/iPadOS 18. Anything
  that cannot reach 18 is out, deliberately.
- Does Apex control the `apexmech.com` domain? The bundle identifier `com.apexmech.pmcontroller`
  assumes a reverse-DNS name Apex owns. Cheap to change now, awkward after App Store submission.



---

## 14. Continuous integration

Three jobs on every pull request (`.github/workflows/ci.yml`):

| Job | Runner | What it proves |
|---|---|---|
| Row-level security | ubuntu | Applies both migrations to a real Postgres 16 and runs the 56 assertions. Principle 8 stops being a claim and becomes a gate. |
| Build for iPad | macOS | The Swift compiles. Nobody needs a Mac for this to be true. |
| Screenshots on iPad | macOS | Boots an iPad simulator, launches the app as each role, and uploads photographs of every screen as a downloadable artifact. |

GitHub's macOS runners are free on public repositories, which is what makes the second and third
jobs practical.

The screenshot job runs the app in **preview mode** — a launch argument that loads the canned
people in `ios/PMController/Core/PreviewData.swift` instead of calling Supabase. That data is
deliberately the same shape as `supabase/seed.sql`, including the man who is Super on one job and
Foreman on another, so a screenshot is a fair picture rather than a flattering one. Nothing in
the UI can switch preview mode on.
