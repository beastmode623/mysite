-- Draft tournaments + registration safety guard
-- Applied to Supabase project wijtkxzleuqdaabfiwsh on 2026-09-09.

alter table public.tournaments alter column start_date drop not null;
alter table public.tournaments alter column format drop not null;
alter table public.tournaments alter column max_teams drop not null;

alter table public.tournaments add column if not exists registration_opens_at timestamptz;
alter table public.tournaments add column if not exists registration_closes_at timestamptz;
alter table public.tournaments add column if not exists team_size smallint;
alter table public.tournaments add column if not exists max_reserves smallint;

alter table public.tournaments drop constraint if exists tournaments_status_check;
alter table public.tournaments add constraint tournaments_status_check
  check (status in ('draft','upcoming','registration','ongoing','live','finished','cancelled'));

alter table public.tournaments drop constraint if exists tournaments_max_teams_check;
alter table public.tournaments add constraint tournaments_max_teams_check
  check (max_teams is null or max_teams > 0);

alter table public.tournaments drop constraint if exists tournaments_team_size_check;
alter table public.tournaments add constraint tournaments_team_size_check
  check (team_size is null or team_size > 0);

alter table public.tournaments drop constraint if exists tournaments_max_reserves_check;
alter table public.tournaments add constraint tournaments_max_reserves_check
  check (max_reserves is null or max_reserves >= 0);

create or replace function private.ensure_tournament_registration_open()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  t public.tournaments%rowtype;
begin
  select * into t from public.tournaments where id = new.tournament_id;
  if not found then raise exception 'Tournament not found'; end if;
  if t.status <> 'registration' then raise exception 'Tournament registration is not open'; end if;
  if t.registration_opens_at is not null and now() < t.registration_opens_at then
    raise exception 'Tournament registration has not opened yet';
  end if;
  if t.registration_closes_at is not null and now() > t.registration_closes_at then
    raise exception 'Tournament registration is closed';
  end if;
  return new;
end;
$$;

drop trigger if exists teams_registration_guard on public.teams;
create trigger teams_registration_guard
before insert on public.teams
for each row execute function private.ensure_tournament_registration_open();
