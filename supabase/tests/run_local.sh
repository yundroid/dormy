#!/usr/bin/env bash
# Yerel bir PostgreSQL'e karşı migration + RLS testlerini çalıştırır.
# Her test dosyası temiz bir veritabanında çalışır.
# Kullanım: PGHOST=... PGPORT=... PGUSER=postgres supabase/tests/run_local.sh
set -euo pipefail
cd "$(dirname "$0")/.."
DB=dormy_test
for t in tests/*_test.sql; do
  echo "== $t"
  psql -q -v ON_ERROR_STOP=1 -c "drop database if exists $DB" -c "create database $DB"
  psql -q -v ON_ERROR_STOP=1 -d $DB -f tests/stub_supabase.sql
  for f in migrations/*.sql; do
    psql -q -v ON_ERROR_STOP=1 -d $DB -f "$f"
  done
  psql -q -v ON_ERROR_STOP=1 -d $DB -f tests/helpers.sql
  psql -q -At -v ON_ERROR_STOP=1 -d $DB -f "$t" | grep -v "^$"
done
