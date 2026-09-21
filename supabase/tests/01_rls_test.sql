-- PM Controller
-- Copyright © 2026 Apex Plumbing and Mechanical Services SC. All rights reserved.
-- Proprietary and confidential. See LICENSE at the repository root.

-- =====================================================================
-- Phase 1 acceptance test.
--
-- SPEC principle 8 says security lives in the database. That claim is
-- only worth something if it is tested from the outside — as the role a
-- phone actually holds, not as the owner. Every test below runs with
-- `set role authenticated` and a signed-in user id, which is exactly
-- what a JWT gives PostgREST.
--
-- The milestone: an admin creates a Lead by email, and that Lead sees
-- only his project and cannot read the receipts tables at all.
--
-- This suite signs work off, approves a change order, moves cards across
-- board columns and deactivates a user. It is deliberately NOT idempotent — it must run against a freshly
-- seeded database, which is what scripts/db-test.sh guarantees.
--
-- Run:  ./scripts/db-test.sh
-- Exit is non-zero and the last line reads FAILED if anything regressed.
-- =====================================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset pager off

create temporary table results (
  n        serial,
  area     text,
  label    text,
  ok       boolean,
  detail   text
);

-- The harness records results while running AS the role under test, so
-- the scratch table has to be reachable from that role. Nothing about
-- this grant touches the tables being tested.
do $$ begin
  execute format('grant usage on schema %s to authenticated',
                 pg_my_temp_schema()::regnamespace);
end $$;
grant all on results to authenticated;
grant all on sequence results_n_seq to authenticated;

-- ---------------------------------------------------------------------
-- Harness
-- ---------------------------------------------------------------------

create or replace function t_eq(p_area text, p_label text, p_sql text, p_expected text)
returns void language plpgsql as $$
declare got text;
begin
  execute p_sql into got;
  insert into results (area, label, ok, detail)
  values (p_area, p_label,
          coalesce(got, '<null>') = p_expected,
          format('expected %s, got %s', p_expected, coalesce(got, '<null>')));
exception when others then
  insert into results (area, label, ok, detail)
  values (p_area, p_label, false, 'raised: ' || sqlerrm);
end;
$$;

-- Asserts the statement is REFUSED. A permission rule that does not
-- refuse is not a rule.
create or replace function t_denied(p_area text, p_label text, p_sql text)
returns void language plpgsql as $$
begin
  execute p_sql;
  insert into results (area, label, ok, detail)
  values (p_area, p_label, false, 'statement was ALLOWED but must be refused');
exception when others then
  insert into results (area, label, ok, detail)
  values (p_area, p_label, true, 'refused: ' || left(sqlerrm, 90));
end;
$$;

-- RLS usually refuses by matching no rows rather than by raising. That is
-- still a refusal, and it is the shape most UPDATE denials take, so it
-- gets its own assertion instead of being mistaken for permission.
create or replace function t_no_effect(p_area text, p_label text, p_sql text)
returns void language plpgsql as $$
declare touched int;
begin
  execute 'with a as (' || p_sql || ' returning 1) select count(*) from a' into touched;
  insert into results (area, label, ok, detail)
  values (p_area, p_label, touched = 0,
          case when touched = 0 then 'no rows reachable'
               else format('CHANGED %s row(s) that should be out of reach', touched) end);
exception when others then
  -- Raising outright is an even stronger refusal.
  insert into results (area, label, ok, detail)
  values (p_area, p_label, true, 'refused: ' || left(sqlerrm, 90));
end;
$$;

create or replace function t_allowed(p_area text, p_label text, p_sql text)
returns void language plpgsql as $$
begin
  execute p_sql;
  insert into results (area, label, ok, detail) values (p_area, p_label, true, 'allowed');
exception when others then
  insert into results (area, label, ok, detail)
  values (p_area, p_label, false, 'refused but should be allowed: ' || left(sqlerrm, 90));
end;
$$;

-- People, by name, so the tests read like the role matrix.
\set manager  '''00000000-0000-4000-8000-000000000001'''
\set pm       '''00000000-0000-4000-8000-000000000002'''
\set apm      '''00000000-0000-4000-8000-000000000003'''
\set super    '''00000000-0000-4000-8000-000000000004'''
\set asuper   '''00000000-0000-4000-8000-000000000005'''
\set foreman  '''00000000-0000-4000-8000-000000000006'''
\set lead     '''00000000-0000-4000-8000-000000000007'''
\set foreman2 '''00000000-0000-4000-8000-000000000008'''
\set lead2    '''00000000-0000-4000-8000-000000000009'''
\set sublead  '''00000000-0000-4000-8000-00000000000a'''
\set task_lead  '''00000000-0000-4000-8000-0000000000e1'''
\set task_open  '''00000000-0000-4000-8000-0000000000e2'''
\set task_lead2 '''00000000-0000-4000-8000-0000000000e3'''
\set rcpt_ray   '''00000000-0000-4000-8000-0000000000d1'''
\set rcpt_wes   '''00000000-0000-4000-8000-0000000000d2'''
\set proj_wb    '''00000000-0000-4000-8000-0000000000f1'''
\set proj_rc    '''00000000-0000-4000-8000-0000000000f2'''

set role authenticated;

-- =====================================================================
-- A. Project isolation — "sees only his project"
-- =====================================================================

select app_login(:lead);
select t_eq('projects', 'Lead sees exactly one project',
            'select count(*)::text from projects', '1');
select t_eq('projects', 'Lead''s one project is the Welcome Building',
            'select number from projects', '2601');
select t_eq('projects', 'Lead sees only his project''s tasks',
            'select count(*)::text from tasks', '3');

select app_login(:sublead);
select t_eq('projects', 'Sub Lead on Riverside sees only Riverside',
            'select number from projects', '2602');
select t_eq('projects', 'Sub Lead sees none of the Welcome Building tasks',
            'select count(*)::text from tasks', '0');

select app_login(:manager);
select t_eq('projects', 'Manager sees every project',
            'select count(*)::text from projects', '2');

select app_login(:foreman);
select t_eq('projects', 'Foreman on two jobs sees both',
            'select count(*)::text from projects', '2');
select t_eq('roles',    'Same man is Foreman on one job',
            'select app.role_on(' || quote_literal(:proj_wb) || ')::text', 'foreman');
select t_eq('roles',    'and Super on the other (roles are per project)',
            'select app.role_on(' || quote_literal(:proj_rc) || ')::text', 'super');

-- =====================================================================
-- B. Material — the sharpest line in the spec.
--    Lead: nothing. Foreman/Super: own uploads. PM and up: everything.
-- =====================================================================

select app_login(:lead);
select t_eq('material', 'Lead reads ZERO receipts',
            'select count(*)::text from receipts', '0');
select t_eq('material', 'Lead reads ZERO receipt lines',
            'select count(*)::text from receipt_lines', '0');
select t_eq('material', 'Lead reads ZERO material categories',
            'select count(*)::text from material_categories', '0');
select t_denied('material', 'Lead cannot upload a receipt',
   'insert into receipts (uploaded_by, image_path, vendor) values (' || quote_literal(:lead) || ', ''x.jpg'', ''Ferguson'')');

select app_login(:foreman);
select t_eq('material', 'Foreman reads exactly his own receipt',
            'select count(*)::text from receipts', '1');
select t_eq('material', 'and it is his',
            'select vendor from receipts', 'Ferguson');
select t_eq('material', 'Foreman cannot read the other Foreman''s receipt by id',
            'select count(*)::text from receipts where id = ' || quote_literal(:rcpt_wes), '0');
select t_eq('material', 'Foreman sees only his own receipt''s lines',
            'select count(*)::text from receipt_lines', '2');

select app_login(:foreman2);
select t_eq('material', 'Second Foreman reads exactly his own receipt',
            'select vendor from receipts', 'Winsupply');

select app_login(:super);
select t_eq('material', 'Super sees own uploads only (he has none)',
            'select count(*)::text from receipts', '0');
select app_login(:asuper);
select t_eq('material', 'Assistant Super is a full clone of Super',
            'select count(*)::text from receipts', '0');

select app_login(:apm);
select t_eq('material', 'Assistant PM keeps full material visibility',
            'select count(*)::text from receipts', '2');
select t_eq('material', 'Assistant PM sees every line item',
            'select count(*)::text from receipt_lines', '3');

select app_login(:pm);
select t_eq('material', 'PM sees every receipt',
            'select count(*)::text from receipts', '2');
select app_login(:manager);
select t_eq('material', 'Manager sees every receipt, all projects',
            'select count(*)::text from receipts', '2');

-- =====================================================================
-- C. Sign-off — Review to Accomplished.
--    Manager, PM, Super, Assistant Super. Never Assistant PM. Never Lead.
-- =====================================================================

-- Setup, as the service role would do it. `reset role` matters: app_logout
-- clears the JWT claim but the database role stays, and an authenticated
-- role with no uid passes no policy, so the setup would silently touch
-- nothing and every test after it would be measuring the wrong thing.
reset role;
select app_logout();
update tasks set status = 'review' where id = :task_lead;
set role authenticated;

select app_login(:lead);
select t_denied('signoff', 'Lead cannot sign off work',
  'update tasks set status = ''accomplished'', accomplished_at = now(), accomplished_by = ' || quote_literal(:lead) || ' where id = ' || quote_literal(:task_lead));

select app_login(:foreman);
select t_denied('signoff', 'Foreman cannot sign off work',
  'update tasks set status = ''accomplished'', accomplished_at = now(), accomplished_by = ' || quote_literal(:foreman) || ' where id = ' || quote_literal(:task_lead));

select app_login(:apm);
select t_denied('signoff', 'Assistant PM cannot sign off (PM minus finality)',
  'update tasks set status = ''accomplished'', accomplished_at = now(), accomplished_by = ' || quote_literal(:apm) || ' where id = ' || quote_literal(:task_lead));

select app_login(:super);
select t_allowed('signoff', 'Super CAN sign off work',
  'update tasks set status = ''accomplished'', accomplished_at = now(), accomplished_by = ' || quote_literal(:super) || ' where id = ' || quote_literal(:task_lead));

-- =====================================================================
-- D. History is never rewritten (SPEC principle 6)
-- =====================================================================

select app_login(:manager);
select t_denied('history', 'An Accomplished task cannot be reopened, even by the Manager',
  'update tasks set status = ''in_progress'' where id = ' || quote_literal(:task_lead));
-- No UPDATE or DELETE policy exists on task_events, so a client's
-- statement matches no rows rather than raising. The guarantee that
-- matters is that history is unchanged afterwards, so assert that —
-- and then prove the append-only trigger stops even a service-role
-- write, which is the only caller that could reach a row at all.
select t_no_effect('history', 'a client UPDATE on task_events changes nothing',
  'update task_events set note = ''tidy up''');
select t_no_effect('history', 'a client DELETE on task_events removes nothing',
  'delete from task_events');
select t_denied('history', 'task_events cannot be written by a client',
  'insert into task_events (task_id, to_status, actor_id) values (' || quote_literal(:task_open) || ', ''review'', ' || quote_literal(:manager) || ')');
select t_eq('history', 'the sign-off wrote its own audit row',
  'select to_status::text from task_events where task_id = ' || quote_literal(:task_lead) || ' order by created_at desc limit 1',
  'accomplished');

-- The service role bypasses RLS entirely. The append-only trigger is
-- what stands between a bad script and a rewritten audit trail.
reset role;
select app_logout();
select t_denied('history', 'not even the service role can rewrite task_events',
  'update task_events set note = ''tidy up''');
select t_denied('history', 'not even the service role can delete task_events',
  'delete from task_events');
set role authenticated;

-- =====================================================================
-- E. Change orders — Manager and PM only
-- =====================================================================

reset role;
select app_logout();
update tasks set cost_class = 'change_order', co_number = 'CO-014', co_hours = 18
  where id = :task_open;
set role authenticated;

select app_login(:apm);
select t_denied('money', 'Assistant PM cannot approve a change order',
  'update tasks set co_approved = true where id = ' || quote_literal(:task_open));
select app_login(:super);
select t_denied('money', 'Super cannot approve a change order',
  'update tasks set co_approved = true where id = ' || quote_literal(:task_open));
select app_login(:pm);
select t_allowed('money', 'PM CAN approve a change order',
  'update tasks set co_approved = true where id = ' || quote_literal(:task_open));
select app_login(:apm);
select t_denied('money', 'Assistant PM cannot un-approve one either',
  'update tasks set co_approved = false where id = ' || quote_literal(:task_open));

-- =====================================================================
-- F. Core statuses are locked in the database, not hidden in the UI
-- =====================================================================

select app_login(:manager);
select t_denied('core', 'A seventh core status cannot be inserted',
  'update tasks set status = ''almost_done'' where id = ' || quote_literal(:task_lead2));
select t_denied('core', 'A board column cannot map to a status it does not match',
  'update tasks set board_column_id = (select id from board_columns where project_id = ' || quote_literal(:proj_wb) ||
  ' and name = ''Accomplished'') where id = ' || quote_literal(:task_lead2));
select t_denied('core', 'rework_count cannot be typed by hand',
  'update tasks set rework_count = 7 where id = ' || quote_literal(:task_lead2));

-- rework_count IS derived: a kick-back bumps it.
select app_login(:super);
select t_allowed('core', 'A kick-back writes a rework_items row',
  'insert into rework_items (task_id, rejected_by, reason) values (' || quote_literal(:task_lead2) || ', ' || quote_literal(:super) || ', ''Hangers at 12ft, spec is 8ft'')');
select t_eq('core', 'and the derived rework_count follows it',
  'select rework_count::text from tasks where id = ' || quote_literal(:task_lead2), '1');

-- =====================================================================
-- G. Lead movement — his own work, within his own statuses
-- =====================================================================

select app_login(:lead2);
select t_allowed('lead', 'Lead moves HIS task to In Progress',
  'update tasks set status = ''in_progress'' where id = ' || quote_literal(:task_lead2));
select t_no_effect('lead', 'Lead cannot touch another Lead''s task',
  'update tasks set status = ''review'' where id = ' || quote_literal(:task_open));
select t_denied('lead', 'Lead cannot create a task',
  'insert into tasks (project_id, area, system, title, created_by) values (' || quote_literal(:proj_wb) || ', ''Area A'', ''gas'', ''mine'', ' || quote_literal(:lead2) || ')');
select t_denied('lead', 'Lead cannot kick work back to Rework',
  'insert into rework_items (task_id, rejected_by, reason) values (' || quote_literal(:task_lead2) || ', ' || quote_literal(:lead2) || ', ''nope'')');

-- =====================================================================
-- H. People — cost visibility, deactivation, self-service
-- =====================================================================

select app_login(:lead);
select t_denied('people', 'Lead cannot read burdened_rate at all',
  'select burdened_rate from users where id = ' || quote_literal(:lead));
select t_eq('people', 'Lead reads nothing from the costed view',
  'select count(*)::text from users_costed', '0');
select t_denied('people', 'Lead cannot promote himself',
  'update users set default_role = ''manager'' where id = ' || quote_literal(:lead));
select t_no_effect('people', 'Lead cannot reactivate a deactivated man',
  'update users set is_active = true where id = ' || quote_literal(:lead2));
select t_allowed('people', 'A man may fix his own phone number',
  'update users set phone = ''555-0177'' where id = ' || quote_literal(:lead));

select app_login(:pm);
select t_eq('people', 'PM reads burdened rates through the costed view',
  'select count(*)::text from users_costed', '9');

select app_login(:manager);
select t_denied('people', 'A user can never be deleted, not even by the Manager',
  'delete from users where id = ' || quote_literal(:lead2));
select t_allowed('people', 'Deactivation is the only path',
  'update users set is_active = false where id = ' || quote_literal(:lead2));

-- =====================================================================
-- I. The board (Phase 2)
--
--    The board's promise is that a column is cosmetic and the core
--    status underneath is not. These assert that promise from the
--    database side, where it is actually kept.
--
--    NOTE: this section deliberately uses `lead` and a ticket of its
--    own. Section H deactivates `lead2`, and an inactive user matches
--    no policy at all — every statement would touch zero rows, which
--    reads as a pass for anything asserting a refusal. A test that
--    passes because nothing happened is worse than no test.
-- =====================================================================

\set col_inprog  '''00000000-0000-4000-8000-0000000000b1'''
\set col_gc      '''00000000-0000-4000-8000-0000000000b2'''
\set col_review  '''00000000-0000-4000-8000-0000000000b3'''
\set task_board  '''00000000-0000-4000-8000-0000000000e9'''

reset role;
select app_logout();

-- Two custom columns inside one core status, and one in another, named
-- so the tests below read without consulting the seed.
insert into board_columns (id, project_id, name, sort_order, core_status,
                           blocked_flag, blocked_reason_type, is_system)
values
  (:col_inprog, :proj_wb, 'Rough-in bay',       210, 'in_progress', false, null,  false),
  (:col_gc,     :proj_wb, 'Held for GC',        220, 'in_progress', true,  'gc',  false),
  (:col_review, :proj_wb, 'Walked, not signed', 230, 'review',      false, null,  false);

-- A ticket of this section's own, assigned to an active Lead.
insert into tasks (id, project_id, area, system, title, est_hours,
                   status, board_column_id, created_by, assigned_lead)
values (:task_board, :proj_wb, 'Area C', 'domestic water',
        'Board fixture — riser 3', 20,
        'in_progress', :col_inprog, :super, :lead);

set role authenticated;

select app_login(:lead);
select t_eq('board', 'A Lead sees every column on his job',
  'select count(*)::text from board_columns where project_id = ' || quote_literal(:proj_wb), '13');

select t_allowed('board', 'A Lead moves his card between two columns of the SAME core status',
  'update tasks set board_column_id = ' || quote_literal(:col_gc) ||
  ' where id = ' || quote_literal(:task_board));
select t_eq('board', 'the card actually moved',
  'select board_column_id::text from tasks where id = ' || quote_literal(:task_board),
  '00000000-0000-4000-8000-0000000000b2');
select t_eq('board', 'and its core status did not change',
  'select status::text from tasks where id = ' || quote_literal(:task_board), 'in_progress');

-- The trigger is what makes a column cosmetic: the pair must agree.
select t_denied('board', 'A column cannot be set without the status that matches it',
  'update tasks set board_column_id = ' || quote_literal(:col_review) ||
  ' where id = ' || quote_literal(:task_board));
select t_allowed('board', 'The same move succeeds when status travels with it',
  'update tasks set board_column_id = ' || quote_literal(:col_review) ||
  ', status = ''review'' where id = ' || quote_literal(:task_board));

-- Cross-project protection is two separate things, and conflating them
-- hides a hole. First: a Lead cannot even NAME another project's column,
-- because row security does not show it to him — so a subquery for one
-- yields null, and a null column is simply "not placed yet".
select t_eq('board', 'A Lead cannot see another project''s columns at all',
  'select count(*)::text from board_columns where project_id = ' || quote_literal(:proj_rc), '0');

-- Second: for somebody who CAN see both projects — a Manager — the
-- trigger is what refuses the mismatch. That is the layer that would
-- matter if a policy were ever loosened.
select app_login(:manager);
select t_eq('board', 'A Manager can see both projects'' columns',
  'select count(*)::text from board_columns where project_id = ' || quote_literal(:proj_rc), '6');
select t_denied('board', 'but cannot drop a card on the other project''s column',
  'update tasks set board_column_id = (select id from board_columns where project_id = ' ||
  quote_literal(:proj_rc) || ' and name = ''Open'') where id = ' || quote_literal(:task_board));
select app_login(:lead);

-- The Phase 2 milestone, stated the way the board states it.
select t_denied('board', 'MILESTONE — a Lead cannot move a card into Accomplished',
  'update tasks set status = ''accomplished'', accomplished_at = now(), accomplished_by = ' ||
  quote_literal(:lead) || ', board_column_id = (select id from board_columns where project_id = ' ||
  quote_literal(:proj_wb) || ' and name = ''Accomplished'') where id = ' || quote_literal(:task_board));
select t_eq('board', 'and the card is still sitting in Review',
  'select status::text from tasks where id = ' || quote_literal(:task_board), 'review');

select app_login(:super);
select t_allowed('board', 'A Super can make that same move',
  'update tasks set status = ''accomplished'', accomplished_at = now(), accomplished_by = ' ||
  quote_literal(:super) || ', board_column_id = (select id from board_columns where project_id = ' ||
  quote_literal(:proj_wb) || ' and name = ''Accomplished'') where id = ' || quote_literal(:task_board));

select t_eq('board', 'the move wrote its own audit row',
  'select to_status::text from task_events where task_id = ' || quote_literal(:task_board) ||
  ' order by created_at desc limit 1', 'accomplished');

-- =====================================================================
-- Report
-- =====================================================================

reset role;
select app_logout();

\set QUIET off
\echo ''
\echo '================ PHASE 1 RLS ACCEPTANCE ================'
select lpad(n::text, 3) as "#",
       rpad(area, 9)    as area,
       case when ok then 'PASS' else 'FAIL' end as result,
       label,
       case when ok then '' else detail end as why
  from results order by n;

select count(*) filter (where ok)        as passed,
       count(*) filter (where not ok)    as failed,
       case when count(*) filter (where not ok) = 0
            then 'ALL GREEN — Phase 1 and Phase 2 database gates met'
            else 'FAILED' end            as verdict
  from results;

-- Non-zero exit when anything failed, so CI can gate on this file.
-- (A `1/0` in a CASE does not work here: Postgres constant-folds it at
-- plan time and the query fails even when every assertion passed.)
do $$
declare failed int;
begin
  select count(*) into failed from results where not ok;
  if failed > 0 then
    raise exception '% RLS assertion(s) failed — see the table above', failed;
  end if;
end $$;
