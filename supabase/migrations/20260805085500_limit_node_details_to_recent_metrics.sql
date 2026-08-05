-- Node detail is a current-state screen. Limit the latest-node lookup to recent
-- infrastructure metrics so large applications do not scan the full retention
-- window while trying to render node rows.

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
      and m.observed_at >= now() - interval '2 hours'
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
