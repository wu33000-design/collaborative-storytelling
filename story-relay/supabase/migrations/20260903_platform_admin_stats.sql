-- Story Relay: platform-level administrator authorization and participation statistics.

begin;

create table if not exists public.platform_admins (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.platform_admins enable row level security;

-- No direct client reads or writes are needed. Platform-admin checks are exposed
-- only through SECURITY DEFINER functions below.
revoke all on table public.platform_admins from anon, authenticated;

create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
     and exists (
       select 1
       from public.platform_admins pa
       where pa.user_id = auth.uid()
     );
$$;

revoke all on function public.is_platform_admin() from public;
grant execute on function public.is_platform_admin() to authenticated;

create or replace function public.get_platform_member_stats()
returns table (
  user_id uuid,
  display_name text,
  activities_created bigint,
  activities_joined bigint,
  groups_joined bigint,
  rounds_selected bigint,
  segments_written bigint,
  total_characters bigint,
  first_joined_at timestamptz,
  last_submission_at timestamptz
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
    from public.platform_admins pa
    where pa.user_id = auth.uid()
  ) then
    raise exception 'Platform administrator access required';
  end if;

  return query
  select
    p.id as user_id,
    p.display_name,
    (select count(*) from public.activities a where a.teacher_id = p.id)::bigint as activities_created,
    (
      select count(distinct g.activity_id)
      from public.group_members gm
      join public.groups g on g.id = gm.group_id
      where gm.user_id = p.id
    )::bigint as activities_joined,
    (
      select count(distinct gm.group_id)
      from public.group_members gm
      where gm.user_id = p.id
    )::bigint as groups_joined,
    (
      select count(*)
      from public.relay_rounds rr
      where rr.current_writer_id = p.id
    )::bigint as rounds_selected,
    (
      select count(*)
      from public.segments s
      where s.author_id = p.id
    )::bigint as segments_written,
    coalesce((
      select sum(coalesce(s.word_count, char_length(s.content)))
      from public.segments s
      where s.author_id = p.id
    ), 0)::bigint as total_characters,
    (
      select min(gm.joined_at)
      from public.group_members gm
      where gm.user_id = p.id
    ) as first_joined_at,
    (
      select max(s.submitted_at)
      from public.segments s
      where s.author_id = p.id
    ) as last_submission_at
  from public.profiles p
  order by lower(coalesce(p.display_name, '')), p.id;
end;
$$;

revoke all on function public.get_platform_member_stats() from public;
grant execute on function public.get_platform_member_stats() to authenticated;

commit;
