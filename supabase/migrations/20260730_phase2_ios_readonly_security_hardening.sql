-- Phase 2: iOS read-only API hardening
--
-- Applied to Supabase project jecrhdilcvetvzygeeqb on 2026-07-30.
-- This migration keeps Phase 1 collector tables unchanged and prepares the
-- existing mobile views/RPCs for authenticated, read-only iOS access.

-- Pin function search paths so security-definer and RPC functions do not depend
-- on caller-controlled search_path state.
alter function public.health_rank(text) set search_path = public, pg_temp;
alter function public.worst_health(text[]) set search_path = public, pg_temp;
alter function public.metric_health(text, double precision) set search_path = public, pg_temp;
alter function public.is_monitoring_data_stale(timestamp with time zone, integer) set search_path = public, pg_temp;
alter function public.get_application_incidents(uuid, integer) set search_path = public, pg_temp;
alter function public.get_application_metric_chart(uuid, text, integer, integer) set search_path = public, pg_temp;
alter function public.get_node_metric_chart(uuid, text, integer, integer) set search_path = public, pg_temp;
alter function public.get_dashboard_rankings(text, integer) set search_path = public, pg_temp;
alter function public.get_health_distribution() set search_path = public, pg_temp;
alter function public.cleanup_appdynamics_realtime_data() set search_path = public, pg_temp;

-- Force mobile views to respect the querying user's permissions and RLS.
alter view public.v_latest_application_metrics set (security_invoker = true);
alter view public.v_latest_node_metrics set (security_invoker = true);
alter view public.v_active_incidents set (security_invoker = true);
alter view public.v_application_nodes set (security_invoker = true);
alter view public.v_monitor_applications set (security_invoker = true);
alter view public.v_application_overview set (security_invoker = true);
alter view public.v_recent_events set (security_invoker = true);
alter view public.v_dashboard_summary set (security_invoker = true);
alter view public.v_collector_status set (security_invoker = true);

-- Anonymous users must not read monitoring data.
revoke all on table
    public.applications,
    public.application_metrics,
    public.tiers,
    public.nodes,
    public.infrastructure_metrics,
    public.health_rule_violations,
    public.application_events,
    public.sync_runs
from anon;

revoke all on table
    public.v_latest_application_metrics,
    public.v_latest_node_metrics,
    public.v_active_incidents,
    public.v_application_nodes,
    public.v_monitor_applications,
    public.v_application_overview,
    public.v_recent_events,
    public.v_dashboard_summary,
    public.v_collector_status
from anon;

-- Authenticated app users are read-only. The collector continues to write with
-- service_role credentials outside the iOS app.
revoke insert, update, delete, truncate, references, trigger on table
    public.applications,
    public.application_metrics,
    public.tiers,
    public.nodes,
    public.infrastructure_metrics,
    public.health_rule_violations,
    public.application_events,
    public.sync_runs
from authenticated;

grant select on table
    public.applications,
    public.application_metrics,
    public.tiers,
    public.nodes,
    public.infrastructure_metrics,
    public.health_rule_violations,
    public.application_events,
    public.sync_runs
to authenticated;

-- sync_runs remains readable to authenticated app users during debugging so the
-- app can show the latest collector run and freshness state.
do $$
begin
    if not exists (
        select 1
        from pg_policies
        where schemaname = 'public'
          and tablename = 'sync_runs'
          and policyname = 'authenticated_read_sync_runs'
    ) then
        create policy authenticated_read_sync_runs
            on public.sync_runs
            for select
            to authenticated
            using (true);
    end if;
end
$$;

revoke all on table
    public.v_latest_application_metrics,
    public.v_latest_node_metrics,
    public.v_active_incidents,
    public.v_application_nodes,
    public.v_monitor_applications,
    public.v_application_overview,
    public.v_recent_events,
    public.v_dashboard_summary,
    public.v_collector_status
from authenticated;

grant select on table
    public.v_latest_application_metrics,
    public.v_latest_node_metrics,
    public.v_active_incidents,
    public.v_application_nodes,
    public.v_monitor_applications,
    public.v_application_overview,
    public.v_recent_events,
    public.v_dashboard_summary,
    public.v_collector_status
to authenticated;

-- RPC access is read-only for authenticated app users. Cleanup stays server-side.
revoke all on function public.health_rank(text) from public, anon;
revoke all on function public.worst_health(text[]) from public, anon;
revoke all on function public.metric_health(text, double precision) from public, anon;
revoke all on function public.is_monitoring_data_stale(timestamp with time zone, integer) from public, anon;
revoke all on function public.get_application_incidents(uuid, integer) from public, anon;
revoke all on function public.get_application_metric_chart(uuid, text, integer, integer) from public, anon;
revoke all on function public.get_node_metric_chart(uuid, text, integer, integer) from public, anon;
revoke all on function public.get_dashboard_rankings(text, integer) from public, anon;
revoke all on function public.get_health_distribution() from public, anon;
revoke all on function public.cleanup_appdynamics_realtime_data() from public, anon, authenticated;

grant execute on function public.health_rank(text) to authenticated, service_role;
grant execute on function public.worst_health(text[]) to authenticated, service_role;
grant execute on function public.metric_health(text, double precision) to authenticated, service_role;
grant execute on function public.is_monitoring_data_stale(timestamp with time zone, integer) to authenticated, service_role;
grant execute on function public.get_application_incidents(uuid, integer) to authenticated, service_role;
grant execute on function public.get_application_metric_chart(uuid, text, integer, integer) to authenticated, service_role;
grant execute on function public.get_node_metric_chart(uuid, text, integer, integer) to authenticated, service_role;
grant execute on function public.get_dashboard_rankings(text, integer) to authenticated, service_role;
grant execute on function public.get_health_distribution() to authenticated, service_role;
grant execute on function public.cleanup_appdynamics_realtime_data() to service_role;
