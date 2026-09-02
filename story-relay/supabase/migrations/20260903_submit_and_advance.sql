-- Story Relay: submit the current writer's segment, update weights, and automatically advance.

begin;

create or replace function public.submit_segment(
  p_round_id uuid,
  p_content text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_round public.relay_rounds%rowtype;
  v_story public.stories%rowtype;
  v_activity public.activities%rowtype;
  v_group_id uuid;
  v_segment_id uuid;
  v_sequence_no integer;
  v_length integer;
  v_completed_segments integer;
  v_next_writer_id uuid;
  v_next_round_id uuid;
  v_next_round_no integer;
  v_total_weight numeric;
  v_pick numeric;
  v_running numeric := 0;
  v_candidate record;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if nullif(trim(p_content), '') is null then
    raise exception 'Segment content cannot be blank';
  end if;

  select * into v_round
  from public.relay_rounds
  where id = p_round_id
  for update;

  if v_round.id is null then
    raise exception 'Relay round not found';
  end if;

  if v_round.status not in ('open', 'writing') then
    raise exception 'This relay round is no longer accepting submissions';
  end if;

  if v_round.current_writer_id <> v_user_id then
    raise exception 'Only the current writer can submit this segment';
  end if;

  select * into v_story
  from public.stories
  where id = v_round.story_id;

  if v_story.id is null or v_story.status <> 'active' then
    raise exception 'Story is not active';
  end if;

  v_group_id := v_story.group_id;

  select a.* into v_activity
  from public.groups g
  join public.activities a on a.id = g.activity_id
  where g.id = v_group_id
  limit 1;

  if v_activity.id is null or v_activity.status <> 'active' then
    raise exception 'Activity is not active';
  end if;

  if v_activity.deadline is not null and v_activity.deadline <= now() then
    raise exception 'Activity deadline has passed';
  end if;

  v_length := char_length(trim(p_content));

  if v_activity.min_words is not null and v_length < v_activity.min_words then
    raise exception 'Segment is shorter than the minimum length';
  end if;

  if v_activity.max_words is not null and v_length > v_activity.max_words then
    raise exception 'Segment exceeds the maximum length';
  end if;

  -- Serialize sequence allocation for this story as part of the locked round transaction.
  select coalesce(max(s.sequence_no), -1) + 1
  into v_sequence_no
  from public.segments s
  where s.story_id = v_story.id;

  insert into public.segments (
    story_id,
    sequence_no,
    author_id,
    content,
    word_count
  ) values (
    v_story.id,
    v_sequence_no,
    v_user_id,
    trim(p_content),
    v_length
  )
  returning id into v_segment_id;

  -- The writer who just wrote resets; every other currently active student waits one more round.
  update public.writer_states ws
  set times_written = ws.times_written + 1,
      waiting_rounds = 0,
      selection_weight = 1,
      updated_at = now()
  where ws.group_id = v_group_id
    and ws.user_id = v_user_id;

  update public.writer_states ws
  set waiting_rounds = ws.waiting_rounds + 1,
      selection_weight = ws.selection_weight + 1,
      updated_at = now()
  where ws.group_id = v_group_id
    and ws.user_id <> v_user_id
    and exists (
      select 1
      from public.group_members gm
      where gm.group_id = ws.group_id
        and gm.user_id = ws.user_id
        and gm.left_at is null
        and gm.role = 'student'
    );

  update public.relay_rounds
  set status = 'completed',
      completed_at = now()
  where id = v_round.id;

  insert into public.activity_events (
    activity_id, group_id, type, actor_id, payload
  ) values (
    v_activity.id,
    v_group_id,
    'segment_submitted',
    v_user_id,
    jsonb_build_object(
      'segment_id', v_segment_id,
      'round_id', v_round.id,
      'round_no', v_round.round_no,
      'sequence_no', v_sequence_no
    )
  );

  -- Writer 0 seed text does not count toward the teacher's requested player-segment total.
  select count(*)
  into v_completed_segments
  from public.segments s
  where s.story_id = v_story.id
    and s.author_id is not null;

  if v_story.required_segments is not null
     and v_completed_segments >= v_story.required_segments then
    update public.stories
    set status = 'completed',
        completed_at = now()
    where id = v_story.id;

    insert into public.activity_events (
      activity_id, group_id, type, actor_id, payload
    ) values (
      v_activity.id,
      v_group_id,
      'story_completed',
      v_user_id,
      jsonb_build_object('story_id', v_story.id, 'segments', v_completed_segments)
    );

    return v_segment_id;
  end if;

  -- Select the next writer from active students using the updated weights.
  select coalesce(sum(ws.selection_weight), 0)
  into v_total_weight
  from public.writer_states ws
  join public.group_members gm
    on gm.group_id = ws.group_id
   and gm.user_id = ws.user_id
  where ws.group_id = v_group_id
    and gm.left_at is null
    and gm.role = 'student'
    and ws.selection_weight > 0;

  if v_total_weight <= 0 then
    raise exception 'No eligible student writers are available for the next round';
  end if;

  v_pick := random() * v_total_weight;

  for v_candidate in
    select ws.user_id, ws.selection_weight
    from public.writer_states ws
    join public.group_members gm
      on gm.group_id = ws.group_id
     and gm.user_id = ws.user_id
    where ws.group_id = v_group_id
      and gm.left_at is null
      and gm.role = 'student'
      and ws.selection_weight > 0
    order by ws.user_id
  loop
    v_running := v_running + v_candidate.selection_weight;
    if v_pick < v_running then
      v_next_writer_id := v_candidate.user_id;
      exit;
    end if;
  end loop;

  if v_next_writer_id is null then
    raise exception 'Unable to select the next writer';
  end if;

  v_next_round_no := v_round.round_no + 1;

  insert into public.relay_rounds (
    story_id,
    round_no,
    current_writer_id,
    status
  ) values (
    v_story.id,
    v_next_round_no,
    v_next_writer_id,
    'writing'
  )
  returning id into v_next_round_id;

  insert into public.activity_events (
    activity_id, group_id, type, actor_id, payload
  ) values (
    v_activity.id,
    v_group_id,
    'relay_round_started',
    v_user_id,
    jsonb_build_object(
      'round_id', v_next_round_id,
      'round_no', v_next_round_no,
      'current_writer_id', v_next_writer_id,
      'trigger', 'segment_submitted'
    )
  );

  return v_segment_id;
end;
$$;

revoke all on function public.submit_segment(uuid,text) from public;
grant execute on function public.submit_segment(uuid,text) to authenticated;

commit;
