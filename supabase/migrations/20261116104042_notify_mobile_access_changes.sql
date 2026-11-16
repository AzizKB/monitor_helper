-- Signal only: the app re-checks its existing access RPC before showing data.
-- Keep access rows out of the Postgres Changes publication.
create schema if not exists monitor_helper_private;
revoke all on schema monitor_helper_private from public, anon, authenticated;

create policy monitor_helper_receive_own_access_signal
on realtime.messages for select to authenticated
using (
    extension = 'broadcast'
    and (select realtime.topic()) = 'mobile-access:' || (select auth.uid())::text
    and topic = (select realtime.topic())
);

create function monitor_helper_private.signal_mobile_access_change()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
    if tg_op = 'UPDATE' then
        if old.status is not distinct from new.status then
            return null;
        end if;
    end if;

    perform realtime.send('{}'::jsonb, 'access_changed', 'mobile-access:' || old.user_id::text, true);
    return null;
exception when others then
    -- A notification failure must never undo the underlying access revocation.
    raise warning 'Monitor Helper access notification failed (%)', sqlstate;
    return null;
end;
$function$;

revoke execute on function monitor_helper_private.signal_mobile_access_change()
from public, anon, authenticated;

create trigger trg_monitor_helper_mobile_access_changed
after update of status or delete on public.mobile_user_access
for each row execute function monitor_helper_private.signal_mobile_access_change();
