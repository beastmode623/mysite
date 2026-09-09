-- CS2 roster rules and admin review workflow.
-- Production migration already applied to Supabase.

alter table public.teams add column if not exists registration_status text not null default 'approved';

-- CS2 future tournament: 5 main players + up to 2 optional reserves.
update public.tournaments
set team_size = 5, max_reserves = 2
where id = 'cs2-future-draft';

-- Application submission is validated server-side:
-- exactly 5 main players, maximum 2 reserves, and only player #1 may be captain.
-- Pending/rejected teams are hidden from public team reads; owners can still see their own.
-- Admin RPCs:
--   public.is_tournament_admin()
--   public.admin_list_applications(text)
--   public.admin_review_application(uuid,text)
-- The detailed function bodies are tracked in Supabase migrations/history.