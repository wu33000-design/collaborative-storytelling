-- Story Relay: Classroom 100 security hardening.
-- Scope: high-impact platform/admin operations only; preserve existing public API signatures.
-- Apply in staging first. This migration does not bootstrap the first platform admin.

begin;

create table if not exists public.admin_audit_log (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references auth.users(id) on delete set null,
  action text not null check (action in (
    'admin_added',
    'admin_removed',
    'activity_deleted',
    'activity_restored',
    'expired_activity_purged'
  )),
  target_type text not null check (target_type in ('user', 'activity')),
  target_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists admin_audit_log_created_at_idx
  on public.admin_audit_log (created_at desc);
create index if not exists admin_audit_log_target_idx
  on public.admin_audit_log (target_type, target_id, created_at desc);

alter table public.admin_audit_log enable row level security;
revoke all on table public.admin_audit_log from public, anon, authenticated;

-- Audit writes are trigger-only. The trigger is SECURITY DEFINER because normal
-- client roles must not receive direct INSERT permission on the audit table.
create or replace function public.write_classroom100_admin_audit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_action text;
  v_target_id uuid;
  v_metadata jsonb := '{}'::jsonb;
begin
  if tg_table_name = 'platform_admins' then
    if tg_op = 'INSERT' then
      v_action := 'admin_added';
      v_target_id := new.user_id;
    elsif tg_op = 'DELETE' then
      v_action := 'admin_removed';
      v_target_id := old.user_id;
    else
      return coalesce(new, old);
    end if;
    v_metadata := jsonb_build_object('source_table', tg_table_name, 'operation', tg_op);
  elsif tg_table_name = 'activities' then
    if tg_op = 'UPDATE' and old.deleted_at is null and new.deleted_at is not null then
      v_action := 'activity_deleted';
      v_target_id := new.id;
      v_metadata := jsonb_build_object('source_table', tg_table_name, 'operation', tg_op, 'mode', 'soft_delete');
    elsif tg_op = 'UPDATE' and old.deleted_at is not null and new.deleted_at is null then
      v_action := 'activity_restored';
      v_target_id := new.id;
      v_metadata := jsonb_build_object('source_table', tg_table_name, 'operation', tg_op, 'mode', 'restore');
    elsif tg_op = 'DELETE' then
      v_action := case when old.deleted_at is not null then 'expired_activity_purged' else 'activity_deleted' end;
      v_target_id := old.id;
      v_metadata := jsonb_build_object('source_table', tg_table_name, 'operation', tg_op, 'mode', 'hard_delete');
    else
      return coalesce(new, old);
    end if;
  else
    return coalesce(new, old);
  end if;

  insert into public.admin_audit_log(actor_id, action, target_type, target_id, metadata)
  values (
    v_actor_id,
    v_action,
    case when v_target_id is not null and tg_table_name = 'platform_admins' then 'user' else 'activity' end,
    v_target_id,
    v_metadata
  );

  return coalesce(new, old);
end;
$$;

revoke all on function public.write_classroom100_admin_audit() from public, anon, authenticated;

-- Recreate only these triggers; no application table data is changed.
drop trigger if exists classroom100_audit_platform_admins on public.platform_admins;
create trigger classroom100_audit_platform_admins
after insert or delete on public.platform_admins
for each row execute function public.write_classroom100_admin_audit();

drop trigger if exists classroom100_audit_activities on public.activities;
create trigger classroom100_audit_activities
after update of deleted_at or delete on public.activities
for each row execute function public.write_classroom100_admin_audit();

-- Platform admins can read the minimum audit fields through a controlled RPC;
-- ordinary clients cannot SELECT the underlying table.
create or replace function public.get_classroom100_admin_audit(p_limit integer default 100)
returns table (
  id uuid,
  actor_id uuid,
  action text,
  target_type text,
  target_id uuid,
  metadata jsonb,
  created_at timestamptz
)
language sql
security definer
set search_path = ''
as $$
  select l.id, l.actor_id, l.action, l.target_type, l.target_id, l.metadata, l.created_at
  from public.admin_audit_log l
  where public.is_platform_admin()
  order by l.created_at desc
  limit least(greatest(coalesce(p_limit, 100), 1), 500);
$$;

revoke all on function public.get_classroom100_admin_audit(integer) from public, anon;
grant execute on function public.get_classroom100_admin_audit(integer) to authenticated;

-- Tighten search_path only for existing SECURITY DEFINER functions in the
-- high-impact surface. Dynamic lookup keeps this migration tolerant of minor
-- signature changes while avoiding a repository-wide text replacement.
do $$
declare
  r record;
  v_names text[] := array[
    'is_platform_admin',
    'add_platform_admin_by_email',
    'remove_platform_admin',
    'get_platform_activity_content',
    'get_platform_deleted_activities',
    'delete_platform_activity',
    'restore_platform_activity',
    'purge_expired_platform_activities',
    'stop_activity',
    'rename_activity',
    'join_activity_by_code',
    'submit_segment',
    'start_relay_round',
    'volunteer_for_round',
    'nominate_candidate'
  ];
begin
  for r in
    select n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) as identity_args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
      and p.proname = any(v_names)
  loop
    execute format(
      'alter function %I.%I(%s) set search_path = %L',
      r.nspname,
      r.proname,
      r.identity_args,
      ''
    );
  end loop;
end;
$$;

commit;
