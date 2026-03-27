# Aurora PostgreSQL Statspack

Performance monitoring toolkit for Amazon Aurora PostgreSQL — captures point-in-time snapshots of database activity into historical tables for trending, diagnostics, and capacity planning.

**Created by Santiago Villa**

---

## Features

- **Statement analysis** — Top SQL by execution time, I/O, time-per-call, and execution variance
- **Wait event tracking** — System-level and per-session wait events from Aurora-specific functions
- **Database statistics** — Commits, rollbacks, deadlocks, cache hit ratios, temp file usage
- **Table & index analysis** — Sequential scan detection, unused indexes, indexes with high null ratios
- **Query plan management** — Historical capture of `apg_plan_mgmt` plans and explain output
- **Parameter change tracking** — Detect DB parameter changes between snapshots
- **Automated snapshots** — Schedule via `pg_cron` with configurable retention

## Prerequisites

- Amazon Aurora PostgreSQL
- Extensions: `pg_stat_statements`, `pg_cron` (for scheduling)
- Optional: `apg_plan_mgmt` (for query plan history)

## Quick Start

### 1. Install

Connect to your Aurora PostgreSQL database and run the setup script:

```sql
\i statspack_setup.sql
```

This creates the `statspack` schema with all tables, procedures, and configuration.

### 2. Take a snapshot

```sql
CALL statspack.statspack_snapshot();
```

### 3. Schedule automatic snapshots with pg_cron

```sql
-- Snapshot every 10 minutes
SELECT cron.schedule('Statspack Snapshot', '*/10 * * * *', 'CALL statspack.statspack_snapshot()');

-- Daily cleanup of old snapshots
SELECT cron.schedule('Statspack Cleanup', '0 0 * * *', 'CALL statspack.statspack_cleanup()');
```

> **Note:** Retention is controlled by `statspack.statspack_config.retention_days` (default: 7).

### 4. Generate a report

```sql
\i statspack_report.sql
```

You'll be prompted for a begin/end snapshot ID. The report is saved as an HTML file: `statspack_<begin>_<end>.html`.

## Schema Reference

### Tables

| Table | Description |
|-------|-------------|
| `statspack.hist_snapshots` | Snapshot IDs and timestamps |
| `statspack.hist_active_sessions_waits` | Active sessions with wait events (per-session from `aurora_stat_backend_waits`) |
| `statspack.hist_stat_system_waits` | System-level wait events (from `aurora_stat_system_waits`) |
| `statspack.hist_pg_stat_statements` | Query statistics from `pg_stat_statements` |
| `statspack.hist_pg_stat_database` | Database-level statistics (commits, rollbacks, I/O, deadlocks) |
| `statspack.hist_pg_stat_all_tables` | Table statistics (scans, tuples, autovacuum) |
| `statspack.hist_pg_settings` | Database parameter values at snapshot time |
| `statspack.hist_pg_users` | Database users and their configuration |
| `statspack.hist_indexes_with_nulls` | Indexes with high null value ratios (optimization candidates) |
| `statspack.hist_unused_indexes` | Indexes with fewer than 10 scans (drop candidates) |
| `statspack.hist_dba_plans` | Query plans from `apg_plan_mgmt` |
| `statspack.statspack_config` | Configuration table (retention days) |

### Procedures

| Procedure | Description |
|-----------|-------------|
| `statspack.statspack_snapshot()` | Capture a new snapshot from all live views |
| `statspack.statspack_remove_snapshot(snap_id)` | Remove a specific snapshot and all its data |
| `statspack.statspack_cleanup()` | Remove snapshots older than the configured retention period |

## Report Sections

The HTML report includes the following analysis between two snapshots:

1. **Database Statistics** — Commits, rollbacks, deadlocks, cache hit ratio, I/O times, temp files
2. **Active Sessions** — Sessions active at the end snapshot with wait event breakdown
3. **Top 10 System Wait Events** — Highest wait time events across the instance
4. **Top 10 Statements by Total Execution Time** — Heaviest queries by cumulative time
5. **Top 10 Statements by Execution Time per Call** — Slowest queries per invocation
6. **Top 10 Statements by I/O per Call** — Most I/O-intensive queries per invocation
7. **Top 10 Statements by Total I/O** — Heaviest queries by cumulative I/O blocks
8. **Top 10 Statements with Execution Time Deviation** — Queries with unstable performance
9. **Sequential Scans** — Tables scanned sequentially (may need indexes)
10. **Indexes with High Null Ratios** — Space optimization opportunities
11. **Unused Index Candidates** — Indexes that can potentially be dropped
12. **Heavy Queries — Full Text and Explain Plans** — Complete query text and plan details
13. **Installed Extensions** — Extensions with available version updates
14. **DB Parameter Changes** — Settings that changed between snapshots

## Historical Lock Analysis

The `hist_active_sessions_waits` table captures wait events that can help identify lock-related activity. While it does **not** capture the blocker→blocked relationship (that requires `pg_locks` / `pg_blocking_pids()`), you can query tentative lockers and locked sessions:

```sql
-- Sessions waiting on locks vs active sessions (potential lockers)
-- for a given snapshot range
WITH snap_range AS (
    SELECT snap_id, snap_timestamp
    FROM statspack.hist_snapshots
    WHERE snap_id BETWEEN :BEGIN_SNAP AND :END_SNAP
),
locked_sessions AS (
    SELECT h.snap_id, s.snap_timestamp, 'LOCKED' AS session_role,
           h.pid, h.usename, h.app_name, h.current_wait_type,
           h.current_wait_event, h.current_state,
           h.xact_start, h.query_start, h.query
    FROM statspack.hist_active_sessions_waits h
    JOIN snap_range s ON h.snap_id = s.snap_id
    WHERE h.current_wait_type = 'Lock'
      AND h.current_wait_event <> 'PgSleep'
      AND h.current_wait_type = h.wait_type
      AND h.current_wait_event = h.wait_event
),
active_not_locked AS (
    SELECT h.snap_id, s.snap_timestamp, 'TENTATIVE LOCKER' AS session_role,
           h.pid, h.usename, h.app_name, h.current_wait_type,
           h.current_wait_event, h.current_state,
           h.xact_start, h.query_start, h.query
    FROM statspack.hist_active_sessions_waits h
    JOIN snap_range s ON h.snap_id = s.snap_id
    WHERE h.current_wait_type <> 'Lock'
      AND h.current_wait_event <> 'PgSleep'
      AND h.current_wait_type = h.wait_type
      AND h.current_wait_event = h.wait_event
)
SELECT snap_id, snap_timestamp, session_role, pid, usename, app_name,
       current_wait_type, current_wait_event, xact_start, query_start,
       substr(query, 1, 120) AS partial_query
FROM (SELECT * FROM locked_sessions UNION ALL SELECT * FROM active_not_locked) combined
ORDER BY snap_id, session_role DESC, xact_start ASC;
```

> **Tip:** For definitive blocker→blocked tracking, consider adding a `hist_lock_tree` table that captures `pg_blocking_pids()` output at snapshot time. See the [docs](docs/) folder for details.

## Managing pg_cron Jobs

```sql
-- List scheduled statspack jobs
SELECT * FROM cron.job WHERE command LIKE '%statspack%';

-- Check recent job execution history
SELECT * FROM cron.job_run_details WHERE command LIKE '%statspack%' ORDER BY end_time DESC LIMIT 10;

-- Remove jobs
SELECT cron.unschedule('Statspack Snapshot');
SELECT cron.unschedule('Statspack Cleanup');
```

## License

See [LICENSE](LICENSE) for details.
