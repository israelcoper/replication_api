#!/bin/bash
set -e

# This script runs inside db01 via docker-entrypoint-initdb.d/
# It executes once during the first initialization of the database.

# 1. Create replication user with login + replication privileges
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE USER replication_user
      WITH REPLICATION LOGIN
      ENCRYPTED PASSWORD 'repl_secret_123';

    GRANT SELECT ON ALL TABLES IN SCHEMA public TO replication_user;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public
      GRANT SELECT ON TABLES TO replication_user;
EOSQL

# 2. Create physical replication slot
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    SELECT pg_create_physical_replication_slot('replication_api_slot');
EOSQL

# 3. Append replication entry to pg_hba.conf
# Using 0.0.0.0/0 so any container on the Docker network can connect
# (Docker network isolation provides the security boundary)
echo "host replication replication_user 0.0.0.0/0 scram-sha-256" \
  >> "$PGDATA/pg_hba.conf"

echo "Primary initialization complete."
echo "  - replication_user created"
echo "  - replication_api_slot created"
echo "  - pg_hba.conf updated for replication access"
