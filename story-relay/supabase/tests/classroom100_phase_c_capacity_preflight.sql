-- CLASSROOM_100 Phase C2 capacity preflight
-- Read-only. Does not create, update, or delete application/auth data.
-- Purpose: determine the safest rollback-only way to simulate 100 distinct joins.

with fk_rows as (
  select
    con.conname as constraint_name,
    src_ns.nspname as source_schema,
    src.relname as source_table,
    tgt_ns.nspname as target_schema,
    tgt.relname as target_table,
    src_att.attname as source_column,
    tgt_att.attname as target_column
  from pg_constraint con
  join pg_class src on src.oid = con.conrelid
  join pg_namespace src_ns on src_ns.oid = src.relnamespace
  join pg_class tgt on tgt.oid = con.confrelid
  join pg_namespace tgt_ns on tgt_ns.oid = tgt.relnamespace
  join lateral unnest(con.conkey, con.confkey) with ordinality as keys(src_attnum, tgt_attnum, ord) on true
  join pg_attribute src_att on src_att.attrelid = src.oid and src_att.attnum = keys.src_attnum
  join pg_attribute tgt_att on tgt_att.attrelid = tgt.oid and tgt_att.attnum = keys.tgt_attnum
  where con.contype = 'f'
)
select jsonb_build_object(
  'profile_count', (select count(*) from public.profiles),
  'platform_admin_count', (select count(*) from public.platform_admins),
  'auth_user_count', (select count(*) from auth.users),
  'profiles_id_foreign_keys', coalesce((
    select jsonb_agg(jsonb_build_object(
      'constraint_name', constraint_name,
      'foreign_table_schema', target_schema,
      'foreign_table_name', target_table,
      'foreign_column_name', target_column
    ) order by constraint_name)
    from fk_rows
    where source_schema = 'public'
      and source_table = 'profiles'
      and source_column = 'id'
  ), '[]'::jsonb),
  'group_members_user_foreign_keys', coalesce((
    select jsonb_agg(jsonb_build_object(
      'constraint_name', constraint_name,
      'foreign_table_schema', target_schema,
      'foreign_table_name', target_table,
      'foreign_column_name', target_column
    ) order by constraint_name)
    from fk_rows
    where source_schema = 'public'
      and source_table = 'group_members'
      and source_column = 'user_id'
  ), '[]'::jsonb),
  'writer_states_user_foreign_keys', coalesce((
    select jsonb_agg(jsonb_build_object(
      'constraint_name', constraint_name,
      'foreign_table_schema', target_schema,
      'foreign_table_name', target_table,
      'foreign_column_name', target_column
    ) order by constraint_name)
    from fk_rows
    where source_schema = 'public'
      and source_table = 'writer_states'
      and source_column = 'user_id'
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
