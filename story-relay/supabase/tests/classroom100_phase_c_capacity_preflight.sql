-- CLASSROOM_100 Phase C2 capacity preflight
-- Read-only. Does not create, update, or delete application/auth data.
-- Purpose: determine the safest rollback-only way to simulate 100 distinct joins.

select jsonb_build_object(
  'profile_count', (select count(*) from public.profiles),
  'platform_admin_count', (select count(*) from public.platform_admins),
  'auth_user_count', (select count(*) from auth.users),
  'profiles_id_foreign_keys', coalesce((
    select jsonb_agg(jsonb_build_object(
      'constraint_name', tc.constraint_name,
      'foreign_table_schema', ccu.table_schema,
      'foreign_table_name', ccu.table_name,
      'foreign_column_name', ccu.column_name
    ) order by tc.constraint_name)
    from information_schema.table_constraints tc
    join information_schema.key_column_usage kcu
      on tc.constraint_name = kcu.constraint_name
     and tc.constraint_schema = kcu.constraint_schema
    join information_schema.constraint_column_usage ccu
      on ccu.constraint_name = tc.constraint_name
     and ccu.constraint_schema = tc.constraint_schema
    where tc.constraint_type = 'FOREIGN KEY'
      and tc.table_schema = 'public'
      and tc.table_name = 'profiles'
      and kcu.column_name = 'id'
  ), '[]'::jsonb),
  'group_members_user_foreign_keys', coalesce((
    select jsonb_agg(jsonb_build_object(
      'constraint_name', tc.constraint_name,
      'foreign_table_schema', ccu.table_schema,
      'foreign_table_name', ccu.table_name,
      'foreign_column_name', ccu.column_name
    ) order by tc.constraint_name)
    from information_schema.table_constraints tc
    join information_schema.key_column_usage kcu
      on tc.constraint_name = kcu.constraint_name
     and tc.constraint_schema = kcu.constraint_schema
    join information_schema.constraint_column_usage ccu
      on ccu.constraint_name = tc.constraint_name
     and ccu.constraint_schema = tc.constraint_schema
    where tc.constraint_type = 'FOREIGN KEY'
      and tc.table_schema = 'public'
      and tc.table_name = 'group_members'
      and kcu.column_name = 'user_id'
  ), '[]'::jsonb),
  'writer_states_user_foreign_keys', coalesce((
    select jsonb_agg(jsonb_build_object(
      'constraint_name', tc.constraint_name,
      'foreign_table_schema', ccu.table_schema,
      'foreign_table_name', ccu.table_name,
      'foreign_column_name', ccu.column_name
    ) order by tc.constraint_name)
    from information_schema.table_constraints tc
    join information_schema.key_column_usage kcu
      on tc.constraint_name = kcu.constraint_name
     and tc.constraint_schema = kcu.constraint_schema
    join information_schema.constraint_column_usage ccu
      on ccu.constraint_name = tc.constraint_name
     and ccu.constraint_schema = tc.constraint_schema
    where tc.constraint_type = 'FOREIGN KEY'
      and tc.table_schema = 'public'
      and tc.table_name = 'writer_states'
      and kcu.column_name = 'user_id'
  ), '[]'::jsonb),
  'auth_users_triggers', coalesce((
    select jsonb_agg(jsonb_build_object(
      'trigger_name', t.tgname,
      'enabled', t.tgenabled,
      'function', p.proname,
      'function_schema', n.nspname
    ) order by t.tgname)
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace cn on cn.oid = c.relnamespace
    join pg_proc p on p.oid = t.tgfoid
    join pg_namespace n on n.oid = p.pronamespace
    where not t.tgisinternal
      and cn.nspname = 'auth'
      and c.relname = 'users'
  ), '[]'::jsonb),
  'join_rpc_exists', to_regprocedure('public.join_activity_by_code(text)') is not null,
  'create_rpc_exists', to_regprocedure('public.create_activity(text,text,text,integer,integer,integer,integer,integer,timestamptz)') is not null,
  'advanced_grouping_guard_exists', to_regprocedure('public.enforce_platform_admin_advanced_grouping()') is not null
) as classroom100_c2_preflight;
