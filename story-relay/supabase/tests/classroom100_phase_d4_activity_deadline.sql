-- CLASSROOM_100 Phase D4 activity deadline finalization test.
-- Rollback-only. Requires 20260904_d4_activity_deadline_finalize.sql first.

begin;

do $$
declare
  v_host uuid := gen_random_uuid();
  v_student uuid := gen_random_uuid();
  v_other uuid := gen_random_uuid();
  v_activity uuid := gen_random_uuid();
  v_group uuid := gen_random_uuid();
  v_story uuid := gen_random_uuid();
  v_round uuid := gen_random_uuid();
  v_manual_activity uuid := gen_random_uuid();
  v_manual_group uuid := gen_random_uuid();
  v_manual_story uuid := gen_random_uuid();
  v_manual_round uuid := gen_random_uuid();
  v_changed boolean;
  v_status text;
  v_reason text;
  v_story_status text;
  v_round_status text;
  v_event_count integer;
  v_blocked boolean := false;
begin
  if to_regprocedure('public.finalize_activity_deadline(uuid)') is null then
    raise exception 'CLASSROOM_100 D4 failed: finalize_activity_deadline(uuid) is not installed';
  end if;

  insert into auth.users (id, email, raw_user_meta_data, created_at, updated_at)
  values
    (v_host, 'd4-host-' || v_host || '@example.invalid', jsonb_build_object('name','D4 Host'), now(), now()),
    (v_student, 'd4-student-' || v_student || '@example.invalid', jsonb_build_object('name','D4 Student'), now(), now()),
    (v_other, 'd4-other-' || v_other || '@example.invalid', jsonb_build_object('name','D4 Other'), now(), now());

  insert into public.activities (id, teacher_id, code, name, status, group_size, deadline)
  values (v_activity, v_host, 'D4' || upper(substr(replace(v_activity::text,'-',''),1,6)), 'D4 Deadline Test', 'active', null, now() + interval '1 hour');

  insert into public.groups (id, activity_id, name)
  values (v_group, v_activity, 'Deadline Group');

  insert into public.stories (id, group_id, title, status)
  values (v_story, v_group, 'D4 Story', 'active');

  insert into public.group_members (group_id, user_id, role)
  values (v_group, v_student, 'student');

  insert into public.writer_states (group_id,user_id,times_written,waiting_rounds,selection_weight)
  values (v_group,v_student,0,0,1);

  insert into public.relay_rounds (id,story_id,round_no,current_writer_id,status,started_at)
  values (v_round,v_story,1,v_student,'writing',now());

  -- Future deadline must be a no-op for an authorized group member.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub',v_student::text,'role','authenticated')::text, true);
  select public.finalize_activity_deadline(v_activity) into v_changed;
  execute 'reset role';

  if v_changed then
    raise exception 'CLASSROOM_100 D4 failed: future deadline was finalized';
  end if;

  -- Unrelated authenticated users cannot force even deterministic finalization.
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub',v_other::text,'role','authenticated')::text, true);
    perform public.finalize_activity_deadline(v_activity);
  exception when others then
    v_blocked := true;
  end;
  execute 'reset role';

  if not v_blocked then
    raise exception 'CLASSROOM_100 D4 failed: unrelated user could finalize activity';
  end if;

  -- Move the fixture deadline into the past, then finalize as a real member.
  update public.activities a
  set deadline = now() - interval '1 minute'
  where a.id = v_activity;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub',v_student::text,'role','authenticated')::text, true);
  select public.finalize_activity_deadline(v_activity) into v_changed;
  execute 'reset role';

  if not v_changed then
    raise exception 'CLASSROOM_100 D4 failed: past deadline did not finalize';
  end if;

  select a.status, a.closed_reason into v_status, v_reason
  from public.activities a where a.id = v_activity;
  select s.status into v_story_status from public.stories s where s.id = v_story;
  select rr.status into v_round_status from public.relay_rounds rr where rr.id = v_round;
  select count(*) into v_event_count
  from public.activity_events ae
  where ae.activity_id = v_activity and ae.type = 'activity_deadline_reached';

  if v_status <> 'closed' or v_reason <> 'deadline' then
    raise exception 'CLASSROOM_100 D4 failed: activity status/reason = %/%', v_status, v_reason;
  end if;
  if v_story_status <> 'closed' then
    raise exception 'CLASSROOM_100 D4 failed: story status = % expected closed', v_story_status;
  end if;
  if v_round_status <> 'expired' then
    raise exception 'CLASSROOM_100 D4 failed: round status = % expected expired', v_round_status;
  end if;
  if v_event_count <> 1 then
    raise exception 'CLASSROOM_100 D4 failed: deadline event count = % expected 1', v_event_count;
  end if;

  -- Idempotency: a second authorized call changes nothing and creates no event.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub',v_host::text,'role','authenticated')::text, true);
  select public.finalize_activity_deadline(v_activity) into v_changed;
  execute 'reset role';

  select count(*) into v_event_count
  from public.activity_events ae
  where ae.activity_id = v_activity and ae.type = 'activity_deadline_reached';

  if v_changed or v_event_count <> 1 then
    raise exception 'CLASSROOM_100 D4 failed: finalizer is not idempotent';
  end if;

  -- Manual stop must remain distinct and preserve the completed_at ambiguity fix.
  insert into public.activities (id, teacher_id, code, name, status, group_size, deadline)
  values (v_manual_activity, v_host, 'DM' || upper(substr(replace(v_manual_activity::text,'-',''),1,6)), 'D4 Manual Stop', 'active', null, now() + interval '1 day');
  insert into public.groups (id, activity_id, name) values (v_manual_group, v_manual_activity, 'Manual Group');
  insert into public.stories (id, group_id, title, status) values (v_manual_story, v_manual_group, 'Manual Story', 'active');
  insert into public.relay_rounds (id,story_id,round_no,current_writer_id,status,started_at)
  values (v_manual_round,v_manual_story,1,v_student,'writing',now());

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub',v_host::text,'role','authenticated')::text, true);
  perform public.stop_activity(v_manual_activity);
  execute 'reset role';

  select a.status, a.closed_reason into v_status, v_reason
  from public.activities a where a.id = v_manual_activity;
  select rr.status into v_round_status from public.relay_rounds rr where rr.id = v_manual_round;

  if v_status <> 'closed' or v_reason <> 'host_stopped' or v_round_status <> 'expired' then
    raise exception 'CLASSROOM_100 D4 failed: manual stop distinction/regression';
  end if;
end;
$$;

select 'CLASSROOM_100 D4 activity deadline passed' as result;

rollback;
