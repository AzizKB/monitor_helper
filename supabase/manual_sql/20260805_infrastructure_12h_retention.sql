-- Emergency retention cleanup for Supabase Free plan pressure.
--
-- Purpose:
-- - Keep application metrics at 48 hours.
-- - Keep infrastructure metrics at 12 hours.
-- - Preserve incidents/events at 48 hours.
-- - Keep OPEN health-rule violations, but remove old RESOLVED/CANCELLED rows.
-- - Preserve sync_runs at 14 days.
--
-- Run this in Supabase SQL Editor.
-- This deletes old infrastructure metric rows. It does not change the collector.

-- 1) Confirm how many infrastructure rows will be removed.
select
    count(*) as infra_total_rows,
    count(*) filter (where observed_at < now() - interval '12 hours') as infra_rows_to_delete,
    count(*) filter (where observed_at >= now() - interval '12 hours') as infra_rows_to_keep,
    min(observed_at) as oldest_observed_at,
    max(observed_at) as newest_observed_at
from public.infrastructure_metrics;

-- 2) Add compact retention indexes.
create index if not exists idx_infrastructure_metrics_observed_at_brin
on public.infrastructure_metrics
using brin (observed_at)
with (pages_per_range = 64);

create index if not exists idx_application_metrics_observed_at_brin
on public.application_metrics
using brin (observed_at)
with (pages_per_range = 64);

-- 3) Optional one-time cleanup for closed health-rule violations.
-- The app uses OPEN violations for active alarms and health calculations.
-- Closed rows are useful only as short-lived reference/history.
delete from public.health_rule_violations
where upper(coalesce(status, '')) in ('RESOLVED', 'CANCELLED')
  and coalesce(end_time, start_time, ingested_at) < now() - interval '48 hours';

-- 4) Update the existing cleanup function so future cleanup keeps infra at 12h
-- and removes old closed health-rule violations. OPEN violations are preserved.
-- Infrastructure deletion is batched to avoid long locks/timeouts.
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
        where observed_at < now() - interval '12 hours'
        order by observed_at
        limit 75000
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
    where observed_at < now() - interval '12 hours';

    if infra_metric_count > 0 then
        analyze public.infrastructure_metrics;
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

-- 5) Ensure the hourly cleanup job stays enabled.
update cron.job
set
    schedule = '17 * * * *',
    active = true
where command = 'select public.cleanup_appdynamics_realtime_data();';

-- 6) Run the cleanup once. Because infra cleanup is batched, run this statement
-- multiple times if infrastructure_backlog_remaining is still high.
select public.cleanup_appdynamics_realtime_data();

-- 7) Verify post-cleanup row counts.
select
    count(*) as infra_total_rows_after_cleanup,
    count(*) filter (where observed_at < now() - interval '12 hours') as old_infra_rows_remaining,
    count(*) filter (where observed_at >= now() - interval '12 hours') as infra_rows_kept,
    min(observed_at) as oldest_remaining_observed_at,
    max(observed_at) as newest_observed_at
from public.infrastructure_metrics;

select
    upper(coalesce(status, 'UNKNOWN')) as status,
    count(*) as rows,
    min(coalesce(end_time, start_time, ingested_at)) as oldest_time,
    max(coalesce(end_time, start_time, ingested_at)) as newest_time
from public.health_rule_violations
group by 1
order by rows desc;

-- Important:
-- Plain DELETE frees rows for reuse, but Supabase's disk graph may not drop
-- immediately because Postgres can keep table/index files allocated.
-- Do not run VACUUM FULL on the Free plan while disk is 96%; it can require
-- extra temporary disk space and may lock the table.
