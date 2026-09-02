-- Story Relay: flexible activity lifecycle
-- Blank limits are represented as NULL (unlimited / no automatic constraint).

begin;

-- Optional activity metadata and limits.
alter table public.activities alter column name drop not null;
alter table public.activities alter column prompt drop not null;
alter table public.activities alter column initial_text drop not null;
alter table public.activities alter column group_size drop not null;
alter table public.activities alter column group_size drop default;
alter table public.activities alter column time_limit_seconds drop not null;
alter table public.activities alter column time_limit_seconds drop default;
alter table public.activities alter column min_words drop not null;
alter table public.activities alter column min_words drop default;
alter table public.activities alter column max_words drop not null;
alter table public.activities alter column max_words drop default;
alter table public.activities alter column required_segments drop not null;
alter table public.activities alter column required_segments drop default;

-- A story can also be open-ended.
alter table public.stories alter column required_segments drop not null;
alter table public.stories alter column required_segments drop default;

-- Writer 0 is virtual, so the seed segment may have no profile author.
alter table public.segments alter column author_id drop not null;

create or replace function public.create_activity(
  p_name text default null,
  p_prompt text default null,
  p_initial_text text default null,
  p_group_size integer default null,
  p_time_limit_seconds integer default null,
  p_min_words integer default null,
  p_max_words integer default null,
  p_required_segments integer default null,
  p_deadline timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_activity_id uuid;
  v_group_id uuid;
  v_story_id uuid;
  v_code text;
  v_attempt integer := 0;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if p_group_size is not null and p_group_size <= 0 then
    raise exception 'group_size must be greater than 0';
  end if;
  if p_time_limit_seconds is not null and p_time_limit_seconds <= 0 then
    raise exception 'time_limit_seconds must be greater than 0';
  end if;
  if p_min_words is not null and p_min_words < 0 then
    raise exception 'min_words must be 0 or greater';
  end if;
  if p_max_words is not null and p_max_words < 0 then
    raise exception 'max_words must be 0 or greater';
  end if;
  if p_min_words is not null and p_max_words is not null and p_min_words > p_max_words then
    raise exception 'min_words cannot exceed max_words';
  end if;
  if p_required_segments is not null and p_required_segments <= 0 then
    raise exception 'required_segments must be greater than 0';
  end if;

  loop
    v_attempt := v_attempt + 1;
    v_code := 'SR-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
    exit when not exists (select 1 from public.activities where code = v_code);
    if v_attempt >= 20 then
      raise exception 'Unable to generate a unique activity code';
    end if;
  end loop;

  insert into public.activities (
    teacher_id, code, name, prompt, initial_text, group_size,
    time_limit_seconds, min_words, max_words, required_segments,
    deadline, status
  ) values (
    v_user_id,
    v_code,
    nullif(trim(p_name), ''),
    nullif(trim(p_prompt), ''),
    nullif(trim(p_initial_text), ''),
    p_group_size,
    p_time_limit_seconds,
    p_min_words,
    p_max_words,
    p_required_segments,
    p_deadline,
    'active'
  ) returning id into v_activity_id;

  insert into public.groups (activity_id, name)
  values (v_activity_id, 'Group 1')
  returning id into v_group_id;

  insert into public.stories (group_id, title, prompt, required_segments, status)
  values (
    v_group_id,
    nullif(trim(p_name), ''),
    nullif(trim(p_prompt), ''),
    p_required_segments,
    'active'
  ) returning id into v_story_id;

  if nullif(trim(p_initial_text), '') is not null then
    insert into public.segments (
      story_id, sequence_no, author_id, content, word_count
    ) values (
      v_story_id,
      0,
      null,
      trim(p_initial_text),
      char_length(trim(p_initial_text))
    );
  end if;

  insert into public.activity_events (activity_id, group_id, type, actor_id, payload)
  values (
    v_activity_id,
    v_group_id,
    'activity_created',
    v_user_id,
    jsonb_build_object('code', v_code)
  );

  return jsonb_build_object(
    'activity_id', v_activity_id,
    'code', v_code,
    'group_id', v_group_id,
    'story_id', v_story_id
  );
end;
$$;

revoke all on function public.create_activity(text,text,text,integer,integer,integer,integer,integer,timestamptz) from public;
grant execute on function public.create_activity(text,text,text,integer,integer,integer,integer,integer,timestamptz) to authenticated;

-- Joining remains possible while the activity is active. A late joiner starts
-- at waiting_rounds=0 / weight=1 and participates in future selections only.
-- The advisory lock prevents concurrent joins from overfilling a finite group.
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
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select * into v_activity
  from public.activities
  where upper(trim(code)) = upper(trim(p_code))
    and status = 'active'
    and (deadline is null or deadline > now())
  limit 1;

  if v_activity.id is null then
    raise exception 'Active activity not found';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_activity.id::text, 0));

  select gm.group_id into v_group_id
  from public.group_members gm
  join public.groups g on g.id = gm.group_id
  where gm.user_id = v_user_id
    and gm.left_at is null
    and g.activity_id = v_activity.id
  limit 1;

  if v_group_id is not null then
    return v_group_id;
  end if;

  select g.id into v_group_id
  from public.groups g
  left join public.group_members gm
    on gm.group_id = g.id
   and gm.left_at is null
   and gm.role = 'student'
  where g.activity_id = v_activity.id
  group by g.id, g.created_at
  having v_activity.group_size is null
      or count(gm.user_id) < v_activity.group_size
  order by count(gm.user_id), g.created_at
  limit 1;

  if v_group_id is null then
    select count(*) + 1 into v_group_no
    from public.groups
    where activity_id = v_activity.id;

    insert into public.groups (activity_id, name)
    values (v_activity.id, 'Group ' || v_group_no)
    returning id into v_group_id;

    insert into public.stories (group_id, title, prompt, required_segments, status)
    values (
      v_group_id,
      v_activity.name,
      v_activity.prompt,
      v_activity.required_segments,
      'active'
    ) returning id into v_story_id;

    if nullif(trim(v_activity.initial_text), '') is not null then
      insert into public.segments (
        story_id, sequence_no, author_id, content, word_count
      ) values (
        v_story_id,
        0,
        null,
        trim(v_activity.initial_text),
        char_length(trim(v_activity.initial_text))
      );
    end if;
  end if;

  insert into public.group_members (group_id, user_id, role)
  values (v_group_id, v_user_id, 'student');

  insert into public.writer_states (
    group_id, user_id, times_written, waiting_rounds, selection_weight
  ) values (
    v_group_id, v_user_id, 0, 0, 1
  )
  on conflict (group_id, user_id) do update
  set waiting_rounds = 0,
      selection_weight = 1,
      updated_at = now();

  insert into public.activity_events (activity_id, group_id, type, actor_id, payload)
  values (
    v_activity.id,
    v_group_id,
    'student_joined',
    v_user_id,
    '{}'::jsonb
  );

  return v_group_id;
end;
$$;

revoke all on function public.join_activity_by_code(text) from public;
grant execute on function public.join_activity_by_code(text) to authenticated;

create or replace function public.stop_activity(p_activity_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1
    from public.activities
    where id = p_activity_id
      and teacher_id = v_user_id
  ) then
    raise exception 'Only the activity teacher can stop this activity';
  end if;

  update public.activities
  set status = 'closed'
  where id = p_activity_id
    and status <> 'closed';

  update public.stories s
  set status = 'closed',
      completed_at = coalesce(completed_at, now())
  from public.groups g
  where s.group_id = g.id
    and g.activity_id = p_activity_id
    and s.status = 'active';

  update public.relay_rounds rr
  set status = 'expired',
      completed_at = coalesce(completed_at, now())
  from public.stories s
  join public.groups g on g.id = s.group_id
  where rr.story_id = s.id
    and g.activity_id = p_activity_id
    and rr.status in ('open', 'writing');

  insert into public.activity_events (activity_id, type, actor_id, payload)
  values (p_activity_id, 'activity_stopped', v_user_id, '{}'::jsonb);
end;
$$;

revoke all on function public.stop_activity(uuid) from public;
grant execute on function public.stop_activity(uuid) to authenticated;

commit;
