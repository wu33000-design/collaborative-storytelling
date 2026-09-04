-- D1: allow an activity host to expire a stuck relay round and choose the next writer.

begin;

create or replace function public.skip_relay_round(p_round_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_round public.relay_rounds%rowtype;
  v_story public.stories%rowtype;
  v_activity public.activities%rowtype;
  v_group_id uuid;
  v_next_writer_id uuid;
  v_next_round_id uuid;
  v_next_round_no integer;
  v_other_eligible_count integer := 0;
  v_has_valid_nominations boolean := false;
  v_total_weight numeric := 0;
  v_pick numeric;
  v_running numeric := 0;
  v_candidate record;
  v_candidate_pool text;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select * into v_round
  from public.relay_rounds rr
  where rr.id = p_round_id
  for update;

  if v_round.id is null then
    raise exception 'Relay round not found';
  end if;
  if v_round.status not in ('open', 'writing') then
    raise exception 'Only an active relay round can be skipped';
  end if;

  select * into v_story
  from public.stories s
  where s.id = v_round.story_id;

  if v_story.id is null or v_story.status <> 'active' then
    raise exception 'Story is not active';
  end if;

  v_group_id := v_story.group_id;

  select a.* into v_activity
  from public.groups g
  join public.activities a on a.id = g.activity_id
  where g.id = v_group_id
  limit 1;

  if v_activity.id is null
     or v_activity.teacher_id <> v_user_id
     or v_activity.status <> 'active'
     or v_activity.deleted_at is not null then
    raise exception 'Only the active activity host can skip this relay round';
  end if;
  if v_activity.deadline is not null and v_activity.deadline <= now() then
    raise exception 'Activity deadline has passed';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_story.id::text, 0));

  -- Reject a stale round id if another open/writing round already superseded it.
  if exists (
    select 1
    from public.relay_rounds rr
    where rr.story_id = v_story.id
      and rr.status in ('open', 'writing')
      and rr.id <> v_round.id
  ) then
    raise exception 'A newer active relay round already exists';
  end if;

  select count(*) into v_other_eligible_count
  from public.writer_states ws
  join public.group_members gm
    on gm.group_id = ws.group_id
   and gm.user_id = ws.user_id
  where ws.group_id = v_group_id
    and ws.user_id <> v_round.current_writer_id
    and gm.left_at is null
    and gm.role = 'student'
    and ws.selection_weight > 0;

  if v_other_eligible_count = 0 then
    if not exists (
      select 1
      from public.writer_states ws
      join public.group_members gm
        on gm.group_id = ws.group_id
       and gm.user_id = ws.user_id
      where ws.group_id = v_group_id
        and ws.user_id = v_round.current_writer_id
        and gm.left_at is null
        and gm.role = 'student'
        and ws.selection_weight > 0
    ) then
      raise exception 'No eligible writers are available for the next round';
    end if;

    v_next_writer_id := v_round.current_writer_id;
    v_candidate_pool := 'single_writer_fallback';
  else
    select exists (
      select 1
      from public.nominations n
      join public.group_members gm
        on gm.group_id = v_group_id
       and gm.user_id = n.candidate_id
      join public.writer_states ws
        on ws.group_id = gm.group_id
       and ws.user_id = gm.user_id
      where n.round_id = v_round.id
        and n.candidate_id <> v_round.current_writer_id
        and gm.left_at is null
        and gm.role = 'student'
        and ws.selection_weight > 0
    ) into v_has_valid_nominations;

    select coalesce(sum(ws.selection_weight), 0)
    into v_total_weight
    from public.writer_states ws
    join public.group_members gm
      on gm.group_id = ws.group_id
     and gm.user_id = ws.user_id
    where ws.group_id = v_group_id
      and ws.user_id <> v_round.current_writer_id
      and gm.left_at is null
      and gm.role = 'student'
      and ws.selection_weight > 0
      and (
        not v_has_valid_nominations
        or exists (
          select 1 from public.nominations n
          where n.round_id = v_round.id
            and n.candidate_id = ws.user_id
        )
      );

    if v_total_weight <= 0 then
      raise exception 'No eligible writers are available for the next round';
    end if;

    v_pick := random() * v_total_weight;

    for v_candidate in
      select ws.user_id, ws.selection_weight
      from public.writer_states ws
      join public.group_members gm
        on gm.group_id = ws.group_id
       and gm.user_id = ws.user_id
      where ws.group_id = v_group_id
        and ws.user_id <> v_round.current_writer_id
        and gm.left_at is null
        and gm.role = 'student'
        and ws.selection_weight > 0
        and (
          not v_has_valid_nominations
          or exists (
            select 1 from public.nominations n
            where n.round_id = v_round.id
              and n.candidate_id = ws.user_id
          )
        )
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

    v_candidate_pool := case when v_has_valid_nominations then 'nominated' else 'all_eligible' end;
  end if;

  update public.relay_rounds rr
  set status = 'expired', completed_at = now()
  where rr.id = v_round.id;

  select coalesce(max(rr.round_no), 0) + 1
  into v_next_round_no
  from public.relay_rounds rr
  where rr.story_id = v_story.id;

  insert into public.relay_rounds (story_id, round_no, current_writer_id, status)
  values (v_story.id, v_next_round_no, v_next_writer_id, 'writing')
  returning id into v_next_round_id;

  insert into public.activity_events (activity_id, group_id, type, actor_id, payload)
  values (
    v_activity.id,
    v_group_id,
    'relay_round_skipped',
    v_user_id,
    jsonb_build_object(
      'expired_round_id', v_round.id,
      'expired_round_no', v_round.round_no,
      'skipped_writer_id', v_round.current_writer_id,
      'next_round_id', v_next_round_id,
      'next_round_no', v_next_round_no,
      'next_writer_id', v_next_writer_id,
      'candidate_pool', v_candidate_pool
    )
  );

  insert into public.activity_events (activity_id, group_id, type, actor_id, payload)
  values (
    v_activity.id,
    v_group_id,
    'relay_round_started',
    v_user_id,
    jsonb_build_object(
      'round_id', v_next_round_id,
      'round_no', v_next_round_no,
      'current_writer_id', v_next_writer_id,
      'trigger', 'host_skip',
      'candidate_pool', v_candidate_pool
    )
  );

  return jsonb_build_object(
    'expired_round_id', v_round.id,
    'next_round_id', v_next_round_id,
    'next_round_no', v_next_round_no,
    'next_writer_id', v_next_writer_id,
    'candidate_pool', v_candidate_pool
  );
end;
$$;

revoke all on function public.skip_relay_round(uuid) from public;
grant execute on function public.skip_relay_round(uuid) to authenticated;

commit;
