# PM Controller

Native iPad and iPhone app for commercial mechanical crews. Makes the production number —
man-hours burned vs. earned, by system and area, with rework separated from first-time work — a
by-product of work the crew already does, rather than a separate reporting step.

Tablet first. Phone second. Laptop later.

Owned by Apex Plumbing and Mechanical Services SC — see [LICENSE](LICENSE). Pilot customer: Paulson Cheek
Mechanical. Apex owns the software; a customer owns its own records.

**[SPEC.md](SPEC.md) is authoritative.** Every phase reads it.
[docs/DECISIONS.md](docs/DECISIONS.md) records what was assumed and why.
[docs/Phase0_Build_Package.pdf](docs/Phase0_Build_Package.pdf) is the plan, milestones
and checklist.

---

## Where this is

| Phase | State |
|---|---|
| 0 — Plan, model, flow, checklist | **Issued** |
| 1 — Schema · auth · admin setup · row-level security | **Complete** — merged in PR #1. |
| 2 — Task board, columns, role-gated transitions | **Database gate met** — 69/69 assertions. App built, in review. |
| 3 onwards | Not started |

The Phase 1 milestone is *"an admin creates a Lead by email, and that Lead sees only his project
and cannot read the receipts tables at all."* That is a claim about the database, so it is tested
against the database — as the role a phone actually holds, never as the owner.

```
./scripts/db-test.sh
```

```
 passed | failed |                verdict
--------+--------+---------------------------------------
     69 |      0 | ALL GREEN — Phase 1 and Phase 2 database gates met
```

---

## Layout

```
SPEC.md                              authoritative spec
docs/DECISIONS.md                    assumptions and the six schema defects found
docs/Phase0_Build_Package.pdf    plan, milestones, checklist

supabase/
  migrations/0001_schema.sql         tables, enums, constraints, triggers
  migrations/0002_rls.sql            row-level security — the role matrix
  seed.sql                           one project, one user per role, plus the
                                     second Foreman that makes isolation testable
  tests/00_local_stub.sql            auth.users / auth.uid() for a plain Postgres
  tests/01_rls_test.sql              the 56 assertions
  functions/admin-create-user/       the only thing holding a service-role key

ios/
  project.yml                        XcodeGen manifest (the .xcodeproj is generated)
  PMController/
    App/                             entry point and root routing
    Core/                            models mirroring the DB enums, session, client,
                                     and the canned people used for previews
    Design/                          one button, one field, 56pt targets
    Features/Auth/                   login, forced first-login password change
    Features/Board/                  the board, cards, detail, move sheet, new ticket
    Features/Home/                   who you are, your jobs, what you may do
    Features/Admin/                  Manager-only: add a person, issue credentials

scripts/db-test.sh                   rebuild a throwaway DB and run the suite
scripts/pick-simulator.py            ask CI's runner which iPad it actually has
.github/workflows/ci.yml             the three CI jobs
```

---

## Your steps, in order

### 1. Supabase project (15 minutes)

Create a free project at [supabase.com](https://supabase.com). From the SQL editor, run in order:

1. `supabase/migrations/0001_schema.sql`
2. `supabase/migrations/0002_rls.sql`

Do **not** run `supabase/tests/00_local_stub.sql` against Supabase — it fakes `auth.users` and
`auth.uid()`, which Supabase already provides. It exists so the migrations can be tested on a
plain Postgres.

Then create your own Manager account: add yourself through **Authentication → Users**, and insert
the matching `users` row plus a `project_members` row with `role = 'manager'`. Everyone after you
is created from inside the app.

### 2. Deploy the admin function

```bash
supabase functions deploy admin-create-user
```

It is the only thing that touches the service-role key, and it re-checks that the caller is an
active Manager before it does. The key never reaches the app.

### 3. Build the app

```bash
brew install xcodegen
cd ios
cp PMController/Resources/Config.example.xcconfig PMController/Resources/Config.xcconfig
#   fill in SUPABASE_URL and SUPABASE_ANON_KEY
xcodegen generate
open PMController.xcodeproj
```

The anon key is the only key that ships. Every query carries the signed-in user's JWT, so
`0002_rls.sql` is what decides what comes back.

> The Swift in this repo has **not been compiled locally** — there is no Swift toolchain on the
> machine it was written on. The `Build for iPad` CI job is what compiles it; check that it is
> green before assuming it builds. The SQL, by contrast, has been applied and tested end to end.

### 4. Before you get much further

- **Confirm which iPads and iPhones the crews carry.** The floor is iOS/iPadOS 18, which runs on
  18, 26 and everything after — a deployment target is a minimum, not a maximum. There is no
  iOS 19–25; Apple went from 18 straight to 26.
- **Confirm Apex controls `apexmech.com`.** The bundle identifier assumes it. Cheap to change
  now, awkward after App Store submission.
- **Start Apple Developer enrolment** ($99/yr) only when you are ready to put builds on other
  people's devices. See below — you do not need it before then.

---

## Seeing it work without paying for anything

| What you want | What it costs |
|---|---|
| Compile it, run it in a Simulator | A Mac. No Apple account at all. |
| Install it on an iPad **you own** | A Mac + a free Apple ID. Re-sign every 7 days. |
| Put it on someone **else's** iPad (TestFlight) | $99/yr Apple Developer Program |
| App Store | $99/yr |

**You have a MacBook Pro, so the top two rows are already open to you** — build it, run it in the
iPad Simulator, and install it on your own iPad, without an Apple Developer account.

CI still earns its keep: every push compiles the app on a macOS runner and uploads photographs of
every screen from an iPad simulator (**Actions → Screenshots on iPad → Artifacts**). That is a
second pair of eyes on a clean machine, and it catches anything that only builds because of
something local to your Mac.

---

## CI

Three jobs on every pull request:

| Job | Runner | What it proves |
|---|---|---|
| Row-level security | ubuntu | Both migrations applied to a real Postgres 16, then the 56 assertions |
| Build for iPad | macOS | The Swift compiles |
| Screenshots on iPad | macOS | The app runs, photographed as each role, uploaded as an artifact |

The screenshot job runs the app in preview mode — a launch argument that loads the canned people
in `ios/PMController/Core/PreviewData.swift` instead of calling Supabase. That data mirrors
`supabase/seed.sql`, including the man who is Super on one job and Foreman on another, so a
screenshot is a fair picture rather than a flattering one. Nothing in the UI can turn it on.

## Running the database tests

Any Postgres 16 with `citext` and `pgcrypto`:

```bash
./scripts/db-test.sh                 # local cluster on port 5439
PGPORT=5432 ./scripts/db-test.sh     # or your own
```

The suite signs work off, approves a change order and deactivates a user, so it is deliberately
not idempotent — the script always rebuilds. It exits non-zero when a rule regresses, which makes
it a usable CI gate. Introducing a single leak (a Foreman able to see another Foreman's receipts)
fails five assertions and the run.
