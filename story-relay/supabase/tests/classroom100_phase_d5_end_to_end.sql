-- CLASSROOM_100 Phase D5 end-to-end classroom acceptance test.
-- Rollback-only. Exercises the current RPC chain after D1-D4.

begin;

do $$
declare
  v_host uuid := gen_random_uuid();
  v_student uuid := gen_random_uuid();
  v_admin uuid := gen_random_uuid();
  v_created jsonb;
  v_activity uuid;
  v_group uuid;
  v_story uuid;
  v_code text;
  v_round jsonb;
  v_round_id uuid;
  v_next_round_id uuid;
  v_segment uuid;
  v_csv_rows integer;
  v_status text;
  v_story_status text;
  v_deleted_at timestamptz;
  v_purge_after timestamptz;
  v_started_at timestamptz;
begin
  -- Preconditions.
  if to_regprocedure('public.create_activity(text,text,text,integer,integer,integer,integer,integer,timestamptz)') is null
     or to_regprocedure('public.join_activity_by_code(text)') is null
     or to_regprocedure('public.start_relay_round(uuid)') is null
     or to_regprocedure('public.submit_segment(uuid,text)') is null
     or to_regprocedure('public.skip_relay_round(uuid)') is null
     or to_regprocedure('public.stop_activity(uuid)') is null
     or to_regprocedure('public.get_teacher_activity_csv(uuid)') is null
     or to_regprocedure('public.delete_platform_activity(uuid)') is null
     or to_regprocedure('public.restore_platform_activity(uuid)') is null then
    raise exception 'CLASSROOM_100 D5 failed: required RPC is missing';
  end if;

  -- Synthetic authenticated identities. Existing auth trigger creates profiles.
  insert into auth.users (id, email, raw_user_meta_data, created_at, updated_at)
  values
    (v_host, 'd5-host-' || v_host || '@example.invalid', jsonb_build_object('name','D5 Host'), now(), now()),
    (v_student, 'd5-student-' || v_student || '@example.invalid', jsonb_build_object('name','D5 Student'), now(), now()),
    (v_admin, 'd5-admin-' || v_admin || '@example.invalid', jsonb_build_object('name','D5 Admin'), now(), now());

  insert into public.platform_admins (user_id) values (v_admin);

  -- 1) Host creates an ordinary single-group activity with a 30-second round limit.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub',v_host::text,'role','authenticated')::text, true);
  select public.create_activity(
    'D5 Acceptance',
    'Continue the story',
    'Writer 0 seed',
    null,
    30,
    null,
    null,
    null,
    null
  ) into v_created;
  execute 'reset role';

  v_activity := (v_created->>'activity_id')::uuid;
  v_group := (v_created->>'group_id')::uuid;
  v_story := (v_created->>'story_id')::uuid;
  v_code := v_created->>'code';

  if v_activity is null or v_group is null or v_story is null or v_code is null then
    raise exception 'CLASSROOM_100 D5 failed: create_activity returned incomplete data';
  end if;

  -- 2) Participant joins by code.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub',v_student::text,'role','authenticated')::text, true);
  if public.join_activity_by_code(v_code) <> v_group then
    raise exception 'CLASSROOM_100 D5 failed: participant joined unexpected group';
  end if;

  -- 3) Participant starts first round; solo fallback must select that participant.
  select public.start_relay_round(v_group) into v_round;
  v_round_id := (v_round->>'round_id')::uuid;
  if (v_round->>'current_writer_id')::uuid <> v_student then
    raise exception 'CLASSROOM_100 D5 failed: first round did not select the only participant';
  end if;
  execute 'reset role';

  select rr.started_at into v_started_at from public.relay_rounds rr where rr.id = v_round_id;
  if v_started_at is null then
    raise exception 'CLASSROOM_100 D5 failed: first round started_at is null';
  end if;

  -- 4) Current writer submits; a next active round must be created.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub',v_student::text,'role','authenticated')::text, true);
  select public.submit_segment(v_round_id, 'D5 participant segment') into v_segment;
  execute 'reset role';

  if v_segment is null then
    raise exception 'CLASSROOM_100 D5 failed: submit_segment returned null';
  end if;

  select rr.id, rr.started_at into v_next_round_id, v_started_at
  from public.relay_rounds rr
  where rr.story_id = v_story and rr.status in ('open','writing')
  order by rr.round_no desc limit 1;

  if v_next_round_id is null or v_started_at is null then
    raise exception 'CLASSROOM_100 D5 failed: next round missing or has null started_at';
  end if;

  -- 5) Host intervention: skip the active round. With one eligible writer, fallback is allowed.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub',v_host::text,'role','authenticated')::text, true);
  perform public.skip_relay_round(v_next_round_id);
  execute 'reset role';

  if not exists (select 1 from public.relay_rounds where id=v_next_round_id and status='expired') then
    raise exception 'CLASSROOM_100 D5 failed: skipped round was not expired';
  end if;
  if not exists (
    select 1 from public.relay_rounds
    where story_id=v_story and status in ('open','writing') and started_at is not null
  ) then
    raise exception 'CLASSROOM_100 D5 failed: skip did not create a timed next round';
  end if;

  -- 6) Host stops the activity; story and active round must converge to closed/expired.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub',v_host::text,'role','authenticated')::text, true);
  perform public.stop_activity(v_activity);

  select count(*) into v_csv_rows from public.get_teacher_activity_csv(v_activity);
  execute 'reset role';

  select a.status, s.status into v_status, v_story_status
  from public.activities a
  join public.groups g on g.activity_id=a.id
  join public.stories s on s.group_id=g.id
  where a.id=v_activity and s.id=v_story;

  if v_status <> 'closed' or v_story_status <> 'closed' then
    raise exception 'CLASSROOM_100 D5 failed: stop did not close activity/story';
  end if;
  if exists (select 1 from public.relay_rounds where story_id=v_story and status in ('open','writing')) then
    raise exception 'CLASSROOM_100 D5 failed: active round remained after stop';
  end if;
  if v_csv_rows <> 1 then
    raise exception 'CLASSROOM_100 D5 failed: expected 1 teacher CSV row after stop, got %', v_csv_rows;
  end if;

  -- 7) Platform admin soft-deletes the stopped activity.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub',v_admin::text,'role','authenticated')::text, true);
  perform public.delete_platform_activity(v_activity);
  execute 'reset role';

  select a.deleted_at, a.purge_after into v_deleted_at, v_purge_after
  from public.activities a where a.id=v_activity;
  if v_deleted_at is null or v_purge_after is null or v_purge_after <= v_deleted_at then
    raise exception 'CLASSROOM_100 D5 failed: soft delete metadata is invalid';
  end if;

  -- 8) Platform admin restores it; previous stopped/closed state must be preserved.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub',v_admin::text,'role','authenticated')::text, true);
  perform public.restore_platform_activity(v_activity);
  execute 'reset role';

  select a.status, a.deleted_at into v_status, v_deleted_at
  from public.activities a where a.id=v_activity;
  if v_status <> 'closed' or v_deleted_at is not null then
    raise exception 'CLASSROOM_100 D5 failed: restore did not preserve closed status or clear deletion';
  end if;

  -- Minimum evidence that the flow left expected durable events inside the transaction.
  if not exists (select 1 from public.activity_events where activity_id=v_activity and type='segment_submitted')
     or not exists (select 1 from public.activity_events where activity_id=v_activity and type='relay_round_skipped')
     or not exists (select 1 from public.activity_events where activity_id=v_activity and type='activity_stopped') then
    raise exception 'CLASSROOM_100 D5 failed: expected lifecycle events are missing';
  end if;
end;
$$;

select 'CLASSROOM_100 D5 end-to-end acceptance passed' as result;

rollback;
