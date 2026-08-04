revoke execute on function public.handle_new_mobile_user() from anon;
revoke execute on function public.handle_new_mobile_user() from authenticated;
revoke execute on function public.handle_new_mobile_user() from public;

revoke execute on function public.set_mobile_user_access_updated_at() from anon;
revoke execute on function public.set_mobile_user_access_updated_at() from authenticated;
revoke execute on function public.set_mobile_user_access_updated_at() from public;
