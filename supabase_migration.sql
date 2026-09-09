create extension if not exists pgcrypto;
create schema if not exists private;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null unique check (char_length(nickname) between 2 and 32),
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.tournaments (
  id text primary key,
  name text not null,
  game text not null,
  description text not null default '',
  start_date date not null,
  end_date date,
  format text not null,
  status text not null check (status in ('upcoming','registration','ongoing','finished','cancelled')),
  max_teams integer not null check (max_teams > 0),
  winner_team_id text,
  runner_up_team_id text,
  playoffs jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.teams (
  id text primary key default gen_random_uuid()::text,
  tournament_id text not null references public.tournaments(id) on delete cascade,
  name text not null,
  tag text not null,
  logo text,
  region text,
  owner_id uuid references auth.users(id) on delete set null,
  group_position integer,
  group_stage jsonb not null default '{}'::jsonb,
  roster_public jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  unique (tournament_id, name),
  unique (tournament_id, tag)
);

create table if not exists public.tournament_applications (
  id uuid primary key default gen_random_uuid(),
  tournament_id text not null references public.tournaments(id) on delete cascade,
  team_id text not null references public.teams(id) on delete cascade,
  submitted_by uuid not null references auth.users(id) on delete cascade,
  roster_private jsonb not null check (jsonb_typeof(roster_private) = 'array'),
  status text not null default 'pending' check (status in ('pending','approved','rejected','withdrawn')),
  submitted_at timestamptz not null default now(),
  reviewed_at timestamptz,
  unique (tournament_id, team_id)
);

create index if not exists teams_tournament_idx on public.teams(tournament_id);
create index if not exists teams_owner_idx on public.teams(owner_id);
create index if not exists tournament_applications_submitter_idx on public.tournament_applications(submitted_by);


create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, nickname)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data->>'nickname'), ''), split_part(new.email, '@', 1), 'player-' || left(new.id::text, 8))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;
revoke all on function private.handle_new_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function private.handle_new_user();


alter table public.profiles enable row level security;
alter table public.tournaments enable row level security;
alter table public.teams enable row level security;
alter table public.tournament_applications enable row level security;

revoke all on public.profiles from anon, authenticated;
revoke all on public.tournaments from anon, authenticated;
revoke all on public.teams from anon, authenticated;
revoke all on public.tournament_applications from anon, authenticated;

grant select on public.profiles to anon, authenticated;
grant select on public.tournaments to anon, authenticated;
grant select on public.teams to anon, authenticated;
grant insert, update on public.teams to authenticated;
grant select, insert, update on public.tournament_applications to authenticated;

drop policy if exists profiles_public_read on public.profiles;
create policy profiles_public_read on public.profiles for select to anon, authenticated using (true);

drop policy if exists profiles_owner_update on public.profiles;
create policy profiles_owner_update on public.profiles for update to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

drop policy if exists tournaments_public_read on public.tournaments;
create policy tournaments_public_read on public.tournaments for select to anon, authenticated using (true);

drop policy if exists teams_public_read on public.teams;
create policy teams_public_read on public.teams for select to anon, authenticated using (true);

drop policy if exists teams_owner_insert on public.teams;
create policy teams_owner_insert on public.teams for insert to authenticated
with check ((select auth.uid()) = owner_id);

drop policy if exists teams_owner_update on public.teams;
create policy teams_owner_update on public.teams for update to authenticated
using ((select auth.uid()) = owner_id)
with check ((select auth.uid()) = owner_id);

drop policy if exists applications_owner_read on public.tournament_applications;
create policy applications_owner_read on public.tournament_applications for select to authenticated
using ((select auth.uid()) = submitted_by);

drop policy if exists applications_owner_insert on public.tournament_applications;
create policy applications_owner_insert on public.tournament_applications for insert to authenticated
with check ((select auth.uid()) = submitted_by and exists (
  select 1 from public.teams t where t.id = team_id and t.owner_id = (select auth.uid())
));

drop policy if exists applications_owner_update on public.tournament_applications;
create policy applications_owner_update on public.tournament_applications for update to authenticated
using ((select auth.uid()) = submitted_by)
with check ((select auth.uid()) = submitted_by);


insert into public.tournaments (id,name,game,description,start_date,end_date,format,status,max_teams,winner_team_id,runner_up_team_id,playoffs)
values ('dota2-winter-2026','Dota 2 Ingogames 2026. Season 1','Dota 2','Зимний чемпионат по Dota 2','2026-01-27','2026-04-19','Group Stage + Double Elimination Playoffs','finished',12,'team-1','team-8','{"upperBracket":{"playIn":[{"id":"ub-playin-1","round":"Play-In","team1":"team-5","team2":"team-12","score1":1,"score2":0,"winner":"team-5","date":"2026-02-24"},{"id":"ub-playin-2","round":"Play-In","team1":"team-6","team2":"team-11","score1":1,"score2":0,"winner":"team-6","date":"2026-02-24"},{"id":"ub-playin-3","round":"Play-In","team1":"team-7","team2":"team-10","score1":0,"score2":1,"winner":"team-10","date":"2026-02-24"},{"id":"ub-playin-4","round":"Play-In","team1":"team-8","team2":"team-9","score1":1,"score2":0,"winner":"team-8","date":"2026-02-28"}],"roundOf16":[{"id":"ub-r16-1","round":"1/8 финала","team1":"team-1","team2":"team-5","score1":1,"score2":0,"winner":"team-1","date":"2026-03-04"},{"id":"ub-r16-2","round":"1/8 финала","team1":"team-2","team2":"team-6","score1":0,"score2":1,"winner":"team-6","date":"2026-03-07"},{"id":"ub-r16-3","round":"1/8 финала","team1":"team-3","team2":"team-10","score1":1,"score2":0,"winner":"team-3","date":"2026-03-07"},{"id":"ub-r16-4","round":"1/8 финала","team1":"team-4","team2":"team-8","score1":0,"score2":1,"winner":"team-8","date":"2026-03-09"}],"semifinals":[{"id":"ub-sf-1","round":"1/2 финала","team1":"team-1","team2":"team-6","score1":1,"score2":0,"winner":"team-1","date":"2026-03-19"},{"id":"ub-sf-2","round":"1/2 финала","team1":"team-3","team2":"team-8","score1":0,"score2":1,"winner":"team-8","date":"2026-03-27"}],"final":{"id":"ub-final","round":"Финал UB","team1":"team-1","team2":"team-8","score1":2,"score2":0,"winner":"team-1","date":"2026-04-05"}},"lowerBracket":{"round1":[{"id":"lb-r1-1","round":"Раунд 1","team1":"team-10","team2":"team-12","score1":1,"score2":0,"winner":"team-10","date":"2026-03-10"},{"id":"lb-r1-2","round":"Раунд 1","team1":"team-4","team2":"team-11","score1":1,"score2":0,"winner":"team-4","date":"2026-03-10"},{"id":"lb-r1-3","round":"Раунд 1","team1":"team-5","team2":"team-7","score1":1,"score2":0,"winner":"team-5","date":"2026-03-11"},{"id":"lb-r1-4","round":"Раунд 1","team1":"team-2","team2":"team-9","score1":0,"score2":1,"winner":"team-9","date":"2026-03-14"}],"roundOf16":[{"id":"lb-r16-1","round":"1/8 финала","team1":"team-10","team2":"team-4","score1":0,"score2":1,"winner":"team-4","date":"2026-03-15"},{"id":"lb-r16-2","round":"1/8 финала","team1":"team-5","team2":"team-9","score1":1,"score2":0,"winner":"team-5","date":"2026-03-22"}],"quarterfinals":[{"id":"lb-qf-1","round":"1/4 финала","team1":"team-6","team2":"team-4","score1":0,"score2":1,"winner":"team-4","date":"2026-04-06"},{"id":"lb-qf-2","round":"1/4 финала","team1":"team-3","team2":"team-5","score1":1,"score2":0,"winner":"team-3","date":"2026-04-05"}],"semifinals":[{"id":"lb-sf-1","round":"1/2 финала","team1":"team-4","team2":"team-3","score1":0,"score2":1,"winner":"team-3","date":"2026-04-10"}],"final":{"id":"lb-final","round":"Финал LB","team1":"team-8","team2":"team-3","score1":2,"score2":0,"winner":"team-8","date":"2026-04-11"}},"grandFinal":{"id":"grand-final","round":"Гранд-финал","team1":"team-1","team2":"team-8","score1":3,"score2":0,"winner":"team-1","date":"2026-04-18"}}'::jsonb)
on conflict (id) do update set
name=excluded.name, game=excluded.game, description=excluded.description, start_date=excluded.start_date,
end_date=excluded.end_date, format=excluded.format, status=excluded.status, max_teams=excluded.max_teams,
winner_team_id=excluded.winner_team_id, runner_up_team_id=excluded.runner_up_team_id,
playoffs=excluded.playoffs, updated_at=now();

insert into public.teams (id,tournament_id,name,tag,logo,region,group_position,group_stage,roster_public)
values ('team-1','dota2-winter-2026','Трон Застрахован','TAG1','T1','Россия',1,'{"position":1,"wins":4,"losses":0,"points":12,"mapDifference":"+4"}'::jsonb,'[{"id":"player-1-1","name":"dns","initials":"NI","role":"Carry","stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-1-2","name":"raketa-","initials":"NI","role":"Mid","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-1-3","name":"vanchecson","initials":"NI","role":"Offlane","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-1-4","name":"So''GBo","initials":"NI","role":"Support","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-1-5","name":"Danvis","initials":"NI","role":"Hard Support","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}}]'::jsonb)
on conflict (id) do update set name=excluded.name, tag=excluded.tag, logo=excluded.logo, region=excluded.region,
group_position=excluded.group_position, group_stage=excluded.group_stage, roster_public=excluded.roster_public;
insert into public.teams (id,tournament_id,name,tag,logo,region,group_position,group_stage,roster_public)
values ('team-2','dota2-winter-2026','Executive Force','TAG2','T2','Россия',2,'{"position":2,"wins":4,"losses":0,"points":12,"mapDifference":"+4"}'::jsonb,'[{"id":"player-2-1","name":"Darkness","initials":"NI","role":"Carry","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-2-2","name":"Бондарь Илья","initials":"NI","role":"Mid","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-2-3","name":"Андреев Владимир","initials":"NI","role":"Offlane","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-2-4","name":"GABR","initials":"NI","role":"Support","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-2-5","name":"Вагин Аскендеров","initials":"NI","role":"Hard Support","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}}]'::jsonb)
on conflict (id) do update set name=excluded.name, tag=excluded.tag, logo=excluded.logo, region=excluded.region,
group_position=excluded.group_position, group_stage=excluded.group_stage, roster_public=excluded.roster_public;
insert into public.teams (id,tournament_id,name,tag,logo,region,group_position,group_stage,roster_public)
values ('team-3','dota2-winter-2026','Punishers','TAG3','T3','Россия',3,'{"position":3,"wins":3,"losses":1,"points":9,"mapDifference":"+2"}'::jsonb,'[{"id":"player-3-1","name":"sayonara","initials":"NI","role":"Carry","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-3-2","name":"Даниил колбасенко","initials":"NI","role":"Mid","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-3-3","name":"d133ct","initials":"NI","role":"Offlane","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-3-4","name":"Черепаха Хлов","initials":"NI","role":"Support","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-3-5","name":"Angel","initials":"NI","role":"Hard Support","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}}]'::jsonb)
on conflict (id) do update set name=excluded.name, tag=excluded.tag, logo=excluded.logo, region=excluded.region,
group_position=excluded.group_position, group_stage=excluded.group_stage, roster_public=excluded.roster_public;
insert into public.teams (id,tournament_id,name,tag,logo,region,group_position,group_stage,roster_public)
values ('team-4','dota2-winter-2026','Kiss Meow','TAG4','T4','Россия',4,'{"position":4,"wins":3,"losses":1,"points":9,"mapDifference":"+2"}'::jsonb,'[{"id":"player-4-1","name":"Thunder","initials":"NI","role":"Carry","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-4-2","name":"hesoyam~","initials":"NI","role":"Mid","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-4-3","name":"Overr1de","initials":"NI","role":"Offlane","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-4-4","name":"1417","initials":"NI","role":"Support","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-4-5","name":"EasyMoney","initials":"NI","role":"Hard Support","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}}]'::jsonb)
on conflict (id) do update set name=excluded.name, tag=excluded.tag, logo=excluded.logo, region=excluded.region,
group_position=excluded.group_position, group_stage=excluded.group_stage, roster_public=excluded.roster_public;
insert into public.teams (id,tournament_id,name,tag,logo,region,group_position,group_stage,roster_public)
values ('team-5','dota2-winter-2026','Asphalt8','TAG5','T5','Россия',5,'{"position":5,"wins":3,"losses":1,"points":9,"mapDifference":"+2"}'::jsonb,'[{"id":"player-5-1","name":"Александр","initials":"NI","role":"Carry","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-5-2","name":"ケック","initials":"NI","role":"Mid","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-5-3","name":"anung un rama","initials":"NI","role":"Offlane","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-5-4","name":"GInOff","initials":"NI","role":"Support","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-5-5","name":"Shipa","initials":"NI","role":"Hard Support","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}}]'::jsonb)
on conflict (id) do update set name=excluded.name, tag=excluded.tag, logo=excluded.logo, region=excluded.region,
group_position=excluded.group_position, group_stage=excluded.group_stage, roster_public=excluded.roster_public;
insert into public.teams (id,tournament_id,name,tag,logo,region,group_position,group_stage,roster_public)
values ('team-6','dota2-winter-2026','No Risk','TAG6','T6','Россия',6,'{"position":6,"wins":2,"losses":2,"points":6,"mapDifference":"0"}'::jsonb,'[{"id":"player-6-1","name":"natlexx","initials":"NI","role":"Carry","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-6-2","name":"Felix","initials":"NI","role":"Mid","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-6-3","name":"Diana 17см","initials":"NI","role":"Offlane","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-6-4","name":"Crazy_Toater","initials":"NI","role":"Support","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-6-5","name":"Amahasla","initials":"NI","role":"Hard Support","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}}]'::jsonb)
on conflict (id) do update set name=excluded.name, tag=excluded.tag, logo=excluded.logo, region=excluded.region,
group_position=excluded.group_position, group_stage=excluded.group_stage, roster_public=excluded.roster_public;
insert into public.teams (id,tournament_id,name,tag,logo,region,group_position,group_stage,roster_public)
values ('team-7','dota2-winter-2026','GLOW','TAG7','T7','Россия',7,'{"position":7,"wins":2,"losses":2,"points":6,"mapDifference":"0"}'::jsonb,'[{"id":"player-7-1","name":"mydachyo[*‿*]","initials":"NI","role":"Carry","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-7-2","name":"Gvadelupa","initials":"NI","role":"Mid","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-7-3","name":"naxuinamotano","initials":"NI","role":"Offlane","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-7-4","name":"arisha","initials":"NI","role":"Support","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-7-5","name":"Na''Srimple''Vi","initials":"NI","role":"Hard Support","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}}]'::jsonb)
on conflict (id) do update set name=excluded.name, tag=excluded.tag, logo=excluded.logo, region=excluded.region,
group_position=excluded.group_position, group_stage=excluded.group_stage, roster_public=excluded.roster_public;
insert into public.teams (id,tournament_id,name,tag,logo,region,group_position,group_stage,roster_public)
values ('team-8','dota2-winter-2026','Шаманчик Связывай','TAG8','T8','Россия',8,'{"position":8,"wins":2,"losses":2,"points":6,"mapDifference":"0"}'::jsonb,'[{"id":"player-8-1","name":"ОлегаFriend","initials":"NI","role":"Carry","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-8-2","name":"кукуруза","initials":"NI","role":"Mid","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-8-3","name":"osago enjoyer","initials":"NI","role":"Offlane","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-8-4","name":"Gandalf the Grey","initials":"NI","role":"Support","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-8-5","name":"LIMP.BRT","initials":"NI","role":"Hard Support","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}}]'::jsonb)
on conflict (id) do update set name=excluded.name, tag=excluded.tag, logo=excluded.logo, region=excluded.region,
group_position=excluded.group_position, group_stage=excluded.group_stage, roster_public=excluded.roster_public;
insert into public.teams (id,tournament_id,name,tag,logo,region,group_position,group_stage,roster_public)
values ('team-9','dota2-winter-2026','Arcane Actuaries','TAG9','T9','Россия',9,'{"position":9,"wins":1,"losses":3,"points":3,"mapDifference":"-2"}'::jsonb,'[{"id":"player-9-1","name":"zybeck","initials":"NI","role":"Carry","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-9-2","name":"GreeNJesus","initials":"NI","role":"Mid","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-9-3","name":"Kantari","initials":"NI","role":"Offlane","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-9-4","name":"ウエコムンド","initials":"NI","role":"Support","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-9-5","name":"Fantomas","initials":"NI","role":"Hard Support","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}}]'::jsonb)
on conflict (id) do update set name=excluded.name, tag=excluded.tag, logo=excluded.logo, region=excluded.region,
group_position=excluded.group_position, group_stage=excluded.group_stage, roster_public=excluded.roster_public;
insert into public.teams (id,tournament_id,name,tag,logo,region,group_position,group_stage,roster_public)
values ('team-10','dota2-winter-2026','Синие Варды','TA10','T10','Россия',10,'{"position":10,"wins":0,"losses":4,"points":0,"mapDifference":"-4"}'::jsonb,'[{"id":"player-10-1","name":"Vinch","initials":"NI","role":"Carry","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-10-2","name":"Роман","initials":"NI","role":"Mid","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-10-3","name":"sauron","initials":"NI","role":"Offlane","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-10-4","name":"TVAR","initials":"NI","role":"Support","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}},{"id":"player-10-5","name":"Sirota_69","initials":"NI","role":"Hard Support","heroPool":[],"stats":{"kills":0,"deaths":0,"assists":0,"gpm":0,"xpm":0}}]'::jsonb)
on conflict (id) do update set name=excluded.name, tag=excluded.tag, logo=excluded.logo, region=excluded.region,
group_position=excluded.group_position, group_stage=excluded.group_stage, roster_public=excluded.roster_public;
insert into public.teams (id,tournament_id,name,tag,logo,region,group_position,group_stage,roster_public)
values ('team-11','dota2-winter-2026','Team 4','TA11','T11','Россия',11,'{"position":11,"wins":0,"losses":4,"points":0,"mapDifference":"-4"}'::jsonb,'[]'::jsonb)
on conflict (id) do update set name=excluded.name, tag=excluded.tag, logo=excluded.logo, region=excluded.region,
group_position=excluded.group_position, group_stage=excluded.group_stage, roster_public=excluded.roster_public;
insert into public.teams (id,tournament_id,name,tag,logo,region,group_position,group_stage,roster_public)
values ('team-12','dota2-winter-2026','Team 9','TA12','T12','Россия',12,'{"position":12,"wins":0,"losses":4,"points":0,"mapDifference":"-4"}'::jsonb,'[]'::jsonb)
on conflict (id) do update set name=excluded.name, tag=excluded.tag, logo=excluded.logo, region=excluded.region,
group_position=excluded.group_position, group_stage=excluded.group_stage, roster_public=excluded.roster_public;