#!/bin/bash
set -e

echo "=== Replica initialization ==="

# 1. Wait for primary to be fully ready
echo "Waiting for primary (primarydb) to accept connections..."
until PGPASSWORD=postgres pg_isready -h primarydb -U postgres -q; do
  echo "  primary not ready yet, retrying in 2s..."
  sleep 2
done
echo "Primary is ready."

# 2. Verify the replication slot exists on the primary
echo "Verifying replication slot on primary..."
until PGPASSWORD=postgres psql -h primarydb -U postgres -tAc \
  "SELECT 1 FROM pg_replication_slots WHERE slot_name = 'replication_api_slot';" \
  | grep -q 1; do
  echo "  slot not found yet, retrying in 2s..."
  sleep 2
done
echo "Replication slot 'replication_api_slot' confirmed."

# 3. Clean out the data directory so pg_basebackup can write to it
echo "Cleaning data directory..."
rm -rf /var/lib/postgresql/data/*

# 4. Run pg_basebackup to clone the primary
echo "Running pg_basebackup from primarydb..."
PGPASSWORD='repl_secret_123' pg_basebackup \
  --host=primarydb \
  --username=replication_user \
  --pgdata=/var/lib/postgresql/data \
  --wal-method=stream \
  --write-recovery-conf \
  --slot=replication_api_slot \
  --checkpoint=fast \
  --verbose \
  --progress

echo "pg_basebackup complete."

# 5. Fix ownership (pg_basebackup ran as root)
chown -R postgres:postgres /var/lib/postgresql/data
chmod 0700 /var/lib/postgresql/data

# 6. Start PostgreSQL in replica (read-only) mode
echo "Starting PostgreSQL replica..."
exec gosu postgres postgres
