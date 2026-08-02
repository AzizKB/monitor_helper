-- Phase 2: range-aware Monitor application summaries
--
-- Applied to Supabase project jecrhdilcvetvzygeeqb on 2026-08-02 as
-- migration 20260802050525_range_aware_monitor_applications_rpc.
--
-- This RPC lets iOS request Monitor/Dashboard application summaries for the
-- selected time range. It keeps the phone from downloading raw metric history
-- and prevents the time-range picker from only changing the label.

create or replace function public.get_monitor_applications(
    p_window_minutes integer default 60
)
returns table (
    application_id uuid,
    appdynamics_id bigint,
    application_name text,
    display_name text,
    performance_health text,
    infrastructure_health text,
    overall_health text,
    response_time_ms double precision,
    calls_per_minute double precision,
    errors_per_minute double precision,
    error_percentage double precision,
    worst_cpu_percent double precision,
    worst_memory_percent double precision,
    availability double precision,
    active_critical_count bigint,
    active_warning_count bigint,
    active_incident_count bigint,
    node_count bigint,
    tier_count bigint,
    latest_application_metric_at timestamp with time zone,
    latest_infrastructure_metric_at timestamp with time zone,
    last_successful_sync_at timestamp with time zone,
    is_stale boolean,
    data_age_minutes integer
)
language sql
stable
set search_path = public, pg_temp
as $$
with params as (
    select least(greatest(coalesce(p_window_minutes, 60), 15), 2880)::integer as window_minutes
),
active_apps as (
    select
        id,
        appdynamics_id,
        name,
        display_name
    from public.applications
    where active = true
      and monitoring_enabled = true
),
range_metrics as (
    select
        m.application_id,
        avg(coalesce(m.value, m.current_value)) filter (where m.metric_key = 'response_time') as response_time_ms,
        avg(coalesce(m.value, m.current_value)) filter (where m.metric_key = 'calls_per_minute') as calls_per_minute,
        avg(coalesce(m.value, m.current_value)) filter (where m.metric_key = 'errors_per_minute') as raw_errors_per_minute,
        max(m.observed_at) as latest_application_metric_at
    from public.application_metrics m
    cross join params p
    where m.metric_key in ('response_time', 'calls_per_minute', 'errors_per_minute')
      and m.observed_at >= now() - make_interval(mins => p.window_minutes)
    group by m.application_id
),
app_state as (
    select
        application_id,
        response_time_ms,
        calls_per_minute,
        coalesce(
            raw_errors_per_minute,
            case
                when response_time_ms is not null or calls_per_minute is not null then 0::double precision
                else null::double precision
            end
        ) as errors_per_minute,
        latest_application_metric_at
    from range_metrics
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
    case
        when s.calls_per_minute > 0 then (s.errors_per_minute / s.calls_per_minute) * 100
        else null::double precision
    end as error_percentage,
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
$$;

revoke all on function public.get_monitor_applications(integer) from public, anon;
grant execute on function public.get_monitor_applications(integer) to authenticated, service_role;
