create table if not exists private.tournament_testers (
  tournament_id text not null references public.tournaments(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (tournament_id, user_id)
);

insert into private.tournament_testers (tournament_id, user_id)
select 'cs2-future-draft', id
from auth.users
where email = 'rew1nd6237@yandex.ru'
on conflict do nothing;

create or replace function public.can_register_for_tournament(p_tournament_id text)
returns table(allowed boolean, mode text, reason text)
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_status text;
  v_user uuid := auth.uid();
begin
  select status into v_status from public.tournaments where id = p_tournament_id;
  if v_status is null then
    return query select false, 'closed'::text, 'Турнир не найден'::text;
    return;
  end if;
  if v_status = 'registration' then
    return query select true, 'public'::text, 'Регистрация открыта'::text;
    return;
  end if;
  if v_status = 'draft' and v_user is not null and exists (
    select 1 from private.tournament_testers tt
    where tt.tournament_id = p_tournament_id and tt.user_id = v_user
  ) then
    return query select true, 'test'::text, 'Тестовый режим'::text;
    return;
  end if;
  return query select false, 'closed'::text,
    case when v_status = 'draft' then 'Турнир находится в черновике' else 'Регистрация закрыта' end;
end;
$$;

grant execute on function public.can_register_for_tournament(text) to anon, authenticated;

create or replace function private.ensure_tournament_registration_open()
returns trigger
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_status text;
  v_user uuid := auth.uid();
begin
  select status into v_status from public.tournaments where id = new.tournament_id;
  if v_status = 'registration' then return new; end if;
  if v_status = 'draft' and v_user is not null and exists (
    select 1 from private.tournament_testers tt
    where tt.tournament_id = new.tournament_id and tt.user_id = v_user
  ) then return new; end if;
  raise exception 'Регистрация на этот турнир закрыта';
end;
$$;

create unique index if not exists tournament_applications_one_per_user_tournament
  on public.tournament_applications (tournament_id, submitted_by);

create unique index if not exists teams_unique_tag_per_tournament
  on public.teams (tournament_id, lower(tag));

create or replace function public.submit_tournament_application(
  p_tournament_id text,
  p_team_name text,
  p_tag text,
  p_roster jsonb
)
returns table(team_id text, application_id uuid, application_status text)
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_user uuid := auth.uid();
  v_status text;
  v_team_size integer;
  v_allowed boolean := false;
  v_team_id text;
  v_application_id uuid;
  v_roster_count integer;
begin
  if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if;
  if nullif(trim(p_team_name), '') is null then raise exception 'Укажите название команды'; end if;
  if nullif(trim(p_tag), '') is null or length(trim(p_tag)) < 2 or length(trim(p_tag)) > 5 then raise exception 'Тег команды должен содержать от 2 до 5 символов'; end if;
  select status, team_size into v_status, v_team_size from public.tournaments where id = p_tournament_id;
  if v_status is null then raise exception 'Турнир не найден'; end if;
  if v_status = 'registration' then v_allowed := true;
  elsif v_status = 'draft' and exists (
    select 1 from private.tournament_testers tt
    where tt.tournament_id = p_tournament_id and tt.user_id = v_user
  ) then v_allowed := true; end if;
  if not v_allowed then raise exception 'Регистрация на этот турнир закрыта'; end if;
  if jsonb_typeof(p_roster) <> 'array' then raise exception 'Некорректный формат состава'; end if;
  v_roster_count := jsonb_array_length(p_roster);
  if v_team_size is not null and v_roster_count < v_team_size then raise exception 'Недостаточно игроков в основном составе'; end if;
  if exists (select 1 from public.tournament_applications where tournament_id = p_tournament_id and submitted_by = v_user) then raise exception 'Вы уже подали заявку на этот турнир'; end if;
  insert into public.teams (tournament_id, name, tag, logo, region, owner_id, roster_public)
  values (p_tournament_id, trim(p_team_name), upper(trim(p_tag)), upper(left(trim(p_tag), 3)), 'Россия', v_user, '[]'::jsonb)
  returning id into v_team_id;
  insert into public.tournament_applications (tournament_id, team_id, submitted_by, roster_private, status)
  values (p_tournament_id, v_team_id, v_user, p_roster, 'pending') returning id into v_application_id;
  return query select v_team_id, v_application_id, 'pending'::text;
end;
$$;

grant execute on function public.submit_tournament_application(text,text,text,jsonb) to authenticated;