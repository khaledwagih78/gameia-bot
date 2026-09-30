#!/usr/bin/env bash
# تشغيل الاختبارات على قاعدة Postgres محلية فاضية
#   PGHOST=... PGPORT=... PGUSER=postgres ./run.sh
set -euo pipefail
cd "$(dirname "$0")"
DB=ams_test
psql -v ON_ERROR_STOP=1 -qc "drop database if exists $DB" -c "create database $DB" postgres
for f in 00_supabase_stub.sql ../migrations/0001_schema.sql ../migrations/0002_logic.sql \
         ../migrations/0003_security.sql ../seed.sql 10_finance_test.sql; do
  psql -v ON_ERROR_STOP=1 -q -d "$DB" -f "$f"
done
