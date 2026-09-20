#!/usr/bin/env bash
# =====================================================================
# Apply the migrations to a throwaway Postgres and run the Phase 1 RLS
# acceptance suite against them.
#
# The suite signs tasks off, approves change orders and deactivates a
# user, so it is deliberately NOT idempotent — it always runs against a
# freshly seeded database. That is the point: it exercises the real
# transitions rather than read-only queries.
#
#   ./scripts/db-test.sh              # uses a local cluster on port 5439
#   PGPORT=5432 ./scripts/db-test.sh  # or point it at your own
# =====================================================================
set -euo pipefail

PGHOST="${PGHOST:-/tmp}"
PGPORT="${PGPORT:-5439}"
PGUSER="${PGUSER:-postgres}"
DB="${DB:-fieldtask}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

psql_() { psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" "$@"; }

echo "==> rebuilding $DB"
psql_ -q -c "drop database if exists $DB;" -c "create database $DB;"

echo "==> local Supabase stub (auth.users, auth.uid, roles)"
psql_ -d "$DB" -v ON_ERROR_STOP=1 -q \
  -c "create extension if not exists pgcrypto;" \
  -f "$ROOT/supabase/tests/00_local_stub.sql"

echo "==> 0001_schema.sql"
psql_ -d "$DB" -v ON_ERROR_STOP=1 -q -f "$ROOT/supabase/migrations/0001_schema.sql"

echo "==> 0002_rls.sql"
psql_ -d "$DB" -v ON_ERROR_STOP=1 -q -f "$ROOT/supabase/migrations/0002_rls.sql"

echo "==> seed.sql"
psql_ -d "$DB" -v ON_ERROR_STOP=1 -q -f "$ROOT/supabase/seed.sql"

echo "==> 01_rls_test.sql"
psql_ -d "$DB" -v ON_ERROR_STOP=1 -f "$ROOT/supabase/tests/01_rls_test.sql"
