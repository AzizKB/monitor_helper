-- Add admin-only observability views for beta operations.
--
-- These views are intentionally kept outside the public schema so the current
-- iOS beta app is not affected and normal authenticated app users cannot query
-- operational/admin data through the Data API.

create schema if not exists admin_monitoring;

revoke all on schema admin_monitoring from public, anon, authenticated;
grant usage on schema admin_monitoring to postgres, service_role;

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
       (select count(*) from public.infrastructure_metrics where observed_at < now() - interval '12 hours') as infrastructure_metrics_over_retention,
       (select count(*) from public.sync_runs where started_at < now() - interval '14 days') as sync_runs_over_retention;

create or replace view admin_monitoring.stale_applications
with (security_invoker = true)
as
with metric_state as (
    select a.id as application_id,
           a.appdynamics_id,
           a.name as application_name,
           coalesce(a.display_name, a.name) as display_name,
           a.active,
           a.monitoring_enabled,
           max(m.observed_at) filter (where m.metric_key = 'response_time') as latest_response_time_at,
           max(m.observed_at) filter (where m.metric_key = 'calls_per_minute') as latest_calls_per_minute_at,
           max(m.observed_at) filter (where m.metric_key = 'errors_per_minute') as latest_errors_per_minute_at,
           max(m.observed_at) as latest_metric_at
    from public.applications a
    left join public.application_metrics m on m.application_id = a.id
    where a.active = true
      and a.monitoring_enabled = true
    group by a.id, a.appdynamics_id, a.name, a.display_name, a.active, a.monitoring_enabled
), active_alarms as (
    select application_id, count(*) as active_alarm_count
    from public.health_rule_violations
    where upper(coalesce(status, '')) = 'OPEN'
    group by application_id
)
select ms.application_id,
       ms.appdynamics_id,
       ms.application_name,
       ms.display_name,
       ms.latest_metric_at,
       floor(extract(epoch from (now() - ms.latest_metric_at)) / 60)::integer as latest_metric_age_minutes,
       ms.latest_response_time_at,
       floor(extract(epoch from (now() - ms.latest_response_time_at)) / 60)::integer as response_time_age_minutes,
       ms.latest_calls_per_minute_at,
       floor(extract(epoch from (now() - ms.latest_calls_per_minute_at)) / 60)::integer as calls_per_minute_age_minutes,
       ms.latest_errors_per_minute_at,
       floor(extract(epoch from (now() - ms.latest_errors_per_minute_at)) / 60)::integer as errors_per_minute_age_minutes,
       coalesce(aa.active_alarm_count, 0) as active_alarm_count,
       case
           when ms.latest_metric_at is null then 'missing_all_metrics'
           when ms.latest_metric_at < now() - interval '30 minutes' then 'stale_metrics'
           when ms.latest_response_time_at is null or ms.latest_calls_per_minute_at is null or ms.latest_errors_per_minute_at is null then 'partial_metrics'
           else 'current'
       end as data_state,
       case
           when ms.latest_metric_at is null then 'No app metric data has been collected for this application.'
           when ms.latest_metric_at < now() - interval '30 minutes' then 'Latest app metric data is older than 30 minutes.'
           when ms.latest_response_time_at is null or ms.latest_calls_per_minute_at is null or ms.latest_errors_per_minute_at is null then 'One or more expected performance metrics is missing.'
           else 'Metric data is current.'
       end as reason
from metric_state ms
left join active_alarms aa on aa.application_id = ms.application_id
where ms.latest_metric_at is null
   or ms.latest_metric_at < now() - interval '30 minutes'
   or ms.latest_response_time_at is null
   or ms.latest_calls_per_minute_at is null
   or ms.latest_errors_per_minute_at is null
order by
    case
        when ms.latest_metric_at is null then 0
        when ms.latest_metric_at < now() - interval '30 minutes' then 1
        else 2
    end,
    ms.latest_metric_at nulls first,
    ms.display_name;

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
    select 'infrastructure_metrics', '12 hours', count(*)::bigint,
           count(*) filter (where observed_at < now() - interval '12 hours')::bigint,
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

create or replace view admin_monitoring.beta_users_admin
with (security_invoker = true)
as
select u.id as auth_user_id,
       u.email,
       case when u.email_confirmed_at is null then 'not_confirmed' else 'confirmed' end as email_status,
       u.created_at as auth_created_at,
       u.email_confirmed_at,
       u.confirmation_sent_at,
       u.last_sign_in_at,
       mua.status as access_status,
       mua.role as access_role,
       mua.requested_at,
       mua.approved_at,
       mua.updated_at as access_updated_at,
       case
           when mua.user_id is null then 'missing_access_row'
           when u.email_confirmed_at is null then 'waiting_email_confirmation'
           when mua.status = 'pending' then 'waiting_admin_approval'
           when mua.status = 'approved' then 'can_access_app'
           when mua.status = 'blocked' then 'blocked'
           else 'unknown'
       end as beta_access_state
from auth.users u
left join public.mobile_user_access mua on mua.user_id = u.id
order by u.created_at desc;

revoke all on all tables in schema admin_monitoring from public, anon, authenticated;
grant select on all tables in schema admin_monitoring to postgres, service_role;
