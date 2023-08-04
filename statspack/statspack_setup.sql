-- this script will create all the objects needed by Aurora Statspack package.
create schema IF NOT EXISTS statspack;

drop table if exists statspack.statspack_config ;

-- Create configuration table
create table statspack.statspack_config as select 7 as retention_days;

drop table if exists statspack.hist_snapshots ;

create table statspack.hist_snapshots as
select 1 as snap_id, now() as snap_timestamp;

drop table if exists statspack.hist_pg_users ;

create table statspack.hist_pg_users as
select
    1 as snap_id,
    usename,
    usesysid,
    useconfig
from
    pg_catalog.pg_user;

drop table if exists statspack.hist_pg_settings ;

create table statspack.hist_pg_settings as
SELECT 1 as snap_id, name, setting, unit FROM pg_show_all_settings();

drop table if exists statspack.hist_pg_stat_statements ;

create table statspack.hist_pg_stat_statements as
select 1 as snap_id, pss.*
from pg_stat_statements pss;

drop table if exists statspack.hist_stat_system_waits ;

create table statspack.hist_stat_system_waits as
SELECT 1 as snap_id, type_name,
             event_name,
             waits,
             wait_time
        FROM aurora_stat_system_waits()
NATURAL JOIN aurora_stat_wait_event()
NATURAL JOIN aurora_stat_wait_type();

drop table if exists statspack.hist_active_sessions_waits ;

create table statspack.hist_active_sessions_waits as
SELECT 1 as snap_id, a.pid,
             a.usename,
             a.app_name,
             a.current_wait_type,
             a.current_wait_event,
             a.current_state,
             wt.type_name AS wait_type,
             we.event_name AS wait_event,
             a.waits,
             a.wait_time,
             a.backend_start,
             a.xact_start,
             a.query_start,
             a.state_change,
             a.query
        FROM (SELECT pid,
                     usename,
                     left(application_name,16) AS app_name,
                     coalesce(wait_event_type,'CPU') AS current_wait_type,
                     coalesce(wait_event,'CPU') AS current_wait_event,
                     state AS current_state,
                     backend_start,
                     xact_start,
                     query_start,
                     state_change,
                     query,
                     (aurora_stat_backend_waits(pid)).*
                FROM pg_stat_activity
               WHERE pid <> pg_backend_pid()
                 AND state <> 'idle') a
NATURAL JOIN aurora_stat_wait_type() wt
NATURAL JOIN aurora_stat_wait_event() we;

drop table if exists statspack.hist_pg_stat_database ;

create table statspack.hist_pg_stat_database as
SELECT 1 as snap_id, psd.*
from pg_stat_database psd;

drop table if exists statspack.hist_pg_stat_all_tables ;

create table statspack.hist_pg_stat_all_tables as
select 1 as snap_id, psat.*
from pg_stat_all_tables psat;

drop table if exists statspack.hist_indexes_with_nulls ;

create table statspack.hist_indexes_with_nulls as
select
    1 as snap_id, 
	c_namespace.nspname as schema,
	c_table.relname as table,
	c.relname as index,
	i.indisunique as unique,
	a.attname as indexed_column,
	pg_relation_size(c.oid) as index_size_bytes,
	round((s.null_frac * 100)::NUMERIC,2) as "null_%",
	round(pg_relation_size(c.oid) * s.null_frac) as expected_saving_bytes
from
	pg_class c
join pg_index i on
	i.indexrelid = c.oid
join pg_attribute a on
	a.attrelid = c.oid
join pg_class c_table on
	c_table.oid = i.indrelid
join pg_namespace c_namespace on
	c_namespace.oid = c_table.relnamespace
left join pg_stats s on
	s.tablename = c_table.relname
	and a.attname = s.attname
where
	-- Primary key cannot be partial
    not i.indisprimary
	-- Exclude already partial indexes
	and i.indpred is null
	-- Exclude composite indexes
	and array_length(i.indkey, 1) = 1
	-- Exclude indexes without null_frac ratio
	and coalesce(s.null_frac, 0) != 0;
	
	
CREATE OR REPLACE PROCEDURE statspack.statspack_snapshot()
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $procedure$
declare
   v_snap_id integer := 0;
begin

-- Create new snapshot id
select (select max(snap_id)+1 INTO v_snap_id from statspack.hist_snapshots);

insert into statspack.hist_snapshots
select v_snap_id, now();

-- Capture from pg_stat_statements for queries with some consumption
insert into statspack.hist_pg_stat_statements
select v_snap_id as snap_id, pss.*
from pg_stat_statements pss
where rows != 0 or shared_blks_hit != 0 or shared_blks_read != 0 or shared_blks_written != 0 or temp_blks_read != 0 or temp_blks_written != 0;

-- insert from aurora_stat_system_waits
insert into statspack.hist_stat_system_waits
SELECT v_snap_id as snap_id, type_name,
             event_name,
             waits,
             wait_time
        FROM aurora_stat_system_waits()
NATURAL JOIN aurora_stat_wait_event()
NATURAL JOIN aurora_stat_wait_type();

-- insert from aurora_stat_backend_waits ONLY for active sessions
insert into statspack.hist_active_sessions_waits
SELECT v_snap_id as snap_id, a.pid,
             a.usename,
             a.app_name,
             a.current_wait_type,
             a.current_wait_event,
             a.current_state,
             wt.type_name AS wait_type,
             we.event_name AS wait_event,
             a.waits,
             a.wait_time,
             a.backend_start,
             a.xact_start,
             a.query_start,
             a.state_change,
             a.query
        FROM (SELECT pid,
                     usename,
                     left(application_name,16) AS app_name,
                     coalesce(wait_event_type,'CPU') AS current_wait_type,
                     coalesce(wait_event,'CPU') AS current_wait_event,
                     state AS current_state,
                     backend_start,
                     xact_start,
                     query_start,
                     state_change,
                     query,
                     (aurora_stat_backend_waits(pid)).*
                FROM pg_stat_activity
               WHERE pid <> pg_backend_pid()
                 AND state <> 'idle') a
NATURAL JOIN aurora_stat_wait_type() wt
NATURAL JOIN aurora_stat_wait_event() we;

-- insert from  pg_stat_database
insert into statspack.hist_pg_stat_database
SELECT v_snap_id as snap_id, psd.*
from pg_stat_database psd;

-- Insert from pg_users
insert
    into
    statspack.hist_pg_users
select
    v_snap_id,
    usename,
    usesysid,
    useconfig
from pg_catalog.pg_user;

-- Insert any new DB setting of changed config
insert
    into
    statspack.hist_pg_settings
select
    v_snap_id,
    name,
    setting,
    unit
from pg_show_all_settings();

-- insert from  pg_stat_all_tables
insert into statspack.hist_pg_stat_all_tables 
select v_snap_id as snap_id, psat.*
from pg_stat_all_tables psat;

insert into statspack.hist_indexes_with_nulls
select
    v_snap_id, 
	c_namespace.nspname as schema,
	c_table.relname as table,
	c.relname as index,
	i.indisunique as unique,
	a.attname as indexed_column,
	pg_relation_size(c.oid) as index_size_bytes,
	round((s.null_frac * 100)::NUMERIC,2) as "null_%",
	round(pg_relation_size(c.oid) * s.null_frac) as expected_saving_bytes
from
	pg_class c
join pg_index i on
	i.indexrelid = c.oid
join pg_attribute a on
	a.attrelid = c.oid
join pg_class c_table on
	c_table.oid = i.indrelid
join pg_namespace c_namespace on
	c_namespace.oid = c_table.relnamespace
left join pg_stats s on
	s.tablename = c_table.relname
	and a.attname = s.attname
where
	-- Primary key cannot be partial
    not i.indisprimary
	-- Exclude already partial indexes
	and i.indpred is null
	-- Exclude composite indexes
	and array_length(i.indkey, 1) = 1
	-- Exclude indexes without null_frac ratio
	and coalesce(s.null_frac, 0) != 0;

end;
$procedure$
;


CREATE OR REPLACE PROCEDURE statspack.statspack_remove_snapshot(p_snap_id integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $procedure$
begin

delete from statspack.hist_active_sessions_waits
where snap_id = p_snap_id;

delete from statspack.hist_stat_system_waits
where snap_id = p_snap_id;

delete from statspack.hist_pg_stat_statements
where snap_id = p_snap_id;

delete from statspack.hist_pg_settings
where snap_id = p_snap_id;

delete from statspack.hist_pg_stat_database
where snap_id = p_snap_id;

delete from statspack.hist_pg_users
where snap_id = p_snap_id;

delete from statspack.hist_pg_stat_all_tables
where snap_id = p_snap_id;

delete from statspack.hist_snapshots
where snap_id = p_snap_id;

end;
$procedure$
;

create or replace
procedure statspack.statspack_cleanup()
 language plpgsql
 security definer
as $procedure$
declare v_snapshot_rec RECORD;
begin
-- will remove all the snapshots older than (statspack_config.retention_days) days
    for v_snapshot_rec in
(
select
    snap_id
from
    statspack.hist_snapshots
where
    snap_timestamp < now() - (
    select
        retention_days
    from
        statspack.statspack_config) * '1 day'::interval) loop
        call statspack.statspack_remove_snapshot(v_snapshot_rec.snap_id);
end loop;
end;
$procedure$
;
