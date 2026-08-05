-- Enforce mobile monitoring retention after moving to high-frequency collection.
--
-- Current ingestion captures infrastructure datapoints every minute while the
-- collector runs every 5 minutes. That volume is useful for near-real-time
-- monitoring, but infrastructure history must be shorter than application
-- history to keep Supabase storage predictable.
--
-- Retention policy:
-- - application_metrics: 48 hours
-- - infrastructure_metrics: 12 hours, deleted in batches
-- - application_events: 48 hours
-- - health_rule_violations: keep OPEN rows; delete old RESOLVED/CANCELLED rows
-- - sync_runs: 14 days

create index if not exists idx_infrastructure_metrics_observed_at_brin
on public.infrastructure_metrics
using brin (observed_at)
with (pages_per_range = 64);

create index if not exists idx_application_metrics_observed_at_brin
on public.application_metrics
using brin (observed_at)
with (pages_per_range = 64);

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

-- Keep the existing hourly cleanup job enabled. The job already exists in this
-- project as: select public.cleanup_appdynamics_realtime_data();
update cron.job
set
    schedule = '17 * * * *',
    active = true
where command = 'select public.cleanup_appdynamics_realtime_data();';
