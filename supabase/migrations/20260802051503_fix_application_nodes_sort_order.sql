-- Phase 2: selected-application node state for iOS
--
-- Applied to Supabase project jecrhdilcvetvzygeeqb on 2026-08-02 as
-- migration 20260802051503_fix_application_nodes_sort_order.
--
-- This replaces the broad v_application_nodes read path with a focused RPC
-- that loads only the selected application's nodes. It also sorts actionable
-- node states before Healthy and No Data rows.

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
)
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
        when public.is_monitoring_data_stale(m.latest_metric_at, 30) then 'No Data'
        when coalesce(m.availability, 1) < 1 then 'Critical'
        when coalesce(m.cpu_percent, 0) >= 95 or coalesce(m.memory_percent, 0) >= 95 then 'Critical'
        when coalesce(m.cpu_percent, 0) >= 75 or coalesce(m.memory_percent, 0) >= 75 then 'Warning'
        else 'Healthy'
    end as node_health,
    m.latest_metric_at,
    public.is_monitoring_data_stale(m.latest_metric_at, 30) as is_stale
from app_nodes n
left join node_metrics m on m.node_id = n.id
order by public.health_rank(
    case
        when public.is_monitoring_data_stale(m.latest_metric_at, 30) then 'No Data'
        when coalesce(m.availability, 1) < 1 then 'Critical'
        when coalesce(m.cpu_percent, 0) >= 95 or coalesce(m.memory_percent, 0) >= 95 then 'Critical'
        when coalesce(m.cpu_percent, 0) >= 75 or coalesce(m.memory_percent, 0) >= 75 then 'Warning'
        else 'Healthy'
    end
) desc, n.tier_name, n.name;
$$;

revoke all on function public.get_application_nodes(uuid) from public, anon;
grant execute on function public.get_application_nodes(uuid) to authenticated, service_role;
