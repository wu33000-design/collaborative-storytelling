-- Story Relay: platform administration console.
-- Adds platform overview, activity management, participant detail, and
-- platform-admin allowlist management. All access is gated server-side.

begin;

create or replace function public.get_platform_overview()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not exists (select 1 from public.platform_admins pa where pa.user_id = auth.uid()) then
    raise exception 'Platform administrator access required';
  end if;

  return jsonb_build_object(
    'members', (select count(*) from public.profiles),
    'activities', (select count(*) from public.activities),
    'active_activities', (select count(*) from public.activities where status = 'active'),
    'active_members_7d', (
      select count(distinct ae.actor_id)
      from public.activity_events ae
      where ae.actor_id is not null
        and ae.created_at >= now() - interval '7 days'
    ),
    'segments', (select count(*) from public.segments),
    'characters', (
      select coalesce(sum(coalesce(s.word_count, char_length(s.content))), 0)
      from public.segments s
    )
  );
end;
$$;

revoke all on function public.get_platform_overview() from public;
grant execute on function public.get_platform_overview() to authenticated;

create or replace function public.get_platform_activity_stats()
returns table (
  activity_id uuid,
  code text,
  name text,
  status text,
  host_user_id uuid,
  host_name text,
  host_email text,
  participant_count bigint,
  group_count bigint,
  segment_count bigint,
  created_at timestamptz,
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
  if not exists (select 1 from public.platform_admins pa where pa.user_id = auth.uid()) then
    raise exception 'Platform administrator access required';
  end if;

  return query
  select
    a.id,
    a.code,
    a.name,
    a.status,
    a.teacher_id,
    p.display_name,
    pmi.login_email,
    (
      select count(distinct gm.user_id)
      from public.groups g
      join public.group_members gm on gm.group_id = g.id
      where g.activity_id = a.id and gm.left_at is null
    )::bigint,
    (select count(*) from public.groups g where g.activity_id = a.id)::bigint,
    (
      select count(*)
      from public.groups g
      join public.stories s on s.group_id = g.id
      join public.segments sg on sg.story_id = s.id
      where g.activity_id = a.id
    )::bigint,
    a.created_at,
    coalesce((select max(ae.created_at) from public.activity_events ae where ae.activity_id = a.id), a.created_at)
  from public.activities a
  left join public.profiles p on p.id = a.teacher_id
  left join public.platform_member_identities pmi on pmi.user_id = a.teacher_id
  order by a.created_at desc;
end;
$$;

revoke all on function public.get_platform_activity_stats() from public;
grant execute on function public.get_platform_activity_stats() to authenticated;

create or replace function public.get_platform_member_activities(p_user_id uuid)
returns table (
  activity_id uuid,
  code text,
  name text,
  activity_status text,
  relation text,
  group_count bigint,
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
  if not exists (select 1 from public.platform_admins pa where pa.user_id = auth.uid()) then
    raise exception 'Platform administrator access required';
  end if;

  return query
  with related as (
    select a.id
    from public.activities a
    where a.teacher_id = p_user_id
    union
    select g.activity_id
    from public.group_members gm
    join public.groups g on g.id = gm.group_id
    where gm.user_id = p_user_id
  )
  select
    a.id,
    a.code,
    a.name,
    a.status,
    case
      when a.teacher_id = p_user_id and exists (
        select 1 from public.group_members gm join public.groups g on g.id = gm.group_id
        where gm.user_id = p_user_id and g.activity_id = a.id
      ) then 'host_and_participant'
      when a.teacher_id = p_user_id then 'host'
      else 'participant'
    end,
    (
      select count(distinct gm.group_id)
      from public.group_members gm
      join public.groups g on g.id = gm.group_id
      where gm.user_id = p_user_id and g.activity_id = a.id
    )::bigint,
    (
      select count(*)
      from public.relay_rounds rr
      join public.stories s on s.id = rr.story_id
      join public.groups g on g.id = s.group_id
      where rr.current_writer_id = p_user_id and g.activity_id = a.id
    )::bigint,
    (
      select count(*)
      from public.segments sg
      join public.stories s on s.id = sg.story_id
      join public.groups g on g.id = s.group_id
      where sg.author_id = p_user_id and g.activity_id = a.id
    )::bigint,
    coalesce((
      select sum(coalesce(sg.word_count, char_length(sg.content)))
      from public.segments sg
      join public.stories s on s.id = sg.story_id
      join public.groups g on g.id = s.group_id
      where sg.author_id = p_user_id and g.activity_id = a.id
    ), 0)::bigint,
    (
      select min(gm.joined_at)
      from public.group_members gm
      join public.groups g on g.id = gm.group_id
      where gm.user_id = p_user_id and g.activity_id = a.id
    ),
    (
      select max(sg.submitted_at)
      from public.segments sg
      join public.stories s on s.id = sg.story_id
      join public.groups g on g.id = s.group_id
      where sg.author_id = p_user_id and g.activity_id = a.id
    )
  from public.activities a
  join related r on r.id = a.id
  order by a.created_at desc;
end;
$$;

revoke all on function public.get_platform_member_activities(uuid) from public;
grant execute on function public.get_platform_member_activities(uuid) to authenticated;

create or replace function public.get_platform_admins()
returns table (
  user_id uuid,
  display_name text,
  login_email text,
  created_at timestamptz,
  is_current_user boolean
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not exists (select 1 from public.platform_admins pa where pa.user_id = auth.uid()) then
    raise exception 'Platform administrator access required';
  end if;

  return query
  select pa.user_id, p.display_name, pmi.login_email, pa.created_at, pa.user_id = auth.uid()
  from public.platform_admins pa
  left join public.profiles p on p.id = pa.user_id
  left join public.platform_member_identities pmi on pmi.user_id = pa.user_id
  order by pa.created_at;
end;
$$;

revoke all on function public.get_platform_admins() from public;
grant execute on function public.get_platform_admins() to authenticated;

create or replace function public.add_platform_admin_by_email(p_email text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_email text := lower(nullif(trim(p_email), ''));
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists (select 1 from public.platform_admins pa where pa.user_id = auth.uid()) then
    raise exception 'Platform administrator access required';
  end if;
  if v_email is null then raise exception 'Email is required'; end if;

  select pmi.user_id into v_user_id
  from public.platform_member_identities pmi
  where lower(pmi.login_email) = v_email
  limit 1;

  if v_user_id is null then
    raise exception 'No synced platform account found for this email';
  end if;

  insert into public.platform_admins (user_id)
  values (v_user_id)
  on conflict (user_id) do nothing;

  return v_user_id;
end;
$$;

revoke all on function public.add_platform_admin_by_email(text) from public;
grant execute on function public.add_platform_admin_by_email(text) to authenticated;

create or replace function public.remove_platform_admin(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists (select 1 from public.platform_admins pa where pa.user_id = auth.uid()) then
    raise exception 'Platform administrator access required';
  end if;
  if not exists (select 1 from public.platform_admins pa where pa.user_id = p_user_id) then
    return;
  end if;
  if (select count(*) from public.platform_admins) <= 1 then
    raise exception 'Cannot remove the last platform administrator';
  end if;

  delete from public.platform_admins where user_id = p_user_id;
end;
$$;

revoke all on function public.remove_platform_admin(uuid) from public;
grant execute on function public.remove_platform_admin(uuid) to authenticated;

commit;
