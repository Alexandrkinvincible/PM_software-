# Decisions and assumptions

Every choice made that SPEC.md did not settle, and every correction made to the reviewed schema
draft. The kickoff prompt asked for assumptions to be logged rather than silently decided; this
is that log.

---

## A. Name, standing, platform

**A0 — The app is called PM Controller, and it is a product, not an Apex tool.**
Decided by the owner. Bundle identifier `com.pmcontroller.app`. Everything Apex-branded is out:
the demo company in `supabase/seed.sql` is now "Meridian Mechanical" and the demo client
"Northside Construction Group", so nothing in the repo implies one contractor owns it. The repo
directory name (`PM_software-`) is unchanged because renaming it breaks existing clone URLs; it
is cosmetic and can be changed later from GitHub's settings if wanted.

**A1 — Native iOS instead of a React PWA.**
Decided by the owner. SPEC §9 is updated accordingly and the trade-off is written out there in
full. Nothing below the client changed: the schema, the policies and all nine principles are
untouched, because none of them depended on the client.

**A2 — iOS/iPadOS 17 minimum. Tablet first, phone second, laptop later.**
Decided by the owner: start with the tablet. One binary covers both
(`TARGETED_DEVICE_FAMILY = "1,2"`); the layouts diverge by size class rather than forking the
app, so the phone version is mostly free when it is wanted. A tablet rotates freely; a phone
stays portrait, which is the spec's own "one-handed on a ladder".

iOS 17 buys `@Observable`, which removes a layer of boilerplate from every screen. **Confirm
which devices the crews actually carry before this hardens** — an iPad 5 or an iPhone 8 would
drop the target to 16.

A laptop version later is not free: SwiftUI reaches the Mac through Catalyst or a separate Mac
target, and neither is a checkbox. Worth deciding before Phase 7, since the progress page is the
screen that most wants a big display.

**A5 — Deployment target is iOS/iPadOS 16.0, so the app runs on 16 through 26 and beyond.**
Asked for as "iOS 26 and older". Worth stating plainly because it is a common trap: a deployment
target is the **minimum** OS the app will install on, never the maximum. The previous 17.0 floor
already ran on 26; it simply excluded anything older. Apple's jump from iOS 18 to iOS 26 in 2025
renumbered the releases, it did not change that rule.

So the real question was how far *back* to go, and that is a cost question:

| Floor | What it costs |
|---|---|
| 17 | Nothing — where we started |
| **16** | **`@Observable` → `ObservableObject`, `#Preview` → `PreviewProvider`, `.topBarTrailing` → `.navigationBarTrailing`. Nine call sites. Chosen.** |
| 15 | The above, plus losing `NavigationStack`, `.presentationDetents` and `.tracking` — a real rewrite of the navigation layer |

16 was chosen because it is the last cheap step. It picks up roughly the 2017-era iPads that 17
drops, which is exactly the kind of hand-me-down tablet that ends up on a job site. Going to 15
buys only hardware from around 2014, which will not run this usefully.

The cost is that `Session` is now an `ObservableObject` with `@Published` properties rather than
the tidier `@Observable`. That is a fair trade for not discovering mid-pilot that a Lead's tablet
cannot install the app. Raising the floor later is a one-line change plus deleting compatibility
spellings; lowering it after the fact is not.

**What CI can and cannot prove here.** The compiler enforces the floor: with a 16.0 deployment
target it refuses any newer API outright, so an accidental iOS 17-only call fails the build. What
CI cannot do is *run* the app on iOS 16 — GitHub's runners carry only recent simulator runtimes.
Actual behaviour on an old iPad still needs an old iPad.

**A4 — Shipping does not require the $99 Apple Developer Program, and seeing it does not
require a Mac.**
The question was asked directly, so the answer is recorded. The paid program is needed only to
put a build on *other people's* devices — TestFlight or the App Store. A free Apple ID builds,
runs in the Simulator, and installs on a device you own yourself (re-signing every 7 days).

The real prerequisite is a Mac. CI covers most of what that would otherwise be for: GitHub's
macOS runners are free on public repositories, so `.github/workflows/ci.yml` compiles the app and
publishes screenshots of it running on an iPad as an artifact of every run. What CI cannot give
is live iteration — clicking through, changing something, seeing it immediately.

**A3 — The Xcode project is generated, not committed.**
`ios/project.yml` plus XcodeGen. A `.pbxproj` is unreviewable in a pull request and is the single
most common source of merge conflicts on an iOS team.

---

## B. Corrections to the reviewed schema draft

The draft that came back for review had six problems. Each is marked `[FIX-n]` in the migration
at the place it was fixed. Four of them would have stopped the app from working at all.

**FIX-1 — `citext` was created after the table that uses it.** *Fatal.*
`users.email` is declared `citext`, but `create extension citext` sat 15 lines below the table.
The migration could not apply at all. Moved to the top with `pgcrypto`.

**FIX-2 — `qty_needs_unit` covered `est_qty` but not `qty_installed`.** *Minor.*
A task could be closed out with "340" and no unit. Widened to cover both.

**FIX-3 — `auth.uid()` is null for service-role writes, and `task_events.actor_id` is `NOT NULL`.** *Fatal for seeds and background jobs.*
Any status change made by a script, a migration or the SQL console raised a not-null violation.
The trigger now falls back to the row's own actor. The audit trail must never be the reason a
write fails.

**FIX-4 — `bump_rework_count` collided with the privileged-column guard.** *Fatal.*
`rework_count` is derived and must not be typed by hand, so the guard forbids changing it — but
the counter trigger changes it. The trigger now flags itself with a transaction-local setting
that the guard honours. A client cannot set that flag; it is turned on and off inside the
function that owns it.

**FIX-5 — the cost view could not work as `security_invoker`.** *Fatal for cost visibility.*
`burdened_rate` is denied to `authenticated` by column grant, so an invoker-rights view reading
it fails for everyone — PM included. The view now runs with the owner's rights, which means it
has to carry its own row scope too, because the owner also bypasses the row policies. Both halves
are written out in `0002_rls.sql` and both are tested.

**FIX-6 — the audit trigger was blocked by its own table's RLS.** *Fatal. The worst of the six.*
`task_events` deliberately has no INSERT policy — nobody forges history. But the trigger that
writes it ran as the client, so RLS refused it, so **no status change could be saved by any role
at all.** The whole app was unusable and nothing about the error pointed at the cause. The
trigger is now `security definer`; clients still cannot insert a row of their own. This is what
test #45 in the suite is watching for.

---

## C. Things SPEC.md did not cover

**C1 — `companies` table added.**
SPEC has `in_house (bool)` on a user, but a boolean cannot answer "which sub?", and the progress
page has to split in-house vs. contractor hours *and dollars*. A company table answers both.
`users.in_house` is now derived from the company by trigger rather than typed, so the two can
never disagree.

**C2 — `task_crew` is separate from `time_entries`.**
The crew a Foreman assigns is not the crew that turned up. Keeping them in one table means an
assigned man who was not there accrues hours, which breaks principle 3. Two tables.

**C3 — Manager is company-wide, not per project.**
SPEC says "Full table, all projects" for Manager and "per project" for roles generally. Read
literally, a Manager would need a membership row on every job to see anything. `app.role_on()`
therefore returns `manager` for a Manager regardless of the project. **Worth confirming** — the
alternative is that a Manager sees only jobs they are explicitly added to.

**C4 — A Lead can read his whole project's board, not only his own tasks.**
He needs to see what is coming. He can only *move* tasks assigned to him, and only between
`assigned`, `in_progress` and `review`. Sign-off and creation are closed to him entirely.

**C5 — The material page is closed to a Lead at the table level, not by hiding a tab.**
`material_categories` too, not just receipts: a category list leaks what a job buys. A Lead
selecting any of the three tables gets zero rows.

**C6 — `burdened_rate` is protected by column grant, not by a row policy.**
A row policy decides which *people* you see. Cost is a different question — you can legitimately
see a man and not what he costs. A Lead selecting `burdened_rate` gets a permission error from
Postgres, not a null.

**C7 — An Accomplished task can never be reopened, by anyone, including the Manager.**
Principle 6 says history is never rewritten. The route back is a discovered-defect ticket
carrying `source_task_id`. Enforced by trigger.

**C8 — Un-approving a change order is as restricted as approving one.**
SPEC says only Manager and PM may approve. Both directions move money, so both are gated.

**C9 — An inactive user is turned away at sign-in.**
Deactivation does not remove the auth login, so a deactivated person could otherwise still sign
in and read their projects. The app signs them straight back out.

**C10 — `must_change_password` can only be cleared by the person themselves, true → false.**
Anything else on the user row — email, role, company, rate, `is_active` — is admin-only, enforced
by trigger because RLS cannot compare old to new.

**C11 — Temporary passwords avoid ambiguous characters and are shown exactly once.**
They get read down a phone line from a job site. `0/O` and `1/l/I` are excluded.

**C12 — The material category list follows SPEC §6, not the Phase 0 plan.**
The two documents disagree: the Phase 0 plan adds a job-charged vs. returns-to-shop flag on
Tools, and groups freight with tax and credits. SPEC is authoritative, so SPEC's list is seeded.
**The tool-disposition flag is a genuinely good idea and is not currently captured anywhere** —
it belongs in Phase 6d. Flagged rather than silently added.

---

## D. Testing

**D1 — Plain SQL assertions instead of pgTAP.**
pgTAP is an extension that has to be installed on the database under test; the suite here runs
on any Postgres and on Supabase alike. It reports a PASS/FAIL table and exits non-zero, which is
all CI needs.

**D2 — The suite is deliberately not idempotent.**
It signs work off, approves a change order and deactivates a user. Re-running it against a used
database is meaningless, so `scripts/db-test.sh` always rebuilds. Testing the real transitions
matters more than being able to run it twice.

**D3 — Every test runs as `authenticated` with a real user id, never as the owner.**
The owner bypasses RLS. A test suite run as the owner proves nothing at all.

**D4 — Preview mode is a launch argument, and its data mirrors the seed.**
The screenshot job needs the app to render real screens without a Supabase project behind it.
`PreviewData.swift` supplies canned people that are deliberately the same shape as
`supabase/seed.sql` — including the man who is Super on one job and Foreman on another — so a
screenshot is a fair picture rather than a flattering one. Nothing in the UI can turn it on.

Both flags carry an explicit value (`-PMControllerPreview YES -PMControllerPreviewRole lead`)
because Foundation's argument domain reads `-flag` as a key whose value is the *next* argument.
A bare `-PMControllerPreview` would have swallowed the role flag and the persona would have
silently never arrived.

**D5 — A missing Supabase key shows a setup screen instead of crashing.**
The first cut called `fatalError` on a missing key. That is a hostile way to report a setup step
somebody has not done, and it would have made the CI screenshot job impossible. The app now has
an `unconfigured` state that says which file to fill in.

**D6 — CI names no simulator device, and pairs it against the runtime that supports it.**
`scripts/pick-simulator.py` asks the runner what it actually has. Naming a device in a workflow
is a slow-motion breakage: Apple renames them every year and the job fails months later for a
reason nobody remembers.

The first cut of this still failed, and the reason is worth keeping. Having a device type and
having a runtime does **not** mean the two go together. The runner carries both an iPad Pro
10.5-inch (2017) and iOS 26.5, and the script — ranking iPads by name, preferring "Pro" — picked
exactly that pair:

    com.apple.CoreSimulator.SimDeviceType.iPad-Pro--10-5-inch- … iOS-26-5
    An error was encountered processing the command (code=403): Incompatible device

Each runtime publishes `supportedDeviceTypes`, so the script now reads the runtime first and
chooses only from what that runtime will actually run — widest screen first, since the
two-column tablet layout only appears at that width. It prints several candidates and the
workflow falls through to the next if creating one fails, so a surprise we cannot see from here
costs a retry rather than a red build.

**D4b — "No rows matched" is treated as a refusal.**
That is the shape most RLS denials actually take on an UPDATE — the statement succeeds and
changes nothing. Asserting only for raised errors would have passed four rules that were never
enforced.

---

## E. Still open

These are not decided. They are carried from SPEC §13 and need answers from PCM or from the owner.

- Burdened rates: real figures, or placeholder multipliers.
- Whether the GC's schedule can be imported or is entered by hand per area.
- Whether PCM shares estimated hours per system or only total contract hours.
- Whether Supervisor should have wider material visibility than Foreman (C5 assumes not).
- Written sign-off from PCM ownership before any PCM data lives in a system you own.
- Which iPads and iPhones the crews carry (A2, A5). The 16.0 floor is a guess at "anything
  plausibly in service"; a real inventory would confirm or cheapen it.
- Whether a Mac is available for interactive development (A4).
- Whether the laptop version is Catalyst or a separate Mac target (A2). Decide before Phase 7.
