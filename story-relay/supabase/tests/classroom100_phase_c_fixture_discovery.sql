-- CLASSROOM_100 Phase C fixture discovery
-- Read-only. This script finds existing rows suitable for cross-group RLS tests.
-- It does not insert, update, delete, or change roles.

with memberships as (
  select
    a.id as activity_id,
    a.code,
    a.name as activity_name,
    a.teacher_id as host_user_id,
    g.id as group_id,
    gm.user_id
  from public.activities a
  join public.groups g on g.activity_id = a.id
  join public.group_members gm on gm.group_id = g.id
  where gm.left_at is null
    and gm.role = 'student'
    and a.deleted_at is null
), pair as (
  select
    a.activity_id,
    a.code,
    a.activity_name,
    a.host_user_id,
    a.group_id as group_a_id,
    a.user_id as user_a_id,
    b.group_id as group_b_id,
    b.user_id as user_b_id
  from memberships a
  join memberships b
    on b.activity_id = a.activity_id
   and b.group_id <> a.group_id
   and b.user_id <> a.user_id
  limit 1
), fixture as (
  select
    p.*,
    (select s.id from public.stories s where s.group_id = p.group_a_id limit 1) as story_a_id,
    (select s.id from public.stories s where s.group_id = p.group_b_id limit 1) as story_b_id,
    (select rr.id
       from public.relay_rounds rr
       join public.stories s on s.id = rr.story_id
      where s.group_id = p.group_a_id
      limit 1) as round_a_id,
    (select rr.id
       from public.relay_rounds rr
       join public.stories s on s.id = rr.story_id
      where s.group_id = p.group_b_id
      limit 1) as round_b_id,
    (select pa.user_id from public.platform_admins pa limit 1) as platform_admin_user_id
  from pair p
)
select
  case
    when f.activity_id is null then 'MISSING_CROSS_GROUP_FIXTURE'
    when f.story_a_id is null or f.story_b_id is null then 'MISSING_STORY_FIXTURE'
    when f.platform_admin_user_id is null then 'MISSING_PLATFORM_ADMIN_FIXTURE'
    else 'READY_FOR_ROLE_MATRIX_TEST'
  end as fixture_status,
  f.activity_id,
  f.code,
  f.activity_name,
  f.host_user_id,
  f.group_a_id,
  f.user_a_id,
  f.story_a_id,
  f.round_a_id,
  f.group_b_id,
  f.user_b_id,
  f.story_b_id,
  f.round_b_id,
  f.platform_admin_user_id
from fixture f

union all

select
  'MISSING_CROSS_GROUP_FIXTURE' as fixture_status,
  null::uuid as activity_id,
  null::text as code,
  null::text as activity_name,
  null::uuid as host_user_id,
  null::uuid as group_a_id,
  null::uuid as user_a_id,
  null::uuid as story_a_id,
  null::uuid as round_a_id,
  null::uuid as group_b_id,
  null::uuid as user_b_id,
  null::uuid as story_b_id,
  null::uuid as round_b_id,
  (select pa.user_id from public.platform_admins pa limit 1) as platform_admin_user_id
where not exists (select 1 from fixture);
