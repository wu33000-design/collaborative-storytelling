-- Story Relay: deterministic next-writer locks + public probability visibility.
-- Product rules (2026-09-06):
-- 1) One successful volunteer locks the next writer at 100%.
-- 2) One successful nomination locks the next writer at 100%.
-- 3) Volunteer and nomination are mutually exclusive locks; whichever is recorded first wins.
-- 4) With no lock, all other eligible students are selected by waiting-weighted random.
-- 5) If no other eligible student exists, keep the existing single-writer fallback.
-- 6) Every authorized room viewer can query the same backend-computed probability table.
--
-- IMPORTANT: Phase E3 renamed the public mutation implementations to *_unthrottled and
-- wrapped them with rate-limited public RPCs. This migration replaces the internal
-- implementations so the existing public rate-limit wrappers remain authoritative.

begin;

create or replace function public.volunteer_for_round_unthrottled(p_round_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_round public.relay_rounds%rowtype;
  v_group_id uuid;
  v_existing_volunteer uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  -- Lock the round row so simultaneous volunteer/nomination attempts serialize.
  select * into v_round
  from public.relay_rounds rr
  where rr.id = p_round_id
  for update;

  if v_round.id is null or v_round.status not in ('open', 'writing') then
    raise exception 'This relay round is not accepting volunteers';
  end if;

  select s.group_id into v_group_id
  from public.stories s
  where s.id = v_round.story_id;

  if not exists (
    select 1
    from public.group_members gm
    join public.writer_states ws
      on ws.group_id = gm.group_id
     and ws.user_id = gm.user_id
    where gm.group_id = v_group_id
      and gm.user_id = v_user_id
      and gm.left_at is null
      and gm.role = 'student'
      and ws.selection_weight > 0
  ) then
    raise exception 'Only an active eligible student in this group can volunteer';
  end if;

  if v_round.current_writer_id = v_user_id then
    raise exception 'The current writer cannot volunteer for the next round';
  end if;

  -- Once a nomination has locked the next writer, a later volunteer cannot override it.
  if exists (
    select 1
    from public.nominations n
    where n.round_id = p_round_id
  ) then
    raise exception 'The next writer is already locked by a nomination';
  end if;

  select v.user_id into v_existing_volunteer
  from public.volunteers v
  where v.round_id = p_round_id
  limit 1;

  if v_existing_volunteer = v_user_id then
    return;
  end if;

  if v_existing_volunteer is not null then
    raise exception 'Another student has already volunteered for the next round';
  end if;

  insert into public.volunteers (round_id, user_id)
  values (p_round_id, v_user_id)
  on conflict (round_id, user_id) do nothing;
end;
$$;

revoke all on function public.volunteer_for_round_unthrottled(uuid) from public, anon, authenticated;

create or replace function public.nominate_candidate_unthrottled(p_round_id uuid, p_candidate_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_round public.relay_rounds%rowtype;
  v_group_id uuid;
  v_existing_nominee uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  -- Same round lock as volunteer_for_round_unthrottled: first successful lock wins.
  select * into v_round
  from public.relay_rounds rr
  where rr.id = p_round_id
  for update;

  if v_round.id is null or v_round.status not in ('open', 'writing') then
    raise exception 'This relay round is not accepting nominations';
  end if;

  if v_round.current_writer_id <> v_user_id then
    raise exception 'Only the current writer can nominate the next writer';
  end if;

  if p_candidate_id = v_user_id then
    raise exception 'The current writer cannot nominate themself for the next round';
  end if;

  select s.group_id into v_group_id
  from public.stories s
  where s.id = v_round.story_id;

  if not exists (
    select 1
    from public.group_members gm
    join public.writer_states ws
      on ws.group_id = gm.group_id
     and ws.user_id = gm.user_id
    where gm.group_id = v_group_id
      and gm.user_id = p_candidate_id
      and gm.left_at is null
      and gm.role = 'student'
      and ws.selection_weight > 0
  ) then
    raise exception 'The nominated student is not eligible for the next round';
  end if;

  -- A volunteer already locks the result and cannot be displaced by a later nomination.
  if exists (
    select 1
    from public.volunteers v
    where v.round_id = p_round_id
  ) then
    raise exception 'The next writer is already locked by a volunteer';
  end if;

  select n.candidate_id into v_existing_nominee
  from public.nominations n
  where n.round_id = p_round_id
  limit 1;

  if v_existing_nominee = p_candidate_id then
    return;
  end if;

  if v_existing_nominee is not null then
    raise exception 'A next writer has already been nominated for this round';
  end if;

  insert into public.nominations (round_id, nominated_by, candidate_id)
  values (p_round_id, v_user_id, p_candidate_id)
  on conflict (round_id, candidate_id) do nothing;
end;
$$;

revoke all on function public.nominate_candidate_unthrottled(uuid, uuid) from public, anon, authenticated;

create or replace function public.get_next_writer_probabilities(p_round_id uuid)
returns table (
  user_id uuid,
  probability_pct numeric,
  effective_weight numeric,
  is_volunteer boolean,
  is_nominated boolean,
  selection_mode text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_round public.relay_rounds%rowtype;
  v_group_id uuid;
  v_activity_id uuid;
  v_volunteer_id uuid;
  v_nominee_id uuid;
  v_other_eligible_count integer := 0;
  v_total_weight numeric := 0;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select * into v_round
  from public.relay_rounds rr
  where rr.id = p_round_id;

  if v_round.id is null or v_round.status not in ('open', 'writing') then
    raise exception 'Active relay round required';
  end if;

  select s.group_id, g.activity_id
  into v_group_id, v_activity_id
  from public.stories s
  join public.groups g on g.id = s.group_id
  where s.id = v_round.story_id;

  if v_group_id is null then
    raise exception 'Relay round group not found';
  end if;

  -- Same visibility boundary as the room: an active group member, the activity host,
  -- or a platform administrator may inspect the complete probability table.
  if not exists (
       select 1 from public.group_members gm
       where gm.group_id = v_group_id
         and gm.user_id = v_user_id
         and gm.left_at is null
     )
     and not exists (
       select 1 from public.activities a
       where a.id = v_activity_id
         and a.teacher_id = v_user_id
         and a.deleted_at is null
     )
     and not exists (
       select 1 from public.platform_admins pa
       where pa.user_id = v_user_id
     ) then
    raise exception 'Room access required';
  end if;

  select v.user_id into v_volunteer_id
  from public.volunteers v
  join public.group_members gm
    on gm.group_id = v_group_id
   and gm.user_id = v.user_id
  join public.writer_states ws
    on ws.group_id = gm.group_id
   and ws.user_id = gm.user_id
  where v.round_id = p_round_id
    and v.user_id <> v_round.current_writer_id
    and gm.left_at is null
    and gm.role = 'student'
    and ws.selection_weight > 0
  limit 1;

  select n.candidate_id into v_nominee_id
  from public.nominations n
  join public.group_members gm
    on gm.group_id = v_group_id
   and gm.user_id = n.candidate_id
  join public.writer_states ws
    on ws.group_id = gm.group_id
   and ws.user_id = gm.user_id
  where n.round_id = p_round_id
    and n.candidate_id <> v_round.current_writer_id
    and gm.left_at is null
    and gm.role = 'student'
    and ws.selection_weight > 0
  limit 1;

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

  if v_volunteer_id is not null then
    return query
    select
      gm.user_id,
      case when gm.user_id = v_volunteer_id then 100::numeric else 0::numeric end,
      case when gm.user_id = v_round.current_writer_id then 0::numeric else (ws.selection_weight + 1)::numeric end,
      gm.user_id = v_volunteer_id,
      gm.user_id = v_nominee_id,
      'volunteer_locked'::text
    from public.group_members gm
    join public.writer_states ws
      on ws.group_id = gm.group_id
     and ws.user_id = gm.user_id
    where gm.group_id = v_group_id
      and gm.left_at is null
      and gm.role = 'student'
    order by gm.joined_at, gm.user_id;
    return;
  end if;

  if v_nominee_id is not null then
    return query
    select
      gm.user_id,
      case when gm.user_id = v_nominee_id then 100::numeric else 0::numeric end,
      case when gm.user_id = v_round.current_writer_id then 0::numeric else (ws.selection_weight + 1)::numeric end,
      false,
      gm.user_id = v_nominee_id,
      'nomination_locked'::text
    from public.group_members gm
    join public.writer_states ws
      on ws.group_id = gm.group_id
     and ws.user_id = gm.user_id
    where gm.group_id = v_group_id
      and gm.left_at is null
      and gm.role = 'student'
    order by gm.joined_at, gm.user_id;
    return;
  end if;

  if v_other_eligible_count = 0 then
    return query
    select
      gm.user_id,
      case when gm.user_id = v_round.current_writer_id and ws.selection_weight > 0 then 100::numeric else 0::numeric end,
      case when gm.user_id = v_round.current_writer_id then ws.selection_weight::numeric else 0::numeric end,
      false,
      false,
      'single_writer_fallback'::text
    from public.group_members gm
    join public.writer_states ws
      on ws.group_id = gm.group_id
     and ws.user_id = gm.user_id
    where gm.group_id = v_group_id
      and gm.left_at is null
      and gm.role = 'student'
    order by gm.joined_at, gm.user_id;
    return;
  end if;

  -- submit_segment increments every other active student's selection_weight before
  -- drawing. Expose that exact prospective weight so the displayed probability is
  -- what would be used if the current writer submitted now.
  select coalesce(sum(ws.selection_weight + 1), 0)
  into v_total_weight
  from public.writer_states ws
  join public.group_members gm
    on gm.group_id = ws.group_id
   and gm.user_id = ws.user_id
  where ws.group_id = v_group_id
    and ws.user_id <> v_round.current_writer_id
    and gm.left_at is null
    and gm.role = 'student'
    and ws.selection_weight > 0;

  if v_total_weight <= 0 then
    raise exception 'No eligible writers are available for the next round';
  end if;

  return query
  select
    gm.user_id,
    case
      when gm.user_id = v_round.current_writer_id then 0::numeric
      else round((((ws.selection_weight + 1)::numeric / v_total_weight) * 100)::numeric, 1)
    end,
    case
      when gm.user_id = v_round.current_writer_id then 0::numeric
      else (ws.selection_weight + 1)::numeric
    end,
    false,
    false,
    'weighted_random'::text
  from public.group_members gm
  join public.writer_states ws
    on ws.group_id = gm.group_id
   and ws.user_id = gm.user_id
  where gm.group_id = v_group_id
    and gm.left_at is null
    and gm.role = 'student'
  order by gm.joined_at, gm.user_id;
end;
$$;

revoke all on function public.get_next_writer_probabilities(uuid) from public, anon;
grant execute on function public.get_next_writer_probabilities(uuid) to authenticated;

create or replace function public.submit_segment_unthrottled(p_round_id uuid, p_content text)
returns uuid
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
  v_segment_id uuid;
  v_sequence_no integer;
  v_length integer;
  v_completed_segments integer;
  v_next_writer_id uuid;
  v_next_round_id uuid;
  v_next_round_no integer;
  v_total_weight numeric := 0;
  v_pick numeric;
  v_running numeric := 0;
  v_candidate record;
  v_other_eligible_count integer := 0;
  v_candidate_pool text;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;
  if nullif(trim(p_content), '') is null then
    raise exception 'Segment content cannot be blank';
  end if;

  select * into v_round
  from public.relay_rounds rr
  where rr.id = p_round_id
  for update;

  if v_round.id is null then raise exception 'Relay round not found'; end if;
  if v_round.status not in ('open', 'writing') then raise exception 'This relay round is no longer accepting submissions'; end if;
  if v_round.current_writer_id <> v_user_id then raise exception 'Only the current writer can submit this segment'; end if;

  select * into v_story
  from public.stories s
  where s.id = v_round.story_id;
  if v_story.id is null or v_story.status <> 'active' then raise exception 'Story is not active'; end if;
  v_group_id := v_story.group_id;

  select a.* into v_activity
  from public.groups g
  join public.activities a on a.id = g.activity_id
  where g.id = v_group_id
  limit 1;

  if v_activity.id is null or v_activity.status <> 'active' or v_activity.deleted_at is not null then
    raise exception 'Activity is not active';
  end if;
  if v_activity.deadline is not null and v_activity.deadline <= now() then
    raise exception 'Activity deadline has passed';
  end if;

  v_length := char_length(trim(p_content));
  if v_activity.min_words is not null and v_length < v_activity.min_words then raise exception 'Segment is shorter than the minimum length'; end if;
  if v_activity.max_words is not null and v_length > v_activity.max_words then raise exception 'Segment exceeds the maximum length'; end if;

  select coalesce(max(s.sequence_no), -1) + 1
  into v_sequence_no
  from public.segments s
  where s.story_id = v_story.id;

  insert into public.segments (story_id, sequence_no, author_id, content, word_count)
  values (v_story.id, v_sequence_no, v_user_id, trim(p_content), v_length)
  returning id into v_segment_id;

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
      select 1 from public.group_members gm
      where gm.group_id = ws.group_id
        and gm.user_id = ws.user_id
        and gm.left_at is null
        and gm.role = 'student'
    );

  update public.relay_rounds rr
  set status = 'completed', completed_at = now()
  where rr.id = v_round.id;

  insert into public.activity_events (activity_id, group_id, type, actor_id, payload)
  values (
    v_activity.id,
    v_group_id,
    'segment_submitted',
    v_user_id,
    jsonb_build_object('segment_id', v_segment_id, 'round_id', v_round.id, 'round_no', v_round.round_no, 'sequence_no', v_sequence_no)
  );

  select count(*) into v_completed_segments
  from public.segments s
  where s.story_id = v_story.id
    and s.author_id is not null;

  if v_story.required_segments is not null and v_completed_segments >= v_story.required_segments then
    update public.stories s
    set status = 'completed', completed_at = now()
    where s.id = v_story.id;

    insert into public.activity_events (activity_id, group_id, type, actor_id, payload)
    values (
      v_activity.id,
      v_group_id,
      'story_completed',
      v_user_id,
      jsonb_build_object('story_id', v_story.id, 'segments', v_completed_segments)
    );

    return v_segment_id;
  end if;

  -- Priority 1: one valid volunteer deterministically becomes the next writer.
  select v.user_id into v_next_writer_id
  from public.volunteers v
  join public.group_members gm
    on gm.group_id = v_group_id
   and gm.user_id = v.user_id
  join public.writer_states ws
    on ws.group_id = gm.group_id
   and ws.user_id = gm.user_id
  where v.round_id = v_round.id
    and v.user_id <> v_user_id
    and gm.left_at is null
    and gm.role = 'student'
    and ws.selection_weight > 0
  limit 1;

  if v_next_writer_id is not null then
    v_candidate_pool := 'volunteer_locked';
  else
    -- Priority 2: one valid nomination deterministically becomes the next writer.
    select n.candidate_id into v_next_writer_id
    from public.nominations n
    join public.group_members gm
      on gm.group_id = v_group_id
     and gm.user_id = n.candidate_id
    join public.writer_states ws
      on ws.group_id = gm.group_id
     and ws.user_id = gm.user_id
    where n.round_id = v_round.id
      and n.candidate_id <> v_user_id
      and gm.left_at is null
      and gm.role = 'student'
      and ws.selection_weight > 0
    limit 1;

    if v_next_writer_id is not null then
      v_candidate_pool := 'nomination_locked';
    else
      select count(*) into v_other_eligible_count
      from public.writer_states ws
      join public.group_members gm
        on gm.group_id = ws.group_id
       and gm.user_id = ws.user_id
      where ws.group_id = v_group_id
        and ws.user_id <> v_user_id
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
            and ws.user_id = v_user_id
            and gm.left_at is null
            and gm.role = 'student'
            and ws.selection_weight > 0
        ) then
          raise exception 'No eligible writers are available for the next round';
        end if;

        v_next_writer_id := v_user_id;
        v_candidate_pool := 'single_writer_fallback';
      else
        -- Priority 3: weighted random among every other eligible active student.
        select coalesce(sum(ws.selection_weight), 0)
        into v_total_weight
        from public.writer_states ws
        join public.group_members gm
          on gm.group_id = ws.group_id
         and gm.user_id = ws.user_id
        where ws.group_id = v_group_id
          and ws.user_id <> v_user_id
          and gm.left_at is null
          and gm.role = 'student'
          and ws.selection_weight > 0;

        if v_total_weight <= 0 then
          raise exception 'No eligible writers are available for the next round';
        end if;

        v_pick := random() * v_total_weight;
        v_running := 0;

        for v_candidate in
          select ws.user_id, ws.selection_weight
          from public.writer_states ws
          join public.group_members gm
            on gm.group_id = ws.group_id
           and gm.user_id = ws.user_id
          where ws.group_id = v_group_id
            and ws.user_id <> v_user_id
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

        v_candidate_pool := 'weighted_random';
      end if;
    end if;
  end if;

  v_next_round_no := v_round.round_no + 1;

  insert into public.relay_rounds (story_id, round_no, current_writer_id, status)
  values (v_story.id, v_next_round_no, v_next_writer_id, 'writing')
  returning id into v_next_round_id;

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
      'trigger', 'segment_submitted',
      'candidate_pool', v_candidate_pool
    )
  );

  return v_segment_id;
end;
$$;

revoke all on function public.submit_segment_unthrottled(uuid, text) from public, anon, authenticated;

-- Host skip must respect an already-visible 100% lock too. Unlike submit, skip does
-- not increment waiting weights; only the unlocked weighted-random fallback differs.
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
  v_total_weight numeric := 0;
  v_pick numeric;
  v_running numeric := 0;
  v_candidate record;
  v_candidate_pool text;
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;

  select * into v_round
  from public.relay_rounds rr
  where rr.id = p_round_id
  for update;

  if v_round.id is null then raise exception 'Relay round not found'; end if;
  if v_round.status not in ('open', 'writing') then raise exception 'Only an active relay round can be skipped'; end if;

  select * into v_story
  from public.stories s
  where s.id = v_round.story_id;
  if v_story.id is null or v_story.status <> 'active' then raise exception 'Story is not active'; end if;

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
  if v_activity.deadline is not null and v_activity.deadline <= now() then raise exception 'Activity deadline has passed'; end if;

  perform pg_advisory_xact_lock(hashtextextended(v_story.id::text, 0));

  if exists (
    select 1 from public.relay_rounds rr
    where rr.story_id = v_story.id
      and rr.status in ('open', 'writing')
      and rr.id <> v_round.id
  ) then
    raise exception 'A newer active relay round already exists';
  end if;

  select v.user_id into v_next_writer_id
  from public.volunteers v
  join public.group_members gm
    on gm.group_id = v_group_id
   and gm.user_id = v.user_id
  join public.writer_states ws
    on ws.group_id = gm.group_id
   and ws.user_id = gm.user_id
  where v.round_id = v_round.id
    and v.user_id <> v_round.current_writer_id
    and gm.left_at is null
    and gm.role = 'student'
    and ws.selection_weight > 0
  limit 1;

  if v_next_writer_id is not null then
    v_candidate_pool := 'volunteer_locked';
  else
    select n.candidate_id into v_next_writer_id
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
    limit 1;

    if v_next_writer_id is not null then
      v_candidate_pool := 'nomination_locked';
    else
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
          and ws.selection_weight > 0;

        if v_total_weight <= 0 then raise exception 'No eligible writers are available for the next round'; end if;

        v_pick := random() * v_total_weight;
        v_running := 0;

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
          order by ws.user_id
        loop
          v_running := v_running + v_candidate.selection_weight;
          if v_pick < v_running then
            v_next_writer_id := v_candidate.user_id;
            exit;
          end if;
        end loop;

        if v_next_writer_id is null then raise exception 'Unable to select the next writer'; end if;
        v_candidate_pool := 'weighted_random';
      end if;
    end if;
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

revoke all on function public.skip_relay_round(uuid) from public, anon;
grant execute on function public.skip_relay_round(uuid) to authenticated;

commit;
