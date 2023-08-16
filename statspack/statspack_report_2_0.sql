\set ECHO errors
\encoding UTF8

\pset footer off
\pset pager off

\pset border 0
\pset tuples_only
select snap_id, max(snap_timestamp) at time zone 'America/New_York' as snap_timestamp
from
statspack.hist_snapshots
where snap_timestamp > now() - interval '1 DAY'
group by snap_id
order by snap_id asc;
\pset tuples_only off

\prompt 'Enter begin snap_id : ' BEGIN_SNAP
\prompt 'Enter last snap_id : ' END_SNAP

\set ECHO queries

\o 'statspack_':BEGIN_SNAP'_':END_SNAP'.html'

\H
\pset border 0
\pset tuples_only
\qecho <h1>Aurora PostgreSQL Statspack report - Created by Santiago Villa</h1>
SELECT 'Statspack v2.0 report generated from '||server_id||' server at ',now() at time zone 'America/New_York' FROM aurora_global_db_instance_status() where session_id='MASTER_SESSION_ID';
\pset tuples_only off

\pset border 0
\pset tuples_only
select ' ' as T;
\pset tuples_only off
\pset border 1

\pset border 2
SELECT min(snap_id) as "Begin SNAPID",
   max(snap_id) as "End SNAPID",
   min(snap_timestamp) at time zone 'America/New_York' as "Begin Timestamp",
   max(snap_timestamp) at time zone 'America/New_York' as "End Timestamp"
FROM statspack.hist_snapshots
WHERE snap_id in (:END_SNAP,:BEGIN_SNAP);

\pset border 0
\pset tuples_only
select ' ' as T;
\pset tuples_only off

\pset tuples_only
\qecho <h2>DATABASE STATISTICS</h2>
\pset tuples_only off
\pset border 1

select
        last_snap.datid as database_id,
        last_snap.datname as database,
        last_snap.numbackends open_sessions,
        last_snap.xact_commit-coalesce (first_snap.xact_commit,0) commits,
        last_snap.xact_rollback-coalesce (first_snap.xact_rollback,0) rollbacks,
        last_snap.deadlocks-coalesce (first_snap.deadlocks,0) deadlocks,
        last_snap.tup_returned-coalesce (first_snap.tup_returned,0) tup_returned,
        last_snap.tup_fetched-coalesce (first_snap.tup_fetched,0) tup_fetched,
        last_snap.tup_updated-coalesce (first_snap.tup_updated,0) tup_updated,
        last_snap.tup_deleted-coalesce (first_snap.tup_deleted,0) tup_deleted,
        last_snap.blks_read-coalesce (first_snap.blks_read,0) blks_read,
        last_snap.blks_hit-coalesce (first_snap.blks_hit,0) blks_hit,
        round(100.0 * (last_snap.blks_hit - coalesce(first_snap.blks_hit,0))/
               nullif((last_snap.blks_hit - coalesce(first_snap.blks_hit,0)) + (last_snap.blks_read - coalesce(first_snap.blks_read,0)), 0),1) AS "cache_hit_%",
        round(((last_snap.blk_read_time-coalesce (first_snap.blk_read_time,0))/1000)::NUMERIC,2) blk_read_time_seconds,
        round(((last_snap.blk_write_time-coalesce (first_snap.blk_write_time,0))/1000)::NUMERIC,2) blk_write_time_seconds,
        last_snap.temp_files-coalesce (first_snap.temp_files,0) temp_files,
        last_snap.temp_bytes-coalesce (first_snap.temp_bytes,0) temp_bytes
from
        (
        select
                *
        from
                statspack.hist_pg_stat_database
        where
                snap_id = :END_SNAP ) last_snap
left join
(
        select
                *
        from
                statspack.hist_pg_stat_database
        where
                snap_id = :BEGIN_SNAP) first_snap
on
        last_snap.datid = first_snap.datid
order by open_sessions desc
;

\pset border 0
\pset tuples_only
select ' ' as T;
\pset tuples_only off

\pset tuples_only
\qecho <h2>ACTIVE SESSIONS</h2>
SELECT '( DBLOAD = '||count(*)||' )' from statspack.hist_active_sessions_waits where snap_id = :END_SNAP and current_wait_type = wait_type and current_wait_event = wait_event;
\pset tuples_only off
\pset border 1

select
        last_snap.pid,
        last_snap.usename,
        last_snap.app_name,
        last_snap.current_wait_type,
        last_snap.current_wait_event,
        last_snap.current_state,
        last_snap.waits-coalesce(first_snap.waits,0) as waits,
        round((last_snap.wait_time-coalesce(first_snap.wait_time,0))/1000000,2) as wait_time_seconds,
        last_snap.backend_start at time zone 'America/New_York' as backend_start,
        last_snap.xact_start at time zone 'America/New_York' as xact_start,
        last_snap.query_start at time zone 'America/New_York' as query_start,
        last_snap.state_change at time zone 'America/New_York' as state_change,
        last_snap.query_id,
        substr(last_snap.query,1,80) as partial_query
from
        (
        select
                *
        from
                statspack.hist_active_sessions_waits
        where
                snap_id = :END_SNAP ) last_snap
left join
(
        select
                *
        from
                statspack.hist_active_sessions_waits
        where
                snap_id = :BEGIN_SNAP) first_snap

on
        last_snap.pid = first_snap.pid
        and last_snap.usename = first_snap.usename
        and last_snap.app_name = first_snap.app_name
        and last_snap.wait_type = first_snap.wait_type
        and last_snap.wait_event = first_snap.wait_event
where last_snap.current_wait_type = last_snap.wait_type and last_snap.current_wait_event = last_snap.wait_event
order by
        (last_snap.wait_time-coalesce(first_snap.wait_time,0)) desc nulls last;

\pset border 0
\pset tuples_only
select ' ' as T;
\pset tuples_only off

\pset tuples_only
\qecho <h2>TOP 10 SYSTEM WAIT EVENTS</h2>
\pset tuples_only off
\pset border 1

select
        last_snap.type_name,
        last_snap.event_name,
        last_snap.waits-first_snap.waits as waits,
        round((last_snap.wait_time-coalesce(first_snap.wait_time,0))/1000000,2) as wait_time_seconds,
        round((last_snap.wait_time-coalesce(first_snap.wait_time,0))/1000000/60,2) as wait_time_minutes
from
        (
        select
                *
        from
                statspack.hist_stat_system_waits
        where
                snap_id = :END_SNAP ) last_snap
left join
(
        select
                *
        from
                statspack.hist_stat_system_waits
        where
                snap_id = :BEGIN_SNAP ) first_snap
on
        last_snap.type_name = first_snap.type_name
        and last_snap.event_name = first_snap.event_name
order by
        last_snap.wait_time-coalesce(first_snap.wait_time,0) desc nulls last
limit 10;

\pset border 0
\pset tuples_only
select ' ' as T;
\pset tuples_only off

\pset tuples_only
\qecho <h2>TOP 10 STATEMENTS BY TOTAL EXECUTION TIME</h2>
\pset tuples_only off
\pset border 1

select
        last_snap.queryid,
        last_snap.usename,
        to_char(((last_snap.total_exec_time-coalesce(first_snap.total_exec_time,0))/ sum((last_snap.total_exec_time-coalesce(first_snap.total_exec_time,0))) over()) * 100, 'FM90D0') || '%' as "total_exec_time_%",
        interval '1 millisecond' * (last_snap.total_exec_time-coalesce(first_snap.total_exec_time,0)) as total_exec_time,
        to_char((last_snap.calls-coalesce(first_snap.calls,0)), 'FM999G999G999G990') as calls,
        case
                when last_snap.calls-coalesce(first_snap.calls, 0) > 0 then round((((last_snap.total_exec_time-coalesce(first_snap.total_exec_time, 0))/ 1000)/(last_snap.calls-coalesce(first_snap.calls, 0)))::numeric, 1)
                else 0
        end as time_by_call_secs,
        (last_snap.shared_blks_read + last_snap.shared_blks_written-coalesce(first_snap.shared_blks_read,0) - coalesce(first_snap.shared_blks_written,0)) as io_blks,
                case
                when last_snap.calls-coalesce(first_snap.calls, 0) > 0 then round(((last_snap.shared_blks_read + last_snap.shared_blks_written-coalesce(first_snap.shared_blks_read,0) - coalesce(first_snap.shared_blks_written,0))
                /(last_snap.calls-coalesce(first_snap.calls, 0)))::numeric, 1)
                else 0
        end as IO_blks_by_call,
        interval '1 second' * (last_snap.blk_read_time + last_snap.blk_write_time - coalesce(first_snap.blk_read_time,0) - coalesce(first_snap.blk_write_time,0)) / 1000 as io_time,
        round(100.0 * (last_snap.shared_blks_hit - coalesce(first_snap.shared_blks_hit,0))/
               nullif((last_snap.shared_blks_hit - coalesce(first_snap.shared_blks_hit,0)) + (last_snap.shared_blks_read - coalesce(first_snap.shared_blks_read,0)), 0),1) AS "cache_hit_%",
        substr(last_snap.query,1,80) as partial_query
from
        (
        select
                pss.*, users.usename
        from
                statspack.hist_pg_stat_statements pss join statspack.hist_pg_users users on pss.snap_id = users.snap_id and pss.userid = users.usesysid
        where
                pss.snap_id = :END_SNAP ) last_snap
left join
(
        select
                *
        from
                statspack.hist_pg_stat_statements
        where
                snap_id = :BEGIN_SNAP ) first_snap
on
        last_snap.userid = first_snap.userid
        and last_snap.dbid = first_snap.dbid
        and last_snap.queryid = first_snap.queryid
        and last_snap.toplevel = first_snap.toplevel
order by
        (last_snap.total_exec_time-coalesce(first_snap.total_exec_time,0)) desc nulls last
limit 10;

\pset border 0
\pset tuples_only
select ' ' as T;
\pset tuples_only off

\pset tuples_only
\qecho <h2>TOP 10 STATEMENTS BY EXECUTION TIME PER CALL</h2>
\pset tuples_only off
\pset border 1

select
        last_snap.queryid,
        last_snap.usename,
        to_char(((case
                when last_snap.calls-coalesce(first_snap.calls, 0) > 0 then round((((last_snap.total_exec_time-coalesce(first_snap.total_exec_time, 0))/ 1000)/(last_snap.calls-coalesce(first_snap.calls, 0)))::numeric, 1)
                else 0
        end)/ sum((case
                when last_snap.calls-coalesce(first_snap.calls, 0) > 0 then round((((last_snap.total_exec_time-coalesce(first_snap.total_exec_time, 0))/ 1000)/(last_snap.calls-coalesce(first_snap.calls, 0)))::numeric, 1)
                else 0
        end)) over()) * 100, 'FM90D0') || '%' as "time_by_call_%",
        interval '1 millisecond' * (last_snap.total_exec_time-coalesce(first_snap.total_exec_time,0)) as total_exec_time,
        to_char((last_snap.calls-coalesce(first_snap.calls,0)), 'FM999G999G999G990') as calls,
        case
                when last_snap.calls-coalesce(first_snap.calls, 0) > 0 then round((((last_snap.total_exec_time-coalesce(first_snap.total_exec_time, 0))::NUMERIC/ 1000)/(last_snap.calls-coalesce(first_snap.calls, 0)))::numeric, 1)
                else 0
        end as time_by_call_secs,
        (last_snap.shared_blks_read + last_snap.shared_blks_written-coalesce(first_snap.shared_blks_read,0) - coalesce(first_snap.shared_blks_written,0)) as io_blks,
                case
                when last_snap.calls-coalesce(first_snap.calls, 0) > 0 then round(((last_snap.shared_blks_read + last_snap.shared_blks_written-coalesce(first_snap.shared_blks_read,0) - coalesce(first_snap.shared_blks_written,0))
                /(last_snap.calls-coalesce(first_snap.calls, 0)))::numeric, 1)
                else 0
        end as IO_blks_by_call,
        interval '1 second' * (last_snap.blk_read_time + last_snap.blk_write_time - coalesce(first_snap.blk_read_time,0) - coalesce(first_snap.blk_write_time,0)) / 1000 as io_time,
        round(100.0 * (last_snap.shared_blks_hit - coalesce(first_snap.shared_blks_hit,0))/
               nullif((last_snap.shared_blks_hit - coalesce(first_snap.shared_blks_hit,0)) + (last_snap.shared_blks_read - coalesce(first_snap.shared_blks_read,0)), 0),1) AS "cache_hit_%",
        substr(last_snap.query,1,80) as partial_query
from
        (
        select
                pss.*, users.usename
        from
                statspack.hist_pg_stat_statements pss join statspack.hist_pg_users users on pss.snap_id = users.snap_id and pss.userid = users.usesysid
        where
                pss.snap_id = :END_SNAP ) last_snap
left join
(
        select
                *
        from
                statspack.hist_pg_stat_statements
        where
                snap_id = :BEGIN_SNAP ) first_snap
on
        last_snap.userid = first_snap.userid
        and last_snap.dbid = first_snap.dbid
        and last_snap.queryid = first_snap.queryid
        and last_snap.toplevel = first_snap.toplevel
order by
        time_by_call_secs desc nulls last,
        (last_snap.calls-coalesce(first_snap.calls,0)) desc nulls last
limit 10;

\pset border 0
\pset tuples_only
select ' ' as T;
\pset tuples_only off

\pset tuples_only
\qecho <h2>TOP 10 STATEMENTS BY IO by call</h2>
\pset tuples_only off
\pset border 1

select
        last_snap.queryid,
        last_snap.usename,
        to_char(((case
                when last_snap.calls-coalesce(first_snap.calls, 0) > 0 then ((last_snap.shared_blks_read + last_snap.shared_blks_written-coalesce(first_snap.shared_blks_read,0) - coalesce(first_snap.shared_blks_written,0))::NUMERIC
                /(last_snap.calls-coalesce(first_snap.calls, 0))::numeric)
                else 0::numeric
        end)/ sum((case
                when last_snap.calls-coalesce(first_snap.calls, 0) > 0 then ((last_snap.shared_blks_read + last_snap.shared_blks_written-coalesce(first_snap.shared_blks_read,0) - coalesce(first_snap.shared_blks_written,0))::NUMERIC
                /(last_snap.calls-coalesce(first_snap.calls, 0))::numeric)
                else 0
        end)) over()) * 100, 'FM90D0') || '%' as "IO_by_call_%",
        interval '1 millisecond' * (last_snap.total_exec_time-coalesce(first_snap.total_exec_time,0)) as total_exec_time,
        to_char((last_snap.calls-coalesce(first_snap.calls,0)), 'FM999G999G999G990') as calls,
        case
                when last_snap.calls-coalesce(first_snap.calls, 0) > 0 then round((((last_snap.total_exec_time-coalesce(first_snap.total_exec_time, 0))/ 1000)/(last_snap.calls-coalesce(first_snap.calls, 0)))::numeric, 1)
                else 0
        end as time_by_call_secs,
        (last_snap.shared_blks_read + last_snap.shared_blks_written-coalesce(first_snap.shared_blks_read,0) - coalesce(first_snap.shared_blks_written,0)) as io_blks,
        case
                when last_snap.calls-coalesce(first_snap.calls, 0) > 0 then round(((last_snap.shared_blks_read + last_snap.shared_blks_written-coalesce(first_snap.shared_blks_read,0) - coalesce(first_snap.shared_blks_written,0))::numeric
                /(last_snap.calls-coalesce(first_snap.calls, 0)))::numeric, 1)
                else 0
        end as IO_blks_by_call,
                interval '1 second' * (last_snap.blk_read_time + last_snap.blk_write_time - coalesce(first_snap.blk_read_time,0) - coalesce(first_snap.blk_write_time,0)) / 1000 as io_time,
        round(100.0 * (last_snap.shared_blks_hit - coalesce(first_snap.shared_blks_hit,0))/
               nullif((last_snap.shared_blks_hit - coalesce(first_snap.shared_blks_hit,0)) + (last_snap.shared_blks_read - coalesce(first_snap.shared_blks_read,0)), 0),1) AS "cache_hit_%",
        substr(last_snap.query,1,80) as partial_query
from
        (
        select
                pss.*, users.usename
        from
                statspack.hist_pg_stat_statements pss join statspack.hist_pg_users users on pss.snap_id = users.snap_id and pss.userid = users.usesysid
        where
                pss.snap_id = :END_SNAP ) last_snap
left join
(
        select
                *
        from
                statspack.hist_pg_stat_statements
        where
                snap_id = :BEGIN_SNAP ) first_snap
on
        last_snap.userid = first_snap.userid
        and last_snap.dbid = first_snap.dbid
        and last_snap.queryid = first_snap.queryid
        and last_snap.toplevel = first_snap.toplevel
order by
        case
                when last_snap.calls-coalesce(first_snap.calls, 0) > 0 then ((last_snap.shared_blks_read + last_snap.shared_blks_written-coalesce(first_snap.shared_blks_read,0) - coalesce(first_snap.shared_blks_written,0))::numeric
                /(last_snap.calls-coalesce(first_snap.calls, 0)))::numeric
                else 0
        end desc nulls last
limit 10;

\pset border 0
\pset tuples_only
select ' ' as T;
\pset tuples_only off

\pset tuples_only
\qecho <h2>TOP 10 STATEMENTS BY TOTAL IO</h2>
\pset tuples_only off
\pset border 1

select
        last_snap.queryid,
        last_snap.usename,
        to_char(((last_snap.shared_blks_read + last_snap.shared_blks_written-coalesce(first_snap.shared_blks_read,0) - coalesce(first_snap.shared_blks_written,0))/ 
        sum((last_snap.shared_blks_read + last_snap.shared_blks_written-coalesce(first_snap.shared_blks_read,0) - coalesce(first_snap.shared_blks_written,0))) over()) * 100, 'FM90D0') || '%' as "IO_%",
        interval '1 millisecond' * (last_snap.total_exec_time-coalesce(first_snap.total_exec_time,0)) as total_exec_time,
        to_char((last_snap.calls-coalesce(first_snap.calls,0)), 'FM999G999G999G990') as calls,
        case
                when last_snap.calls-coalesce(first_snap.calls, 0) > 0 then round((((last_snap.total_exec_time-coalesce(first_snap.total_exec_time, 0))/ 1000)/(last_snap.calls-coalesce(first_snap.calls, 0)))::numeric, 1)
                else 0
        end as time_by_call_secs,
        (last_snap.shared_blks_read + last_snap.shared_blks_written-coalesce(first_snap.shared_blks_read,0) - coalesce(first_snap.shared_blks_written,0)) as io_blks,
        case
                when last_snap.calls-coalesce(first_snap.calls, 0) > 0 then round(((last_snap.shared_blks_read + last_snap.shared_blks_written-coalesce(first_snap.shared_blks_read,0) - coalesce(first_snap.shared_blks_written,0))
                /(last_snap.calls-coalesce(first_snap.calls, 0)))::numeric, 1)
                else 0
        end as IO_blks_by_call,
                interval '1 second' * (last_snap.blk_read_time + last_snap.blk_write_time - coalesce(first_snap.blk_read_time,0) - coalesce(first_snap.blk_write_time,0)) / 1000 as io_time,
        round(100.0 * (last_snap.shared_blks_hit - coalesce(first_snap.shared_blks_hit,0))/
               nullif((last_snap.shared_blks_hit - coalesce(first_snap.shared_blks_hit,0)) + (last_snap.shared_blks_read - coalesce(first_snap.shared_blks_read,0)), 0),1) AS "cache_hit_%",
        substr(last_snap.query,1,80) as partial_query
from
        (
        select
                pss.*, users.usename
        from
                statspack.hist_pg_stat_statements pss join statspack.hist_pg_users users on pss.snap_id = users.snap_id and pss.userid = users.usesysid
        where
                pss.snap_id = :END_SNAP ) last_snap
left join
(
        select
                *
        from
                statspack.hist_pg_stat_statements
        where
                snap_id = :BEGIN_SNAP ) first_snap
on
        last_snap.userid = first_snap.userid
        and last_snap.dbid = first_snap.dbid
        and last_snap.queryid = first_snap.queryid
        and last_snap.toplevel = first_snap.toplevel
order by
        io_blks desc nulls last
limit 10;

\pset border 0
\pset tuples_only
select ' ' as T;
\pset tuples_only off

\pset tuples_only
\qecho <h2>TOP 10 STATEMENTS WITH EXECUTION TIME DEVIATION</h2>
\pset tuples_only off
\pset border 1

WITH statements AS (
SELECT * FROM statspack.hist_pg_stat_statements pss
		JOIN statspack.hist_pg_users pr ON (pss.userid=pr.usesysid and pss.snap_id=pr.snap_id)
		where pss.snap_id = :END_SNAP
)
SELECT queryid,
        usename,
        calls,
	round((min_exec_time/1000)::numeric,1) as "min_exec_time(secs)",
        round((max_exec_time/1000)::numeric,1) as "max_exec_time(secs)",
	round(mean_exec_time::numeric,2) as mean_exec_time,
	round(stddev_exec_time::numeric,2) as stddev_exec_time,
	round((stddev_exec_time/mean_exec_time)::numeric,2) AS coeff_of_variance,
	substr(query,1,80) as partial_query
FROM statements
WHERE calls > 100
AND shared_blks_hit > 0
ORDER BY coeff_of_variance DESC
LIMIT 10;

\pset border 0
\pset tuples_only
select ' ' as T;
\pset tuples_only off

\pset tuples_only
\qecho <h2>SEQUENCIAL SCANS BETWEEN SNAPSHOTS - Check if we need indexes</h2>
\pset tuples_only off
\pset border 1

select
        last_snap.schemaname as schema_name,
        last_snap.relname as table_name,
        (last_snap.seq_scan -coalesce(first_snap.seq_scan,0)) as seq_scan,
        coalesce(last_snap.idx_scan, 0)-coalesce(first_snap.idx_scan, 0) as idx_scan ,
        (100 * (coalesce(last_snap.idx_scan, 0)-coalesce(first_snap.idx_scan, 0)) / ((last_snap.seq_scan-coalesce(first_snap.seq_scan,0)) + (coalesce(last_snap.idx_scan, 0)-coalesce(first_snap.idx_scan, 0))))
        percent_of_times_index_used,
        last_snap.n_live_tup rows_in_table
from
        (
        select
                *
        from
                statspack.hist_pg_stat_all_tables
        where
                snap_id = :END_SNAP ) last_snap
left join
(
        select
                *
        from
                statspack.hist_pg_stat_all_tables
        where
                snap_id = :BEGIN_SNAP ) first_snap
                on
        last_snap.schemaname = first_snap.schemaname
        and last_snap.relname = first_snap.relname
where
        ((last_snap.seq_scan-coalesce(first_snap.seq_scan,0)) >0
                or last_snap.idx_scan-coalesce(first_snap.idx_scan,0)>0)
        and last_snap.n_live_tup > 0
order by
        percent_of_times_index_used asc,
        (last_snap.seq_scan-coalesce(first_snap.seq_scan,0)) * last_snap.n_live_tup desc,
        coalesce(last_snap.idx_scan, 0)-coalesce(first_snap.idx_scan, 0) asc,
        last_snap.n_live_tup desc
limit 10;

\pset border 0
\pset tuples_only
select ' ' as T;
\pset tuples_only off

\pset tuples_only
\qecho <h2>SEQUENCIAL SCANS FROM TABLE STATS (Cumulative) - Top 20 - Check if we need indexes</h2>
\pset tuples_only off
\pset border 1

select
        schemaname as schema_name,
        relname as table_name,
        seq_scan,
        coalesce(idx_scan, 0) as idx_scan ,
        (100 * coalesce(idx_scan, 0) / (seq_scan + coalesce(idx_scan, 0)))
   percent_of_times_index_used,
        n_live_tup rows_in_table
from
        statspack.hist_pg_stat_all_tables
where
        snap_id = :END_SNAP
        and (seq_scan >0
                or idx_scan >0)
        and n_live_tup > 0
order by
        percent_of_times_index_used asc,
        seq_scan desc,
        coalesce(idx_scan, 0) asc,
        n_live_tup desc
limit 20;

\pset border 0
\pset tuples_only
select ' ' as T;
\pset tuples_only off

\pset tuples_only
\qecho <h2>TOP 10 INDEXES WITH A HIGH RATIO OF NULL VALUES</h2>
\pset tuples_only off
\pset border 1

select
        schema,
        p.table as table_name,
        index as index_name,
        p.unique ,
        indexed_column,
        pg_size_pretty (index_size_bytes::bigint) as index_size,
        p."null_%",
        pg_size_pretty (expected_saving_bytes::bigint) as expected_saving
from
        statspack.hist_indexes_with_nulls p
where
        snap_id = :END_SNAP
order by
        expected_saving_bytes desc
LIMIT 10;

\pset border 0
\pset tuples_only
select ' ' as T;
\pset tuples_only off

\pset tuples_only
\qecho <h2>TOP 10 INDEXES CANDIDATES TO BE DROPPED</h2>
\pset tuples_only off
\pset border 1

select
        *
from
        statspack.hist_unused_indexes p
where
        snap_id = :END_SNAP
order by
        idx_scan asc, index_size desc
LIMIT 10;

\pset border 0
\pset tuples_only
select ' ' as T;
\pset tuples_only off

\pset tuples_only
\qecho <h2>HEAVY QUERIES - FULL TEXT AND EXPLAIN PLANS</h2>
\pset tuples_only off
\pset border 1

select
	full_stmts.queryid,
	full_stmts.usename,
	hdp.sql_hash ,
	hdp.plan_hash ,
	hdp.enabled ,
	hdp.status ,
	round(hdp.estimated_total_cost,0) as estimated_total_cost,
	hdp.last_used ,
	hdp.explain_plan,
	coalesce(hdp.sql_text,full_stmts.query) full_query
from
	(
	(
	select
		last_snap.queryid,
		pu.usename ,
		last_snap.snap_id,
                last_snap.query
	from
		(
		select
			*
		from
			statspack.hist_pg_stat_statements
		where
			snap_id = :END_SNAP ) last_snap
	join statspack.hist_pg_users pu on
		last_snap.userid = pu.usesysid
		and pu.snap_id = last_snap.snap_id
	left join
(
		select
			*
		from
			statspack.hist_pg_stat_statements
		where
			snap_id = :BEGIN_SNAP ) first_snap
on
		last_snap.userid = first_snap.userid
		and last_snap.dbid = first_snap.dbid
		and last_snap.queryid = first_snap.queryid
                and last_snap.toplevel = first_snap.toplevel
	order by
		(last_snap.total_exec_time-coalesce(first_snap.total_exec_time,
		0)) desc nulls last
	limit 10)
union 
	(
select
	last_snap.queryid,
	pu.usename ,
	last_snap.snap_id,
        last_snap.query
from
	(
	select
		*
	from
		statspack.hist_pg_stat_statements
	where
		snap_id = :END_SNAP ) last_snap
join statspack.hist_pg_users pu on
	last_snap.userid = pu.usesysid
	and pu.snap_id = last_snap.snap_id
left join
(
	select
		*
	from
		statspack.hist_pg_stat_statements
	where
		snap_id = :BEGIN_SNAP ) first_snap
on
	last_snap.userid = first_snap.userid
	and last_snap.dbid = first_snap.dbid
	and last_snap.queryid = first_snap.queryid
        and last_snap.toplevel = first_snap.toplevel
order by
	case
		when last_snap.calls-coalesce(first_snap.calls,
		0) > 0 then round((((last_snap.total_exec_time-coalesce(first_snap.total_exec_time,
		0))/ 1000)/(last_snap.calls-coalesce(first_snap.calls,
		0)))::numeric,
		1)
		else 0
	end desc nulls last,
	(last_snap.calls-COALESCE(first_snap.calls,0)) desc nulls last
limit 10)
union 
	(
select
	last_snap.queryid,
	pu.usename ,
	last_snap.snap_id,
        last_snap.query
from
	(
select
		*
from
		statspack.hist_pg_stat_statements
where
		snap_id = :END_SNAP ) last_snap
join statspack.hist_pg_users pu on
	last_snap.userid = pu.usesysid
and pu.snap_id = last_snap.snap_id
left join
(
select
		*
from
		statspack.hist_pg_stat_statements
where
		snap_id = :BEGIN_SNAP ) first_snap
on
	last_snap.userid = first_snap.userid
and last_snap.dbid = first_snap.dbid
and last_snap.queryid = first_snap.queryid
and last_snap.toplevel = first_snap.toplevel
order by
                case
	when last_snap.calls-coalesce(first_snap.calls,
	0) > 0 then round(((last_snap.shared_blks_read + last_snap.shared_blks_written-coalesce(first_snap.shared_blks_read,0)-coalesce(first_snap.shared_blks_written,0))
                /(last_snap.calls-coalesce(first_snap.calls,
	0)))::numeric,
	1)
	else 0
end desc nulls last
limit 10)
union 
	(
select
	last_snap.queryid,
	pu.usename ,
	last_snap.snap_id,
        last_snap.query
from
	(
select
		*
from
		statspack.hist_pg_stat_statements
where
		snap_id = :END_SNAP ) last_snap
join statspack.hist_pg_users pu on
	last_snap.userid = pu.usesysid
and pu.snap_id = last_snap.snap_id
left join
(
select
		*
from
		statspack.hist_pg_stat_statements
where
		snap_id = :BEGIN_SNAP ) first_snap
on
	last_snap.userid = first_snap.userid
and last_snap.dbid = first_snap.dbid
and last_snap.queryid = first_snap.queryid
and last_snap.toplevel = first_snap.toplevel
order by
                (last_snap.shared_blks_read + last_snap.shared_blks_written - coalesce(first_snap.shared_blks_read,
0) - coalesce(first_snap.shared_blks_written,
0)) desc nulls last
limit 10)
union
(SELECT query_id as queryid,
	usename ,
	snap_id,
        query
        from statspack.hist_active_sessions_waits where snap_id = :END_SNAP and current_wait_type = wait_type and current_wait_event = wait_event
)
union 
	(
select
	last_snap.queryid,
	pu.usename ,
	last_snap.snap_id,
        last_snap.query
from
	(
select
		*
from
		statspack.hist_pg_stat_statements
where
		snap_id = :END_SNAP ) last_snap
join statspack.hist_pg_users pu on last_snap.userid = pu.usesysid and pu.snap_id = last_snap.snap_id
WHERE calls > 100 AND shared_blks_hit > 0
order by (stddev_exec_time/mean_exec_time) desc nulls last
limit 10)
         ) full_stmts
left join statspack.hist_dba_plans hdp
on
	full_stmts.queryid = hdp.queryid
	and full_stmts.snap_id = hdp.snap_id
	and full_stmts.usename = hdp.created_by
order by
	full_stmts.queryid ,
	hdp.sql_hash ,
	hdp.last_used,
	hdp.estimated_total_cost ;

\pset border 0
\pset tuples_only
select ' ' as T;
\pset tuples_only off

\qecho <h2>PG installed extensions</h2>
\pset border 1

select
        pe.extname as extension_name,
        pe.extversion as installed_version,
        latest_versions.latest_version as available_version
from
        pg_extension pe
join (
        select
                name ,
                max(version) latest_version
        from
                pg_available_extension_versions
        group by
                name) latest_versions
on
        pe.extname = latest_versions.name
order by
        extension_name;

\pset border 0
\pset tuples_only
select ' ' as T;
\pset tuples_only off

\qecho <h2>DB Parameter changes</h2>
\pset border 1

select
        last_snap.name as parameter_name,
        last_snap.setting as current_value,
        last_snap.unit as current_unit,
        first_snap.setting as old_value,
        first_snap.unit as old_unit
from
        (
        select
                *
        from
                statspack.hist_pg_settings
        where
                snap_id = :END_SNAP ) last_snap
left join
(
        select
                *
        from
                statspack.hist_pg_settings
        where
                snap_id = :BEGIN_SNAP) first_snap
on
        last_snap.name = first_snap.name
where last_snap.setting != coalesce(first_snap.setting,last_snap.setting) or last_snap.unit != coalesce(first_snap.unit,last_snap.unit)
order by
        last_snap.name asc nulls last;

\pset border 0
\pset tuples_only
select ' ' as T;
\pset tuples_only off

\qecho <h2>Full list of DB parameters</h2>
\pset border 1

select
        name as Parameter_name,
        setting,
        unit
from
        statspack.hist_pg_settings
where
                snap_id = :END_SNAP
order by name;

\pset border 0
\qecho <h3>Aurora PostgreSQL Statspack - Created by Santiago Villa - <a href="https://github.com/SantiDBA/aurora-statspack" target="_blank">https://github.com/SantiDBA/aurora-statspack</a></h3>
\pset tuples_only off

