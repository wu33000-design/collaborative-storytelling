-- CLASSROOM_100 Phase C2 auth-fixture preflight
-- Read-only. Does not create, update, or delete application/auth data.
-- Purpose: inspect the actual auth.users requirements before creating rollback-only
-- synthetic auth users for the 100-participant capacity smoke test.

with auth_columns as (
  select
    a.attnum,
    a.attname as column_name,
    pg_catalog.format_type(a.atttypid, a.atttypmod) as data_type,
    a.attnotnull as not_null,
    pg_get_expr(d.adbin, d.adrelid) as default_expression
  from pg_attribute a
  join pg_class c on c.oid = a.attrelid
  join pg_namespace n on n.oid = c.relnamespace
  left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
  where n.nspname = 'auth'
    and c.relname = 'users'
    and a.attnum > 0
    and not a.attisdropped
  order by a.attnum
),
profile_fk as (
  select jsonb_agg(jsonb_build_object(
    'constraint_name', con.conname,
    'source_schema', src_ns.nspname,
    'source_table', src.relname,
    'source_columns', (
      select jsonb_agg(sa.attname order by ord.ordinality)
      from unnest(con.conkey) with ordinality ord(attnum, ordinality)
      join pg_attribute sa on sa.attrelid = con.conrelid and sa.attnum = ord.attnum
    ),
    'target_schema', tgt_ns.nspname,
    'target_table', tgt.relname,
    'target_columns', (
      select jsonb_agg(ta.attname order by ord.ordinality)
      from unnest(con.confkey) with ordinality ord(attnum, ordinality)
      join pg_attribute ta on ta.attrelid = con.confrelid and ta.attnum = ord.attnum
    )
  ) order by con.conname) as value
  from pg_constraint con
  join pg_class src on src.oid = con.conrelid
  join pg_namespace src_ns on src_ns.oid = src.relnamespace
  join pg_class tgt on tgt.oid = con.confrelid
  join pg_namespace tgt_ns on tgt_ns.oid = tgt.relnamespace
  where con.contype = 'f'
    and src_ns.nspname = 'public'
    and src.relname = 'profiles'
),
trigger_function as (
  select jsonb_agg(jsonb_build_object(
    'trigger_name', t.tgname,
    'function_schema', pn.nspname,
    'function_name', p.proname,
    'function_definition', pg_get_functiondef(p.oid)
  ) order by t.tgname) as value
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_namespace cn on cn.oid = c.relnamespace
  join pg_proc p on p.oid = t.tgfoid
  join pg_namespace pn on pn.oid = p.pronamespace
  where not t.tgisinternal
    and cn.nspname = 'auth'
    and c.relname = 'users'
)
select jsonb_build_object(
  'profiles_foreign_keys', coalesce((select value from profile_fk), '[]'::jsonb),
  'auth_users_columns', coalesce((
    select jsonb_agg(jsonb_build_object(
      'ordinal', attnum,
      'column_name', column_name,
      'data_type', data_type,
      'not_null', not_null,
      'default_expression', default_expression
    ) order by attnum)
    from auth_columns
  ), '[]'::jsonb),
  'auth_users_triggers_and_functions', coalesce((select value from trigger_function), '[]'::jsonb)
) as classroom100_c2_auth_fixture_preflight;
