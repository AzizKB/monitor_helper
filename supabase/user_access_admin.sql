-- monitor_helper beta user access commands
--
-- Use this file as a copy/paste helper in the Supabase SQL Editor.
-- Replace USER_EMAIL_HERE with the user's email address.
--
-- Status meanings:
-- pending  = user signed up, but cannot access monitoring data yet
-- approved = user can access the iOS app monitoring data
-- blocked  = user can sign in, but cannot access monitoring data

-- 1. List all beta users
select
    email,
    status,
    role,
    requested_at,
    approved_at,
    updated_at
from public.mobile_user_access
order by requested_at desc;

-- 2. List users waiting for approval
select
    email,
    status,
    role,
    requested_at
from public.mobile_user_access
where status = 'pending'
order by requested_at asc;

-- 3. Approve a beta user
update public.mobile_user_access
set status = 'approved',
    role = 'beta',
    approved_at = now(),
    updated_at = now()
where lower(email) = lower('USER_EMAIL_HERE');

-- 4. Deactivate or block a user
update public.mobile_user_access
set status = 'blocked',
    updated_at = now()
where lower(email) = lower('USER_EMAIL_HERE');

-- 5. Reactivate a blocked user
update public.mobile_user_access
set status = 'approved',
    role = 'beta',
    approved_at = coalesce(approved_at, now()),
    updated_at = now()
where lower(email) = lower('USER_EMAIL_HERE');

-- 6. Make a user an admin in the beta access table
-- This only labels the user as admin for beta management.
-- It does not give service-role access or backend write access to the iOS app.
update public.mobile_user_access
set status = 'approved',
    role = 'admin',
    approved_at = coalesce(approved_at, now()),
    updated_at = now()
where lower(email) = lower('USER_EMAIL_HERE');

-- 7. Check one user
select
    email,
    status,
    role,
    requested_at,
    approved_at,
    updated_at
from public.mobile_user_access
where lower(email) = lower('USER_EMAIL_HERE');
