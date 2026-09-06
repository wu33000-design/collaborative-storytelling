-- Story Relay next-writer priority/probability acceptance test.
-- Rollback-only. Requires 20260906_next_writer_priority_and_probabilities.sql.

begin;

do $$
declare
  v_host uuid := gen_random_uuid();
  v_a uuid := gen_random_uuid();
  v_b uuid := gen_random_uuid();
  v_c uuid := gen_random_uuid();
  v_activity uuid := gen_random_uuid();
  v_group uuid := gen_random_uuid();
  v_story uuid := gen_random_uuid();
  v_round1 uuid := gen_random_uuid();
  v_round2 uuid;
  v_round3 uuid;
  v_pct_a numeric;
  v_pct_b numeric;
  v_pct_c numeric;
  v_mode text;
  v_writer uuid;
  v_failed boolean;
  v_skip jsonb;
begin
  insert into auth.users (id,email,raw_user_meta_data,created_at,updated_at)
  values
    (v_host,'nw-host-'||v_host||'@example.invalid',jsonb_build_object('name','NW Host'),now(),now()),
    (v_a,'nw-a-'||v_a||'@example.invalid',jsonb_build_object('name','NW A'),now(),now()),
    (v_b,'nw-b-'||v_b||'@example.invalid',jsonb_build_object('name','NW B'),now(),now()),
    (v_c,'nw-c-'||v_c||'@example.invalid',jsonb_build_object('name','NW C'),now(),now());

  insert into public.activities(id,teacher_id,code,name,status,group_size)
  values(v_activity,v_host,'NW'||upper(substr(replace(v_activity::text,'-',''),1,6)),'Next Writer Test','active',null);

  insert into public.groups(id,activity_id,name) values(v_group,v_activity,'NW Group');
  insert into public.stories(id,group_id,title,status) values(v_story,v_group,'NW Story','active');
  insert into public.group_members(group_id,user_id,role)
  values(v_group,v_a,'student'),(v_group,v_b,'student'),(v_group,v_c,'student');
  insert into public.writer_states(group_id,user_id,times_written,waiting_rounds,selection_weight)
  values(v_group,v_a,0,0,1),(v_group,v_b,0,0,1),(v_group,v_c,0,0,1);
  insert into public.relay_rounds(id,story_id,round_no,current_writer_id,status)
  values(v_round1,v_story,1,v_a,'writing');

  -- Unlocked probabilities: current writer 0%, the two equal candidates 50/50.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',json_build_object('sub',v_b::text,'role','authenticated')::text,true);
  select probability_pct,selection_mode into v_pct_b,v_mode
  from public.get_next_writer_probabilities(v_round1) where user_id=v_b;
  select probability_pct into v_pct_c
  from public.get_next_writer_probabilities(v_round1) where user_id=v_c;
  select probability_pct into v_pct_a
  from public.get_next_writer_probabilities(v_round1) where user_id=v_a;
  execute 'reset role';

  if v_mode <> 'weighted_random' or v_pct_a <> 0 or v_pct_b <> 50.0 or v_pct_c <> 50.0 then
    raise exception 'NEXT_WRITER failed: unlocked probability table is incorrect: A %, B %, C %, mode %',v_pct_a,v_pct_b,v_pct_c,v_mode;
  end if;

  -- B volunteers first: B must lock at 100%, and no second volunteer/nomination may override it.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',json_build_object('sub',v_b::text,'role','authenticated')::text,true);
  perform public.volunteer_for_round(v_round1);
  execute 'reset role';

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',json_build_object('sub',v_c::text,'role','authenticated')::text,true);
  v_failed := false;
  begin
    perform public.volunteer_for_round(v_round1);
  exception when others then
    v_failed := true;
  end;
  execute 'reset role';
  if not v_failed then raise exception 'NEXT_WRITER failed: second volunteer was accepted'; end if;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',json_build_object('sub',v_a::text,'role','authenticated')::text,true);
  v_failed := false;
  begin
    perform public.nominate_candidate(v_round1,v_c);
  exception when others then
    v_failed := true;
  end;
  execute 'reset role';
  if not v_failed then raise exception 'NEXT_WRITER failed: nomination overrode volunteer lock'; end if;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',json_build_object('sub',v_c::text,'role','authenticated')::text,true);
  select probability_pct,selection_mode into v_pct_b,v_mode
  from public.get_next_writer_probabilities(v_round1) where user_id=v_b;
  select probability_pct into v_pct_c
  from public.get_next_writer_probabilities(v_round1) where user_id=v_c;
  execute 'reset role';
  if v_pct_b <> 100 or v_pct_c <> 0 or v_mode <> 'volunteer_locked' then
    raise exception 'NEXT_WRITER failed: volunteer lock probabilities incorrect';
  end if;

  -- Current writer submits; next round must deterministically be B.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',json_build_object('sub',v_a::text,'role','authenticated')::text,true);
  perform public.submit_segment(v_round1,'Round one text');
  execute 'reset role';

  select id,current_writer_id into v_round2,v_writer
  from public.relay_rounds where story_id=v_story and round_no=2;
  if v_writer <> v_b then raise exception 'NEXT_WRITER failed: volunteer did not become next writer'; end if;

  -- B nominates C. Nomination must lock C at 100%; later volunteer cannot override it.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',json_build_object('sub',v_b::text,'role','authenticated')::text,true);
  perform public.nominate_candidate(v_round2,v_c);
  execute 'reset role';

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',json_build_object('sub',v_a::text,'role','authenticated')::text,true);
  v_failed := false;
  begin
    perform public.volunteer_for_round(v_round2);
  exception when others then
    v_failed := true;
  end;
  execute 'reset role';
  if not v_failed then raise exception 'NEXT_WRITER failed: volunteer overrode nomination lock'; end if;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',json_build_object('sub',v_a::text,'role','authenticated')::text,true);
  select probability_pct,selection_mode into v_pct_c,v_mode
  from public.get_next_writer_probabilities(v_round2) where user_id=v_c;
  execute 'reset role';
  if v_pct_c <> 100 or v_mode <> 'nomination_locked' then
    raise exception 'NEXT_WRITER failed: nomination lock probability incorrect';
  end if;

  -- Host skip must also honor the visible nomination lock.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',json_build_object('sub',v_host::text,'role','authenticated')::text,true);
  select public.skip_relay_round(v_round2) into v_skip;
  execute 'reset role';

  if (v_skip->>'next_writer_id')::uuid <> v_c or v_skip->>'candidate_pool' <> 'nomination_locked' then
    raise exception 'NEXT_WRITER failed: host skip ignored nomination lock';
  end if;

  v_round3 := (v_skip->>'next_round_id')::uuid;
  select current_writer_id into v_writer from public.relay_rounds where id=v_round3;
  if v_writer <> v_c then raise exception 'NEXT_WRITER failed: skipped round did not create C as next writer'; end if;
end;
$$;

select 'CLASSROOM_100 next-writer priority and probabilities passed' as result;

rollback;
