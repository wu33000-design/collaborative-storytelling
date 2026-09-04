-- CLASSROOM_100 Phase C2-A: 100-participant join/grouping smoke test
--
-- Purpose:
--   Exercise the real join_activity_by_code() RPC 100 times with distinct
--   rollback-only auth identities and verify finite grouping invariants.
--
-- Safety:
--   Synthetic auth.users rows, trigger-created profiles, memberships, groups,
--   stories, writer states, and events are all created inside one transaction
--   and ALWAYS rolled back.

begin;

do $$
declare
  v_host uuid;
  v_activity uuid := gen_random_uuid();
  v_group uuid := gen_random_uuid();
  v_story uuid := gen_random_uuid();
  v_code text := 'C2-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
  v_user uuid;
  v_joined_group uuid;
  v_first_user uuid;
  v_first_group uuid;
  v_i integer;
  v_count integer;
  v_min integer;
  v_max integer;
  v_checks integer := 0;
  v_failed text := null;
begin
  select p.id into v_host
  from public.profiles p
  order by p.id
  limit 1;

  if v_host is null then
    raise exception 'C2 fixture requires at least one existing profile-backed account. No data was changed.';
  end if;

  insert into public.activities (
    id, teacher_id, code, name, status, group_size
  ) values (
    v_activity, v_host, v_code, 'CLASSROOM_100 C2 rollback fixture', 'active', 5
  );

  insert into public.groups (id, activity_id, name)
  values (v_group, v_activity, 'Group 1');

  insert into public.stories (id, group_id, title, status)
  values (v_story, v_group, 'CLASSROOM_100 C2 rollback fixture', 'active');

  for v_i in 1..100 loop
    v_user := gen_random_uuid();
    if v_i = 1 then v_first_user := v_user; end if;

    -- Insert a rollback-only auth identity. The existing on_auth_user_created
    -- trigger calls public.handle_new_user(), which creates public.profiles.
    insert into auth.users (
      id,
      aud,
      role,
      email,
      raw_app_meta_data,
      raw_user_meta_data,
      created_at,
      updated_at,
      is_sso_user,
      is_anonymous
    ) values (
      v_user,
      'authenticated',
      'authenticated',
      format('c2-participant-%s-%s@example.invalid', lpad(v_i::text, 3, '0'), substr(replace(v_user::text, '-', ''), 1, 8)),
      '{}'::jsonb,
      jsonb_build_object('full_name', format('C2 Participant %s', lpad(v_i::text, 3, '0'))),
      now(),
      now(),
      false,
      false
    );

    -- Positive fixture check: auth trigger must have created the profile.
    if not exists (select 1 from public.profiles p where p.id = v_user) then
      raise exception 'C2 auth fixture trigger did not create profile for participant %', v_i;
    end if;

    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', v_user::text, true);
    perform set_config(
      'request.jwt.claims',
      jsonb_build_object('sub', v_user, 'role', 'authenticated')::text,
      true
    );

    v_joined_group := public.join_activity_by_code(v_code);
    if v_i = 1 then v_first_group := v_joined_group; end if;

    if v_joined_group is null then
      v_failed := concat_ws('; ', v_failed, 'join returned NULL at participant ' || v_i);
      exit;
    end if;

    perform set_config('role', 'none', true);
  end loop;

  perform set_config('role', 'none', true);

  select count(*) into v_count
  from public.group_members gm
  join public.groups g on g.id = gm.group_id
  where g.activity_id = v_activity
    and gm.role = 'student'
    and gm.left_at is null;
  v_checks := v_checks + 1;
  if v_count <> 100 then
    v_failed := concat_ws('; ', v_failed, 'member_count=' || v_count || ' expected=100');
  end if;

  select count(*) into v_count
  from public.groups g
  where g.activity_id = v_activity;
  v_checks := v_checks + 1;
  if v_count <> 20 then
    v_failed := concat_ws('; ', v_failed, 'group_count=' || v_count || ' expected=20');
  end if;

  select min(member_count), max(member_count)
  into v_min, v_max
  from (
    select g.id, count(gm.user_id)::integer as member_count
    from public.groups g
    left join public.group_members gm
      on gm.group_id = g.id
     and gm.role = 'student'
     and gm.left_at is null
    where g.activity_id = v_activity
    group by g.id
  ) x;
  v_checks := v_checks + 1;
  if v_min <> 5 or v_max <> 5 then
    v_failed := concat_ws('; ', v_failed, 'group_size range=' || coalesce(v_min::text,'NULL') || '..' || coalesce(v_max::text,'NULL') || ' expected=5..5');
  end if;

  select count(*) into v_count
  from public.writer_states ws
  join public.groups g on g.id = ws.group_id
  where g.activity_id = v_activity;
  v_checks := v_checks + 1;
  if v_count <> 100 then
    v_failed := concat_ws('; ', v_failed, 'writer_state_count=' || v_count || ' expected=100');
  end if;

  select count(*) into v_count
  from public.stories s
  join public.groups g on g.id = s.group_id
  where g.activity_id = v_activity
    and s.status = 'active';
  v_checks := v_checks + 1;
  if v_count <> 20 then
    v_failed := concat_ws('; ', v_failed, 'active_story_count=' || v_count || ' expected=20');
  end if;

  -- Confirm all 100 synthetic auth identities produced profiles.
  select count(*) into v_count
  from public.profiles p
  join auth.users u on u.id = p.id
  where u.email like 'c2-participant-%@example.invalid';
  v_checks := v_checks + 1;
  if v_count <> 100 then
    v_failed := concat_ws('; ', v_failed, 'trigger_created_profile_count=' || v_count || ' expected=100');
  end if;

  -- Repeat-join idempotency positive control.
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', v_first_user::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', v_first_user, 'role', 'authenticated')::text,
    true
  );
  v_joined_group := public.join_activity_by_code(v_code);
  perform set_config('role', 'none', true);

  v_checks := v_checks + 1;
  if v_joined_group is distinct from v_first_group then
    v_failed := concat_ws('; ', v_failed, 'repeat join returned a different group');
  end if;

  select count(*) into v_count
  from public.group_members gm
  join public.groups g on g.id = gm.group_id
  where g.activity_id = v_activity
    and gm.user_id = v_first_user
    and gm.left_at is null;
  v_checks := v_checks + 1;
  if v_count <> 1 then
    v_failed := concat_ws('; ', v_failed, 'repeat join membership_count=' || v_count || ' expected=1');
  end if;

  if v_failed is not null then
    raise exception 'CLASSROOM_100 C2-A join capacity smoke failed: %', v_failed;
  end if;

  raise notice 'CLASSROOM_100 C2-A join capacity smoke passed | participants=100 | groups=20 | group_size=5 | checks=% | fixture will be rolled back', v_checks;
end;
$$;

rollback;

select 'CLASSROOM_100 C2-A join capacity smoke passed' as result;
