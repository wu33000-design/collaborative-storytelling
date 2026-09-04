-- Remove temporary CLASSROOM_100 C2 Realtime capacity probe RPCs.
-- The browser fixture must be cleaned before applying this migration.

begin;

drop function if exists public.create_classroom100_realtime_probe();
drop function if exists public.run_classroom100_realtime_probe_burst(uuid);
drop function if exists public.cleanup_classroom100_realtime_probe(uuid);

commit;
