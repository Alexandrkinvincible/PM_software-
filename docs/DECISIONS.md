# Decisions and assumptions

Every choice made that SPEC.md did not settle, and every correction made to the reviewed schema
draft. The kickoff prompt asked for assumptions to be logged rather than silently decided; this
is that log.

---

## A. Platform

**A1 — Native iOS instead of a React PWA.**
Decided by the owner. SPEC §9 is updated accordingly and the trade-off is written out there in
full. Nothing below the client changed: the schema, the policies and all nine principles are
untouched, because none of them depended on the client.

**A2 — iOS 17 minimum, iPhone only, portrait only.**
Assumed. iOS 17 buys `@Observable`, which removes a layer of boilerplate from every screen.
Portrait-only follows from the spec's own "one-handed on a ladder". **Confirm which iPhones the
Leads actually carry before this hardens** — if anyone is on an iPhone 8 or SE 1, iOS 17 excludes
them and the target drops to 16.

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

**D4 — "No rows matched" is treated as a refusal.**
That is the shape most RLS denials actually take on an UPDATE — the statement succeeds and
changes nothing. Asserting only for raised errors would have passed four rules that were never
enforced.

---

## E. Still open

These are not decided. They are carried from SPEC §13 and need answers from PCM or from the owner.

- The app's name — blocks the bundle identifier and the App Store listing.
- Burdened rates: real figures, or placeholder multipliers.
- Whether the GC's schedule can be imported or is entered by hand per area.
- Whether PCM shares estimated hours per system or only total contract hours.
- Whether Supervisor should have wider material visibility than Foreman (C5 assumes not).
- Written sign-off from PCM ownership before any PCM data lives in an Apex-owned system.
- Which iPhones the Leads carry (A2).
