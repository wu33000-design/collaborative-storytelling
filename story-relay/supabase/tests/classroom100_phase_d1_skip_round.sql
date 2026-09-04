-- CLASSROOM_100 Phase D1 host skip/expire recovery test.
-- Rollback-only. Requires 20260904_d1_host_skip_relay_round.sql to be applied first.

begin;

do $$
declare
  v_host uuid := gen_random_uuid();
  v_writer_a uuid := gen_random_uuid();
  v_writer_b uuid := gen_random_uuid();
  v_activity uuid := gen_random_uuid();
  v_group uuid := gen_random_uuid();
  v_story uuid := gen_random_uuid();
  v_round_1 uuid := gen_random_uuid();
  v_result jsonb;
  v_round_2 uuid;
  v_round_3 uuid;
  v_count integer;
  v_status text;
  v_writer uuid;
  v_nonhost_blocked boolean := false;
begin
  if to_regprocedure('public.skip_relay_round(uuid)') is null then
    raise exception 'CLASSROOM_100 D1 failed: skip_relay_round(uuid) is not installed';
  end if;

  insert into auth.users (id, email, raw_user_meta_data, created_at, updated_at)
  values
    (v_host, 'd1-host-' || v_host || '@example.invalid', jsonb_build_object('name','D1 Host'), now(), now()),
    (v_writer_a, 'd1-a-' || v_writer_a || '@example.invalid', jsonb_build_object('name','D1 Writer A'), now(), now()),
    (v_writer_b, 'd1-b-' || v_writer_b || '@example.invalid', jsonb_build_object('name','D1 Writer B'), now(), now());

  if (select count(*) from public.profiles where id in (v_host,v_writer_a,v_writer_b)) <> 3 then
    raise exception 'CLASSROOM_100 D1 failed: auth trigger did not create all profiles';
  end if;

  insert into public.activities (id, teacher_id, code, name, status, group_size)
  values (v_activity, v_host, 'D1' || upper(substr(replace(v_activity::text,'-',''),1,6)), 'D1 Skip Test', 'active', null);

  insert into public.groups (id, activity_id, name)
  values (v_group, v_activity, 'D1 Group');

  insert into public.stories (id, group_id, title, status)
  values (v_story, v_group, 'D1 Story', 'active');

  insert into public.group_members (group_id, user_id, role)
  values (v_group,v_writer_a,'student'), (v_group,v_writer_b,'student');

  insert into public.writer_states (group_id,user_id,times_written,waiting_rounds,selection_weight)
  values (v_group,v_writer_a,0,0,1), (v_group,v_writer_b,0,0,1);

  insert into public.relay_rounds (id,story_id,round_no,current_writer_id,status)
  values (v_round_1,v_story,1,v_writer_a,'writing');

  -- Host skips Writer A. Writer B is the only other eligible writer, so selection is deterministic.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub',v_host::text,'role','authenticated')::text, true);
  select public.skip_relay_round(v_round_1) into v_result;
  execute 'reset role';

  v_round_2 := (v_result->>'next_round_id')::uuid;
  if (v_result->>'next_writer_id')::uuid <> v_writer_b then
    raise exception 'CLASSROOM_100 D1 failed: host skip did not select the other eligible writer';
  end if;

  select status into v_status from public.relay_rounds where id=v_round_1;
  if v_status <> 'expired' then
    raise exception 'CLASSROOM_100 D1 failed: skipped round was not preserved as expired';
  end if;

  select status,current_writer_id into v_status,v_writer from public.relay_rounds where id=v_round_2;
  if v_status <> 'writing' or v_writer <> v_writer_b then
    raise exception 'CLASSROOM_100 D1 failed: next writing round is incorrect';
  end if;

  select count(*) into v_count from public.segments where story_id=v_story;
  if v_count <> 0 then
    raise exception 'CLASSROOM_100 D1 failed: skip created a segment';
  end if;

  select coalesce(sum(times_written),0) into v_count from public.writer_states where group_id=v_group;
  if v_count <> 0 then
    raise exception 'CLASSROOM_100 D1 failed: skip changed times_written';
  end if;

  -- A non-host participant must not be able to skip the new round.
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub',v_writer_a::text,'role','authenticated')::text, true);
    perform public.skip_relay_round(v_round_2);
  exception when others then
    v_nonhost_blocked := true;
  end;
  execute 'reset role';

  if not v_nonhost_blocked then
    raise exception 'CLASSROOM_100 D1 failed: non-host participant could skip a round';
  end if;

  -- Writer A leaves. With only Writer B active, host skip must use single-writer fallback.
  update public.group_members
  set left_at=now()
  where group_id=v_group and user_id=v_writer_a;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub',v_host::text,'role','authenticated')::text, true);
  select public.skip_relay_round(v_round_2) into v_result;
  execute 'reset role';

  v_round_3 := (v_result->>'next_round_id')::uuid;
  if (v_result->>'candidate_pool') <> 'single_writer_fallback'
     or (v_result->>'next_writer_id')::uuid <> v_writer_b then
    raise exception 'CLASSROOM_100 D1 failed: single-writer fallback after leave is incorrect';
  end if;

  select status into v_status from public.relay_rounds where id=v_round_2;
  if v_status <> 'expired' then
    raise exception 'CLASSROOM_100 D1 failed: second skipped round was not expired';
  end if;

  select status,current_writer_id into v_status,v_writer from public.relay_rounds where id=v_round_3;
  if v_status <> 'writing' or v_writer <> v_writer_b then
    raise exception 'CLASSROOM_100 D1 failed: fallback next round is incorrect';
  end if;

  select count(*) into v_count
  from public.activity_events
  where activity_id=v_activity and type='relay_round_skipped';
  if v_count <> 2 then
    raise exception 'CLASSROOM_100 D1 failed: expected 2 relay_round_skipped events, got %',v_count;
  end if;
end;
$$;

select 'CLASSROOM_100 D1 host skip relay round passed' as result;

rollback;
