-- D3: teacher-only activity member statistics for CSV export.
-- Story text and platform login email are intentionally excluded.

begin;

create or replace function public.get_teacher_activity_csv(p_activity_id uuid)
returns table (
  group_id uuid,
  group_name text,
  user_id uuid,
  display_name text,
  role text,
  joined_at timestamptz,
  left_at timestamptz,
  rounds_selected bigint,
  segments_written bigint,
  total_characters bigint,
  first_submission_at timestamptz,
  last_submission_at timestamptz
)
language plpgsql
security definer
set search_path = ''
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
      and a.deleted_at is null
  ) then
    raise exception 'Teacher access required';
  end if;

  return query
  select
    g.id as group_id,
    g.name as group_name,
    gm.user_id,
    p.display_name,
    gm.role,
    gm.joined_at,
    gm.left_at,
    (
      select count(*)
      from public.relay_rounds rr
      join public.stories s on s.id = rr.story_id
      where s.group_id = g.id
        and rr.current_writer_id = gm.user_id
    )::bigint as rounds_selected,
    (
      select count(*)
      from public.segments seg
      join public.stories s on s.id = seg.story_id
      where s.group_id = g.id
        and seg.author_id = gm.user_id
    )::bigint as segments_written,
    coalesce((
      select sum(char_length(seg.content))
      from public.segments seg
      join public.stories s on s.id = seg.story_id
      where s.group_id = g.id
        and seg.author_id = gm.user_id
    ), 0)::bigint as total_characters,
    (
      select min(seg.submitted_at)
      from public.segments seg
      join public.stories s on s.id = seg.story_id
      where s.group_id = g.id
        and seg.author_id = gm.user_id
    ) as first_submission_at,
    (
      select max(seg.submitted_at)
      from public.segments seg
      join public.stories s on s.id = seg.story_id
      where s.group_id = g.id
        and seg.author_id = gm.user_id
    ) as last_submission_at
  from public.groups g
  join public.group_members gm on gm.group_id = g.id
  left join public.profiles p on p.id = gm.user_id
  where g.activity_id = p_activity_id
  order by g.created_at, g.name, gm.joined_at, gm.user_id;
end;
$$;

revoke all on function public.get_teacher_activity_csv(uuid) from public, anon;
grant execute on function public.get_teacher_activity_csv(uuid) to authenticated;

commit;
