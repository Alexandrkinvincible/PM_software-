-- =====================================================================
-- Local test harness only. NEVER applied to a Supabase project.
--
-- Supabase gives us auth.users, auth.uid() and the anon / authenticated
-- / service_role grants for free. To apply and test the real migrations
-- on a plain Postgres, we stand up just enough of that surface, then run
-- 0001 and 0002 completely unmodified.
--
-- auth.uid() reads a session GUC here instead of a JWT claim. Calling
-- app_login('<uuid>') is the local equivalent of signing in as that
-- person, which is what makes the RLS tests in 01_rls_test.sql possible.
-- =====================================================================

create schema if not exists auth;

create table if not exists auth.users (
  id            uuid primary key default gen_random_uuid(),
  email         text unique,
  created_at    timestamptz not null default now()
);

create or replace function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

create or replace function auth.role() returns text
language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), 'anon');
$$;

do $$ begin
  create role anon nologin;
exception when duplicate_object then null; end $$;

do $$ begin
  create role authenticated nologin;
exception when duplicate_object then null; end $$;

do $$ begin
  create role service_role nologin bypassrls;
exception when duplicate_object then null; end $$;

grant usage on schema public to anon, authenticated, service_role;
grant usage on schema auth   to anon, authenticated, service_role;
grant select on auth.users   to authenticated, service_role;

alter default privileges in schema public
  grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public
  grant all on tables to service_role;

-- Sign in as a person for the duration of the transaction.
create or replace function app_login(p_user uuid) returns void
language plpgsql as $$
begin
  -- Session scope, not transaction scope: the tests sign in once and
  -- then run many statements as that person.
  perform set_config('request.jwt.claim.sub', p_user::text, false);
  perform set_config('request.jwt.claim.role', 'authenticated', false);
end;
$$;

-- Drop back to no user at all (service-role style write).
create or replace function app_logout() returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', '', false);
  perform set_config('request.jwt.claim.role', 'service_role', false);
end;
$$;
