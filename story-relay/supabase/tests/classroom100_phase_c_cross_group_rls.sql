-- CLASSROOM_100 Phase C: cross-group RLS role test
--
-- Purpose:
--   Verify the classroom isolation property with real RLS.
--   With >=3 profile-backed accounts, run symmetric participant A/B isolation.
--   With exactly 2 accounts, use one account as host + Group A member and verify
--   the non-host Group B participant cannot read Group A; anon must see neither.
--
-- Safety:
--   This script creates fixture rows inside one transaction and ALWAYS rolls the
--   transaction back. It does not create auth users and leaves no fixture data.

begin;

create temp table classroom100_fixture (
  mode text not null,
  host_user_id uuid not null,
  user_a_id uuid not null,
  user_b_id uuid not null,
  activity_id uuid not null,
  group_a_id uuid not null,
  group_b_id uuid not null,
  story_a_id uuid not null,
  story_b_id uuid not null,
  segment_a_id uuid not null,
  segment_b_id uuid not null,
  round_a_id uuid not null,
  round_b_id uuid not null
) on commit drop;

create temp table classroom100_results (
  role_name text not null,
  check_name text not null,
  observed integer not null,
  expected integer not null,
  passed boolean not null
) on commit drop;

grant select on pg_temp.classroom100_fixture to anon, authenticated;
grant insert, select on pg_temp.classroom100_results to anon, authenticated;

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
begin
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

  insert into public.activities (id, teacher_id, code, name, status, group_size)
  values (v_activity, v_host, 'C1-' || upper(substr(replace(v_activity::text, '-', ''), 1, 6)), 'CLASSROOM_100 C1 rollback fixture', 'active', 1);

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

  insert into pg_temp.classroom100_fixture values (
    v_mode, v_host, v_a, v_b, v_activity, v_ga, v_gb, v_sa, v_sb,
    v_sega, v_segb, v_ra, v_rb
  );
end;
$$;

-- Participant B: always a non-host participant.
set local role authenticated;
select set_config('request.jwt.claim.sub', (select user_b_id::text from pg_temp.classroom100_fixture), true);
select set_config('request.jwt.claims', jsonb_build_object('sub', (select user_b_id from pg_temp.classroom100_fixture), 'role', 'authenticated')::text, true);

insert into pg_temp.classroom100_results
select 'participant_b', 'own_group', count(*)::int, 1, count(*) = 1 from public.groups where id = (select group_b_id from pg_temp.classroom100_fixture);
insert into pg_temp.classroom100_results
select 'participant_b', 'other_group', count(*)::int, 0, count(*) = 0 from public.groups where id = (select group_a_id from pg_temp.classroom100_fixture);
insert into pg_temp.classroom100_results
select 'participant_b', 'own_story', count(*)::int, 1, count(*) = 1 from public.stories where id = (select story_b_id from pg_temp.classroom100_fixture);
insert into pg_temp.classroom100_results
select 'participant_b', 'other_story', count(*)::int, 0, count(*) = 0 from public.stories where id = (select story_a_id from pg_temp.classroom100_fixture);
insert into pg_temp.classroom100_results
select 'participant_b', 'own_segment', count(*)::int, 1, count(*) = 1 from public.segments where id = (select segment_b_id from pg_temp.classroom100_fixture);
insert into pg_temp.classroom100_results
select 'participant_b', 'other_segment', count(*)::int, 0, count(*) = 0 from public.segments where id = (select segment_a_id from pg_temp.classroom100_fixture);
insert into pg_temp.classroom100_results
select 'participant_b', 'own_round', count(*)::int, 1, count(*) = 1 from public.relay_rounds where id = (select round_b_id from pg_temp.classroom100_fixture);
insert into pg_temp.classroom100_results
select 'participant_b', 'other_round', count(*)::int, 0, count(*) = 0 from public.relay_rounds where id = (select round_a_id from pg_temp.classroom100_fixture);
reset role;

-- Participant A symmetric checks are valid only when A is distinct from host.
do $$
begin
  if (select mode from pg_temp.classroom100_fixture) = 'THREE_ACCOUNT_SYMMETRIC' then
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', (select user_a_id::text from pg_temp.classroom100_fixture), true);
    perform set_config('request.jwt.claims', jsonb_build_object('sub', (select user_a_id from pg_temp.classroom100_fixture), 'role', 'authenticated')::text, true);

    insert into pg_temp.classroom100_results
    select 'participant_a', 'own_group', count(*)::int, 1, count(*) = 1 from public.groups where id = (select group_a_id from pg_temp.classroom100_fixture);
    insert into pg_temp.classroom100_results
    select 'participant_a', 'other_group', count(*)::int, 0, count(*) = 0 from public.groups where id = (select group_b_id from pg_temp.classroom100_fixture);
    insert into pg_temp.classroom100_results
    select 'participant_a', 'own_story', count(*)::int, 1, count(*) = 1 from public.stories where id = (select story_a_id from pg_temp.classroom100_fixture);
    insert into pg_temp.classroom100_results
    select 'participant_a', 'other_story', count(*)::int, 0, count(*) = 0 from public.stories where id = (select story_b_id from pg_temp.classroom100_fixture);
    insert into pg_temp.classroom100_results
    select 'participant_a', 'own_segment', count(*)::int, 1, count(*) = 1 from public.segments where id = (select segment_a_id from pg_temp.classroom100_fixture);
    insert into pg_temp.classroom100_results
    select 'participant_a', 'other_segment', count(*)::int, 0, count(*) = 0 from public.segments where id = (select segment_b_id from pg_temp.classroom100_fixture);
    insert into pg_temp.classroom100_results
    select 'participant_a', 'own_round', count(*)::int, 1, count(*) = 1 from public.relay_rounds where id = (select round_a_id from pg_temp.classroom100_fixture);
    insert into pg_temp.classroom100_results
    select 'participant_a', 'other_round', count(*)::int, 0, count(*) = 0 from public.relay_rounds where id = (select round_b_id from pg_temp.classroom100_fixture);

    perform set_config('role', 'none', true);
  end if;
end;
$$;

-- Anonymous -------------------------------------------------------------------
set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{"role":"anon"}', true);
insert into pg_temp.classroom100_results
select 'anon', 'group_a_hidden', count(*)::int, 0, count(*) = 0 from public.groups where id = (select group_a_id from pg_temp.classroom100_fixture);
insert into pg_temp.classroom100_results
select 'anon', 'story_a_hidden', count(*)::int, 0, count(*) = 0 from public.stories where id = (select story_a_id from pg_temp.classroom100_fixture);
insert into pg_temp.classroom100_results
select 'anon', 'segment_a_hidden', count(*)::int, 0, count(*) = 0 from public.segments where id = (select segment_a_id from pg_temp.classroom100_fixture);
insert into pg_temp.classroom100_results
select 'anon', 'round_a_hidden', count(*)::int, 0, count(*) = 0 from public.relay_rounds where id = (select round_a_id from pg_temp.classroom100_fixture);
reset role;

-- Evaluate before rollback.
do $$
declare
  v_failed text;
begin
  select string_agg(role_name || ':' || check_name || ' observed=' || observed || ' expected=' || expected, '; ' order by role_name, check_name)
  into v_failed
  from pg_temp.classroom100_results
  where not passed;

  if v_failed is not null then
    raise exception 'CLASSROOM_100 C1 cross-group RLS failed: %', v_failed;
  end if;
end;
$$;

select
  (select mode from pg_temp.classroom100_fixture) as test_mode,
  'CLASSROOM_100 C1 cross-group RLS passed; fixture will now be rolled back' as result,
  count(*) as checks_passed
from pg_temp.classroom100_results
where passed;

rollback;
