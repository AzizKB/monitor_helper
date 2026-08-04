revoke execute on function public.is_mobile_user_approved() from anon;
revoke execute on function public.is_mobile_user_approved() from public;
grant execute on function public.is_mobile_user_approved() to authenticated;

revoke execute on function public.get_mobile_access_status() from anon;
revoke execute on function public.get_mobile_access_status() from public;
grant execute on function public.get_mobile_access_status() to authenticated;
