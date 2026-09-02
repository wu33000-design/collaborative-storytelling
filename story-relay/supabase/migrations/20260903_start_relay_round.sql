-- Story Relay: atomically start the first/next relay round with weighted selection.

begin;

create or replace function public.start_relay_round(p_group_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_activity_id uuid;
  v_story_id uuid;
  v_round_id uuid;
  v_round_no integer;
  v_writer_id uuid;
  v_total_weight numeric;
  v_pick numeric;
  v_running numeric := 0;
  v_candidate record;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1
    from public.group_members gm
    where gm.group_id = p_group_id
      and gm.user_id = v_user_id
      and gm.left_at is null
  ) then
    raise exception 'Only active group members can start a relay round';
  end if;

  select g.activity_id, s.id
  into v_activity_id, v_story_id
  from public.groups g
  join public.stories s on s.group_id = g.id
  join public.activities a on a.id = g.activity_id
  where g.id = p_group_id
    and a.status = 'active'
    and s.status = 'active'
    and (a.deadline is null or a.deadline > now())
  limit 1;

  if v_story_id is null then
    raise exception 'Active story not found';
  end if;

  -- Serialize starts for the same story so concurrent clicks cannot create two rounds.
  perform pg_advisory_xact_lock(hashtextextended(v_story_id::text, 0));

  -- Idempotent: return the currently active round if one already exists.
  select rr.id, rr.round_no, rr.current_writer_id
  into v_round_id, v_round_no, v_writer_id
  from public.relay_rounds rr
  where rr.story_id = v_story_id
    and rr.status in ('open', 'writing')
  order by rr.round_no desc
  limit 1;

  if v_round_id is not null then
    return jsonb_build_object(
      'round_id', v_round_id,
      'round_no', v_round_no,
      'current_writer_id', v_writer_id,
      'created', false
    );
  end if;

  select coalesce(sum(ws.selection_weight), 0)
  into v_total_weight
  from public.writer_states ws
  join public.group_members gm
    on gm.group_id = ws.group_id
   and gm.user_id = ws.user_id
  where ws.group_id = p_group_id
    and gm.left_at is null
    and gm.role = 'student'
    and ws.selection_weight > 0;

  if v_total_weight <= 0 then
    raise exception 'No eligible student writers are available';
  end if;

  v_pick := random() * v_total_weight;

  for v_candidate in
    select ws.user_id, ws.selection_weight
    from public.writer_states ws
    join public.group_members gm
      on gm.group_id = ws.group_id
     and gm.user_id = ws.user_id
    where ws.group_id = p_group_id
      and gm.left_at is null
      and gm.role = 'student'
      and ws.selection_weight > 0
    order by ws.user_id
  loop
    v_running := v_running + v_candidate.selection_weight;
    if v_pick < v_running then
      v_writer_id := v_candidate.user_id;
      exit;
    end if;
  end loop;

  if v_writer_id is null then
    raise exception 'Unable to select a writer';
  end if;

  select coalesce(max(rr.round_no), 0) + 1
  into v_round_no
  from public.relay_rounds rr
  where rr.story_id = v_story_id;

  insert into public.relay_rounds (
    story_id, round_no, current_writer_id, status
  ) values (
    v_story_id, v_round_no, v_writer_id, 'writing'
  )
  returning id into v_round_id;

  insert into public.activity_events (
    activity_id, group_id, type, actor_id, payload
  ) values (
    v_activity_id,
    p_group_id,
    'relay_round_started',
    v_user_id,
    jsonb_build_object(
      'round_id', v_round_id,
      'round_no', v_round_no,
      'current_writer_id', v_writer_id
    )
  );

  return jsonb_build_object(
    'round_id', v_round_id,
    'round_no', v_round_no,
    'current_writer_id', v_writer_id,
    'created', true
  );
end;
$$;

revoke all on function public.start_relay_round(uuid) from public;
grant execute on function public.start_relay_round(uuid) to authenticated;

commit;
