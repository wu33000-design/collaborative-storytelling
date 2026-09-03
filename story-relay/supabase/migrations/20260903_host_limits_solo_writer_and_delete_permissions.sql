-- Story Relay: host limits, single-writer continuation, and host deletion permissions.
-- Rules:
-- 1) A host may own at most 3 non-deleted activities. Active and stopped/closed both count.
-- 2) A soft-deleted activity no longer counts toward that limit and is invisible to its host.
-- 3) Hosts may stop or soft-delete their own activities; only platform admins may restore.
-- 4) If a group has no eligible writer other than the current writer, the current writer may continue.

begin;

-- Enforce the 3-activity host ceiling at the table boundary so it also applies
-- to any future insert path, not just the current create_activity RPC.
create or replace function public.enforce_host_activity_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  if new.teacher_id is null then
    return new;
  end if;

  -- Serialize activity creation per host so concurrent requests cannot both pass.
  perform pg_advisory_xact_lock(hashtextextended(new.teacher_id::text, 0));

  select count(*) into v_count
  from public.activities a
  where a.teacher_id = new.teacher_id
    and a.deleted_at is null;

  if v_count >= 3 then
    raise exception 'A host may have at most 3 non-deleted activities';
  end if;

  return new;
end;
$$;

drop trigger if exists activities_enforce_host_limit on public.activities;
create trigger activities_enforce_host_limit
before insert on public.activities
for each row execute function public.enforce_host_activity_limit();

-- Hosts and platform admins may soft-delete. Restoration remains platform-admin only.
create or replace function public.delete_platform_activity(p_activity_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_teacher_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select a.status, a.teacher_id
  into v_status, v_teacher_id
  from public.activities a
  where a.id = p_activity_id
  for update;

  if not found then
    raise exception 'Activity not found';
  end if;

  if v_teacher_id <> auth.uid()
     and not exists (select 1 from public.platform_admins pa where pa.user_id = auth.uid()) then
    raise exception 'Only the activity host or a platform administrator can delete this activity';
  end if;

  if exists (
    select 1 from public.activities a
    where a.id = p_activity_id and a.deleted_at is not null
  ) then
    return;
  end if;

  update public.activities
  set deleted_at = now(),
      deleted_by = auth.uid(),
      purge_after = now() + interval '30 days',
      deleted_previous_status = v_status,
      status = 'closed'
  where id = p_activity_id;
end;
$$;
revoke all on function public.delete_platform_activity(uuid) from public;
grant execute on function public.delete_platform_activity(uuid) to authenticated;

-- Restoring cannot be used to exceed the 3-activity ceiling.
create or replace function public.restore_platform_activity(p_activity_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_previous_status text;
  v_purge_after timestamptz;
  v_teacher_id uuid;
  v_count integer;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists (select 1 from public.platform_admins pa where pa.user_id = auth.uid()) then
    raise exception 'Platform administrator access required';
  end if;

  select a.deleted_previous_status, a.purge_after, a.teacher_id
  into v_previous_status, v_purge_after, v_teacher_id
  from public.activities a
  where a.id = p_activity_id
    and a.deleted_at is not null
  for update;

  if not found then raise exception 'Deleted activity not found'; end if;
  if v_purge_after <= now() then raise exception 'The 30-day restore window has expired'; end if;

  perform pg_advisory_xact_lock(hashtextextended(v_teacher_id::text, 0));

  select count(*) into v_count
  from public.activities a
  where a.teacher_id = v_teacher_id
    and a.deleted_at is null;

  if v_count >= 3 then
    raise exception 'Cannot restore: this host already has 3 non-deleted activities';
  end if;

  update public.activities
  set status = coalesce(v_previous_status, 'closed'),
      deleted_at = null,
      deleted_by = null,
      purge_after = null,
      deleted_previous_status = null
  where id = p_activity_id;
end;
$$;
revoke all on function public.restore_platform_activity(uuid) from public;
grant execute on function public.restore_platform_activity(uuid) to authenticated;

-- Hosts may stop only their own non-deleted activity.
create or replace function public.stop_activity(p_activity_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;

  if not exists (
    select 1 from public.activities a
    where a.id = p_activity_id
      and a.teacher_id = v_user_id
      and a.deleted_at is null
  ) then
    raise exception 'Only the activity host can stop this non-deleted activity';
  end if;

  update public.activities
  set status = 'closed'
  where id = p_activity_id
    and deleted_at is null
    and status <> 'closed';

  update public.stories s
  set status = 'closed', completed_at = coalesce(completed_at, now())
  from public.groups g
  where s.group_id = g.id
    and g.activity_id = p_activity_id
    and s.status = 'active';

  update public.relay_rounds rr
  set status = 'expired', completed_at = coalesce(completed_at, now())
  from public.stories s
  join public.groups g on g.id = s.group_id
  where rr.story_id = s.id
    and g.activity_id = p_activity_id
    and rr.status in ('open', 'writing');

  insert into public.activity_events(activity_id, type, actor_id, payload)
  values (p_activity_id, 'activity_stopped', v_user_id, '{}'::jsonb);
end;
$$;
revoke all on function public.stop_activity(uuid) from public;
grant execute on function public.stop_activity(uuid) to authenticated;

-- Deleted activities must not remain operable through SECURITY DEFINER dashboard access.
create or replace function public.get_teacher_activity_dashboard(p_activity_id uuid)
returns table (
  group_id uuid,
  group_name text,
  story_id uuid,
  story_status text,
  member_count bigint,
  completed_segments bigint,
  required_segments integer,
  current_round_no integer,
  current_round_status text,
  current_writer_id uuid,
  current_writer_name text,
  last_activity_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;

  if not exists (
    select 1 from public.activities a
    where a.id = p_activity_id
      and a.teacher_id = auth.uid()
      and a.deleted_at is null
  ) then
    raise exception 'Host access required';
  end if;

  return query
  select
    g.id,
    g.name,
    s.id,
    s.status,
    (select count(*) from public.group_members gm where gm.group_id=g.id and gm.role='student' and gm.left_at is null)::bigint,
    (select count(*) from public.segments seg where seg.story_id=s.id and seg.author_id is not null)::bigint,
    s.required_segments,
    rr.round_no,
    rr.status,
    rr.current_writer_id,
    p.display_name,
    greatest(
      g.created_at,
      coalesce((select max(seg.submitted_at) from public.segments seg where seg.story_id=s.id), g.created_at),
      coalesce((select max(r2.started_at) from public.relay_rounds r2 where r2.story_id=s.id), g.created_at)
    )
  from public.groups g
  join public.stories s on s.group_id=g.id
  left join lateral (
    select r.round_no, r.status, r.current_writer_id
    from public.relay_rounds r
    where r.story_id=s.id and r.status in ('open','writing')
    order by r.round_no desc limit 1
  ) rr on true
  left join public.profiles p on p.id=rr.current_writer_id
  where g.activity_id=p_activity_id
  order by g.created_at,g.name,g.id;
end;
$$;
revoke all on function public.get_teacher_activity_dashboard(uuid) from public;
grant execute on function public.get_teacher_activity_dashboard(uuid) to authenticated;

-- Deleted activities must also reject rename by UUID even though the function is SECURITY DEFINER.
create or replace function public.rename_activity(p_activity_id uuid, p_new_name text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_old_name text;
  v_new_name text := nullif(trim(p_new_name), '');
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;

  select a.name into v_old_name
  from public.activities a
  where a.id = p_activity_id
    and a.teacher_id = v_user_id
    and a.deleted_at is null
  for update;

  if not found then raise exception 'Only the activity host can rename this non-deleted activity'; end if;

  if v_old_name is not distinct from v_new_name then
    return jsonb_build_object('activity_id',p_activity_id,'old_name',v_old_name,'new_name',v_new_name,'changed',false);
  end if;

  update public.activities set name=v_new_name where id=p_activity_id and deleted_at is null;
  update public.stories s set title=v_new_name
  from public.groups g
  where s.group_id=g.id and g.activity_id=p_activity_id;

  insert into public.activity_name_history(activity_id,old_name,new_name,changed_by)
  values(p_activity_id,v_old_name,v_new_name,v_user_id);

  insert into public.activity_events(activity_id,type,actor_id,payload)
  values(p_activity_id,'activity_renamed',v_user_id,jsonb_build_object('old_name',v_old_name,'new_name',v_new_name));

  return jsonb_build_object('activity_id',p_activity_id,'old_name',v_old_name,'new_name',v_new_name,'changed',true);
end;
$$;
revoke all on function public.rename_activity(uuid,text) from public;
grant execute on function public.rename_activity(uuid,text) to authenticated;

-- Single-writer continuation while preserving nomination-scoped weighted selection
-- whenever at least one other eligible writer exists.
create or replace function public.submit_segment(p_round_id uuid, p_content text)
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
  v_has_valid_nominations boolean := false;
  v_other_eligible_count integer := 0;
  v_candidate_pool text;
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;
  if nullif(trim(p_content),'') is null then raise exception 'Segment content cannot be blank'; end if;

  select * into v_round from public.relay_rounds where id=p_round_id for update;
  if v_round.id is null then raise exception 'Relay round not found'; end if;
  if v_round.status not in ('open','writing') then raise exception 'This relay round is no longer accepting submissions'; end if;
  if v_round.current_writer_id <> v_user_id then raise exception 'Only the current writer can submit this segment'; end if;

  select * into v_story from public.stories where id=v_round.story_id;
  if v_story.id is null or v_story.status <> 'active' then raise exception 'Story is not active'; end if;
  v_group_id := v_story.group_id;

  select a.* into v_activity
  from public.groups g join public.activities a on a.id=g.activity_id
  where g.id=v_group_id limit 1;
  if v_activity.id is null or v_activity.status <> 'active' or v_activity.deleted_at is not null then
    raise exception 'Activity is not active';
  end if;
  if v_activity.deadline is not null and v_activity.deadline <= now() then raise exception 'Activity deadline has passed'; end if;

  v_length := char_length(trim(p_content));
  if v_activity.min_words is not null and v_length < v_activity.min_words then raise exception 'Segment is shorter than the minimum length'; end if;
  if v_activity.max_words is not null and v_length > v_activity.max_words then raise exception 'Segment exceeds the maximum length'; end if;

  select coalesce(max(s.sequence_no),-1)+1 into v_sequence_no from public.segments s where s.story_id=v_story.id;
  insert into public.segments(story_id,sequence_no,author_id,content,word_count)
  values(v_story.id,v_sequence_no,v_user_id,trim(p_content),v_length)
  returning id into v_segment_id;

  update public.writer_states ws
  set times_written=ws.times_written+1, waiting_rounds=0, selection_weight=1, updated_at=now()
  where ws.group_id=v_group_id and ws.user_id=v_user_id;

  update public.writer_states ws
  set waiting_rounds=ws.waiting_rounds+1, selection_weight=ws.selection_weight+1, updated_at=now()
  where ws.group_id=v_group_id and ws.user_id<>v_user_id
    and exists(select 1 from public.group_members gm where gm.group_id=ws.group_id and gm.user_id=ws.user_id and gm.left_at is null and gm.role='student');

  update public.relay_rounds set status='completed',completed_at=now() where id=v_round.id;
  insert into public.activity_events(activity_id,group_id,type,actor_id,payload)
  values(v_activity.id,v_group_id,'segment_submitted',v_user_id,
    jsonb_build_object('segment_id',v_segment_id,'round_id',v_round.id,'round_no',v_round.round_no,'sequence_no',v_sequence_no));

  select count(*) into v_completed_segments from public.segments s where s.story_id=v_story.id and s.author_id is not null;
  if v_story.required_segments is not null and v_completed_segments >= v_story.required_segments then
    update public.stories set status='completed',completed_at=now() where id=v_story.id;
    insert into public.activity_events(activity_id,group_id,type,actor_id,payload)
    values(v_activity.id,v_group_id,'story_completed',v_user_id,jsonb_build_object('story_id',v_story.id,'segments',v_completed_segments));
    return v_segment_id;
  end if;

  -- First determine whether anyone other than the current writer is eligible.
  select count(*) into v_other_eligible_count
  from public.writer_states ws
  join public.group_members gm on gm.group_id=ws.group_id and gm.user_id=ws.user_id
  where ws.group_id=v_group_id
    and ws.user_id<>v_user_id
    and gm.left_at is null
    and gm.role='student'
    and ws.selection_weight>0;

  if v_other_eligible_count = 0 then
    -- Exceptional single-writer mode: allow immediate self-repeat only if the current
    -- writer is still an active eligible member of this group.
    if not exists(
      select 1 from public.writer_states ws
      join public.group_members gm on gm.group_id=ws.group_id and gm.user_id=ws.user_id
      where ws.group_id=v_group_id and ws.user_id=v_user_id
        and gm.left_at is null and gm.role='student' and ws.selection_weight>0
    ) then
      raise exception 'No eligible writers are available for the next round';
    end if;
    v_next_writer_id := v_user_id;
    v_candidate_pool := 'single_writer_fallback';
  else
    select exists(
      select 1 from public.nominations n
      join public.group_members gm on gm.group_id=v_group_id and gm.user_id=n.candidate_id
      join public.writer_states ws on ws.group_id=gm.group_id and ws.user_id=gm.user_id
      where n.round_id=v_round.id and n.candidate_id<>v_user_id
        and gm.left_at is null and gm.role='student' and ws.selection_weight>0
    ) into v_has_valid_nominations;

    select coalesce(sum(ws.selection_weight),0) into v_total_weight
    from public.writer_states ws
    join public.group_members gm on gm.group_id=ws.group_id and gm.user_id=ws.user_id
    where ws.group_id=v_group_id and ws.user_id<>v_user_id
      and gm.left_at is null and gm.role='student' and ws.selection_weight>0
      and (not v_has_valid_nominations or exists(select 1 from public.nominations n where n.round_id=v_round.id and n.candidate_id=ws.user_id));

    if v_total_weight<=0 then raise exception 'No eligible writers are available for the next round'; end if;
    v_pick := random()*v_total_weight;

    for v_candidate in
      select ws.user_id,ws.selection_weight
      from public.writer_states ws
      join public.group_members gm on gm.group_id=ws.group_id and gm.user_id=ws.user_id
      where ws.group_id=v_group_id and ws.user_id<>v_user_id
        and gm.left_at is null and gm.role='student' and ws.selection_weight>0
        and (not v_has_valid_nominations or exists(select 1 from public.nominations n where n.round_id=v_round.id and n.candidate_id=ws.user_id))
      order by ws.user_id
    loop
      v_running:=v_running+v_candidate.selection_weight;
      if v_pick<v_running then v_next_writer_id:=v_candidate.user_id; exit; end if;
    end loop;

    if v_next_writer_id is null then raise exception 'Unable to select the next writer'; end if;
    v_candidate_pool := case when v_has_valid_nominations then 'nominated' else 'all_eligible' end;
  end if;

  v_next_round_no:=v_round.round_no+1;
  insert into public.relay_rounds(story_id,round_no,current_writer_id,status)
  values(v_story.id,v_next_round_no,v_next_writer_id,'writing')
  returning id into v_next_round_id;

  insert into public.activity_events(activity_id,group_id,type,actor_id,payload)
  values(v_activity.id,v_group_id,'relay_round_started',v_user_id,
    jsonb_build_object('round_id',v_next_round_id,'round_no',v_next_round_no,'current_writer_id',v_next_writer_id,'trigger','segment_submitted','candidate_pool',v_candidate_pool));

  return v_segment_id;
end;
$$;
revoke all on function public.submit_segment(uuid,text) from public;
grant execute on function public.submit_segment(uuid,text) to authenticated;

commit;
