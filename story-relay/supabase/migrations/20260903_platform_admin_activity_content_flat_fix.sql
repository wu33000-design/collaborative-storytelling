-- Story Relay: repair platform-admin activity content inspection with a flat, auditable snapshot.
-- Avoid deep nested JSON aggregation so groups/stories/segments/rounds cannot disappear as a whole.

begin;

create or replace function public.get_platform_activity_content(p_activity_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1 from public.platform_admins pa where pa.user_id = auth.uid()
  ) then
    raise exception 'Platform administrator access required';
  end if;

  if not exists (select 1 from public.activities a where a.id = p_activity_id) then
    raise exception 'Activity not found';
  end if;

  select jsonb_build_object(
    'activity', jsonb_build_object(
      'id', a.id,
      'code', a.code,
      'name', a.name,
      'prompt', a.prompt,
      'initial_text', a.initial_text,
      'status', a.status,
      'group_size', a.group_size,
      'time_limit_seconds', a.time_limit_seconds,
      'min_words', a.min_words,
      'max_words', a.max_words,
      'required_segments', a.required_segments,
      'deadline', a.deadline,
      'created_at', a.created_at,
      'deleted_at', a.deleted_at,
      'purge_after', a.purge_after,
      'host_user_id', a.teacher_id,
      'host_name', hp.display_name,
      'host_email', hpi.login_email
    ),
    'groups', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', g.id,
        'name', g.name,
        'created_at', g.created_at
      ) order by g.created_at, g.id)
      from public.groups g
      where g.activity_id = a.id
    ), '[]'::jsonb),
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
        'group_id', gm.group_id,
        'user_id', gm.user_id,
        'display_name', p.display_name,
        'email', pi.login_email,
        'role', gm.role,
        'joined_at', gm.joined_at,
        'left_at', gm.left_at
      ) order by gm.group_id, gm.joined_at, gm.user_id)
      from public.group_members gm
      join public.groups g on g.id = gm.group_id
      left join public.profiles p on p.id = gm.user_id
      left join public.platform_member_identities pi on pi.user_id = gm.user_id
      where g.activity_id = a.id
    ), '[]'::jsonb),
    'stories', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id,
        'group_id', s.group_id,
        'title', s.title,
        'prompt', s.prompt,
        'status', s.status,
        'required_segments', s.required_segments,
        'completed_at', s.completed_at
      ) order by s.group_id, s.id)
      from public.stories s
      join public.groups g on g.id = s.group_id
      where g.activity_id = a.id
    ), '[]'::jsonb),
    'segments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', sg.id,
        'story_id', sg.story_id,
        'sequence_no', sg.sequence_no,
        'author_id', sg.author_id,
        'author_name', ap.display_name,
        'author_email', api.login_email,
        'content', sg.content,
        'character_count', coalesce(sg.word_count, char_length(sg.content)),
        'submitted_at', sg.submitted_at
      ) order by sg.story_id, sg.sequence_no, sg.submitted_at, sg.id)
      from public.segments sg
      join public.stories s on s.id = sg.story_id
      join public.groups g on g.id = s.group_id
      left join public.profiles ap on ap.id = sg.author_id
      left join public.platform_member_identities api on api.user_id = sg.author_id
      where g.activity_id = a.id
    ), '[]'::jsonb),
    'rounds', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', rr.id,
        'story_id', rr.story_id,
        'round_no', rr.round_no,
        'current_writer_id', rr.current_writer_id,
        'current_writer_name', rp.display_name,
        'status', rr.status,
        'started_at', rr.started_at,
        'completed_at', rr.completed_at
      ) order by rr.story_id, rr.round_no, rr.started_at, rr.id)
      from public.relay_rounds rr
      join public.stories s on s.id = rr.story_id
      join public.groups g on g.id = s.group_id
      left join public.profiles rp on rp.id = rr.current_writer_id
      where g.activity_id = a.id
    ), '[]'::jsonb)
  ) into v_result
  from public.activities a
  left join public.profiles hp on hp.id = a.teacher_id
  left join public.platform_member_identities hpi on hpi.user_id = a.teacher_id
  where a.id = p_activity_id;

  return v_result;
end;
$$;

revoke all on function public.get_platform_activity_content(uuid) from public, anon;
grant execute on function public.get_platform_activity_content(uuid) to authenticated;

commit;
