-- Phase 2: separate stale-data visibility from No Data health
--
-- A 30-minute freshness warning is useful, but it is too aggressive as a hard
-- No Data cutoff for a 15-minute collector and 10-minute AppDynamics buckets.
-- The mobile API now marks rows stale after 30 minutes while only changing
-- health to No Data after 60 minutes or when metric data is missing.

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
latest_app_metric as (
    select
        m.application_id,
        max(m.observed_at) as latest_application_metric_at
    from public.application_metrics m
    where m.metric_key in ('response_time', 'calls_per_minute', 'errors_per_minute')
    group by m.application_id
),
range_metrics as (
    select
        m.application_id,
        coalesce(
            (sum(m.sum_value) filter (where m.metric_key = 'response_time'))
                / nullif(sum(m.count_value) filter (where m.metric_key = 'response_time'), 0),
            avg(m.value) filter (where m.metric_key = 'response_time'),
            avg(m.current_value) filter (where m.metric_key = 'response_time')
        ) as response_time_ms,
        coalesce(
            avg(m.value) filter (where m.metric_key = 'calls_per_minute'),
            avg(m.current_value) filter (where m.metric_key = 'calls_per_minute')
        ) as calls_per_minute,
        coalesce(
            avg(m.value) filter (where m.metric_key = 'errors_per_minute'),
            avg(m.current_value) filter (where m.metric_key = 'errors_per_minute')
        ) as raw_errors_per_minute,
        max(l.latest_application_metric_at) as latest_application_metric_at
    from public.application_metrics m
    join latest_app_metric l on l.application_id = m.application_id
    cross join params p
    where m.metric_key in ('response_time', 'calls_per_minute', 'errors_per_minute')
      and m.observed_at > l.latest_application_metric_at - make_interval(mins => p.window_minutes)
      and m.observed_at <= l.latest_application_metric_at
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
    select application_id, count(*) as node_count
    from public.nodes
    group by application_id
),
tier_counts as (
    select application_id, count(*) as tier_count
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
        when public.is_monitoring_data_stale(s.latest_application_metric_at, 60) then 'No Data'
        else 'Healthy'
    end as performance_health,
    case
        when public.is_monitoring_data_stale(s.latest_application_metric_at, 60) then 'No Data'
        else 'Healthy'
    end as infrastructure_health,
    case
        when coalesce(ic.active_critical_count, 0) > 0 then 'Critical'
        when coalesce(ic.active_warning_count, 0) > 0 then 'Warning'
        when public.is_monitoring_data_stale(s.latest_application_metric_at, 60) then 'No Data'
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

create or replace function public.get_application_nodes(
    p_application_id uuid
)
returns table (
    application_id uuid,
    tier_id uuid,
    tier_name text,
    node_id uuid,
    node_name text,
    machine_name text,
    agent_type text,
    app_agent_version text,
    machine_agent_version text,
    cpu_percent double precision,
    memory_percent double precision,
    availability double precision,
    node_health text,
    latest_metric_at timestamp with time zone,
    is_stale boolean
)
language sql
stable
set search_path = public, pg_temp
as $$
with app_nodes as (
    select
        n.id,
        n.application_id,
        n.tier_id,
        coalesce(n.tier_name, t.name) as tier_name,
        n.name,
        n.machine_name,
        n.agent_type,
        n.app_agent_version,
        n.machine_agent_version
    from public.nodes n
    left join public.tiers t on t.id = n.tier_id
    where n.application_id = p_application_id
),
node_metrics as (
    select
        n.id as node_id,
        max(l.metric_value) filter (where l.metric_key = 'node_cpu_busy') as cpu_percent,
        max(l.metric_value) filter (where l.metric_key = 'node_memory_used_percent') as memory_percent,
        max(l.metric_value) filter (where l.metric_key = 'node_app_availability') as availability,
        max(l.observed_at) as latest_metric_at
    from app_nodes n
    left join lateral (
        select distinct on (m.metric_key)
            m.metric_key,
            coalesce(m.value, m.current_value) as metric_value,
            m.observed_at
        from public.infrastructure_metrics m
        where m.node_id = n.id
          and m.metric_key in ('node_cpu_busy', 'node_memory_used_percent', 'node_app_availability')
        order by m.metric_key, m.observed_at desc, m.id desc
    ) l on true
    group by n.id
),
node_states as (
    select
        n.application_id,
        n.tier_id,
        n.tier_name,
        n.id as node_id,
        n.name as node_name,
        n.machine_name,
        n.agent_type,
        n.app_agent_version,
        n.machine_agent_version,
        m.cpu_percent,
        m.memory_percent,
        m.availability,
        case
            when public.is_monitoring_data_stale(m.latest_metric_at, 60) then 'No Data'
            when coalesce(m.availability, 1) < 1 then 'Critical'
            when coalesce(m.cpu_percent, 0) >= 95 or coalesce(m.memory_percent, 0) >= 95 then 'Critical'
            when coalesce(m.cpu_percent, 0) >= 75 or coalesce(m.memory_percent, 0) >= 75 then 'Warning'
            else 'Healthy'
        end as node_health,
        m.latest_metric_at,
        public.is_monitoring_data_stale(m.latest_metric_at, 30) as is_stale
    from app_nodes n
    left join node_metrics m on m.node_id = n.id
)
select *
from node_states
order by public.health_rank(node_health) desc, tier_name, node_name;
$$;

revoke all on function public.get_application_nodes(uuid) from public, anon;
grant execute on function public.get_application_nodes(uuid) to authenticated, service_role;
