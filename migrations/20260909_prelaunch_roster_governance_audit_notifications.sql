-- Applied to Supabase production on 2026-09-09.
-- Adds roster governance, audit, admin recovery, lifecycle locks and in-site notifications.

alter table public.tournament_applications add column if not exists reviewed_by uuid references auth.users(id) on delete set null;

create table if not exists private.team_activity_log (
  id uuid primary key default gen_random_uuid(),
  team_id text not null references public.teams(id) on delete cascade,
  tournament_id text not null references public.tournaments(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  target_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists team_activity_log_team_time_idx on private.team_activity_log(team_id, created_at desc);
create index if not exists team_activity_log_tournament_time_idx on private.team_activity_log(tournament_id, created_at desc);

create table if not exists private.user_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null,
  title text not null,
  body text,
  href text,
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index if not exists user_notifications_user_time_idx on private.user_notifications(user_id, created_at desc);
create index if not exists user_notifications_unread_idx on private.user_notifications(user_id, read_at) where read_at is null;

create table if not exists private.team_roster_change_requests (
  id uuid primary key default gen_random_uuid(),
  team_id text not null references public.teams(id) on delete cascade,
  tournament_id text not null references public.tournaments(id) on delete cascade,
  requested_by uuid not null references auth.users(id) on delete cascade,
  main_member_id uuid not null references public.team_members(id) on delete cascade,
  reserve_member_id uuid not null references public.team_members(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  requested_at timestamptz not null default now(),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  review_note text,
  check (main_member_id <> reserve_member_id)
);
create unique index if not exists one_pending_roster_change_per_team on private.team_roster_change_requests(team_id) where status='pending';

-- Helper functions and public RPCs are defined in the applied Supabase migration named
-- prelaunch_roster_governance_audit_notifications. The production migration includes:
-- private.ensure_team_changes_open
-- private.notify_user
-- public.get_my_notifications / mark_notification_read
-- public.get_my_roster_change_requests / captain_request_role_swap
-- public.admin_list_roster_change_requests / admin_review_roster_change_request
-- public.admin_reassign_team_captain / admin_release_team_slot / admin_get_team_activity
-- lifecycle-aware replacements for invitation, acceptance, captain transfer, leave and application review.
