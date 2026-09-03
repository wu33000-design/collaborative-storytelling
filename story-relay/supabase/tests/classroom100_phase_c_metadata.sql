-- CLASSROOM_100 Phase C metadata smoke test
-- Read-only assertions. Run in a staging Supabase project after all migrations.
-- This script does not insert, update, delete, or request any secret.

-- 1) Every business table used by Story Relay must have RLS enabled.
do $$
declare
  v_table text;
  v_missing text[] := array[]::text[];
  v_tables text[] := array[
    'activities', 'groups', 'group_members', 'stories', 'segments',
    'writer_states', 'relay_rounds', 'nominations', 'volunteers',
    'activity_events', 'activity_name_history', 'platform_admins',
    'platform_member_identities', 'admin_audit_log'
  ];
begin
  foreach v_table in array v_tables loop
    if to_regclass('public.' || v_table) is not null
       and not exists (
         select 1 from pg_class c
         join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public'
           and c.relname = v_table
           and c.relrowsecurity
       ) then
      v_missing := array_append(v_missing, v_table);
    end if;
  end loop;
  if cardinality(v_missing) > 0 then
    raise exception 'RLS disabled on tables: %', array_to_string(v_missing, ', ');
  end if;
end;
$$;

-- 2) Sensitive tables must not be directly writable by anon/authenticated.
do $$
begin
  if has_table_privilege('anon', 'public.platform_admins', 'INSERT')
     or has_table_privilege('anon', 'public.platform_admins', 'UPDATE')
     or has_table_privilege('anon', 'public.platform_admins', 'DELETE')
     or has_table_privilege('authenticated', 'public.platform_admins', 'INSERT')
     or has_table_privilege('authenticated', 'public.platform_admins', 'UPDATE')
     or has_table_privilege('authenticated', 'public.platform_admins', 'DELETE') then
    raise exception 'platform_admins has direct client write privilege';
  end if;

  if has_table_privilege('anon', 'public.admin_audit_log', 'INSERT')
     or has_table_privilege('anon', 'public.admin_audit_log', 'UPDATE')
     or has_table_privilege('anon', 'public.admin_audit_log', 'DELETE')
     or has_table_privilege('authenticated', 'public.admin_audit_log', 'INSERT')
     or has_table_privilege('authenticated', 'public.admin_audit_log', 'UPDATE')
     or has_table_privilege('authenticated', 'public.admin_audit_log', 'DELETE') then
    raise exception 'admin_audit_log has direct client write privilege';
  end if;
end;
$$;

-- 3) Realtime publication must contain only the tables intentionally used by
-- StoryRoom and host monitoring. Frontend filters are not authorization; these
-- tables still rely on RLS for row-level isolation.
do $$
declare
  v_unexpected text;
begin
  select string_agg(tablename, ', ' order by tablename)
  into v_unexpected
  from pg_publication_tables
  where pubname = 'supabase_realtime'
    and schemaname = 'public'
    and tablename not in (
      'activities', 'stories', 'group_members', 'segments',
      'relay_rounds', 'activity_name_history',
      'nominations', 'volunteers', 'activity_events'
    );

  if v_unexpected is not null then
    raise exception 'Unexpected public Realtime tables: %', v_unexpected;
  end if;
end;
$$;

-- 4) High-impact SECURITY DEFINER functions must have an explicit empty
-- search_path. PostgreSQL may expose the empty string in pg_proc.proconfig as
-- either search_path= or search_path="" depending on representation/version.
do $$
declare
  r record;
  v_missing text[] := array[]::text[];
  v_names text[] := array[
    'is_platform_admin', 'add_platform_admin_by_email', 'remove_platform_admin',
    'get_platform_activity_content', 'get_platform_deleted_activities',
    'delete_platform_activity', 'restore_platform_activity',
    'purge_expired_platform_activities', 'stop_activity', 'rename_activity',
    'join_activity_by_code', 'submit_segment', 'start_relay_round',
    'volunteer_for_round', 'nominate_candidate'
  ];
begin
  for r in
    select p.oid, p.proname, pg_get_function_identity_arguments(p.oid) as args,
           p.proconfig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
      and p.proname = any(v_names)
  loop
    if r.proconfig is null
       or not exists (
         select 1
         from unnest(r.proconfig) x
         where x in ('search_path=', 'search_path=""')
       ) then
      v_missing := array_append(v_missing, format('%s(%s)', r.proname, r.args));
    end if;
  end loop;

  if cardinality(v_missing) > 0 then
    raise exception 'SECURITY DEFINER functions missing SET search_path = empty: %',
      array_to_string(v_missing, ', ');
  end if;
end;
$$;

select
  'CLASSROOM_100 metadata smoke test passed' as result,
  now() as checked_at;
