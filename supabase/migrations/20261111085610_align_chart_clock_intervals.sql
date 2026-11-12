-- Align long-range charts to completed clock ten-minute boundaries.
-- Ten-minute points are labeled by interval end; one-minute points retain source minute labels.
-- The shipped beta API and collector remain unchanged.
create or replace function public.get_application_metric_chart_series(
    p_application_id uuid,
    p_metric_key text,
    p_window_minutes integer default 60,
    p_end_at timestamptz default now()
)
returns table (
    observed_at timestamptz,
    value double precision,
    current_value double precision,
    min_value double precision,
    max_value double precision,
    count_value bigint,
    sum_value double precision,
    sample_count bigint,
    peak_value double precision,
    peak_observed_at timestamptz,
    window_start timestamptz,
    window_end timestamptz,
    bucket_minutes integer
)
language plpgsql
stable
security invoker
set search_path to 'public', 'pg_temp'
as $function$
declare
    v_interval integer;
    v_end timestamptz;
    v_start timestamptz;
begin
    if p_metric_key is null or p_metric_key not in ('response_time', 'calls_per_minute', 'errors_per_minute') then
        raise exception 'Unsupported application metric key' using errcode = '22023';
    end if;
    if p_window_minutes is null or p_window_minutes not in (15, 30, 60, 180, 360, 720, 1440) then
        raise exception 'Unsupported chart window' using errcode = '22023';
    end if;

    v_interval := case when p_window_minutes <= 180 then 1 else 10 end;
    -- A request at 11:32 ends at 11:30 until the clock reaches 11:40.
    v_end := date_bin(
        make_interval(mins => v_interval),
        least(coalesce(p_end_at, now()), now()),
        timestamptz '2000-01-01 00:00:00+00'
    );
    v_start := v_end - make_interval(mins => p_window_minutes);

    return query
    with source_points as (
        select m.observed_at, coalesce(m.value, m.current_value) as observed_value,
               m.current_value, m.min_value, m.max_value, m.count_value, m.sum_value,
               date_bin(make_interval(mins => v_interval), m.observed_at, v_start) as bucket_start
        from public.application_metrics m
        where m.application_id = p_application_id
          and m.metric_key = p_metric_key
          and m.observed_at >= v_start
          and m.observed_at < v_end
          and coalesce(m.value, m.current_value) is not null
    )
    select case when v_interval > 1
                then s.bucket_start + make_interval(mins => v_interval)
                else s.bucket_start end,
           case
               -- Keep the original observed value at one-minute resolution.
               when v_interval > 1 and p_metric_key = 'response_time'
                    and bool_and(s.sum_value is not null and s.count_value is not null)
               then coalesce(sum(s.sum_value) / nullif(sum(s.count_value), 0), avg(s.observed_value))
               -- Calls/errors remain rates, rather than a sum of rates.
               else avg(s.observed_value)
           end::double precision,
           (array_agg(s.current_value order by s.observed_at desc))[1],
           min(s.min_value), max(s.max_value),
           case when bool_and(s.count_value is not null) then sum(s.count_value)::bigint end,
           case when bool_and(s.sum_value is not null) then sum(s.sum_value) end,
           count(*)::bigint,
           max(s.observed_value),
           (array_agg(s.observed_at order by s.observed_value desc, s.observed_at))[1],
           v_start, v_end, v_interval
    from source_points s
    group by s.bucket_start
    order by s.bucket_start;
end;
$function$;

revoke all on function public.get_application_metric_chart_series(uuid, text, integer, timestamptz)
    from public, anon, authenticated, service_role;
grant execute on function public.get_application_metric_chart_series(uuid, text, integer, timestamptz)
    to authenticated, service_role;

comment on function public.get_application_metric_chart_series(uuid, text, integer, timestamptz)
    is 'Full-window application charts: 1-minute intervals through 3H, completed clock-aligned 10-minute intervals labeled by end from 6H. SECURITY INVOKER preserves the existing approved-user RLS.';
