# PM Controller

Native iPad and iPhone app for commercial mechanical crews. Makes the production number —
man-hours burned vs. earned, by system and area, with rework separated from first-time work — a
by-product of work the crew already does, rather than a separate reporting step.

Tablet first. Phone second. Laptop later.

Owned by Apex Plumbing and Mechanical Services SC — see [LICENSE](LICENSE). Pilot customer: Paulson Cheek
Mechanical. Apex owns the software; a customer owns its own records.

**Setting it up: [SETUP.md](SETUP.md).** Xcode first — the app runs and shows real screens
with no database at all.

**[SPEC.md](SPEC.md) is authoritative.** Every phase reads it.
[docs/DECISIONS.md](docs/DECISIONS.md) records what was assumed and why.
[docs/Phase0_Build_Package.pdf](docs/Phase0_Build_Package.pdf) is the plan, milestones
and checklist. Each phase carries its own record in `docs/`:

| Document | |
|---|---|
| `Phase0_Build_Package.pdf` | Plan, milestones, checklist |
| `Phase1_Completion.pdf` | Schema, auth, RLS — what was delivered and what was not |
| `Phase2_Action_Plan.pdf` | The board, planned before it was built |
| `Phase2_Completion.pdf` | The board, as delivered |

---

## Where this is

| Phase | State |
|---|---|
| 0 — Plan, model, flow, checklist | **Issued** |
| 1 — Schema · auth · admin setup · row-level security | **Complete** — merged in PR #1. |
| 2 — Task board, columns, role-gated transitions | **Complete** — merged in PR #2. |
| 3 — Time capture, crew selection, per-person rows | Not started |
| 4 onwards | Not started |

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
SETUP.md                             getting it running: Xcode first, Supabase second
docs/DECISIONS.md                    assumptions and the six schema defects found
docs/Phase0_Build_Package.pdf    plan, milestones, checklist

supabase/
  migrations/0001_schema.sql         tables, enums, constraints, triggers
  migrations/0002_rls.sql            row-level security — the role matrix
  seed.sql                           one project, one user per role, plus the
                                     second Foreman that makes isolation testable
  tests/00_local_stub.sql            auth.users / auth.uid() for a plain Postgres
  tests/01_rls_test.sql              the 69 assertions
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

Full detail is in **[SETUP.md](SETUP.md)**. The short version:

### 1. Run it on your Mac, tonight, with nothing else

No Supabase, no Apple account, no money.

```bash
brew install xcodegen
git clone https://github.com/Alexandrkinvincible/PM_software-.git
cd PM_software-/ios
cp PMController/Resources/Config.example.xcconfig PMController/Resources/Config.xcconfig
xcodegen generate
open PMController.xcodeproj
```

Needs **Xcode 16 or newer** — that is what carries the iOS 18 SDK. (The current release is
numbered 26.x. Apple renamed Xcode to the OS year in 2025, so 26 is newer than 16.)

Pick an **iPad** simulator and press ⌘R. The first build sits for several minutes while Swift
Package Manager fetches `supabase-swift`; it is not hung.

You get a **"Not connected yet"** screen. That is correct — the build works, there is just no
database behind it.

### 2. Turn on preview mode and see the real thing

**Product → Scheme → Edit Scheme → Run → Arguments → Arguments Passed On Launch**, two rows:

```
-PMControllerPreview        YES
-PMControllerPreviewRole    super-board
```

⌘R again and you are on the board with canned data mirroring `supabase/seed.sql`. Change the
second value to `lead-board`, `manager`, `lead`, `super`, `first-login` or `signed-out`.

Run `super-board` and `lead-board` back to back. Same job, same cards — the difference between
them is the role matrix, which is the thing worth judging.

### 3. Then connect a database

Create a free project at [supabase.com](https://supabase.com) and run, in order:

1. `supabase/migrations/0001_schema.sql`
2. `supabase/migrations/0002_rls.sql`

Do **not** run `supabase/tests/00_local_stub.sql` against Supabase — it fakes `auth.users` and
`auth.uid()`, which Supabase already provides. Do **not** run `supabase/seed.sql` either: it
writes to `auth.users` with fixed ids and no passwords, so none of those accounts can sign in.
[SETUP.md](SETUP.md) has the bootstrap SQL for your own first Manager account instead.

Then fill in `Config.xcconfig`, remove the preview launch arguments, and deploy the admin
function:

```bash
supabase functions deploy admin-create-user
```

It is the only thing that touches the service-role key, and it re-checks that the caller is an
active Manager before it does. The key never reaches the app.

### 4. Before you get much further

- **Confirm which iPads and iPhones the crews carry.** The floor is iOS/iPadOS 18, which runs on
  18, 26 and everything after — a deployment target is a minimum, not a maximum. There is no
  iOS 19–25; Apple went from 18 straight to 26.
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
| Row-level security | ubuntu | Both migrations applied to a real Postgres 16, then the 69 assertions |
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
