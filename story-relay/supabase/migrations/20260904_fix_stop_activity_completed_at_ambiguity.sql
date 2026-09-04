-- Story Relay: fix stop_activity completed_at ambiguity.
--
-- The previous function body used unqualified completed_at references inside
-- UPDATE ... FROM statements. In the relay_rounds update both relay_rounds and
-- stories expose completed_at, so PostgreSQL raises SQLSTATE 42702.
--
-- Keep the Classroom 100 hardening posture: SECURITY DEFINER with empty
-- search_path and fully-qualified object references.

begin;

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
  set status = 'closed'
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
  values (p_activity_id, 'activity_stopped', v_user_id, '{}'::jsonb);
end;
$$;

revoke all on function public.stop_activity(uuid) from public, anon;
grant execute on function public.stop_activity(uuid) to authenticated;

commit;
