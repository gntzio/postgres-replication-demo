#!/bin/bash
set -e

PRIMARY_CONTAINER=pg_primary
REPLICA_CONTAINER=pg_replica

echo ">>> Step 1: Stopping replica container to replace its data dir..."
docker compose stop replica 2>/dev/null || true

echo ""
echo ">>> Step 2: Running pg_basebackup from primary into replica volume..."
# Use a temporary container that mounts the replica volume
docker run --rm \
    --network postgres-replica_pg_net \
    -e PGPASSWORD=rep_pass \
    -v postgres-replica_replica_data:/var/lib/postgresql/data \
    postgres:17 \
    bash -c "
        rm -rf /var/lib/postgresql/data/*
        pg_basebackup -h pg_primary -U rep_user -D /var/lib/postgresql/data -Fp -Xs -P -R
    "

echo ""
echo ">>> Step 3: Ensuring standby.signal and connection info exist..."
docker run --rm \
    -v postgres-replica_replica_data:/var/lib/postgresql/data \
    postgres:17 \
    bash -c "
        touch /var/lib/postgresql/data/standby.signal
        # Append primary_conninfo if pg_basebackup didn't write it
        if ! grep -q primary_conninfo /var/lib/postgresql/data/postgresql.auto.conf 2>/dev/null; then
            echo \"primary_conninfo = 'host=pg_primary port=5444 user=rep_user password=rep_pass'\" \
                >> /var/lib/postgresql/data/postgresql.auto.conf
        fi

        # Use the replication slot so the primary retains WAL until this replica consumes it
        if ! grep -q primary_slot_name /var/lib/postgresql/data/postgresql.auto.conf 2>/dev/null; then
            echo \"primary_slot_name = 'replica1_slot'\" \\
                >> /var/lib/postgresql/data/postgresql.auto.conf
        fi    "

echo ""
echo ">>> Step 4: Starting replica..."
docker compose up -d replica

echo ""
echo ">>> Step 5: Replica is starting. Waiting for it to become ready..."
until docker exec "$REPLICA_CONTAINER" pg_isready -U replicator 2>/dev/null; do
    sleep 1
done

echo ""
echo "=== Replication setup complete ==="
