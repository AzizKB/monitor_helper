-- Reduce infrastructure metric retention for beta stability.
--
-- Node-level infrastructure data is the largest table in this project. Keeping
-- it to 6 hours protects database size while preserving enough recent detail
-- for mobile troubleshooting.

create or replace function public.cleanup_appdynamics_realtime_data()
returns jsonb
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare
    app_metric_count integer;
    infra_metric_count integer;
    event_count integer;
    violation_count integer;
    sync_count integer;
    infra_backlog_remaining integer;
begin
    delete from public.application_metrics
    where observed_at < now() - interval '48 hours';
    get diagnostics app_metric_count = row_count;

    with doomed as (
        select id
        from public.infrastructure_metrics
        where observed_at < now() - interval '6 hours'
        order by observed_at
        limit 25000
    ),
    deleted as (
        delete from public.infrastructure_metrics m
        using doomed
        where m.id = doomed.id
        returning 1
    )
    select count(*)::integer
    into infra_metric_count
    from deleted;

    delete from public.application_events
    where event_time < now() - interval '48 hours';
    get diagnostics event_count = row_count;

    delete from public.health_rule_violations
    where upper(coalesce(status, '')) in ('RESOLVED', 'CANCELLED')
      and coalesce(end_time, start_time, ingested_at) < now() - interval '48 hours';
    get diagnostics violation_count = row_count;

    delete from public.sync_runs
    where started_at < now() - interval '14 days';
    get diagnostics sync_count = row_count;

    select count(*)::integer
    into infra_backlog_remaining
    from public.infrastructure_metrics
    where observed_at < now() - interval '6 hours';

    if app_metric_count > 0 then
        analyze public.application_metrics;
    end if;

    if infra_metric_count > 0 then
        analyze public.infrastructure_metrics;
    end if;

    if violation_count > 0 then
        analyze public.health_rule_violations;
    end if;

    if sync_count > 0 then
        analyze public.sync_runs;
    end if;

    return jsonb_build_object(
        'application_metrics_deleted', app_metric_count,
        'infrastructure_metrics_deleted', infra_metric_count,
        'infrastructure_backlog_remaining', infra_backlog_remaining,
        'events_deleted', event_count,
        'closed_violations_deleted', violation_count,
        'sync_runs_deleted', sync_count,
        'completed_at', now()
    );
end;
$function$;

revoke all on function public.cleanup_appdynamics_realtime_data() from public, anon, authenticated;
grant execute on function public.cleanup_appdynamics_realtime_data() to service_role;

create or replace view admin_monitoring.backend_health
with (security_invoker = true)
as
with latest_successful_sync as (
    select started_at, completed_at, status, applications_processed, metric_points_written,
           events_written, violations_written, error_count
    from public.sync_runs
    where lower(status) = 'success'
      and completed_at is not null
    order by completed_at desc
    limit 1
), latest_any_sync as (
    select started_at, completed_at, status, applications_processed, metric_points_written,
           events_written, violations_written, error_count
    from public.sync_runs
    order by started_at desc
    limit 1
), app_latest as (
    select a.id as application_id,
           max(m.observed_at) as latest_metric_at
    from public.applications a
    left join public.application_metrics m on m.application_id = a.id
    where a.active = true
      and a.monitoring_enabled = true
    group by a.id
), cleanup_job as (
    select jobid, schedule, active, jobname
    from cron.job
    where command = 'select public.cleanup_appdynamics_realtime_data();'
    order by jobid
    limit 1
), latest_cleanup_run as (
    select status, start_time, end_time, return_message
    from cron.job_run_details
    where command = 'select public.cleanup_appdynamics_realtime_data();'
    order by start_time desc
    limit 1
)
select now() as checked_at,
       (select status from latest_any_sync) as latest_sync_status,
       (select started_at from latest_any_sync) as latest_sync_started_at,
       (select completed_at from latest_any_sync) as latest_sync_completed_at,
       (select completed_at from latest_successful_sync) as latest_successful_sync_at,
       floor(extract(epoch from (now() - (select completed_at from latest_successful_sync))) / 60)::integer as minutes_since_successful_sync,
       (select applications_processed from latest_successful_sync) as latest_applications_processed,
       (select metric_points_written from latest_successful_sync) as latest_metric_points_written,
       (select error_count from latest_successful_sync) as latest_sync_error_count,
       (select max(observed_at) from public.application_metrics) as latest_application_metric_at,
       (select max(observed_at) from public.infrastructure_metrics) as latest_infrastructure_metric_at,
       (select count(*) from app_latest) as monitored_application_count,
       (select count(*) from app_latest where latest_metric_at is null) as missing_metric_application_count,
       (select count(*) from app_latest where latest_metric_at < now() - interval '30 minutes') as stale_application_count,
       (select max(floor(extract(epoch from (now() - latest_metric_at)) / 60)::integer) from app_latest where latest_metric_at is not null) as oldest_metric_age_minutes,
       (select schedule from cleanup_job) as cleanup_schedule,
       (select active from cleanup_job) as cleanup_active,
       (select status from latest_cleanup_run) as latest_cleanup_status,
       (select start_time from latest_cleanup_run) as latest_cleanup_started_at,
       (select end_time from latest_cleanup_run) as latest_cleanup_completed_at,
       (select return_message from latest_cleanup_run) as latest_cleanup_return_message,
       (select count(*) from public.application_metrics where observed_at < now() - interval '48 hours') as application_metrics_over_retention,
       (select count(*) from public.infrastructure_metrics where observed_at < now() - interval '6 hours') as infrastructure_metrics_over_retention,
       (select count(*) from public.sync_runs where started_at < now() - interval '14 days') as sync_runs_over_retention;

create or replace view admin_monitoring.cleanup_status
with (security_invoker = true)
as
with cleanup_job as (
    select jobid, schedule, active, jobname
    from cron.job
    where command = 'select public.cleanup_appdynamics_realtime_data();'
    order by jobid
    limit 1
), latest_cleanup_run as (
    select status, start_time, end_time, return_message
    from cron.job_run_details
    where command = 'select public.cleanup_appdynamics_realtime_data();'
    order by start_time desc
    limit 1
), retention_rows as (
    select 'application_metrics'::text as dataset,
           '48 hours'::text as retention_window,
           count(*)::bigint as total_rows,
           count(*) filter (where observed_at < now() - interval '48 hours')::bigint as rows_over_retention,
           min(observed_at) as oldest_record_at,
           max(observed_at) as newest_record_at
    from public.application_metrics
    union all
    select 'infrastructure_metrics', '6 hours', count(*)::bigint,
           count(*) filter (where observed_at < now() - interval '6 hours')::bigint,
           min(observed_at), max(observed_at)
    from public.infrastructure_metrics
    union all
    select 'application_events', '48 hours', count(*)::bigint,
           count(*) filter (where event_time < now() - interval '48 hours')::bigint,
           min(event_time), max(event_time)
    from public.application_events
    union all
    select 'closed_health_rule_violations', '48 hours', count(*)::bigint,
           count(*) filter (where upper(coalesce(status, '')) in ('RESOLVED','CANCELLED') and coalesce(end_time, start_time, ingested_at) < now() - interval '48 hours')::bigint,
           min(coalesce(end_time, start_time, ingested_at)), max(coalesce(end_time, start_time, ingested_at))
    from public.health_rule_violations
    where upper(coalesce(status, '')) in ('RESOLVED','CANCELLED')
    union all
    select 'sync_runs', '14 days', count(*)::bigint,
           count(*) filter (where started_at < now() - interval '14 days')::bigint,
           min(started_at), max(started_at)
    from public.sync_runs
)
select rr.*,
       case when rr.rows_over_retention = 0 then 'healthy' else 'cleanup_needed' end as retention_status,
       floor(extract(epoch from (now() - rr.newest_record_at)) / 60)::integer as newest_record_age_minutes,
       (select schedule from cleanup_job) as cleanup_schedule,
       (select active from cleanup_job) as cleanup_active,
       (select status from latest_cleanup_run) as latest_cleanup_status,
       (select start_time from latest_cleanup_run) as latest_cleanup_started_at,
       (select end_time from latest_cleanup_run) as latest_cleanup_completed_at,
       (select return_message from latest_cleanup_run) as latest_cleanup_return_message
from retention_rows rr
order by case rr.dataset
    when 'infrastructure_metrics' then 1
    when 'application_metrics' then 2
    when 'sync_runs' then 3
    when 'closed_health_rule_violations' then 4
    else 5
end;
