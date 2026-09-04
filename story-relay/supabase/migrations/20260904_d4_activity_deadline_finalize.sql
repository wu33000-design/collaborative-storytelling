-- Story Relay Phase D4: converge expired activities to an explicit closed state.
-- Join and submit already reject deadline-past activities; this migration adds
-- durable close reason plus an idempotent finalizer for UI/read-time convergence.

begin;

alter table public.activities
  add column if not exists closed_reason text;

alter table public.activities
  drop constraint if exists activities_closed_reason_check;

alter table public.activities
  add constraint activities_closed_reason_check
  check (closed_reason is null or closed_reason in ('deadline', 'host_stopped'));

create or replace function public.finalize_activity_deadline(p_activity_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_activity public.activities%rowtype;
  v_row_count integer := 0;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if not (
    exists (
      select 1
      from public.activities a
      where a.id = p_activity_id
        and a.deleted_at is null
        and a.teacher_id = v_user_id
    )
    or exists (
      select 1
      from public.groups g
      join public.group_members gm on gm.group_id = g.id
      where g.activity_id = p_activity_id
        and gm.user_id = v_user_id
        and gm.left_at is null
    )
    or exists (
      select 1
      from public.platform_admins pa
      where pa.user_id = v_user_id
    )
  ) then
    raise exception 'Activity access required';
  end if;

  select a.*
  into v_activity
  from public.activities a
  where a.id = p_activity_id
    and a.deleted_at is null
  for update;

  if not found then
    raise exception 'Activity not found';
  end if;

  if v_activity.status <> 'active'
     or v_activity.deadline is null
     or v_activity.deadline > now() then
    return false;
  end if;

  update public.activities a
  set status = 'closed',
      closed_reason = 'deadline'
  where a.id = p_activity_id
    and a.status = 'active';

  get diagnostics v_row_count = row_count;

  if v_row_count = 0 then
    return false;
  end if;

  update public.stories s
  set status = 'closed',
      completed_at = coalesce(s.completed_at, now())
  from public.groups g
  where s.group_id = g.id
    and g.activity_id = p_activity_id
    and s.status = 'active';

  update public.relay_rounds rr
  set status = 'expired',
      completed_at = coalesce(rr.completed_at, now())
  from public.stories s
  join public.groups g on g.id = s.group_id
  where rr.story_id = s.id
    and g.activity_id = p_activity_id
    and rr.status in ('open', 'writing');

  insert into public.activity_events(activity_id, type, actor_id, payload)
  values (
    p_activity_id,
    'activity_deadline_reached',
    v_user_id,
    jsonb_build_object('deadline', v_activity.deadline, 'reason', 'deadline')
  );

  return true;
end;
$$;

revoke all on function public.finalize_activity_deadline(uuid) from public, anon;
grant execute on function public.finalize_activity_deadline(uuid) to authenticated;

-- Preserve the fixed, fully-qualified stop_activity implementation and record
-- an explicit manual-stop reason without overwriting a prior deadline reason.
create or replace function public.stop_activity(p_activity_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1
    from public.activities a
    where a.id = p_activity_id
      and a.teacher_id = v_user_id
      and a.deleted_at is null
  ) then
    raise exception 'Only the activity host can stop this non-deleted activity';
  end if;

  update public.activities a
  set status = 'closed',
      closed_reason = coalesce(a.closed_reason, 'host_stopped')
  where a.id = p_activity_id
    and a.deleted_at is null
    and a.status <> 'closed';

  update public.stories s
  set status = 'closed',
      completed_at = coalesce(s.completed_at, now())
  from public.groups g
  where s.group_id = g.id
    and g.activity_id = p_activity_id
    and s.status = 'active';

  update public.relay_rounds rr
  set status = 'expired',
      completed_at = coalesce(rr.completed_at, now())
  from public.stories s
  join public.groups g on g.id = s.group_id
  where rr.story_id = s.id
    and g.activity_id = p_activity_id
    and rr.status in ('open', 'writing');

  insert into public.activity_events(activity_id, type, actor_id, payload)
  values (p_activity_id, 'activity_stopped', v_user_id, jsonb_build_object('reason', 'host_stopped'));
end;
$$;

revoke all on function public.stop_activity(uuid) from public, anon;
grant execute on function public.stop_activity(uuid) to authenticated;

commit;
