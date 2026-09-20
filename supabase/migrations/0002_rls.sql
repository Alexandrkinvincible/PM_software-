-- =====================================================================
-- Migration 0002 — Row-level security.
--
-- SPEC principle 8: security lives in the database, not the UI.
-- A Foreman querying the REST endpoint directly with his own JWT must
-- not see another Foreman's receipts. Every policy below is written to
-- survive that test, not to make the app convenient.
--
-- The role matrix implemented here is SPEC.md section 3, verbatim.
-- =====================================================================

create schema if not exists app;
revoke all on schema app from public, anon, authenticated;
grant usage on schema app to authenticated;

-- ---------------------------------------------------------------------
-- Helper functions.
--
-- These are SECURITY DEFINER on purpose: a policy on project_members
-- that queries project_members would recurse forever. Definer rights
-- break the loop. search_path is pinned so the functions cannot be
-- hijacked by a caller-controlled schema.
-- ---------------------------------------------------------------------

-- The caller's role on one project. Manager is company-wide: a Manager
-- holds authority on every project whether or not a membership row
-- exists (SPEC section 3, "Full table, all projects").
create or replace function app.role_on(p_project uuid)
returns project_role
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
    when exists (
      select 1 from project_members pm
        join users u on u.id = pm.user_id
       where pm.user_id = auth.uid()
         and pm.role = 'manager'
         and pm.active
         and u.is_active
    ) then 'manager'::project_role
    else (
      select pm.role
        from project_members pm
        join users u on u.id = pm.user_id
       where pm.user_id = auth.uid()
         and pm.project_id = p_project
         and pm.active
         and u.is_active
       limit 1
    )
  end;
$$;

create or replace function app.is_manager()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from project_members pm
      join users u on u.id = pm.user_id
     where pm.user_id = auth.uid()
       and pm.role = 'manager'
       and pm.active
       and u.is_active
  );
$$;

-- Membership test used by nearly every policy below.
create or replace function app.is_member(p_project uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select app.role_on(p_project) is not null;
$$;

-- Review -> Accomplished. SPEC section 4: Manager, PM, Super, Asst Super.
-- Assistant PM is explicitly excluded — final sign-off is one of the two
-- actions that separate Assistant PM from PM.
create or replace function app.can_sign_off(p_project uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select app.role_on(p_project)
         in ('manager','pm','super','assistant_super');
$$;

-- Change-order approval. SPEC section 3: Manager and PM only.
create or replace function app.can_approve_co(p_project uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select app.role_on(p_project) in ('manager','pm');
$$;

-- Create tasks and assign them. Everyone but Lead (SPEC section 3).
create or replace function app.can_assign(p_project uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select app.role_on(p_project)
         in ('manager','pm','assistant_pm','super','assistant_super','foreman');
$$;

-- Kick a task back to Rework. Everyone but Lead (SPEC section 3).
create or replace function app.can_kick_back(p_project uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select app.role_on(p_project)
         in ('manager','pm','assistant_pm','super','assistant_super','foreman');
$$;

-- Full material visibility: line items, prices, totals, other people's
-- receipts. SPEC section 3: Manager, PM, Assistant PM only.
create or replace function app.sees_all_material()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from project_members pm
      join users u on u.id = pm.user_id
     where pm.user_id = auth.uid()
       and pm.role in ('manager','pm','assistant_pm')
       and pm.active
       and u.is_active
  );
$$;

-- Can touch the material page at all. Lead cannot, anywhere, ever.
create or replace function app.sees_any_material()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from project_members pm
      join users u on u.id = pm.user_id
     where pm.user_id = auth.uid()
       and pm.role <> 'lead'
       and pm.active
       and u.is_active
  );
$$;

-- Admin: create users, issue credentials. Manager only (SPEC section 3).
create or replace function app.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select app.is_manager();
$$;

grant execute on all functions in schema app to authenticated;

-- ---------------------------------------------------------------------
-- Enable RLS everywhere. Default deny; every grant below is deliberate.
-- ---------------------------------------------------------------------

alter table companies           enable row level security;
alter table users               enable row level security;
alter table projects            enable row level security;
alter table project_members     enable row level security;
alter table board_columns       enable row level security;
alter table tasks               enable row level security;
alter table task_crew           enable row level security;
alter table schedule_baselines  enable row level security;
alter table time_entries        enable row level security;
alter table task_media          enable row level security;
alter table rework_items        enable row level security;
alter table notifications       enable row level security;
alter table blocked_periods     enable row level security;
alter table material_categories enable row level security;
alter table receipts            enable row level security;
alter table receipt_lines       enable row level security;
alter table task_events         enable row level security;
alter table saved_filters       enable row level security;

-- Force RLS even for the table owner, so a mistake in a definer
-- function cannot quietly hand out the whole table.
alter table receipts      force row level security;
alter table receipt_lines force row level security;
alter table users         force row level security;

-- ---------------------------------------------------------------------
-- companies — readable by any signed-in user (a crew list needs names);
-- writable by admin only.
-- ---------------------------------------------------------------------

create policy companies_read on companies
  for select to authenticated
  using (true);

create policy companies_admin_write on companies
  for all to authenticated
  using (app.is_admin())
  with check (app.is_admin());

-- ---------------------------------------------------------------------
-- users
--
-- You always see yourself. Otherwise you see people you share a project
-- with — the crew picker needs that, and nothing more.
--
-- burdened_rate is NOT protected by these row policies; it is protected
-- by the column grants at the bottom of this file. Row security decides
-- which people you see. Column security decides whether you see what
-- they cost.
-- ---------------------------------------------------------------------

create policy users_read_self on users
  for select to authenticated
  using (id = auth.uid());

create policy users_read_shared_project on users
  for select to authenticated
  using (
    app.is_manager()
    or exists (
      select 1
        from project_members mine
        join project_members theirs on theirs.project_id = mine.project_id
       where mine.user_id = auth.uid()
         and mine.active
         and theirs.user_id = users.id
         and theirs.active
    )
  );

-- A person may correct their own name and phone. Role, company, rate,
-- is_active and must_change_password are admin territory; the trigger
-- below enforces that, because RLS cannot compare old to new.
create policy users_update_self on users
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

create policy users_admin_all on users
  for all to authenticated
  using (app.is_admin())
  with check (app.is_admin());

create or replace function guard_user_self_update() returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- Admin and service-role writes pass through untouched.
  if auth.uid() is null or app.is_admin() then
    return new;
  end if;

  if new.id <> old.id then
    raise exception 'A user id cannot be changed.';
  end if;

  if new.email          is distinct from old.email
     or new.default_role   is distinct from old.default_role
     or new.company_id     is distinct from old.company_id
     or new.burdened_rate  is distinct from old.burdened_rate
     or new.in_house       is distinct from old.in_house
     or new.is_active      is distinct from old.is_active then
    raise exception
      'Only an admin can change email, role, company, rate, in_house or is_active.';
  end if;

  -- must_change_password may only be cleared, and only by the person
  -- themselves, and only from true to false. That is the first-login flow.
  if new.must_change_password is distinct from old.must_change_password
     and not (old.must_change_password and not new.must_change_password
              and new.id = auth.uid()) then
    raise exception 'must_change_password may only be cleared by the user at first login.';
  end if;

  return new;
end;
$$;

create trigger trg_users_guard_self_update
  before update on users
  for each row execute function guard_user_self_update();

-- ---------------------------------------------------------------------
-- projects — you see a project if you are on it. Manager sees all.
-- ---------------------------------------------------------------------

create policy projects_read_member on projects
  for select to authenticated
  using (app.is_member(id));

create policy projects_admin_write on projects
  for all to authenticated
  using (app.is_admin())
  with check (app.is_admin());

-- PM may edit the projects they run (contract hours, value, status).
create policy projects_pm_update on projects
  for update to authenticated
  using (app.role_on(id) in ('pm','assistant_pm'))
  with check (app.role_on(id) in ('pm','assistant_pm'));

-- ---------------------------------------------------------------------
-- project_members — visible within a shared project; written by admin.
-- ---------------------------------------------------------------------

create policy members_read on project_members
  for select to authenticated
  using (user_id = auth.uid() or app.is_member(project_id));

create policy members_admin_write on project_members
  for all to authenticated
  using (app.is_admin())
  with check (app.is_admin());

-- ---------------------------------------------------------------------
-- board_columns — read by members; shaped by PM and above.
-- ---------------------------------------------------------------------

create policy columns_read on board_columns
  for select to authenticated
  using (app.is_member(project_id));

create policy columns_write on board_columns
  for all to authenticated
  using (app.role_on(project_id) in ('manager','pm','assistant_pm','super','assistant_super'))
  with check (app.role_on(project_id) in ('manager','pm','assistant_pm','super','assistant_super'));

-- ---------------------------------------------------------------------
-- tasks
--
-- Read: any member of the project. A Lead sees the whole board for his
-- job — he needs to know what is coming — but he can only move his own
-- work, and he can never sign anything off.
-- ---------------------------------------------------------------------

create policy tasks_read on tasks
  for select to authenticated
  using (app.is_member(project_id));

create policy tasks_insert on tasks
  for insert to authenticated
  with check (
    app.can_assign(project_id)
    and created_by = auth.uid()
    -- Nobody creates a task that is already signed off.
    and status <> 'accomplished'
  );

-- Everyone but Lead can update a task on their project.
create policy tasks_update_staff on tasks
  for update to authenticated
  using (app.can_assign(project_id))
  with check (
    app.can_assign(project_id)
    -- A row may only END UP accomplished if the writer can sign off.
    and (status <> 'accomplished' or app.can_sign_off(project_id))
  );

-- A Lead updates only the tasks assigned to him, and only within the
-- statuses SPEC section 4 gives him: assigned -> in_progress -> review,
-- and rework -> in_progress -> review.
create policy tasks_update_lead on tasks
  for update to authenticated
  using (
    app.role_on(project_id) = 'lead'
    and assigned_lead = auth.uid()
  )
  with check (
    app.role_on(project_id) = 'lead'
    and assigned_lead = auth.uid()
    and status in ('assigned','in_progress','review')
  );

-- ---------------------------------------------------------------------
-- Column-level authority on tasks.
--
-- RLS WITH CHECK sees only the new row, so it cannot express "you may
-- not CHANGE this column". These rules need old vs new, so they live in
-- a trigger. Same enforcement point, same guarantee: the database.
-- ---------------------------------------------------------------------

create or replace function guard_task_privileged_columns() returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- Service role, migrations and seed run without a JWT.
  -- Internal writes are the database's own triggers (see bump_rework_count
  -- in 0001), never anything a client can set: the flag is transaction
  -- local and is turned off again by the function that set it.
  if auth.uid() is null
     or coalesce(current_setting('app.internal_write', true), 'off') = 'on' then
    return new;
  end if;

  -- Change-order approval: Manager and PM only (SPEC section 3).
  -- This covers un-approving as well as approving; both move money.
  if new.co_approved is distinct from old.co_approved
     and not app.can_approve_co(new.project_id) then
    raise exception
      'Only a Manager or PM can change change-order approval.';
  end if;

  -- Sign-off stamps are written by the sign-off, never typed.
  if (new.accomplished_by is distinct from old.accomplished_by
      or new.accomplished_at is distinct from old.accomplished_at)
     and not app.can_sign_off(new.project_id) then
    raise exception 'Only a Manager, PM, Super or Assistant Super can sign off work.';
  end if;

  -- History is never rewritten (SPEC principle 6). An Accomplished task
  -- stays Accomplished; a later problem becomes a new defect ticket
  -- pointing back at it.
  if old.status = 'accomplished' and new.status <> 'accomplished' then
    raise exception
      'An Accomplished task cannot be reopened. Create a discovered-defect ticket with source_task_id = %.',
      old.id;
  end if;

  -- rework_count is derived from rework_items, never typed.
  if new.rework_count is distinct from old.rework_count then
    raise exception 'rework_count is derived from rework_items and cannot be set directly.';
  end if;

  return new;
end;
$$;

create trigger trg_tasks_guard_privileged
  before update on tasks
  for each row execute function guard_task_privileged_columns();

-- ---------------------------------------------------------------------
-- task_crew, task_media, rework_items, blocked_periods, schedule_baselines
-- — all scoped to the task's project.
-- ---------------------------------------------------------------------

create policy crew_read on task_crew
  for select to authenticated
  using (exists (select 1 from tasks t where t.id = task_id and app.is_member(t.project_id)));

create policy crew_write on task_crew
  for all to authenticated
  using (exists (select 1 from tasks t where t.id = task_id and app.can_assign(t.project_id)))
  with check (exists (select 1 from tasks t where t.id = task_id and app.can_assign(t.project_id)));

create policy media_read on task_media
  for select to authenticated
  using (exists (select 1 from tasks t where t.id = task_id and app.is_member(t.project_id)));

-- Anyone on the job can add a photo — that is the point of the phone.
create policy media_insert on task_media
  for insert to authenticated
  with check (
    uploaded_by = auth.uid()
    and exists (select 1 from tasks t where t.id = task_id and app.is_member(t.project_id))
  );

create policy rework_read on rework_items
  for select to authenticated
  using (exists (select 1 from tasks t where t.id = task_id and app.is_member(t.project_id)));

create policy rework_insert on rework_items
  for insert to authenticated
  with check (
    rejected_by = auth.uid()
    and exists (select 1 from tasks t where t.id = task_id and app.can_kick_back(t.project_id))
  );

create policy blocked_read on blocked_periods
  for select to authenticated
  using (exists (select 1 from tasks t where t.id = task_id and app.is_member(t.project_id)));

create policy blocked_write on blocked_periods
  for all to authenticated
  using (exists (select 1 from tasks t where t.id = task_id and app.is_member(t.project_id)))
  with check (exists (select 1 from tasks t where t.id = task_id and app.is_member(t.project_id)));

create policy baselines_read on schedule_baselines
  for select to authenticated
  using (app.is_member(project_id));

create policy baselines_write on schedule_baselines
  for all to authenticated
  using (app.role_on(project_id) in ('manager','pm','assistant_pm'))
  with check (app.role_on(project_id) in ('manager','pm','assistant_pm'));

-- ---------------------------------------------------------------------
-- time_entries
--
-- SPEC principle: hours are never typed. The Lead opens and closes a
-- session and picks the crew; the app writes one row per person. A man
-- can always see his own hours.
-- ---------------------------------------------------------------------

create policy time_read on time_entries
  for select to authenticated
  using (
    user_id = auth.uid()
    or exists (select 1 from tasks t where t.id = task_id and app.is_member(t.project_id))
  );

create policy time_write on time_entries
  for all to authenticated
  using (exists (
    select 1 from tasks t
     where t.id = task_id
       and (app.can_assign(t.project_id)
            or (app.role_on(t.project_id) = 'lead' and t.assigned_lead = auth.uid()))
  ))
  with check (exists (
    select 1 from tasks t
     where t.id = task_id
       and (app.can_assign(t.project_id)
            or (app.role_on(t.project_id) = 'lead' and t.assigned_lead = auth.uid()))
  ));

-- ---------------------------------------------------------------------
-- notifications — strictly your own.
-- ---------------------------------------------------------------------

create policy notifications_own on notifications
  for select to authenticated
  using (recipient_id = auth.uid());

create policy notifications_mark_read on notifications
  for update to authenticated
  using (recipient_id = auth.uid())
  with check (recipient_id = auth.uid());

-- ---------------------------------------------------------------------
-- task_events — the audit trail. Readable by the project; never written
-- by a client. Only the 0001 trigger inserts here.
-- ---------------------------------------------------------------------

create policy events_read on task_events
  for select to authenticated
  using (exists (select 1 from tasks t where t.id = task_id and app.is_member(t.project_id)));

-- No insert, update or delete policy exists for task_events on purpose.

-- ---------------------------------------------------------------------
-- MATERIAL — the sharpest line in the spec.
--
--   Manager / PM / Assistant PM : every receipt and every line item.
--   Super / Asst Super / Foreman: only rows they uploaded themselves.
--   Lead                        : nothing. Not one row, not one column.
--
-- This is the Phase 1 acceptance test.
-- ---------------------------------------------------------------------

create policy categories_read on material_categories
  for select to authenticated
  using (app.sees_any_material());

create policy categories_pm_write on material_categories
  for all to authenticated
  using (app.sees_all_material())
  with check (app.sees_all_material());

create policy receipts_read on receipts
  for select to authenticated
  using (
    app.sees_all_material()
    or (app.sees_any_material() and uploaded_by = auth.uid())
  );

create policy receipts_insert on receipts
  for insert to authenticated
  with check (app.sees_any_material() and uploaded_by = auth.uid());

create policy receipts_update on receipts
  for update to authenticated
  using (
    app.sees_all_material()
    or (app.sees_any_material() and uploaded_by = auth.uid())
  )
  with check (
    app.sees_all_material()
    or (app.sees_any_material() and uploaded_by = auth.uid())
  );

create policy lines_read on receipt_lines
  for select to authenticated
  using (
    exists (
      select 1 from receipts r
       where r.id = receipt_id
         and (app.sees_all_material()
              or (app.sees_any_material() and r.uploaded_by = auth.uid()))
    )
  );

create policy lines_write on receipt_lines
  for all to authenticated
  using (app.sees_all_material())
  with check (app.sees_all_material());

-- ---------------------------------------------------------------------
-- saved_filters — every progress-page number is one of these.
-- ---------------------------------------------------------------------

create policy filters_read on saved_filters
  for select to authenticated
  using (project_id is null or app.is_member(project_id));

create policy filters_write on saved_filters
  for all to authenticated
  using (project_id is not null and app.can_assign(project_id) and not is_system)
  with check (project_id is not null and app.can_assign(project_id) and not is_system);

-- ---------------------------------------------------------------------
-- Column-level security on burdened_rate.
--
-- Row policies say which people you can see. This says whether you can
-- see what they cost. A Lead or Foreman selecting users.burdened_rate
-- gets a permission error from Postgres, not a null.
-- ---------------------------------------------------------------------

revoke all on users from authenticated;
grant select (
  id, email, name, phone, default_role, company_id, trade, in_house,
  is_active, must_change_password, created_at, updated_at
) on users to authenticated;
grant insert, update, delete on users to authenticated;

-- burdened_rate is reachable only through this view.
--
-- [FIX-5] The first cut made this security_invoker, which cannot work:
-- the column grants above deny `authenticated` any access to
-- burdened_rate, so an invoker-rights view reading it fails for
-- everybody, PM included. The view therefore runs with the owner's
-- rights — which means it must carry its own row scope, because the
-- owner also bypasses the row policies on users. Both halves of that
-- scope are written out below and tested in 01_rls_test.sql.
--
--   1. Who may see cost at all: Manager, PM, Assistant PM.
--   2. Whose cost they may see: people sharing one of their projects
--      (a Manager is company-wide and sees everyone).
create or replace view users_costed as
  select u.id, u.name, u.email, u.default_role, u.company_id,
         u.in_house, u.burdened_rate, u.is_active
    from users u
   where app.sees_all_material()
     and (
       app.is_manager()
       or exists (
         select 1
           from project_members mine
           join project_members theirs on theirs.project_id = mine.project_id
          where mine.user_id = auth.uid()
            and mine.active
            and theirs.user_id = u.id
            and theirs.active
       )
     );

revoke all on users_costed from public, anon;
grant select on users_costed to authenticated;

-- =====================================================================
-- End of 0002.
-- =====================================================================
