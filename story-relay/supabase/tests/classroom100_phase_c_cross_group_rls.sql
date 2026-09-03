-- CLASSROOM_100 Phase C: cross-group RLS role test
--
-- Purpose:
--   Verify the classroom isolation property with real RLS.
--   With >=3 profile-backed accounts, run symmetric participant A/B isolation.
--   With exactly 2 accounts, use one account as host + Group A member and verify
--   the non-host Group B participant cannot read Group A; anon must see neither.
--
-- Safety:
--   All fixture rows are created inside one transaction and ALWAYS rolled back.
--   No auth users are created and no fixture data remains.
--
-- Implementation note:
--   This version deliberately avoids temporary tables because Supabase SQL Editor
--   role switching can make pg_temp objects unavailable to authenticated/anon.

begin;

do $$
declare
  v_host uuid;
  v_a uuid;
  v_b uuid;
  v_mode text;

  v_activity uuid := gen_random_uuid();
  v_ga uuid := gen_random_uuid();
  v_gb uuid := gen_random_uuid();
  v_sa uuid := gen_random_uuid();
  v_sb uuid := gen_random_uuid();
  v_sega uuid := gen_random_uuid();
  v_segb uuid := gen_random_uuid();
  v_ra uuid := gen_random_uuid();
  v_rb uuid := gen_random_uuid();

  v_count integer;
  v_checks integer := 0;
  v_failed text := null;

  procedure assert_count(p_role text, p_check text, p_observed integer, p_expected integer)
  language plpgsql
  as $proc$
  begin
    v_checks := v_checks + 1;
    if p_observed <> p_expected then
      v_failed := concat_ws('; ', v_failed,
        p_role || ':' || p_check || ' observed=' || p_observed || ' expected=' || p_expected);
    end if;
  end;
  $proc$;
begin
  -- Pick a host below the 3-activity cap.
  select p.id
  into v_host
  from public.profiles p
  left join public.activities a
    on a.teacher_id = p.id
   and a.deleted_at is null
  group by p.id
  having count(a.id) < 3
  order by count(a.id), p.id
  limit 1;

  select p.id
  into v_b
  from public.profiles p
  where p.id <> v_host
  order by p.id
  limit 1;

  if v_host is null or v_b is null then
    raise exception 'C1 fixture requires at least 2 existing profile-backed accounts. No data was changed.';
  end if;

  select p.id
  into v_a
  from public.profiles p
  where p.id <> v_host
    and p.id <> v_b
  order by p.id
  limit 1;

  if v_a is null then
    v_mode := 'TWO_ACCOUNT_ONE_WAY';
    v_a := v_host;
  else
    v_mode := 'THREE_ACCOUNT_SYMMETRIC';
  end if;

  -- Create rollback-only fixture as SQL Editor owner before role simulation.
  insert into public.activities (id, teacher_id, code, name, status, group_size)
  values (
    v_activity,
    v_host,
    'C1-' || upper(substr(replace(v_activity::text, '-', ''), 1, 6)),
    'CLASSROOM_100 C1 rollback fixture',
    'active',
    1
  );

  insert into public.groups (id, activity_id, name)
  values (v_ga, v_activity, 'C1 Group A'),
         (v_gb, v_activity, 'C1 Group B');

  insert into public.stories (id, group_id, title, status)
  values (v_sa, v_ga, 'C1 Story A', 'active'),
         (v_sb, v_gb, 'C1 Story B', 'active');

  insert into public.group_members (group_id, user_id, role)
  values (v_ga, v_a, 'student'),
         (v_gb, v_b, 'student');

  insert into public.writer_states (group_id, user_id, times_written, waiting_rounds, selection_weight)
  values (v_ga, v_a, 0, 0, 1),
         (v_gb, v_b, 0, 0, 1)
  on conflict (group_id, user_id) do nothing;

  insert into public.segments (id, story_id, sequence_no, author_id, content, word_count)
  values (v_sega, v_sa, 1, v_a, 'C1-A', 4),
         (v_segb, v_sb, 1, v_b, 'C1-B', 4);

  insert into public.relay_rounds (id, story_id, round_no, current_writer_id, status)
  values (v_ra, v_sa, 1, v_a, 'writing'),
         (v_rb, v_sb, 1, v_b, 'writing');

  -- Participant B: always a non-host participant.
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', v_b::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_b, 'role', 'authenticated')::text, true);

  select count(*) into v_count from public.groups where id = v_gb;
  call assert_count('participant_b', 'own_group', v_count, 1);
  select count(*) into v_count from public.groups where id = v_ga;
  call assert_count('participant_b', 'other_group', v_count, 0);

  select count(*) into v_count from public.stories where id = v_sb;
  call assert_count('participant_b', 'own_story', v_count, 1);
  select count(*) into v_count from public.stories where id = v_sa;
  call assert_count('participant_b', 'other_story', v_count, 0);

  select count(*) into v_count from public.segments where id = v_segb;
  call assert_count('participant_b', 'own_segment', v_count, 1);
  select count(*) into v_count from public.segments where id = v_sega;
  call assert_count('participant_b', 'other_segment', v_count, 0);

  select count(*) into v_count from public.relay_rounds where id = v_rb;
  call assert_count('participant_b', 'own_round', v_count, 1);
  select count(*) into v_count from public.relay_rounds where id = v_ra;
  call assert_count('participant_b', 'other_round', v_count, 0);

  -- Participant A symmetric test only when A is not also the activity host.
  if v_mode = 'THREE_ACCOUNT_SYMMETRIC' then
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    perform set_config('request.jwt.claims', jsonb_build_object('sub', v_a, 'role', 'authenticated')::text, true);

    select count(*) into v_count from public.groups where id = v_ga;
    call assert_count('participant_a', 'own_group', v_count, 1);
    select count(*) into v_count from public.groups where id = v_gb;
    call assert_count('participant_a', 'other_group', v_count, 0);

    select count(*) into v_count from public.stories where id = v_sa;
    call assert_count('participant_a', 'own_story', v_count, 1);
    select count(*) into v_count from public.stories where id = v_sb;
    call assert_count('participant_a', 'other_story', v_count, 0);

    select count(*) into v_count from public.segments where id = v_sega;
    call assert_count('participant_a', 'own_segment', v_count, 1);
    select count(*) into v_count from public.segments where id = v_segb;
    call assert_count('participant_a', 'other_segment', v_count, 0);

    select count(*) into v_count from public.relay_rounds where id = v_ra;
    call assert_count('participant_a', 'own_round', v_count, 1);
    select count(*) into v_count from public.relay_rounds where id = v_rb;
    call assert_count('participant_a', 'other_round', v_count, 0);
  end if;

  -- Anonymous user must not see fixture content.
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);

  select count(*) into v_count from public.groups where id = v_ga;
  call assert_count('anon', 'group_a_hidden', v_count, 0);
  select count(*) into v_count from public.stories where id = v_sa;
  call assert_count('anon', 'story_a_hidden', v_count, 0);
  select count(*) into v_count from public.segments where id = v_sega;
  call assert_count('anon', 'segment_a_hidden', v_count, 0);
  select count(*) into v_count from public.relay_rounds where id = v_ra;
  call assert_count('anon', 'round_a_hidden', v_count, 0);

  -- Restore SQL Editor role before reporting.
  perform set_config('role', 'none', true);

  if v_failed is not null then
    raise exception 'CLASSROOM_100 C1 cross-group RLS failed: %', v_failed;
  end if;

  raise notice 'CLASSROOM_100 C1 cross-group RLS passed | mode=% | checks=% | fixture will be rolled back',
    v_mode, v_checks;
end;
$$;

rollback;

-- If the query finishes successfully, the DO block raised no exception and all
-- fixture data has been rolled back.
select 'CLASSROOM_100 C1 cross-group RLS passed' as result;
