-- CLASSROOM_100 Phase C2-B: relay/submission/dashboard capacity smoke test
--
-- Exercises a rollback-only 100-participant / 20-group classroom fixture.
-- For each group, starts a relay and performs 5 real submit_segment() calls,
-- yielding 100 submissions total and exercising next-writer selection.
-- Finally verifies the host dashboard can summarize all 20 groups.
--
-- Safety: all synthetic auth users, profiles, memberships, rounds, segments,
-- events, and activity data are created inside one transaction and rolled back.

begin;

do $$
declare
  v_host uuid;
  v_activity uuid := gen_random_uuid();
  v_group uuid := gen_random_uuid();
  v_story uuid := gen_random_uuid();
  v_code text := 'C2R-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
  v_user uuid;
  v_i integer;
  v_j integer;
  v_count integer;
  v_min integer;
  v_max integer;
  v_round jsonb;
  v_round_id uuid;
  v_writer_id uuid;
  v_starter uuid;
  v_dashboard_rows integer;
  v_checks integer := 0;
  v_failed text := null;
begin
  select p.id into v_host
  from public.profiles p
  order by p.id
  limit 1;

  if v_host is null then
    raise exception 'C2-B fixture requires at least one existing profile-backed host. No data was changed.';
  end if;

  -- Trusted SQL Editor creates an advanced-grouping fixture. Normal client
  -- creation remains gated to platform administrators by the product trigger.
  insert into public.activities (
    id, teacher_id, code, name, status, group_size, required_segments
  ) values (
    v_activity, v_host, v_code,
    'CLASSROOM_100 C2-B rollback fixture', 'active', 5, null
  );

  insert into public.groups (id, activity_id, name)
  values (v_group, v_activity, 'Group 1');

  insert into public.stories (id, group_id, title, status, required_segments)
  values (v_story, v_group, 'CLASSROOM_100 C2-B rollback fixture', 'active', null);

  -- Create 100 rollback-only auth users. The existing on_auth_user_created
  -- trigger creates public.profiles, preserving the real FK path.
  for v_i in 1..100 loop
    v_user := gen_random_uuid();

    insert into auth.users (
      id, aud, role, email, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at
    ) values (
      v_user,
      'authenticated',
      'authenticated',
      format('c2-relay-%s-%s@example.invalid', lpad(v_i::text, 3, '0'), substr(replace(v_user::text, '-', ''), 1, 8)),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('full_name', format('C2 Relay Participant %s', lpad(v_i::text, 3, '0'))),
      now(),
      now()
    );

    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', v_user::text, true);
    perform set_config(
      'request.jwt.claims',
      jsonb_build_object('sub', v_user, 'role', 'authenticated')::text,
      true
    );

    perform public.join_activity_by_code(v_code);
    perform set_config('role', 'none', true);
  end loop;

  -- Fixture sanity before relay work.
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

  -- For every group: any active member starts the first round; then execute five
  -- real submissions by whichever writer the database selected for each round.
  for v_group in
    select g.id
    from public.groups g
    where g.activity_id = v_activity
    order by g.created_at, g.name, g.id
  loop
    select gm.user_id into v_starter
    from public.group_members gm
    where gm.group_id = v_group
      and gm.role = 'student'
      and gm.left_at is null
    order by gm.joined_at, gm.user_id
    limit 1;

    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', v_starter::text, true);
    perform set_config(
      'request.jwt.claims',
      jsonb_build_object('sub', v_starter, 'role', 'authenticated')::text,
      true
    );

    v_round := public.start_relay_round(v_group);
    v_round_id := (v_round->>'round_id')::uuid;
    v_writer_id := (v_round->>'current_writer_id')::uuid;
    perform set_config('role', 'none', true);

    if v_round_id is null or v_writer_id is null then
      v_failed := concat_ws('; ', v_failed, 'start_relay_round returned incomplete data for group=' || v_group);
      exit;
    end if;

    for v_j in 1..5 loop
      perform set_config('role', 'authenticated', true);
      perform set_config('request.jwt.claim.sub', v_writer_id::text, true);
      perform set_config(
        'request.jwt.claims',
        jsonb_build_object('sub', v_writer_id, 'role', 'authenticated')::text,
        true
      );

      perform public.submit_segment(
        v_round_id,
        format('C2-B group %s relay submission %s', v_group::text, v_j)
      );

      perform set_config('role', 'none', true);

      -- submit_segment() must have completed the prior round and created exactly
      -- one next writing round. Read it as trusted SQL owner for the next call.
      select rr.id, rr.current_writer_id
      into v_round_id, v_writer_id
      from public.relay_rounds rr
      join public.stories s on s.id = rr.story_id
      where s.group_id = v_group
        and rr.status = 'writing'
      order by rr.round_no desc
      limit 1;

      if v_round_id is null or v_writer_id is null then
        v_failed := concat_ws('; ', v_failed, 'next round missing after group=' || v_group || ' submission=' || v_j);
        exit;
      end if;
    end loop;

    exit when v_failed is not null;
  end loop;

  perform set_config('role', 'none', true);

  -- 100 authored segments total (5 per group x 20 groups).
  select count(*) into v_count
  from public.segments seg
  join public.stories s on s.id = seg.story_id
  join public.groups g on g.id = s.group_id
  where g.activity_id = v_activity
    and seg.author_id is not null;
  v_checks := v_checks + 1;
  if v_count <> 100 then
    v_failed := concat_ws('; ', v_failed, 'authored_segment_count=' || v_count || ' expected=100');
  end if;

  -- Exactly 100 rounds completed and 20 next rounds remain writing.
  select count(*) into v_count
  from public.relay_rounds rr
  join public.stories s on s.id = rr.story_id
  join public.groups g on g.id = s.group_id
  where g.activity_id = v_activity
    and rr.status = 'completed';
  v_checks := v_checks + 1;
  if v_count <> 100 then
    v_failed := concat_ws('; ', v_failed, 'completed_round_count=' || v_count || ' expected=100');
  end if;

  select count(*) into v_count
  from public.relay_rounds rr
  join public.stories s on s.id = rr.story_id
  join public.groups g on g.id = s.group_id
  where g.activity_id = v_activity
    and rr.status = 'writing';
  v_checks := v_checks + 1;
  if v_count <> 20 then
    v_failed := concat_ws('; ', v_failed, 'writing_round_count=' || v_count || ' expected=20');
  end if;

  select count(*) into v_count
  from public.relay_rounds rr
  join public.stories s on s.id = rr.story_id
  join public.groups g on g.id = s.group_id
  where g.activity_id = v_activity;
  v_checks := v_checks + 1;
  if v_count <> 120 then
    v_failed := concat_ws('; ', v_failed, 'total_round_count=' || v_count || ' expected=120');
  end if;

  -- Writer-state accounting must match the 100 completed submissions.
  select coalesce(sum(ws.times_written), 0)::integer into v_count
  from public.writer_states ws
  join public.groups g on g.id = ws.group_id
  where g.activity_id = v_activity;
  v_checks := v_checks + 1;
  if v_count <> 100 then
    v_failed := concat_ws('; ', v_failed, 'times_written_sum=' || v_count || ' expected=100');
  end if;

  -- Per-group authored segment count must be exactly five.
  select min(segment_count), max(segment_count)
  into v_min, v_max
  from (
    select g.id, count(seg.id)::integer as segment_count
    from public.groups g
    join public.stories s on s.group_id = g.id
    left join public.segments seg on seg.story_id = s.id and seg.author_id is not null
    where g.activity_id = v_activity
    group by g.id
  ) x;
  v_checks := v_checks + 1;
  if v_min <> 5 or v_max <> 5 then
    v_failed := concat_ws('; ', v_failed, 'per_group_segment_range=' || coalesce(v_min::text,'NULL') || '..' || coalesce(v_max::text,'NULL') || ' expected=5..5');
  end if;

  -- Host dashboard must summarize all groups with the expected classroom state.
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', v_host::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', v_host, 'role', 'authenticated')::text,
    true
  );

  select count(*) into v_dashboard_rows
  from public.get_teacher_activity_dashboard(v_activity);

  v_checks := v_checks + 1;
  if v_dashboard_rows <> 20 then
    v_failed := concat_ws('; ', v_failed, 'dashboard_row_count=' || v_dashboard_rows || ' expected=20');
  end if;

  select min(d.member_count::integer), max(d.member_count::integer)
  into v_min, v_max
  from public.get_teacher_activity_dashboard(v_activity) d;
  v_checks := v_checks + 1;
  if v_min <> 5 or v_max <> 5 then
    v_failed := concat_ws('; ', v_failed, 'dashboard_member_range=' || coalesce(v_min::text,'NULL') || '..' || coalesce(v_max::text,'NULL') || ' expected=5..5');
  end if;

  select min(d.completed_segments::integer), max(d.completed_segments::integer)
  into v_min, v_max
  from public.get_teacher_activity_dashboard(v_activity) d;
  perform set_config('role', 'none', true);

  v_checks := v_checks + 1;
  if v_min <> 5 or v_max <> 5 then
    v_failed := concat_ws('; ', v_failed, 'dashboard_segment_range=' || coalesce(v_min::text,'NULL') || '..' || coalesce(v_max::text,'NULL') || ' expected=5..5');
  end if;

  if v_failed is not null then
    raise exception 'CLASSROOM_100 C2-B relay capacity smoke failed: %', v_failed;
  end if;

  raise notice 'CLASSROOM_100 C2-B relay capacity smoke passed | participants=100 | groups=20 | submissions=100 | completed_rounds=100 | writing_rounds=20 | dashboard_rows=20 | checks=% | fixture will be rolled back', v_checks;
end;
$$;

rollback;

select 'CLASSROOM_100 C2-B relay capacity smoke passed' as result;
