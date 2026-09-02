-- Story Relay: story title and prompt are optional.
-- Blank activity metadata may therefore propagate as NULL into each story.

begin;

alter table public.stories alter column title drop not null;
alter table public.stories alter column prompt drop not null;

commit;
