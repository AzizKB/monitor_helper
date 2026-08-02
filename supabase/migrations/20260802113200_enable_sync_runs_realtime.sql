-- Enable lightweight realtime notifications for collector sync completion.
-- Do not add high-volume metric tables to the realtime publication.

do $$
begin
    if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'sync_runs'
    ) then
        alter publication supabase_realtime add table public.sync_runs;
    end if;
end $$;
