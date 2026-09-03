-- Story Relay: keep authenticated login email for platform-level identity mapping.
-- Email is never exposed through ordinary profile/table reads. A user may only
-- sync the email asserted by their own authenticated JWT; platform admins read
-- it through the protected statistics RPC.

begin;

create table if not exists public.platform_member_identities (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  login_email text not null,
  synced_at timestamptz not null default now()
);

alter table public.platform_member_identities enable row level security;
revoke all on table public.platform_member_identities from anon, authenticated;

create or replace function public.sync_my_login_identity()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_email text := nullif(trim(auth.jwt() ->> 'email'), '');
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if v_email is null then
    raise exception 'Authenticated email is unavailable';
  end if;

  insert into public.platform_member_identities (user_id, login_email, synced_at)
  values (v_user_id, lower(v_email), now())
  on conflict (user_id) do update
  set login_email = excluded.login_email,
      synced_at = excluded.synced_at;
end;
$$;

revoke all on function public.sync_my_login_identity() from public;
grant execute on function public.sync_my_login_identity() to authenticated;

-- PostgreSQL cannot CREATE OR REPLACE a function when the OUT-column row type
-- changes. Drop and recreate this zero-argument RPC before adding login_email.
drop function if exists public.get_platform_member_stats();

create function public.get_platform_member_stats()
returns table (
  user_id uuid,
  display_name text,
  login_email text,
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
    pmi.login_email,
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
  left join public.platform_member_identities pmi on pmi.user_id = p.id
  order by lower(coalesce(pmi.login_email, '')), lower(coalesce(p.display_name, '')), p.id;
end;
$$;

revoke all on function public.get_platform_member_stats() from public;
grant execute on function public.get_platform_member_stats() to authenticated;

commit;
