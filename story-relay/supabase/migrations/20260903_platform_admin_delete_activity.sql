-- Story Relay: platform-admin permanent activity deletion.
-- This is intentionally separate from host stop/close semantics.

begin;

create or replace function public.delete_platform_activity(p_activity_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1
    from public.platform_admins pa
    where pa.user_id = auth.uid()
  ) then
    raise exception 'Platform administrator access required';
  end if;

  if not exists (
    select 1 from public.activities a where a.id = p_activity_id
  ) then
    raise exception 'Activity not found';
  end if;

  -- Delete round-scoped intent first.
  delete from public.nominations n
  where n.round_id in (
    select rr.id
    from public.relay_rounds rr
    join public.stories s on s.id = rr.story_id
    join public.groups g on g.id = s.group_id
    where g.activity_id = p_activity_id
  );

  delete from public.volunteers v
  where v.round_id in (
    select rr.id
    from public.relay_rounds rr
    join public.stories s on s.id = rr.story_id
    join public.groups g on g.id = s.group_id
    where g.activity_id = p_activity_id
  );

  delete from public.relay_rounds rr
  where rr.story_id in (
    select s.id
    from public.stories s
    join public.groups g on g.id = s.group_id
    where g.activity_id = p_activity_id
  );

  delete from public.segments sg
  where sg.story_id in (
    select s.id
    from public.stories s
    join public.groups g on g.id = s.group_id
    where g.activity_id = p_activity_id
  );

  delete from public.writer_states ws
  where ws.group_id in (
    select g.id from public.groups g where g.activity_id = p_activity_id
  );

  delete from public.group_members gm
  where gm.group_id in (
    select g.id from public.groups g where g.activity_id = p_activity_id
  );

  delete from public.stories s
  where s.group_id in (
    select g.id from public.groups g where g.activity_id = p_activity_id
  );

  delete from public.activity_events ae where ae.activity_id = p_activity_id;
  delete from public.activity_name_history anh where anh.activity_id = p_activity_id;
  delete from public.groups g where g.activity_id = p_activity_id;
  delete from public.activities a where a.id = p_activity_id;
end;
$$;

revoke all on function public.delete_platform_activity(uuid) from public;
grant execute on function public.delete_platform_activity(uuid) to authenticated;

commit;
