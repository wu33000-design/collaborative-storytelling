-- Story Relay: teacher-only activity monitoring dashboard.

begin;

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
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1
    from public.activities a
    where a.id = p_activity_id
      and a.teacher_id = auth.uid()
  ) then
    raise exception 'Teacher access required';
  end if;

  return query
  select
    g.id as group_id,
    g.name as group_name,
    s.id as story_id,
    s.status as story_status,
    (
      select count(*)
      from public.group_members gm
      where gm.group_id = g.id
        and gm.role = 'student'
        and gm.left_at is null
    )::bigint as member_count,
    (
      select count(*)
      from public.segments seg
      where seg.story_id = s.id
        and seg.author_id is not null
    )::bigint as completed_segments,
    s.required_segments,
    rr.round_no as current_round_no,
    rr.status as current_round_status,
    rr.current_writer_id,
    p.display_name as current_writer_name,
    greatest(
      g.created_at,
      coalesce((
        select max(seg.submitted_at)
        from public.segments seg
        where seg.story_id = s.id
      ), g.created_at),
      coalesce((
        select max(r2.started_at)
        from public.relay_rounds r2
        where r2.story_id = s.id
      ), g.created_at)
    ) as last_activity_at
  from public.groups g
  join public.stories s on s.group_id = g.id
  left join lateral (
    select r.id, r.round_no, r.status, r.current_writer_id
    from public.relay_rounds r
    where r.story_id = s.id
      and r.status in ('open', 'writing')
    order by r.round_no desc
    limit 1
  ) rr on true
  left join public.profiles p on p.id = rr.current_writer_id
  where g.activity_id = p_activity_id
  order by g.created_at, g.name, g.id;
end;
$$;

revoke all on function public.get_teacher_activity_dashboard(uuid) from public;
grant execute on function public.get_teacher_activity_dashboard(uuid) to authenticated;

-- activity_events is the compact event stream for teacher dashboard refreshes.
do $$
begin
  alter publication supabase_realtime add table public.activity_events;
exception
  when duplicate_object then null;
end $$;

commit;
