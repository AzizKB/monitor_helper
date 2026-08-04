create table if not exists public.mobile_user_access (
    user_id uuid primary key references auth.users(id) on delete cascade,
    email text not null,
    status text not null default 'pending' check (status in ('pending', 'approved', 'blocked')),
    role text not null default 'beta' check (role in ('beta', 'admin')),
    requested_at timestamptz not null default now(),
    approved_at timestamptz,
    approved_by uuid references auth.users(id),
    updated_at timestamptz not null default now()
);

alter table public.mobile_user_access enable row level security;

create index if not exists mobile_user_access_status_idx
    on public.mobile_user_access (status);

create index if not exists mobile_user_access_email_lower_idx
    on public.mobile_user_access (lower(email));

revoke all on table public.mobile_user_access from anon;
revoke all on table public.mobile_user_access from authenticated;
grant select on table public.mobile_user_access to authenticated;
grant select, insert, update, delete on table public.mobile_user_access to service_role;

drop policy if exists mobile_user_access_select_own on public.mobile_user_access;
create policy mobile_user_access_select_own
on public.mobile_user_access
for select
to authenticated
using ((select auth.uid()) = user_id);

create or replace function public.set_mobile_user_access_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

revoke all on function public.set_mobile_user_access_updated_at() from public;

drop trigger if exists trg_mobile_user_access_updated_at on public.mobile_user_access;
create trigger trg_mobile_user_access_updated_at
before update on public.mobile_user_access
for each row execute function public.set_mobile_user_access_updated_at();

create or replace function public.handle_new_mobile_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    insert into public.mobile_user_access (user_id, email, status, role, requested_at, updated_at)
    values (new.id, coalesce(new.email, ''), 'pending', 'beta', now(), now())
    on conflict (user_id) do update
        set email = excluded.email,
            updated_at = now();

    return new;
end;
$$;

revoke all on function public.handle_new_mobile_user() from public;

drop trigger if exists on_auth_user_created_mobile_access on auth.users;
create trigger on_auth_user_created_mobile_access
after insert on auth.users
for each row execute function public.handle_new_mobile_user();

insert into public.mobile_user_access (
    user_id,
    email,
    status,
    role,
    requested_at,
    approved_at,
    updated_at
)
select
    id,
    coalesce(email, ''),
    'approved',
    'admin',
    coalesce(created_at, now()),
    now(),
    now()
from auth.users
on conflict (user_id) do update
    set email = excluded.email,
        status = case
            when public.mobile_user_access.status = 'blocked' then 'blocked'
            else 'approved'
        end,
        role = case
            when public.mobile_user_access.role = 'admin' then 'admin'
            else 'admin'
        end,
        approved_at = coalesce(public.mobile_user_access.approved_at, now()),
        updated_at = now();

create or replace function public.is_mobile_user_approved()
returns boolean
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
    select exists (
        select 1
        from public.mobile_user_access access
        where access.user_id = (select auth.uid())
          and access.status = 'approved'
    );
$$;

revoke all on function public.is_mobile_user_approved() from public;
grant execute on function public.is_mobile_user_approved() to authenticated;

create or replace function public.get_mobile_access_status()
returns table (
    user_id uuid,
    email text,
    status text,
    role text,
    requested_at timestamptz,
    approved_at timestamptz
)
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
    select
        access.user_id,
        access.email,
        access.status,
        access.role,
        access.requested_at,
        access.approved_at
    from public.mobile_user_access access
    where access.user_id = (select auth.uid());
$$;

revoke all on function public.get_mobile_access_status() from public;
grant execute on function public.get_mobile_access_status() to authenticated;

alter view public.v_active_incidents set (security_invoker = true);
alter view public.v_application_nodes set (security_invoker = true);
alter view public.v_application_overview set (security_invoker = true);
alter view public.v_collector_status set (security_invoker = true);
alter view public.v_dashboard_summary set (security_invoker = true);
alter view public.v_latest_application_metrics set (security_invoker = true);
alter view public.v_latest_node_metrics set (security_invoker = true);
alter view public.v_monitor_applications set (security_invoker = true);
alter view public.v_recent_events set (security_invoker = true);

drop policy if exists authenticated_read_applications on public.applications;
create policy authenticated_read_applications
on public.applications
for select
to authenticated
using ((select public.is_mobile_user_approved()));

drop policy if exists authenticated_read_application_metrics on public.application_metrics;
create policy authenticated_read_application_metrics
on public.application_metrics
for select
to authenticated
using ((select public.is_mobile_user_approved()));

drop policy if exists authenticated_read_infrastructure_metrics on public.infrastructure_metrics;
create policy authenticated_read_infrastructure_metrics
on public.infrastructure_metrics
for select
to authenticated
using ((select public.is_mobile_user_approved()));

drop policy if exists authenticated_read_tiers on public.tiers;
create policy authenticated_read_tiers
on public.tiers
for select
to authenticated
using ((select public.is_mobile_user_approved()));

drop policy if exists authenticated_read_nodes on public.nodes;
create policy authenticated_read_nodes
on public.nodes
for select
to authenticated
using ((select public.is_mobile_user_approved()));

drop policy if exists authenticated_read_health_rule_violations on public.health_rule_violations;
create policy authenticated_read_health_rule_violations
on public.health_rule_violations
for select
to authenticated
using ((select public.is_mobile_user_approved()));

drop policy if exists authenticated_read_application_events on public.application_events;
create policy authenticated_read_application_events
on public.application_events
for select
to authenticated
using ((select public.is_mobile_user_approved()));

drop policy if exists authenticated_read_sync_runs on public.sync_runs;
create policy authenticated_read_sync_runs
on public.sync_runs
for select
to authenticated
using ((select public.is_mobile_user_approved()));
