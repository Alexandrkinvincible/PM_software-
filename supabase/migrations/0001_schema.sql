-- PM Controller
-- Copyright © 2026 Apex Plumbing and Mechanical Services SC. All rights reserved.
-- Proprietary and confidential. See LICENSE at the repository root.

-- =====================================================================
-- PM Controller
-- Migration 0001 — Schema only (RLS in 0002, seed in seed.sql)
-- Authoritative source: SPEC.md section 5.
--
-- Changes from the reviewed draft are marked [FIX-n] and are logged in
-- docs/DECISIONS.md. Nothing else in the draft was altered.
-- =====================================================================

-- [FIX-1] citext must exist BEFORE users.email is declared citext.
-- The draft created it after the table and would have failed to apply.
create extension if not exists citext;
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1. Enumerated types
--    Core statuses are a Postgres enum. A seventh value cannot be
--    inserted from any client; adding one requires a migration.
-- ---------------------------------------------------------------------

create type core_status as enum (
  'open',
  'assigned',
  'in_progress',
  'rework',
  'review',
  'accomplished'
);

create type project_role as enum (
  'manager',
  'pm',
  'assistant_pm',
  'super',
  'assistant_super',
  'foreman',
  'lead'
);

create type cost_class as enum ('base', 'change_order', 'our_cost');

create type work_class as enum ('first_time', 'review_rework', 'discovered_defect');

create type cost_responsibility as enum ('our_cost', 'gc_owner', 'other_trade');

-- SPEC section 5: fixed dropdown, never free text
create type root_cause as enum (
  'layout_error',
  'dimension_misread',
  'coordination_miss',
  'spec_change',
  'damage_by_others'
);

create type qty_unit as enum ('ft', 'ea');

create type blocked_party as enum ('gc', 'other_trade', 'material', 'owner', 'us');

create type notification_type as enum ('rework', 'assigned', 'review_pending');

create type notification_delivery as enum ('push', 'sms', 'in_app');

create type receipt_review_status as enum ('pending', 'needs_review', 'approved', 'rejected');

create type project_status as enum ('active', 'on_hold', 'closed');

-- ---------------------------------------------------------------------
-- 2. companies
--    Every worker belongs to one: the house company, or a sub on the job.
--    in_house on users must agree with the company (enforced below).
-- ---------------------------------------------------------------------

create table companies (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique check (length(trim(name)) > 0),
  is_house    boolean not null default false,
  phone       text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

-- Exactly one house company.
create unique index one_house_company on companies (is_house) where is_house;

-- ---------------------------------------------------------------------
-- 3. users
--    id matches auth.users.id 1:1. Email is the login identity.
--    Deletion is blocked; is_active is the only deactivation path.
-- ---------------------------------------------------------------------

create table users (
  id                    uuid primary key references auth.users(id) on delete restrict,
  email                 citext not null unique,
  name                  text not null check (length(trim(name)) > 0),
  phone                 text,
  default_role          project_role not null,
  company_id            uuid not null references companies(id) on delete restrict,
  trade                 text,
  in_house              boolean not null default true,
  burdened_rate         numeric(10,2) check (burdened_rate >= 0),
  is_active             boolean not null default true,
  must_change_password  boolean not null default true,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

comment on column users.burdened_rate is
  'Cost visibility is role-gated. Readable only through the users_costed view
   (see 0002_rls.sql). Never exposed to Lead or Foreman.';

-- Hard block on deletion, per SPEC principle 9.
create or replace function block_user_delete() returns trigger
language plpgsql as $$
begin
  raise exception
    'Users cannot be deleted. Set is_active = false instead (SPEC principle 9).';
end;
$$;

create trigger trg_users_no_delete
  before delete on users
  for each row execute function block_user_delete();

-- in_house is not typed independently — it follows the company.
create or replace function sync_user_in_house() returns trigger
language plpgsql as $$
begin
  select is_house into new.in_house from companies where id = new.company_id;
  return new;
end;
$$;

create trigger trg_users_in_house
  before insert or update of company_id on users
  for each row execute function sync_user_in_house();

-- ---------------------------------------------------------------------
-- 4. projects and membership
-- ---------------------------------------------------------------------

create table projects (
  id              uuid primary key default gen_random_uuid(),
  name            text not null check (length(trim(name)) > 0),
  number          text not null,
  client          text,
  contract_hours  numeric(10,2) check (contract_hours >= 0),
  contract_value  numeric(14,2) check (contract_value >= 0),
  status          project_status not null default 'active',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (number)
);

-- Roles are per project. The same person can be Super on one job and
-- Foreman on another (SPEC section 3).
create table project_members (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references users(id) on delete restrict,
  project_id  uuid not null references projects(id) on delete restrict,
  role        project_role not null,
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  unique (user_id, project_id)
);

create index on project_members (project_id, role) where active;
create index on project_members (user_id) where active;

-- ---------------------------------------------------------------------
-- 5. board_columns
--    Custom columns map to exactly one locked core status.
-- ---------------------------------------------------------------------

create table board_columns (
  id                   uuid primary key default gen_random_uuid(),
  project_id           uuid not null references projects(id) on delete restrict,
  name                 text not null check (length(trim(name)) > 0),
  sort_order           integer not null,
  core_status          core_status not null,
  blocked_flag         boolean not null default false,
  blocked_reason_type  blocked_party,
  is_system            boolean not null default false,
  created_at           timestamptz not null default now(),
  unique (project_id, name),
  unique (project_id, sort_order) deferrable initially deferred,
  -- A blocked column must name who is being waited on.
  constraint blocked_needs_party check (
    (blocked_flag = false and blocked_reason_type is null)
    or (blocked_flag = true and blocked_reason_type is not null)
  ),
  -- Only In Progress columns can carry a blocked flag (SPEC section 3a).
  constraint blocked_only_in_progress check (
    blocked_flag = false or core_status = 'in_progress'
  )
);

create index on board_columns (project_id, sort_order);

-- ---------------------------------------------------------------------
-- 6. tasks
-- ---------------------------------------------------------------------

create table tasks (
  id                  uuid primary key default gen_random_uuid(),
  project_id          uuid not null references projects(id) on delete restrict,
  area                text not null,
  system              text not null,
  title               text not null check (length(trim(title)) > 0),
  description         text,

  est_hours           numeric(8,2) check (est_hours >= 0),
  est_qty             numeric(12,2) check (est_qty >= 0),
  unit                qty_unit,
  qty_installed       numeric(12,2) check (qty_installed >= 0),

  status              core_status not null default 'open',
  board_column_id     uuid references board_columns(id) on delete restrict,

  created_by          uuid not null references users(id) on delete restrict,
  assigned_foreman    uuid references users(id) on delete restrict,
  assigned_lead       uuid references users(id) on delete restrict,
  parent_task_id      uuid references tasks(id) on delete restrict,

  rework_count        integer not null default 0 check (rework_count >= 0),
  accomplished_at     timestamptz,
  accomplished_by     uuid references users(id) on delete restrict,

  -- Money
  cost_class          cost_class not null default 'base',
  co_number           text,
  co_approved         boolean not null default false,
  co_hours            numeric(8,2) check (co_hours >= 0),
  co_value            numeric(14,2) check (co_value >= 0),

  -- Work classification and defect lineage
  work_class          work_class not null default 'first_time',
  source_task_id      uuid references tasks(id) on delete restrict,
  root_cause          root_cause,
  discovered_by       uuid references users(id) on delete restrict,
  discovered_at       timestamptz,
  cost_responsibility cost_responsibility not null default 'our_cost',

  -- Schedule
  gc_planned_start    date,
  gc_planned_finish   date,
  our_planned_start   date,
  our_planned_finish  date,
  actual_start        timestamptz,
  actual_finish       timestamptz,
  schedule_baseline_id uuid,

  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  -- A quantity implies a unit. [FIX-2] qty_installed is covered too;
  -- the draft constrained est_qty only.
  constraint qty_needs_unit check (
    (est_qty is null and qty_installed is null) or unit is not null
  ),

  -- CO fields only make sense on change-order tickets.
  constraint co_fields_require_co_class check (
    cost_class = 'change_order'
    or (co_number is null and co_hours is null and co_value is null
        and co_approved = false)
  ),

  -- A discovered defect must say where it came from and why (SPEC section 6).
  constraint defect_requires_lineage check (
    work_class <> 'discovered_defect'
    or (source_task_id is not null and root_cause is not null
        and discovered_by is not null and discovered_at is not null)
  ),

  -- Accomplished tickets carry who and when.
  constraint accomplished_stamped check (
    (status = 'accomplished' and accomplished_at is not null and accomplished_by is not null)
    or (status <> 'accomplished' and accomplished_at is null and accomplished_by is null)
  ),

  constraint no_self_parent check (parent_task_id is distinct from id),
  constraint no_self_source check (source_task_id is distinct from id),
  constraint gc_dates_ordered check (
    gc_planned_finish is null or gc_planned_start is null
    or gc_planned_finish >= gc_planned_start
  ),
  constraint our_dates_ordered check (
    our_planned_finish is null or our_planned_start is null
    or our_planned_finish >= our_planned_start
  )
);

create index on tasks (project_id, status);
create index on tasks (project_id, area, system);
create index on tasks (assigned_lead) where assigned_lead is not null;
create index on tasks (assigned_foreman) where assigned_foreman is not null;
create index on tasks (source_task_id) where source_task_id is not null;
create index on tasks (board_column_id);

-- The task's board column must belong to the task's project and must map
-- to the task's current core status. This is the guarantee that reporting
-- never reads a column name.
create or replace function enforce_column_status_match() returns trigger
language plpgsql as $$
declare
  col_project uuid;
  col_status  core_status;
begin
  if new.board_column_id is null then
    return new;
  end if;

  select project_id, core_status into col_project, col_status
    from board_columns where id = new.board_column_id;

  if col_project <> new.project_id then
    raise exception 'Board column belongs to a different project.';
  end if;

  if col_status <> new.status then
    raise exception
      'Board column "%" maps to core status %, but task status is %.',
      new.board_column_id, col_status, new.status;
  end if;

  return new;
end;
$$;

create trigger trg_tasks_column_status
  before insert or update of board_column_id, status, project_id on tasks
  for each row execute function enforce_column_status_match();

-- ---------------------------------------------------------------------
-- 7. task_crew — who the Foreman or Lead put on this task.
--    This is the ASSIGNED crew. time_entries records who actually
--    turned up on a given session. The two are deliberately separate:
--    an assigned man who was not there must not accrue hours.
-- ---------------------------------------------------------------------

create table task_crew (
  id           uuid primary key default gen_random_uuid(),
  task_id      uuid not null references tasks(id) on delete restrict,
  user_id      uuid not null references users(id) on delete restrict,
  assigned_by  uuid not null references users(id) on delete restrict,
  assigned_at  timestamptz not null default now(),
  removed_at   timestamptz,
  unique (task_id, user_id)
);

create index on task_crew (task_id) where removed_at is null;
create index on task_crew (user_id) where removed_at is null;

-- ---------------------------------------------------------------------
-- 8. schedule_baselines  (FK added after tasks exists)
-- ---------------------------------------------------------------------

create table schedule_baselines (
  id           uuid primary key default gen_random_uuid(),
  project_id   uuid not null references projects(id) on delete restrict,
  version      integer not null,
  issued_by    text not null,          -- the GC issuing the schedule
  issued_date  date not null,
  notes        text,
  created_at   timestamptz not null default now(),
  unique (project_id, version)
);

alter table tasks
  add constraint tasks_schedule_baseline_fk
  foreign key (schedule_baseline_id)
  references schedule_baselines(id) on delete restrict;

-- ---------------------------------------------------------------------
-- 9. time_entries
--    One row per person per session. Hours are computed, never typed.
-- ---------------------------------------------------------------------

create table time_entries (
  id               uuid primary key default gen_random_uuid(),
  task_id          uuid not null references tasks(id) on delete restrict,
  user_id          uuid not null references users(id) on delete restrict,
  start_at         timestamptz not null,
  end_at           timestamptz,
  hours            numeric(8,2)
                   generated always as (
                     case when end_at is null then null
                          else round(extract(epoch from (end_at - start_at)) / 3600.0, 2)
                     end
                   ) stored,
  crew_session_id  uuid not null,
  is_rework        boolean not null default false,
  created_at       timestamptz not null default now(),
  constraint end_after_start check (end_at is null or end_at > start_at)
);

create index on time_entries (task_id);
create index on time_entries (user_id, start_at);
create index on time_entries (crew_session_id);

-- One person cannot have two open sessions at once.
create unique index one_open_session_per_user
  on time_entries (user_id) where end_at is null;

-- ---------------------------------------------------------------------
-- 10. task_media
-- ---------------------------------------------------------------------

create table task_media (
  id            uuid primary key default gen_random_uuid(),
  task_id       uuid not null references tasks(id) on delete restrict,
  storage_path  text not null unique,
  caption       text,
  uploaded_by   uuid not null references users(id) on delete restrict,
  created_at    timestamptz not null default now()
);

create index on task_media (task_id);

-- ---------------------------------------------------------------------
-- 11. rework_items
-- ---------------------------------------------------------------------

create table rework_items (
  id                uuid primary key default gen_random_uuid(),
  task_id           uuid not null references tasks(id) on delete restrict,
  rejected_by       uuid not null references users(id) on delete restrict,
  reason            text not null check (length(trim(reason)) > 0),
  punch_photos      text[] not null default '{}',
  rejected_at       timestamptz not null default now(),
  resolved_at       timestamptz,
  hours_attributed  numeric(8,2) check (hours_attributed >= 0),
  constraint resolved_after_rejected check (
    resolved_at is null or resolved_at >= rejected_at
  )
);

create index on rework_items (task_id);

-- rework_count is derived, never typed.
-- [FIX-4] This is a direct write to tasks.rework_count, which the
-- privileged-column guard in 0002 forbids to clients. It flags itself as
-- an internal write for the life of the statement so the guard lets it
-- through without opening the column to anyone else.
create or replace function bump_rework_count() returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform set_config('app.internal_write', 'on', true);
  update tasks
     set rework_count = rework_count + 1,
         updated_at = now()
   where id = new.task_id;
  perform set_config('app.internal_write', 'off', true);
  return new;
end;
$$;

create trigger trg_rework_count
  after insert on rework_items
  for each row execute function bump_rework_count();

-- ---------------------------------------------------------------------
-- 12. notifications
-- ---------------------------------------------------------------------

create table notifications (
  id            uuid primary key default gen_random_uuid(),
  recipient_id  uuid not null references users(id) on delete restrict,
  task_id       uuid references tasks(id) on delete restrict,
  type          notification_type not null,
  delivery      notification_delivery not null,
  sent_at       timestamptz,
  read_at       timestamptz,
  created_at    timestamptz not null default now()
);

create index on notifications (recipient_id, read_at);

-- ---------------------------------------------------------------------
-- 13. blocked_periods
-- ---------------------------------------------------------------------

create table blocked_periods (
  id                 uuid primary key default gen_random_uuid(),
  task_id            uuid not null references tasks(id) on delete restrict,
  start_at           timestamptz not null,
  end_at             timestamptz,
  reason             text not null check (length(trim(reason)) > 0),
  responsible_party  blocked_party not null,
  created_at         timestamptz not null default now(),
  constraint block_end_after_start check (end_at is null or end_at > start_at)
);

create index on blocked_periods (task_id);
create index on blocked_periods (responsible_party, start_at);

-- ---------------------------------------------------------------------
-- 14. Material — receipts and lines.
--     SPEC section 6: NOT linked to tasks. Separate page.
-- ---------------------------------------------------------------------

-- Fixed category list, editable by PM, never free text (SPEC section 6).
create table material_categories (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  sort_order  integer not null,
  is_active   boolean not null default true
);

insert into material_categories (name, sort_order) values
  ('Pipe & fittings',        10),
  ('Valves & specialties',   20),
  ('Hangers & supports',     30),
  ('Fixtures & trim',        40),
  ('Insulation',             50),
  ('Hardware & fasteners',   60),
  ('Consumables',            70),
  ('Tools',                  80),
  ('Equipment rental',       90),
  ('Freight & delivery',    100),
  ('Other',                 110);

create table receipts (
  id              uuid primary key default gen_random_uuid(),
  uploaded_by     uuid not null references users(id) on delete restrict,
  vendor          text,
  date            date,
  invoice_number  text,
  total           numeric(12,2),
  image_path      text not null,
  project_id      uuid references projects(id) on delete restrict,
  area            text,
  cost_class      cost_class,
  duplicate_of    uuid references receipts(id) on delete restrict,
  review_status   receipt_review_status not null default 'pending',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint no_self_duplicate check (duplicate_of is distinct from id)
);

create index on receipts (uploaded_by);
create index on receipts (project_id);
-- Duplicate detection on vendor + date + total (SPEC section 6).
create index on receipts (vendor, date, total);

create table receipt_lines (
  id              uuid primary key default gen_random_uuid(),
  receipt_id      uuid not null references receipts(id) on delete cascade,
  description     text not null,
  quantity        numeric(12,3),
  unit            text,
  unit_price      numeric(12,4),
  extended_price  numeric(12,2),
  category_id     uuid references material_categories(id) on delete restrict,
  confidence      numeric(4,3) check (confidence between 0 and 1),
  corrected_by    uuid references users(id) on delete restrict,
  created_at      timestamptz not null default now()
);

create index on receipt_lines (receipt_id);
create index on receipt_lines (category_id);

-- ---------------------------------------------------------------------
-- 15. task_events — the audit trail is the product.
--     Append only. No update, no delete, ever.
-- ---------------------------------------------------------------------

create table task_events (
  id           uuid primary key default gen_random_uuid(),
  task_id      uuid not null references tasks(id) on delete restrict,
  from_status  core_status,
  to_status    core_status not null,
  actor_id     uuid not null references users(id) on delete restrict,
  note         text,
  created_at   timestamptz not null default now()
);

create index on task_events (task_id, created_at);

create or replace function block_event_mutation() returns trigger
language plpgsql as $$
begin
  raise exception 'task_events is append-only. History is never rewritten.';
end;
$$;

create trigger trg_events_immutable
  before update or delete on task_events
  for each row execute function block_event_mutation();

-- Every status change writes an event. No exceptions.
-- [FIX-3] auth.uid() is null when the change comes from a service-role
-- job, a seed, or a SQL console, and actor_id is NOT NULL — the draft
-- would have raised a not-null violation there. Fall back to the row's
-- own actor so the audit trail can never be the reason a write fails.
-- [FIX-6] SECURITY DEFINER is load-bearing, not decoration. task_events
-- has no INSERT policy for clients — nobody forges history — so an
-- invoker-rights trigger is refused by RLS and NO status change can be
-- saved by any role at all. The trigger writes as the table owner; the
-- client still cannot insert a row of its own.
create or replace function log_task_status_change() returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  actor uuid;
begin
  if tg_op = 'INSERT' then
    insert into task_events (task_id, from_status, to_status, actor_id)
    values (new.id, null, new.status, new.created_by);
  elsif new.status is distinct from old.status then
    actor := coalesce(
      auth.uid(),
      case when new.status = 'accomplished' then new.accomplished_by end,
      new.assigned_lead,
      new.created_by
    );
    insert into task_events (task_id, from_status, to_status, actor_id)
    values (new.id, old.status, new.status, actor);
  end if;
  return new;
end;
$$;

create trigger trg_tasks_status_event
  after insert or update of status on tasks
  for each row execute function log_task_status_change();

-- ---------------------------------------------------------------------
-- 16. saved_filters — every progress-page metric is one of these.
-- ---------------------------------------------------------------------

create table saved_filters (
  id          uuid primary key default gen_random_uuid(),
  project_id  uuid references projects(id) on delete restrict,
  name        text not null,
  definition  jsonb not null,
  created_by  uuid references users(id) on delete restrict,
  is_system   boolean not null default false,
  created_at  timestamptz not null default now(),
  unique (project_id, name)
);

-- ---------------------------------------------------------------------
-- 17. updated_at maintenance
-- ---------------------------------------------------------------------

create or replace function touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_users_touch     before update on users
  for each row execute function touch_updated_at();
create trigger trg_projects_touch  before update on projects
  for each row execute function touch_updated_at();
create trigger trg_tasks_touch     before update on tasks
  for each row execute function touch_updated_at();
create trigger trg_receipts_touch  before update on receipts
  for each row execute function touch_updated_at();

-- =====================================================================
-- End of 0001. RLS policies follow in 0002_rls.sql.
-- =====================================================================
