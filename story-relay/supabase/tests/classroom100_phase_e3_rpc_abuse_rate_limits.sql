-- CLASSROOM_100 Phase E3 RPC abuse-rate-limit test.
-- Rollback-only. Requires 20260904_e3_rpc_abuse_rate_limits.sql first.

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
  v_blocked boolean := false;
  v_count integer;
  i integer;
begin
  if to_regprocedure('public.consume_rpc_rate_limit(text,integer,integer)') is null then
    raise exception 'CLASSROOM_100 E3 failed: rate-limit helper is not installed';
  end if;
  if to_regprocedure('public.volunteer_for_round_unthrottled(uuid)') is null then
    raise exception 'CLASSROOM_100 E3 failed: internal volunteer implementation is missing';
  end if;

  if has_function_privilege('authenticated', 'public.volunteer_for_round_unthrottled(uuid)', 'EXECUTE') then
    raise exception 'CLASSROOM_100 E3 failed: authenticated can bypass the volunteer wrapper';
  end if;
  if has_function_privilege('authenticated', 'public.consume_rpc_rate_limit(text,integer,integer)', 'EXECUTE') then
    raise exception 'CLASSROOM_100 E3 failed: authenticated can directly mutate rate-limit buckets';
  end if;

  insert into auth.users (id, email, raw_user_meta_data, created_at, updated_at)
  values
    (v_host, 'e3-host-' || v_host || '@example.invalid', jsonb_build_object('name','E3 Host'), now(), now()),
    (v_student, 'e3-student-' || v_student || '@example.invalid', jsonb_build_object('name','E3 Student'), now(), now()),
    (v_other, 'e3-other-' || v_other || '@example.invalid', jsonb_build_object('name','E3 Other'), now(), now());

  insert into public.activities (id, teacher_id, code, name, status, group_size)
  values (v_activity, v_host, 'E3' || upper(substr(replace(v_activity::text,'-',''),1,6)), 'E3 Rate Limit Test', 'active', null);

  insert into public.groups (id, activity_id, name)
  values (v_group, v_activity, 'E3 Group');

  insert into public.stories (id, group_id, title, status)
  values (v_story, v_group, 'E3 Story', 'active');

  insert into public.group_members (group_id, user_id, role)
  values (v_group,v_student,'student'), (v_group,v_other,'student');

  insert into public.writer_states (group_id,user_id,times_written,waiting_rounds,selection_weight)
  values (v_group,v_student,0,0,1), (v_group,v_other,0,0,1);

  -- Student is not the current writer, so volunteering is valid and idempotent.
  insert into public.relay_rounds (id,story_id,round_no,current_writer_id,status)
  values (v_round,v_story,1,v_other,'writing');

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub',v_student::text,'role','authenticated')::text, true);

  for i in 1..20 loop
    perform public.volunteer_for_round(v_round);
  end loop;

  begin
    perform public.volunteer_for_round(v_round);
  exception when others then
    if position('Too many requests for volunteer_for_round' in sqlerrm) > 0 then
      v_blocked := true;
    else
      raise;
    end if;
  end;

  execute 'reset role';

  if not v_blocked then
    raise exception 'CLASSROOM_100 E3 failed: 21st volunteer call was not throttled';
  end if;

  select request_count into v_count
  from public.rpc_rate_limit_state
  where user_id=v_student and action='volunteer_for_round';

  -- The blocked call rolls back its increment, leaving the durable bucket at the cap.
  if v_count <> 20 then
    raise exception 'CLASSROOM_100 E3 failed: expected durable count 20 after throttle, got %', v_count;
  end if;

  -- Buckets are per authenticated user, not global/classroom-wide.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub',v_host::text,'role','authenticated')::text, true);
  perform public.consume_rpc_rate_limit('test_independent_bucket', 1, 60);
  execute 'reset role';

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub',v_other::text,'role','authenticated')::text, true);
  perform public.consume_rpc_rate_limit('test_independent_bucket', 1, 60);
  execute 'reset role';

  if (select count(*) from public.rpc_rate_limit_state where action='test_independent_bucket') <> 2 then
    raise exception 'CLASSROOM_100 E3 failed: independent users did not receive independent buckets';
  end if;
end;
$$;

select 'CLASSROOM_100 E3 RPC abuse rate limits passed' as result;

rollback;
