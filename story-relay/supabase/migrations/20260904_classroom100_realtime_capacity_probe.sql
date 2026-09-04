-- TEMPORARY CLASSROOM_100 C2 Realtime capacity probe helpers.
-- Apply only for the C2 browser smoke test, then remove with the cleanup migration.

begin;

create or replace function public.create_classroom100_realtime_probe()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_activity_id uuid := gen_random_uuid();
  v_group_id uuid := gen_random_uuid();
  v_story_id uuid := gen_random_uuid();
  v_code text := 'RT-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not exists (select 1 from public.platform_admins pa where pa.user_id = v_user_id) then
    raise exception 'Platform administrator access required';
  end if;

  insert into public.activities (id, teacher_id, code, name, status, group_size)
  values (v_activity_id, v_user_id, v_code, 'CLASSROOM_100 C2 Realtime Probe', 'active', null);

  insert into public.groups (id, activity_id, name)
  values (v_group_id, v_activity_id, 'Probe Group');

  insert into public.stories (id, group_id, title, status)
  values (v_story_id, v_group_id, 'CLASSROOM_100 C2 Realtime Probe', 'active');

  insert into public.group_members (group_id, user_id, role)
  values (v_group_id, v_user_id, 'student');

  insert into public.writer_states (group_id, user_id, times_written, waiting_rounds, selection_weight)
  values (v_group_id, v_user_id, 0, 0, 1);

  return jsonb_build_object(
    'activity_id', v_activity_id,
    'group_id', v_group_id,
    'story_id', v_story_id,
    'code', v_code
  );
end;
$$;

revoke all on function public.create_classroom100_realtime_probe() from public;
grant execute on function public.create_classroom100_realtime_probe() to authenticated;

create or replace function public.run_classroom100_realtime_probe_burst(p_story_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_group_id uuid;
  v_activity_id uuid;
  v_i integer;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not exists (select 1 from public.platform_admins pa where pa.user_id = v_user_id) then
    raise exception 'Platform administrator access required';
  end if;

  select s.group_id, g.activity_id
  into v_group_id, v_activity_id
  from public.stories s
  join public.groups g on g.id = s.group_id
  where s.id = p_story_id
    and exists (
      select 1 from public.activities a
      where a.id = g.activity_id
        and a.teacher_id = v_user_id
        and a.name = 'CLASSROOM_100 C2 Realtime Probe'
    );

  if v_group_id is null then
    raise exception 'Probe story not found or not owned by caller';
  end if;

  -- 100 segment INSERT events.
  for v_i in 1..100 loop
    insert into public.segments (story_id, sequence_no, author_id, content, word_count)
    values (p_story_id, v_i, v_user_id, 'C2 realtime probe segment ' || v_i, 28);
  end loop;

  -- 100 relay_round INSERT events. Completed status avoids creating an active round.
  for v_i in 1..100 loop
    insert into public.relay_rounds (story_id, round_no, current_writer_id, status, completed_at)
    values (p_story_id, v_i, v_user_id, 'completed', now());
  end loop;

  return jsonb_build_object('segments_inserted', 100, 'rounds_inserted', 100, 'events_expected', 200);
end;
$$;

revoke all on function public.run_classroom100_realtime_probe_burst(uuid) from public;
grant execute on function public.run_classroom100_realtime_probe_burst(uuid) to authenticated;

create or replace function public.cleanup_classroom100_realtime_probe(p_activity_id uuid)
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
  if not exists (select 1 from public.platform_admins pa where pa.user_id = v_user_id) then
    raise exception 'Platform administrator access required';
  end if;
  if not exists (
    select 1 from public.activities a
    where a.id = p_activity_id
      and a.teacher_id = v_user_id
      and a.name = 'CLASSROOM_100 C2 Realtime Probe'
  ) then
    raise exception 'Probe activity not found or not owned by caller';
  end if;

  delete from public.nominations n
  using public.relay_rounds rr, public.stories s, public.groups g
  where n.round_id = rr.id and rr.story_id = s.id and s.group_id = g.id and g.activity_id = p_activity_id;

  delete from public.volunteers v
  using public.relay_rounds rr, public.stories s, public.groups g
  where v.round_id = rr.id and rr.story_id = s.id and s.group_id = g.id and g.activity_id = p_activity_id;

  delete from public.relay_rounds rr
  using public.stories s, public.groups g
  where rr.story_id = s.id and s.group_id = g.id and g.activity_id = p_activity_id;

  delete from public.segments seg
  using public.stories s, public.groups g
  where seg.story_id = s.id and s.group_id = g.id and g.activity_id = p_activity_id;

  delete from public.writer_states ws
  using public.groups g
  where ws.group_id = g.id and g.activity_id = p_activity_id;

  delete from public.group_members gm
  using public.groups g
  where gm.group_id = g.id and g.activity_id = p_activity_id;

  delete from public.activity_events ae where ae.activity_id = p_activity_id;
  delete from public.activity_name_history anh where anh.activity_id = p_activity_id;

  delete from public.stories s
  using public.groups g
  where s.group_id = g.id and g.activity_id = p_activity_id;

  delete from public.groups g where g.activity_id = p_activity_id;
  delete from public.activities a where a.id = p_activity_id;
end;
$$;

revoke all on function public.cleanup_classroom100_realtime_probe(uuid) from public;
grant execute on function public.cleanup_classroom100_realtime_probe(uuid) to authenticated;

commit;
