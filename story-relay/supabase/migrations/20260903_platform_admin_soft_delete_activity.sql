-- Story Relay: 30-day soft deletion / restore for platform-managed activities.
-- Deleted activities are hidden from normal reads, kept intact for 30 days,
-- and visible/restorable only to platform administrators.

begin;

alter table public.activities
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid references public.profiles(id),
  add column if not exists purge_after timestamptz,
  add column if not exists deleted_previous_status text;

create index if not exists activities_deleted_at_idx on public.activities(deleted_at);
create index if not exists activities_purge_after_idx on public.activities(purge_after) where deleted_at is not null;

-- A restrictive policy composes with the existing permissive activity policies.
-- Ordinary users cannot SELECT a soft-deleted activity even if they created or joined it.
drop policy if exists "soft deleted activities visible only to platform admins" on public.activities;
create policy "soft deleted activities visible only to platform admins"
on public.activities
as restrictive
for select
to authenticated
using (deleted_at is null or public.is_platform_admin());

-- Replace the old permanent-delete RPC with soft delete semantics.
create or replace function public.delete_platform_activity(p_activity_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists (select 1 from public.platform_admins pa where pa.user_id = auth.uid()) then
    raise exception 'Platform administrator access required';
  end if;

  select a.status into v_status
  from public.activities a
  where a.id = p_activity_id
  for update;

  if not found then raise exception 'Activity not found'; end if;
  if exists (select 1 from public.activities a where a.id = p_activity_id and a.deleted_at is not null) then
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

create or replace function public.restore_platform_activity(p_activity_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_previous_status text;
  v_purge_after timestamptz;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists (select 1 from public.platform_admins pa where pa.user_id = auth.uid()) then
    raise exception 'Platform administrator access required';
  end if;

  select a.deleted_previous_status, a.purge_after
  into v_previous_status, v_purge_after
  from public.activities a
  where a.id = p_activity_id and a.deleted_at is not null
  for update;

  if not found then raise exception 'Deleted activity not found'; end if;
  if v_purge_after <= now() then raise exception 'The 30-day restore window has expired'; end if;

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

-- Internal hard-delete helper. It is never executable by clients directly.
create or replace function public.hard_delete_expired_activity(p_activity_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.activities a
    where a.id = p_activity_id
      and a.deleted_at is not null
      and a.purge_after <= now()
  ) then return; end if;

  delete from public.nominations n where n.round_id in (
    select rr.id from public.relay_rounds rr
    join public.stories s on s.id = rr.story_id
    join public.groups g on g.id = s.group_id
    where g.activity_id = p_activity_id
  );
  delete from public.volunteers v where v.round_id in (
    select rr.id from public.relay_rounds rr
    join public.stories s on s.id = rr.story_id
    join public.groups g on g.id = s.group_id
    where g.activity_id = p_activity_id
  );
  delete from public.relay_rounds rr where rr.story_id in (
    select s.id from public.stories s join public.groups g on g.id = s.group_id where g.activity_id = p_activity_id
  );
  delete from public.segments sg where sg.story_id in (
    select s.id from public.stories s join public.groups g on g.id = s.group_id where g.activity_id = p_activity_id
  );
  delete from public.writer_states ws where ws.group_id in (select id from public.groups where activity_id = p_activity_id);
  delete from public.group_members gm where gm.group_id in (select id from public.groups where activity_id = p_activity_id);
  delete from public.stories s where s.group_id in (select id from public.groups where activity_id = p_activity_id);
  delete from public.activity_events where activity_id = p_activity_id;
  delete from public.activity_name_history where activity_id = p_activity_id;
  delete from public.groups where activity_id = p_activity_id;
  delete from public.activities where id = p_activity_id;
end;
$$;
revoke all on function public.hard_delete_expired_activity(uuid) from public, anon, authenticated;

create or replace function public.purge_expired_platform_activities()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_count integer := 0;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists (select 1 from public.platform_admins pa where pa.user_id = auth.uid()) then
    raise exception 'Platform administrator access required';
  end if;

  for v_id in select id from public.activities where deleted_at is not null and purge_after <= now()
  loop
    perform public.hard_delete_expired_activity(v_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke all on function public.purge_expired_platform_activities() from public;
grant execute on function public.purge_expired_platform_activities() to authenticated;

create or replace function public.get_platform_deleted_activities()
returns table (
  activity_id uuid,
  code text,
  name text,
  previous_status text,
  host_user_id uuid,
  host_name text,
  host_email text,
  participant_count bigint,
  group_count bigint,
  segment_count bigint,
  deleted_at timestamptz,
  purge_after timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists (select 1 from public.platform_admins pa where pa.user_id = auth.uid()) then
    raise exception 'Platform administrator access required';
  end if;

  perform public.purge_expired_platform_activities();

  return query
  select a.id, a.code, a.name, a.deleted_previous_status, a.teacher_id,
         p.display_name, pmi.login_email,
         (select count(distinct gm.user_id) from public.groups g join public.group_members gm on gm.group_id=g.id where g.activity_id=a.id and gm.left_at is null)::bigint,
         (select count(*) from public.groups g where g.activity_id=a.id)::bigint,
         (select count(*) from public.groups g join public.stories s on s.group_id=g.id join public.segments sg on sg.story_id=s.id where g.activity_id=a.id)::bigint,
         a.deleted_at, a.purge_after
  from public.activities a
  left join public.profiles p on p.id=a.teacher_id
  left join public.platform_member_identities pmi on pmi.user_id=a.teacher_id
  where a.deleted_at is not null
  order by a.deleted_at desc;
end;
$$;
revoke all on function public.get_platform_deleted_activities() from public;
grant execute on function public.get_platform_deleted_activities() to authenticated;

-- Normal platform lists and totals exclude soft-deleted activities.
create or replace function public.get_platform_overview()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists (select 1 from public.platform_admins pa where pa.user_id = auth.uid()) then raise exception 'Platform administrator access required'; end if;
  return jsonb_build_object(
    'members', (select count(*) from public.profiles),
    'activities', (select count(*) from public.activities where deleted_at is null),
    'active_activities', (select count(*) from public.activities where deleted_at is null and status='active'),
    'active_members_7d', (
      select count(distinct ae.actor_id) from public.activity_events ae
      join public.activities a on a.id=ae.activity_id
      where a.deleted_at is null and ae.actor_id is not null and ae.created_at >= now()-interval '7 days'
    ),
    'segments', (
      select count(*) from public.segments sg join public.stories s on s.id=sg.story_id join public.groups g on g.id=s.group_id join public.activities a on a.id=g.activity_id where a.deleted_at is null
    ),
    'characters', (
      select coalesce(sum(coalesce(sg.word_count,char_length(sg.content))),0) from public.segments sg join public.stories s on s.id=sg.story_id join public.groups g on g.id=s.group_id join public.activities a on a.id=g.activity_id where a.deleted_at is null
    )
  );
end;
$$;

create or replace function public.get_platform_activity_stats()
returns table (
  activity_id uuid, code text, name text, status text, host_user_id uuid, host_name text, host_email text,
  participant_count bigint, group_count bigint, segment_count bigint, created_at timestamptz, last_activity_at timestamptz
)
language plpgsql security definer set search_path=public
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists (select 1 from public.platform_admins pa where pa.user_id=auth.uid()) then raise exception 'Platform administrator access required'; end if;
  return query
  select a.id,a.code,a.name,a.status,a.teacher_id,p.display_name,pmi.login_email,
    (select count(distinct gm.user_id) from public.groups g join public.group_members gm on gm.group_id=g.id where g.activity_id=a.id and gm.left_at is null)::bigint,
    (select count(*) from public.groups g where g.activity_id=a.id)::bigint,
    (select count(*) from public.groups g join public.stories s on s.group_id=g.id join public.segments sg on sg.story_id=s.id where g.activity_id=a.id)::bigint,
    a.created_at,coalesce((select max(ae.created_at) from public.activity_events ae where ae.activity_id=a.id),a.created_at)
  from public.activities a
  left join public.profiles p on p.id=a.teacher_id
  left join public.platform_member_identities pmi on pmi.user_id=a.teacher_id
  where a.deleted_at is null
  order by a.created_at desc;
end;
$$;

create or replace function public.get_platform_member_activities(p_user_id uuid)
returns table (
  activity_id uuid, code text, name text, activity_status text, relation text, group_count bigint,
  rounds_selected bigint, segments_written bigint, total_characters bigint, first_joined_at timestamptz, last_submission_at timestamptz
)
language plpgsql security definer set search_path=public
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists (select 1 from public.platform_admins pa where pa.user_id=auth.uid()) then raise exception 'Platform administrator access required'; end if;
  return query
  with related as (
    select a.id from public.activities a where a.teacher_id=p_user_id and a.deleted_at is null
    union
    select g.activity_id from public.group_members gm join public.groups g on g.id=gm.group_id join public.activities a on a.id=g.activity_id where gm.user_id=p_user_id and a.deleted_at is null
  )
  select a.id,a.code,a.name,a.status,
    case when a.teacher_id=p_user_id and exists(select 1 from public.group_members gm join public.groups g on g.id=gm.group_id where gm.user_id=p_user_id and g.activity_id=a.id) then 'host_and_participant'
         when a.teacher_id=p_user_id then 'host' else 'participant' end,
    (select count(distinct gm.group_id) from public.group_members gm join public.groups g on g.id=gm.group_id where gm.user_id=p_user_id and g.activity_id=a.id)::bigint,
    (select count(*) from public.relay_rounds rr join public.stories s on s.id=rr.story_id join public.groups g on g.id=s.group_id where rr.current_writer_id=p_user_id and g.activity_id=a.id)::bigint,
    (select count(*) from public.segments sg join public.stories s on s.id=sg.story_id join public.groups g on g.id=s.group_id where sg.author_id=p_user_id and g.activity_id=a.id)::bigint,
    coalesce((select sum(coalesce(sg.word_count,char_length(sg.content))) from public.segments sg join public.stories s on s.id=sg.story_id join public.groups g on g.id=s.group_id where sg.author_id=p_user_id and g.activity_id=a.id),0)::bigint,
    (select min(gm.joined_at) from public.group_members gm join public.groups g on g.id=gm.group_id where gm.user_id=p_user_id and g.activity_id=a.id),
    (select max(sg.submitted_at) from public.segments sg join public.stories s on s.id=sg.story_id join public.groups g on g.id=s.group_id where sg.author_id=p_user_id and g.activity_id=a.id)
  from public.activities a join related r on r.id=a.id
  where a.deleted_at is null
  order by a.created_at desc;
end;
$$;

-- Existing join RPC must explicitly reject soft-deleted activities because deletion preserves the original status for restore.
create or replace function public.join_activity_by_code(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_activity public.activities%rowtype;
  v_group_id uuid;
  v_story_id uuid;
  v_group_no integer;
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;
  select * into v_activity from public.activities
  where upper(trim(code))=upper(trim(p_code)) and status='active' and deleted_at is null and (deadline is null or deadline>now()) limit 1;
  if v_activity.id is null then raise exception 'Active activity not found'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_activity.id::text,0));
  select gm.group_id into v_group_id from public.group_members gm join public.groups g on g.id=gm.group_id
  where gm.user_id=v_user_id and gm.left_at is null and g.activity_id=v_activity.id limit 1;
  if v_group_id is not null then return v_group_id; end if;
  select g.id into v_group_id from public.groups g
  left join public.group_members gm on gm.group_id=g.id and gm.left_at is null and gm.role='student'
  where g.activity_id=v_activity.id group by g.id,g.created_at
  having v_activity.group_size is null or count(gm.user_id)<v_activity.group_size
  order by count(gm.user_id),g.created_at limit 1;
  if v_group_id is null then
    select count(*)+1 into v_group_no from public.groups where activity_id=v_activity.id;
    insert into public.groups(activity_id,name) values(v_activity.id,'Group '||v_group_no) returning id into v_group_id;
    insert into public.stories(group_id,title,prompt,required_segments,status) values(v_group_id,v_activity.name,v_activity.prompt,v_activity.required_segments,'active') returning id into v_story_id;
    if nullif(trim(v_activity.initial_text),'') is not null then
      insert into public.segments(story_id,sequence_no,author_id,content,word_count) values(v_story_id,0,null,trim(v_activity.initial_text),char_length(trim(v_activity.initial_text)));
    end if;
  end if;
  insert into public.group_members(group_id,user_id,role) values(v_group_id,v_user_id,'student');
  insert into public.writer_states(group_id,user_id,times_written,waiting_rounds,selection_weight) values(v_group_id,v_user_id,0,0,1)
  on conflict(group_id,user_id) do update set waiting_rounds=0,selection_weight=1,updated_at=now();
  insert into public.activity_events(activity_id,group_id,type,actor_id,payload) values(v_activity.id,v_group_id,'student_joined',v_user_id,'{}'::jsonb);
  return v_group_id;
end;
$$;

commit;
