#!/bin/bash
set -e

# This script runs inside the primary container as an init‑db hook.
# It creates a replication user and configures pg_hba for streaming replication.

cat <<'EOF'
=== Configuring PRIMARY for streaming replication ===
EOF

# Create a dedicated replication role (login + replication privileges)
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-SQL
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'rep_user') THEN
            CREATE ROLE rep_user WITH REPLICATION LOGIN PASSWORD 'rep_pass';
        END IF;
    END
    \$\$;

    -- Create a replication slot so WAL is retained until the replica consumes it
    SELECT pg_create_physical_replication_slot('replica1_slot')
    WHERE NOT EXISTS (
        SELECT 1 FROM pg_replication_slots WHERE slot_name = 'replica1_slot'
    );
SQL

# Allow the replica to connect for replication from the docker network
# (pg_hba.conf is regenerated on each start, so append)
echo "host replication rep_user 0.0.0.0/0 md5" >> "$PGDATA/pg_hba.conf"

# Tune WAL settings for replication
cat >> "$PGDATA/postgresql.conf" <<CONF

wal_level = replica
max_wal_senders = 5
wal_keep_size = 64MB
hot_standby = on
CONF

echo "=== Primary configuration complete ==="
