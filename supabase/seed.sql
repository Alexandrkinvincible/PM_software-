-- PM Controller
-- Copyright © 2026 Apex Plumbing and Mechanical Services SC. All rights reserved.
-- Proprietary and confidential. See LICENSE at the repository root.

-- =====================================================================
-- Seed — one project, one user per role, plus the second Foreman and
-- second Lead that make the isolation tests meaningful. A matrix you
-- cannot exercise is a matrix you have not implemented.
--
-- Deterministic UUIDs so 01_rls_test.sql can name people directly.
--
-- Local/test use. Against a real Supabase project the people are created
-- through the Admin API (an admin screen or scripts/seed-remote.mjs), so
-- they get real credentials; this file's auth.users inserts are skipped
-- there because the rows already exist.
-- =====================================================================

select app_logout();   -- seed runs without a JWT, like the service role

-- ---- people -----------------------------------------------------------
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-000000000001', 'manager@example.com'),
  ('00000000-0000-4000-8000-000000000002', 'pm@example.com'),
  ('00000000-0000-4000-8000-000000000003', 'apm@example.com'),
  ('00000000-0000-4000-8000-000000000004', 'super@example.com'),
  ('00000000-0000-4000-8000-000000000005', 'asuper@example.com'),
  ('00000000-0000-4000-8000-000000000006', 'foreman@example.com'),
  ('00000000-0000-4000-8000-000000000007', 'lead@example.com'),
  ('00000000-0000-4000-8000-000000000008', 'foreman2@example.com'),
  ('00000000-0000-4000-8000-000000000009', 'lead2@example.com'),
  ('00000000-0000-4000-8000-00000000000a', 'sublead@example.com')
on conflict (id) do nothing;

-- ---- companies --------------------------------------------------------
insert into companies (id, name, is_house, phone) values
  ('00000000-0000-4000-8000-0000000000c1', 'Apex Plumbing and Mechanical Services SC', true,  '555-0100'),
  ('00000000-0000-4000-8000-0000000000c2', 'Harbor Mechanical (sub)',    false, '555-0200')
on conflict (id) do nothing;

-- ---- users ------------------------------------------------------------
-- in_house is not typed; the trigger in 0001 derives it from the company.
insert into users (id, email, name, default_role, company_id, trade, burdened_rate) values
  ('00000000-0000-4000-8000-000000000001','manager@example.com', 'Dana Whitfield',  'manager',          '00000000-0000-4000-8000-0000000000c1', 'management', 145.00),
  ('00000000-0000-4000-8000-000000000002','pm@example.com',      'Marcus Reyes',    'pm',               '00000000-0000-4000-8000-0000000000c1', 'management', 120.00),
  ('00000000-0000-4000-8000-000000000003','apm@example.com',     'Priya Anand',     'assistant_pm',     '00000000-0000-4000-8000-0000000000c1', 'management',  95.00),
  ('00000000-0000-4000-8000-000000000004','super@example.com',   'Tom Brenner',     'super',            '00000000-0000-4000-8000-0000000000c1', 'plumbing',    110.00),
  ('00000000-0000-4000-8000-000000000005','asuper@example.com',  'Ellis Nakamura',  'assistant_super',  '00000000-0000-4000-8000-0000000000c1', 'plumbing',     92.00),
  ('00000000-0000-4000-8000-000000000006','foreman@example.com', 'Ray Colton',      'foreman',          '00000000-0000-4000-8000-0000000000c1', 'plumbing',     88.00),
  ('00000000-0000-4000-8000-000000000007','lead@example.com',    'Junior Alvarez',  'lead',             '00000000-0000-4000-8000-0000000000c1', 'plumbing',     74.00),
  ('00000000-0000-4000-8000-000000000008','foreman2@example.com','Wes Okafor',      'foreman',          '00000000-0000-4000-8000-0000000000c1', 'plumbing',     88.00),
  ('00000000-0000-4000-8000-000000000009','lead2@example.com',   'Cal Mendoza',     'lead',             '00000000-0000-4000-8000-0000000000c1', 'plumbing',     74.00),
  ('00000000-0000-4000-8000-00000000000a','sublead@example.com', 'Ivan Petrov',     'lead',             '00000000-0000-4000-8000-0000000000c2', 'plumbing',     68.00)
on conflict (id) do nothing;

-- ---- projects ---------------------------------------------------------
insert into projects (id, name, number, client, contract_hours, contract_value) values
  ('00000000-0000-4000-8000-0000000000f1', 'Welcome Building — Phase 2', '2601', 'Northside Construction Group', 4200, 780000),
  ('00000000-0000-4000-8000-0000000000f2', 'Riverside Clinic',           '2602', 'Northside Construction Group', 1800, 310000)
on conflict (id) do nothing;

-- ---- membership -------------------------------------------------------
-- Everyone is on the Welcome Building. On Riverside, Ray Colton is the
-- Super, not the Foreman — SPEC section 3: roles are per project, and
-- this is the case that proves it.
insert into project_members (user_id, project_id, role) values
  ('00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-0000000000f1','manager'),
  ('00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-0000000000f1','pm'),
  ('00000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-0000000000f1','assistant_pm'),
  ('00000000-0000-4000-8000-000000000004','00000000-0000-4000-8000-0000000000f1','super'),
  ('00000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-0000000000f1','assistant_super'),
  ('00000000-0000-4000-8000-000000000006','00000000-0000-4000-8000-0000000000f1','foreman'),
  ('00000000-0000-4000-8000-000000000007','00000000-0000-4000-8000-0000000000f1','lead'),
  ('00000000-0000-4000-8000-000000000008','00000000-0000-4000-8000-0000000000f1','foreman'),
  ('00000000-0000-4000-8000-000000000009','00000000-0000-4000-8000-0000000000f1','lead'),
  -- Riverside: a different job, a different role for the same man.
  ('00000000-0000-4000-8000-000000000006','00000000-0000-4000-8000-0000000000f2','super'),
  ('00000000-0000-4000-8000-00000000000a','00000000-0000-4000-8000-0000000000f2','lead')
on conflict (user_id, project_id) do nothing;

-- ---- board columns ----------------------------------------------------
-- The six system columns map 1:1 to the six core statuses. The custom
-- ones are the examples from SPEC section 3a, and every one of them
-- still maps to exactly one locked core status.
insert into board_columns (project_id, name, sort_order, core_status, blocked_flag, blocked_reason_type, is_system) values
  ('00000000-0000-4000-8000-0000000000f1','Open',                10,'open',         false, null,      true),
  ('00000000-0000-4000-8000-0000000000f1','Assigned',            20,'assigned',     false, null,      true),
  ('00000000-0000-4000-8000-0000000000f1','In Progress',         30,'in_progress',  false, null,      true),
  ('00000000-0000-4000-8000-0000000000f1','Waiting on GC',       40,'in_progress',  true,  'gc',       false),
  ('00000000-0000-4000-8000-0000000000f1','Material on order',   50,'in_progress',  true,  'material', false),
  ('00000000-0000-4000-8000-0000000000f1','Ready for inspection',60,'review',       false, null,      false),
  ('00000000-0000-4000-8000-0000000000f1','Review',              70,'review',       false, null,      true),
  ('00000000-0000-4000-8000-0000000000f1','Punch list',          80,'rework',       false, null,      false),
  ('00000000-0000-4000-8000-0000000000f1','Rework',              90,'rework',       false, null,      true),
  ('00000000-0000-4000-8000-0000000000f1','Accomplished',       100,'accomplished', false, null,      true),
  ('00000000-0000-4000-8000-0000000000f2','Open',                10,'open',         false, null,      true),
  ('00000000-0000-4000-8000-0000000000f2','Assigned',            20,'assigned',     false, null,      true),
  ('00000000-0000-4000-8000-0000000000f2','In Progress',         30,'in_progress',  false, null,      true),
  ('00000000-0000-4000-8000-0000000000f2','Review',              40,'review',       false, null,      true),
  ('00000000-0000-4000-8000-0000000000f2','Rework',              50,'rework',       false, null,      true),
  ('00000000-0000-4000-8000-0000000000f2','Accomplished',        60,'accomplished', false, null,      true)
on conflict (project_id, name) do nothing;

-- ---- a little work to look at ----------------------------------------
insert into tasks (id, project_id, area, system, title, est_hours, est_qty, unit,
                   status, created_by, assigned_foreman, assigned_lead)
values
  ('00000000-0000-4000-8000-0000000000e1','00000000-0000-4000-8000-0000000000f1',
   'Welcome Bldg','domestic water','2nd floor branch rough-in', 64, 380, 'ft',
   'assigned','00000000-0000-4000-8000-000000000002',
   '00000000-0000-4000-8000-000000000006','00000000-0000-4000-8000-000000000007'),
  ('00000000-0000-4000-8000-0000000000e2','00000000-0000-4000-8000-0000000000f1',
   'Area A','sanitary','Underground stub-outs', 40, 24, 'ea',
   'open','00000000-0000-4000-8000-000000000002', null, null),
  ('00000000-0000-4000-8000-0000000000e3','00000000-0000-4000-8000-0000000000f1',
   'Area B','gas','Rooftop unit gas piping', 28, 160, 'ft',
   'assigned','00000000-0000-4000-8000-000000000004',
   '00000000-0000-4000-8000-000000000008','00000000-0000-4000-8000-000000000009')
on conflict (id) do nothing;

-- ---- receipts: the row that proves the material rule ------------------
-- Two Foremen, one receipt each. Ray must never see Wes's, and the Lead
-- must never see either.
insert into receipts (id, uploaded_by, vendor, date, invoice_number, total, image_path, project_id) values
  ('00000000-0000-4000-8000-0000000000d1','00000000-0000-4000-8000-000000000006',
   'Ferguson',   current_date - 3, 'FRG-88120',  1284.55, 'receipts/ray-ferguson.jpg',
   '00000000-0000-4000-8000-0000000000f1'),
  ('00000000-0000-4000-8000-0000000000d2','00000000-0000-4000-8000-000000000008',
   'Winsupply',  current_date - 1, 'WIN-44019',   640.10, 'receipts/wes-winsupply.jpg',
   '00000000-0000-4000-8000-0000000000f1')
on conflict (id) do nothing;

insert into receipt_lines (receipt_id, description, quantity, unit, unit_price, extended_price, category_id, confidence)
select '00000000-0000-4000-8000-0000000000d1'::uuid, '2" TYPE L COPPER TUBE', 100, 'ft', 9.82, 982.00,
       (select id from material_categories where name = 'Pipe & fittings'), 0.980
union all
select '00000000-0000-4000-8000-0000000000d1'::uuid, 'CLEVIS HANGER 2IN', 40, 'ea', 7.56, 302.40,
       (select id from material_categories where name = 'Hangers & supports'), 0.710
union all
select '00000000-0000-4000-8000-0000000000d2'::uuid, 'BALL VALVE 1-1/2 FULL PORT', 10, 'ea', 64.01, 640.10,
       (select id from material_categories where name = 'Valves & specialties'), 0.940;

-- ---- saved filters: every progress-page number starts life as one ------
insert into saved_filters (project_id, name, definition, is_system) values
  ('00000000-0000-4000-8000-0000000000f1','Hours burned vs earned — base contract',
   '{"cost_class":["base"],"group_by":["area","system"],"measure":"hours_burned_vs_earned"}', true),
  ('00000000-0000-4000-8000-0000000000f1','Rework hours',
   '{"is_rework":true,"measure":"hours"}', true),
  ('00000000-0000-4000-8000-0000000000f1','Unapproved change-order hours',
   '{"cost_class":["change_order"],"co_approved":false,"measure":"hours","aging":true}', true),
  ('00000000-0000-4000-8000-0000000000f1','Discovered defects',
   '{"work_class":["discovered_defect"],"group_by":["root_cause"],"measure":"count_hours_cost"}', true)
on conflict (project_id, name) do nothing;
