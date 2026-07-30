-- Phase 2: Optimize Monitor application list for iOS
--
-- Applied to Supabase project jecrhdilcvetvzygeeqb on 2026-07-30 as
-- migration 20260730182222_optimize_monitor_applications_view.
-- The previous v_monitor_applications view joined through v_application_nodes,
-- which forced Postgres to scan the latest metric state for every node before
-- returning the main Monitor list. That caused PostgREST statement timeouts in
-- the iOS app.
--
-- This view keeps the same mobile-facing columns, but makes the Monitor list a
-- light current-state query. Infrastructure detail remains available through
-- the dedicated node/infrastructure endpoints after the user opens an app.

create or replace view public.v_monitor_applications
with (security_invoker = true)
as
with active_apps as (
    select
        id,
        appdynamics_id,
        name,
        display_name
    from public.applications
    where active = true
      and monitoring_enabled = true
),
app_state as (
    select
        a.id as application_id,
        rt.metric_value as response_time_ms,
        cpm.metric_value as calls_per_minute,
        epm.metric_value as errors_per_minute,
        greatest(rt.observed_at, cpm.observed_at, epm.observed_at) as latest_application_metric_at
    from active_apps a
    left join lateral (
        select
            coalesce(value, current_value) as metric_value,
            observed_at
        from public.application_metrics
        where application_id = a.id
          and metric_key = 'response_time'
        order by observed_at desc, id desc
        limit 1
    ) rt on true
    left join lateral (
        select
            coalesce(value, current_value) as metric_value,
            observed_at
        from public.application_metrics
        where application_id = a.id
          and metric_key = 'calls_per_minute'
        order by observed_at desc, id desc
        limit 1
    ) cpm on true
    left join lateral (
        select
            coalesce(value, current_value) as metric_value,
            observed_at
        from public.application_metrics
        where application_id = a.id
          and metric_key = 'errors_per_minute'
        order by observed_at desc, id desc
        limit 1
    ) epm on true
),
node_counts as (
    select
        application_id,
        count(*) as node_count
    from public.nodes
    group by application_id
),
tier_counts as (
    select
        application_id,
        count(*) as tier_count
    from public.tiers
    group by application_id
),
incident_counts as (
    select
        application_id,
        count(*) filter (where upper(severity) = 'CRITICAL') as active_critical_count,
        count(*) filter (where upper(severity) = 'WARNING') as active_warning_count,
        count(*) as active_incident_count
    from public.health_rule_violations
    where upper(status) = 'OPEN'
    group by application_id
),
latest_sync as (
    select completed_at
    from public.sync_runs
    where lower(status) = 'success'
      and completed_at is not null
    order by completed_at desc
    limit 1
)
select
    a.id as application_id,
    a.appdynamics_id,
    a.name as application_name,
    coalesce(a.display_name, a.name) as display_name,
    case
        when coalesce(ic.active_critical_count, 0) > 0 then 'Critical'
        when coalesce(ic.active_warning_count, 0) > 0 then 'Warning'
        when public.is_monitoring_data_stale(s.latest_application_metric_at, 30) then 'No Data'
        else 'Healthy'
    end as performance_health,
    case
        when public.is_monitoring_data_stale(s.latest_application_metric_at, 30) then 'No Data'
        else 'Healthy'
    end as infrastructure_health,
    case
        when coalesce(ic.active_critical_count, 0) > 0 then 'Critical'
        when coalesce(ic.active_warning_count, 0) > 0 then 'Warning'
        when public.is_monitoring_data_stale(s.latest_application_metric_at, 30) then 'No Data'
        else 'Healthy'
    end as overall_health,
    s.response_time_ms,
    s.calls_per_minute,
    s.errors_per_minute,
    null::double precision as worst_cpu_percent,
    null::double precision as worst_memory_percent,
    null::double precision as availability,
    coalesce(ic.active_critical_count, 0) as active_critical_count,
    coalesce(ic.active_warning_count, 0) as active_warning_count,
    coalesce(ic.active_incident_count, 0) as active_incident_count,
    coalesce(nc.node_count, 0) as node_count,
    coalesce(tc.tier_count, 0) as tier_count,
    s.latest_application_metric_at,
    null::timestamp with time zone as latest_infrastructure_metric_at,
    ls.completed_at as last_successful_sync_at,
    public.is_monitoring_data_stale(s.latest_application_metric_at, 30) as is_stale,
    case
        when s.latest_application_metric_at is null then null::integer
        else floor(extract(epoch from now() - s.latest_application_metric_at) / 60)::integer
    end as data_age_minutes
from active_apps a
left join app_state s on s.application_id = a.id
left join node_counts nc on nc.application_id = a.id
left join tier_counts tc on tc.application_id = a.id
left join incident_counts ic on ic.application_id = a.id
cross join latest_sync ls;

revoke all on table public.v_monitor_applications from anon;
grant select on table public.v_monitor_applications to authenticated;
