# Field Task & Production Management

Native iOS app for commercial mechanical crews. Makes the production number — man-hours burned
vs. earned, by system and area, with rework separated from first-time work — a by-product of work
the crew already does, rather than a separate reporting step.

Owner: Alex Kulikov, Apex Plumbing & Mechanical. Pilot: Paulson Cheek Mechanical.

**[SPEC.md](SPEC.md) is authoritative.** Every phase reads it.
[docs/DECISIONS.md](docs/DECISIONS.md) records what was assumed and why.
[docs/Phase0_iOS_Build_Package.pdf](docs/Phase0_iOS_Build_Package.pdf) is the plan, milestones
and checklist.

---

## Where this is

| Phase | State |
|---|---|
| 0 — Plan, model, flow, checklist | **Issued** |
| 1 — Schema · auth · admin setup · row-level security | **Database gate met** — 56/56 assertions green. iOS shell written; needs a Mac to build. |
| 2 onwards | Not started |

The Phase 1 milestone is *"an admin creates a Lead by email, and that Lead sees only his project
and cannot read the receipts tables at all."* That is a claim about the database, so it is tested
against the database — as the role a phone actually holds, never as the owner.

```
./scripts/db-test.sh
```

```
 passed | failed |                verdict
--------+--------+---------------------------------------
     56 |      0 | ALL GREEN — Phase 1 database gate met
```

---

## Layout

```
SPEC.md                              authoritative spec
docs/DECISIONS.md                    assumptions and the six schema defects found
docs/Phase0_iOS_Build_Package.pdf    plan, milestones, checklist

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
  FieldTask/
    App/                             entry point and root routing
    Core/                            models mirroring the DB enums, session, client
    Design/                          one button, one field, 56pt targets
    Features/Auth/                   login, forced first-login password change
    Features/Home/                   who you are, your jobs, what you may do
    Features/Admin/                  Manager-only: add a person, issue credentials

scripts/db-test.sh                   rebuild a throwaway DB and run the suite
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

### 3. Build the app — needs a Mac

```bash
brew install xcodegen
cd ios
cp FieldTask/Resources/Config.example.xcconfig FieldTask/Resources/Config.xcconfig
#   fill in SUPABASE_URL and SUPABASE_ANON_KEY
xcodegen generate
open FieldTask.xcodeproj
```

The anon key is the only key that ships. Every query carries the signed-in user's JWT, so
`0002_rls.sql` is what decides what comes back.

> The Swift in this repo has **not been compiled** — there is no Swift toolchain on the machine it
> was written on. Expect to fix small things on the first build. The SQL, by contrast, has been
> applied and tested end to end.

### 4. Before you get much further

- **Name the app.** It blocks the bundle identifier and the App Store listing.
  `com.apexmech.fieldtask` is a placeholder.
- **Start Apple Developer enrolment** ($99/yr, up to 48 hours) before it is on the critical path.
- **Confirm which iPhones the Leads carry.** iOS 17 is assumed.

---

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
