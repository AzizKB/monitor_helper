-- Count mobile-facing infrastructure nodes from metric coverage instead of every
-- node ever discovered. This avoids stale node inventory inflating app summaries.

create or replace function public.get_application_nodes(p_application_id uuid)
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
    latest_metric_at timestamptz,
    is_stale boolean
)
language sql
stable
set search_path to 'public', 'pg_temp'
as $function$
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
      and exists (
          select 1
          from public.infrastructure_metrics m
          where m.node_id = n.id
            and m.metric_key in (
                'node_cpu_busy',
                'node_memory_used_percent',
                'node_app_availability'
            )
      )
),
latest_node_metrics as (
    select distinct on (m.node_id, m.metric_key)
        m.node_id,
        m.metric_key,
        coalesce(m.value, m.current_value) as metric_value,
        m.observed_at
    from public.infrastructure_metrics m
    where m.application_id = p_application_id
      and m.node_id is not null
      and m.observed_at >= now() - interval '65 minutes'
      and m.metric_key in (
          'node_cpu_busy',
          'node_memory_used_percent',
          'node_app_availability'
      )
    order by m.node_id, m.metric_key, m.observed_at desc, m.id desc
),
node_metrics as (
    select
        latest_node_metrics.node_id,
        max(latest_node_metrics.metric_value) filter (
            where latest_node_metrics.metric_key = 'node_cpu_busy'
        ) as cpu_percent,
        max(latest_node_metrics.metric_value) filter (
            where latest_node_metrics.metric_key = 'node_memory_used_percent'
        ) as memory_percent,
        max(latest_node_metrics.metric_value) filter (
            where latest_node_metrics.metric_key = 'node_app_availability'
        ) as availability,
        max(latest_node_metrics.observed_at) as latest_metric_at
    from latest_node_metrics
    group by latest_node_metrics.node_id
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
$function$;

create or replace view public.v_monitor_applications
with (security_invoker = true)
as
with active_apps as (
    select
        applications.id,
        applications.appdynamics_id,
        applications.name,
        applications.display_name
    from public.applications
    where applications.active = true
      and applications.monitoring_enabled = true
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
            coalesce(application_metrics.value, application_metrics.current_value) as metric_value,
            application_metrics.observed_at
        from public.application_metrics
        where application_metrics.application_id = a.id
          and application_metrics.metric_key = 'response_time'
        order by application_metrics.observed_at desc, application_metrics.id desc
        limit 1
    ) rt on true
    left join lateral (
        select
            coalesce(application_metrics.value, application_metrics.current_value) as metric_value,
            application_metrics.observed_at
        from public.application_metrics
        where application_metrics.application_id = a.id
          and application_metrics.metric_key = 'calls_per_minute'
        order by application_metrics.observed_at desc, application_metrics.id desc
        limit 1
    ) cpm on true
    left join lateral (
        select
            coalesce(application_metrics.value, application_metrics.current_value) as metric_value,
            application_metrics.observed_at
        from public.application_metrics
        where application_metrics.application_id = a.id
          and application_metrics.metric_key = 'errors_per_minute'
        order by application_metrics.observed_at desc, application_metrics.id desc
        limit 1
    ) epm on true
),
node_counts as (
    select
        n.application_id,
        count(*) filter (
            where exists (
                select 1
                from public.infrastructure_metrics m
                where m.node_id = n.id
                  and m.metric_key in (
                      'node_cpu_busy',
                      'node_memory_used_percent',
                      'node_app_availability'
                  )
            )
        ) as node_count,
        count(*) filter (
            where exists (
                select 1
                from public.infrastructure_metrics m
                where m.node_id = n.id
                  and m.observed_at >= now() - interval '65 minutes'
                  and m.metric_key in (
                      'node_cpu_busy',
                      'node_memory_used_percent',
                      'node_app_availability'
                  )
            )
        ) as nodes_reporting
    from public.nodes n
    group by n.application_id
),
tier_counts as (
    select
        tiers.application_id,
        count(*) as tier_count
    from public.tiers
    group by tiers.application_id
),
incident_counts as (
    select
        health_rule_violations.application_id,
        count(*) filter (where upper(health_rule_violations.severity) = 'CRITICAL') as active_critical_count,
        count(*) filter (where upper(health_rule_violations.severity) = 'WARNING') as active_warning_count,
        count(*) as active_incident_count
    from public.health_rule_violations
    where upper(health_rule_violations.status) = 'OPEN'
    group by health_rule_violations.application_id
),
latest_sync as (
    select sync_runs.completed_at
    from public.sync_runs
    where lower(sync_runs.status) = 'success'
      and sync_runs.completed_at is not null
    order by sync_runs.completed_at desc
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
    end as data_age_minutes,
    coalesce(nc.nodes_reporting, 0) as nodes_reporting
from active_apps a
left join app_state s on s.application_id = a.id
left join node_counts nc on nc.application_id = a.id
left join tier_counts tc on tc.application_id = a.id
left join incident_counts ic on ic.application_id = a.id
cross join latest_sync ls;

create or replace view public.v_application_overview
with (security_invoker = true)
as
select
    application_id,
    appdynamics_id,
    application_name,
    display_name,
    performance_health,
    infrastructure_health,
    overall_health,
    response_time_ms,
    calls_per_minute,
    errors_per_minute,
    worst_cpu_percent,
    worst_memory_percent,
    availability,
    active_critical_count,
    active_warning_count,
    active_incident_count,
    node_count,
    tier_count,
    latest_application_metric_at,
    latest_infrastructure_metric_at,
    last_successful_sync_at,
    is_stale,
    data_age_minutes,
    nodes_reporting
from public.v_monitor_applications;

grant select on public.v_monitor_applications to authenticated;
grant select on public.v_application_overview to authenticated;
grant execute on function public.get_application_nodes(uuid) to authenticated;
