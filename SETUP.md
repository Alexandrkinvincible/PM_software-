# Setting up

Two paths. **A** gets the app running on your Mac tonight with nothing else — no Supabase, no
Apple account, no money. **B** connects it to a real database when you are ready.

Do A first. If something is wrong with the build, you want to know that before a database is
involved.

---

## A. Run it tonight (about 20 minutes, most of it waiting)

### 1. Xcode

From the Mac App Store. You need **Xcode 16 or newer** — that is what carries the iOS 18 SDK, and
this app's deployment floor is iOS/iPadOS 18. The current release is numbered 26.x; Apple renamed
Xcode to match the OS year in 2025, so 26 is newer than 16, not older.

It is a large download. Start it first and do the rest while it goes.

### 2. XcodeGen

```bash
brew install xcodegen
```

The `.xcodeproj` is generated rather than committed — an Xcode project file is unreviewable in a
pull request and is the most common source of merge conflicts on an iOS team.

### 3. Generate and open

```bash
git clone https://github.com/Alexandrkinvincible/PM_software-.git
cd PM_software-/ios
cp PMController/Resources/Config.example.xcconfig PMController/Resources/Config.xcconfig
xcodegen generate
open PMController.xcodeproj
```

You are copying `Config.xcconfig` without editing it. That is deliberate — an unconfigured build
is a valid state and the app says so rather than crashing.

### 4. First build

Pick an **iPad** simulator from the scheme selector at the top — iPad Pro 13-inch is a good
default. This is a tablet-first app; on an iPhone you get the phone layout, which is correct but
is not the layout to judge.

Press **⌘R**.

> **The first build will sit there for several minutes.** Xcode is downloading `supabase-swift`
> and its dependencies through Swift Package Manager. It is not hung. Subsequent builds are fast.

### 5. What you should see

A screen headed **"Not connected yet"**, listing the two config values to fill in.

That is the correct result, not a failure. The build works; there is simply no database behind it
yet.

### 6. Now see the actual app

This is the part worth doing tonight. The app carries canned data that mirrors
`supabase/seed.sql`, and a launch argument turns it on.

**Product → Scheme → Edit Scheme → Run → Arguments → Arguments Passed On Launch**, then add these
two, in this order:

```
-PMControllerPreview        YES
-PMControllerPreviewRole    super-board
```

Each goes in its own row. Press ⌘R again and you land on the board as Tom Brenner,
Superintendent.

Change the second value to see the app as someone else:

| Value | What you get |
|---|---|
| `super-board` | The board as a Superintendent |
| `lead-board` | The same board as a Lead — Accomplished is locked, and only his own tickets are marked |
| `super` | Home screen, Superintendent (Super on one job, Foreman on the other) |
| `lead` | Home screen, Lead — no material page |
| `manager` | Home screen, Manager — everything allowed |
| `first-login` | The forced password change |
| `signed-out` | Sign in |

**Run `super-board` and `lead-board` back to back.** Same job, same columns, same cards — the
difference between them is the role matrix, and it is the thing worth judging before Phase 3
builds on top of it.

Tap a card to open it and read its history. Long-press for **Move…**, which lists every column
including the ones closed to you, and says why.

### 7. Xcode's own previews

Open `App/RootView.swift` and press **⌥⌘↩** for the canvas. Every screen has a preview, including
both board roles, and they render without running the app at all.

---

## B. Connect it to Supabase

### 1. Create the project

Free tier at [supabase.com](https://supabase.com). Note the **project URL** and the **anon key**
from Settings → API.

### 2. Apply the migrations

SQL editor, in order:

1. `supabase/migrations/0001_schema.sql`
2. `supabase/migrations/0002_rls.sql`

**Do not run `supabase/tests/00_local_stub.sql`.** It fakes `auth.users` and `auth.uid()`, which
Supabase already provides properly. It exists so the migrations can be tested on a plain Postgres.

**Do not run `supabase/seed.sql` either.** It inserts rows straight into `auth.users` with fixed
ids and no passwords — fine for a test database, useless on a real one, because none of those
accounts can actually sign in. Use the bootstrap below instead.

### 3. Make yourself the first Manager

There is no self-registration anywhere in this app, so the first account is made by hand. Everyone
after you is created from inside it.

**Authentication → Users → Add user.** Use a real email and password, and tick *Auto Confirm User*.
Copy the UUID it gives you.

Then in the SQL editor, replacing the two placeholders:

```sql
insert into companies (name, is_house, phone)
values ('Apex Plumbing and Mechanical Services SC', true, null)
returning id;
-- copy that company id into the next statement

insert into users (id, email, name, default_role, company_id, must_change_password)
values (
  '<your auth UUID>',
  '<your email>',
  '<your name>',
  'manager',
  '<the company id from above>',
  false          -- you chose your own password already
);

insert into projects (name, number, client)
values ('First job', '0001', null)
returning id;
-- copy that project id into the next two statements

insert into project_members (user_id, project_id, role)
values ('<your auth UUID>', '<the project id>', 'manager');

-- The six system columns, so the board has something to draw.
insert into board_columns (project_id, name, sort_order, core_status, is_system) values
  ('<the project id>', 'Open',         10, 'open',         true),
  ('<the project id>', 'Assigned',     20, 'assigned',     true),
  ('<the project id>', 'In Progress',  30, 'in_progress',  true),
  ('<the project id>', 'Review',       40, 'review',       true),
  ('<the project id>', 'Rework',       50, 'rework',       true),
  ('<the project id>', 'Accomplished', 60, 'accomplished', true);
```

`must_change_password` is set to `false` for you because you picked your own password. Everybody
created through the app gets `true` and is made to change it at first sign-in.

### 4. Point the app at it

Edit `ios/PMController/Resources/Config.xcconfig`:

```
SUPABASE_URL = https:/$()/YOUR-PROJECT.supabase.co
SUPABASE_ANON_KEY = your-anon-key
```

The `$()` in the middle of `https://` is not a typo — it stops the xcconfig parser treating `//`
as a comment.

**Remove the preview launch arguments** from the scheme (step A6), or the app will keep showing
canned data instead of talking to your project.

⌘R, and sign in with the email and password you created.

> The anon key is the only key that ever ships in the app. It is public by design. Every query
> carries the signed-in user's JWT, so `0002_rls.sql` is what decides what comes back — not the
> app.
>
> **Never put a service-role key in this file.** It bypasses every policy in the database.

### 5. Deploy the admin function

Needed only when you want to add people from inside the app.

```bash
brew install supabase/tap/supabase
supabase login
supabase link --project-ref <your project ref>
supabase functions deploy admin-create-user
```

It is the only thing that touches the service-role key, and it re-checks that the caller is an
active Manager before it uses it.

---

## What to look for, and what it means

| What happens | What it means |
|---|---|
| "Not connected yet" | `Config.xcconfig` is unedited. Correct for path A. |
| Build hangs on first run | SPM resolving `supabase-swift`. Wait. |
| "That email and password did not match" | Deliberately vague — saying which half was wrong tells an attacker which emails are real. |
| You are sent to a password screen and cannot leave | `must_change_password` is true on your row. That is the design; set it false for your own bootstrap account. |
| Signed in but no jobs listed | You have no `project_members` row, or `active` is false on it. |
| The board is empty | The project has no `board_columns`. See the bootstrap above. |
| The bootstrap insert is refused: *"new row violates row-level security policy"* | `users` is under `force row level security`, so even the table owner is subject to it, and your SQL editor session is not running with `bypassrls`. Run `alter table users no force row level security;`, do the insert, then **put it straight back** with `alter table users force row level security;`. Nothing else in the bootstrap touches a forced table. |
| A card snaps back with an alert | The database refused the move. That is the point — read the message. |

---

## If the build fails

The `Build for iPad` job in CI compiles this exact code on a clean machine on every push, and it
is green. So a local failure is almost certainly environmental:

- **Xcode too old.** iOS 18 SDK needs Xcode 16 or newer.
- **XcodeGen not installed**, or `xcodegen generate` not re-run after pulling changes to
  `ios/project.yml`.
- **`Config.xcconfig` missing.** It is gitignored on purpose; copy it from the example.
- **Package resolution failed.** File → Packages → Reset Package Caches, then build again.

If it is none of those, send me the error and I will fix it.
