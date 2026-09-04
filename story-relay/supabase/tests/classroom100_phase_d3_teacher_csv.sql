-- CLASSROOM_100 Phase D3 teacher CSV statistics test.
-- Rollback-only. Requires 20260904_d3_teacher_activity_csv.sql first.

begin;

do $$
declare
  v_host uuid := gen_random_uuid();
  v_student uuid := gen_random_uuid();
  v_other uuid := gen_random_uuid();
  v_activity uuid := gen_random_uuid();
  v_group uuid := gen_random_uuid();
  v_story uuid := gen_random_uuid();
  v_round_1 uuid := gen_random_uuid();
  v_round_2 uuid := gen_random_uuid();
  v_rows integer;
  v_rounds bigint;
  v_segments bigint;
  v_chars bigint;
  v_group_name text;
  v_display_name text;
  v_first timestamptz;
  v_last timestamptz;
  v_nonhost_blocked boolean := false;
begin
  if to_regprocedure('public.get_teacher_activity_csv(uuid)') is null then
    raise exception 'CLASSROOM_100 D3 failed: get_teacher_activity_csv(uuid) is not installed';
  end if;

  insert into auth.users (id, email, raw_user_meta_data, created_at, updated_at)
  values
    (v_host, 'd3-host-' || v_host || '@example.invalid', jsonb_build_object('name','D3 Host'), now(), now()),
    (v_student, 'd3-student-' || v_student || '@example.invalid', jsonb_build_object('name','=D3 Student'), now(), now()),
    (v_other, 'd3-other-' || v_other || '@example.invalid', jsonb_build_object('name','D3 Other'), now(), now());

  insert into public.activities (id, teacher_id, code, name, status, group_size)
  values (v_activity, v_host, 'D3' || upper(substr(replace(v_activity::text,'-',''),1,6)), 'D3 CSV Test', 'active', null);

  insert into public.groups (id, activity_id, name)
  values (v_group, v_activity, 'CSV Group');

  insert into public.stories (id, group_id, title, status)
  values (v_story, v_group, 'D3 Story', 'active');

  insert into public.group_members (group_id, user_id, role, joined_at)
  values (v_group, v_student, 'student', now() - interval '10 minutes');

  insert into public.writer_states (group_id,user_id,times_written,waiting_rounds,selection_weight)
  values (v_group,v_student,1,0,1);

  insert into public.relay_rounds (id,story_id,round_no,current_writer_id,status,started_at,completed_at)
  values
    (v_round_1,v_story,1,v_student,'completed',now()-interval '8 minutes',now()-interval '7 minutes'),
    (v_round_2,v_story,2,v_student,'expired',now()-interval '6 minutes',now()-interval '5 minutes');

  -- Writer 0 seed must not count toward student statistics.
  insert into public.segments (story_id,sequence_no,author_id,content,word_count,submitted_at)
  values
    (v_story,0,null,'Writer zero seed',16,now()-interval '9 minutes'),
    (v_story,1,v_student,'abc中文',5,now()-interval '4 minutes');

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub',v_host::text,'role','authenticated')::text, true);

  select count(*) into v_rows
  from public.get_teacher_activity_csv(v_activity);

  select r.group_name, r.display_name, r.rounds_selected, r.segments_written,
         r.total_characters, r.first_submission_at, r.last_submission_at
  into v_group_name, v_display_name, v_rounds, v_segments, v_chars, v_first, v_last
  from public.get_teacher_activity_csv(v_activity) r
  where r.user_id = v_student;

  execute 'reset role';

  if v_rows <> 1 then
    raise exception 'CLASSROOM_100 D3 failed: expected 1 CSV row, got %', v_rows;
  end if;
  if v_group_name <> 'CSV Group' or v_display_name <> '=D3 Student' then
    raise exception 'CLASSROOM_100 D3 failed: member identity/group output incorrect';
  end if;
  if v_rounds <> 2 then
    raise exception 'CLASSROOM_100 D3 failed: rounds_selected=% expected=2', v_rounds;
  end if;
  if v_segments <> 1 then
    raise exception 'CLASSROOM_100 D3 failed: segments_written=% expected=1', v_segments;
  end if;
  if v_chars <> 5 then
    raise exception 'CLASSROOM_100 D3 failed: total_characters=% expected=5', v_chars;
  end if;
  if v_first is null or v_last is null or v_first <> v_last then
    raise exception 'CLASSROOM_100 D3 failed: submission timestamps incorrect';
  end if;

  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub',v_other::text,'role','authenticated')::text, true);
    perform * from public.get_teacher_activity_csv(v_activity);
  exception when others then
    v_nonhost_blocked := true;
  end;
  execute 'reset role';

  if not v_nonhost_blocked then
    raise exception 'CLASSROOM_100 D3 failed: non-host could read teacher CSV data';
  end if;
end;
$$;

select 'CLASSROOM_100 D3 teacher CSV passed' as result;

rollback;
