# PostgreSQL Physical Streaming Replication Demo

A minimal two-container setup to demonstrate **physical (WAL-based) streaming replication** in PostgreSQL.

> **Note:** Credentials are hardcoded for simplicity.

## Quick Start

### 1. Start the primary

```bash
docker compose up -d primary
```

### 2. Bootstrap the replica

```bash
chmod +x setup-and-start-replica.sh
./setup-and-start-replica.sh
```

### 3. Verify replication

```bash
# On the primary - should show one connected replica
docker exec pg_primary psql -U replicator -d demo \
  -c "SELECT pid, usename, client_addr, state, sent_lsn, replay_lsn FROM pg_stat_replication;"

# On the replica - should return 't'
docker exec pg_replica psql -U replicator -d demo \
  -c "SELECT pg_is_in_recovery();"
```

### 4. Testing

```bash
# Write on primary
docker exec pg_primary psql -U replicator -d demo \
  -c "CREATE TABLE hello (id serial PRIMARY KEY, msg text);
      INSERT INTO hello (msg) VALUES ('replicated!');"

# Read on replica (may take a fraction of a second)
docker exec pg_replica psql -U replicator -d demo \
  -c "SELECT * FROM hello;"
```


## Stop replication

### Pause replication (keep replica running, just stop applying WAL)

```bash
docker exec pg_replica psql -U replicator -d demo \
  -c "SELECT pg_wal_replay_pause();"
```

Resume:

```bash
docker exec pg_replica psql -U replicator -d demo \
  -c "SELECT pg_wal_replay_resume();"
```

### Promote replica to standalone primary

This permanently breaks the replication link and makes the replica a writable, independent server:

```bash
docker exec pg_replica psql -U replicator -d demo \
  -c "SELECT pg_promote();"
```

Verify it is no longer in recovery:

```bash
docker exec pg_replica psql -U replicator -d demo \
  -c "SELECT pg_is_in_recovery();"
# Should return 'f' (false)
```

### Stop the replica container entirely

```bash
docker stop pg_replica
```

The primary will keep running and accumulating WAL. Restart with `docker start pg_replica` and it will catch up automatically.

## Tear down

```bash
docker compose down -v
```
