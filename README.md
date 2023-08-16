# aurora-statspack

Aurora Statspack to monitor performance on Aurora compatible with PostgreSQL

Created by Santiago Villa, last modified on Jan 03, 2023

This is a package to capture Aurora performance statistics in historical tables inside a new schema: statspack.

Statspack Setup

Run statspack_setup.sql script into the target Aurora PostgreSQL database to create all the Statspack objects.

Statspack Tables and Procedures

Tables:
    
    - statspack.hist_active_sessions_waits
    - statspack.hist_indexes_with_nulls
    - statspack.hist_pg_settings
    - statspack.hist_pg_stat_all_tables
    - statspack.hist_pg_stat_database
    - statspack.hist_pg_stat_statements
    - statspack.hist_pg_users
    - statspack.hist_snapshots
    - statspack.hist_stat_system_waits
    - statspack.statspack_config

Procedures:

    -- Take Aurora snapshot from live views and functions
    call statspack.statspack_snapshot();

    -- Remove specific snapshot from Statspack schema
    call statspack.statspack_remove_snapshot(1);

    -- Remove snapshots based on retention configuration
    call statspack.statspack_cleanup();

Setting up automatic Statspack jobs using pg_cron

    Create snapshot job
    	SELECT cron.schedule('Statspack Snapshot', '*/10 * * * *', 'call statspack.statspack_snapshot()');

    	NOTE: this example will take one snapshot every 10 minutes

    Create Statspack purging job
    	SELECT cron.schedule('Statspack Cleanup', '0 0 * * *', 'call statspack.statspack_cleanup()');

    	NOTE: retention days is set on statspack_config table

Monitoring jobs and logs

    -- Check which Statpack jobs are scheduled on pg_cron
    SELECT * from cron.job WHERE command like '%statspack%';

    -- Check Statpack jobs execution in the log table
    SELECT * from cron.job_run_details WHERE command like '%statspack%' order by end_time desc limit 10;

Remove snapshot job
SELECT cron.unschedule ('Statspack Snapshot');

Remove Statspack purging job
SELECT cron.unschedule ('Statspack Cleanup');

Aurora Statspack Report

Connect to the target Aurora DB and execute the statspack report (statspack_report.sql).
i.e.
postgres=> \i statspack_report.sql
