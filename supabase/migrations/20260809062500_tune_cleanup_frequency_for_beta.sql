-- Tune cleanup cadence for the beta monitoring workload.
--
-- The collector now runs frequently and writes dense infrastructure metrics.
-- Running cleanup every 15 minutes keeps retention steady with smaller delete
-- batches instead of allowing larger hourly cleanup spikes.

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
    where observed_at < now() - interval '12 hours';

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

select cron.alter_job(
    job_id := 1,
    schedule := '2,17,32,47 * * * *',
    command := 'select public.cleanup_appdynamics_realtime_data();',
    active := true
);
