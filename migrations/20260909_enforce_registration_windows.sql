create or replace function public.can_register_for_tournament(p_tournament_id text)
returns table(allowed boolean, mode text, reason text)
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_status text;
  v_user uuid := auth.uid();
  v_opens_at timestamptz;
  v_closes_at timestamptz;
begin
  select status, registration_opens_at, registration_closes_at
    into v_status, v_opens_at, v_closes_at
  from public.tournaments where id = p_tournament_id;

  if v_status is null then
    return query select false, 'closed'::text, 'Турнир не найден'::text;
    return;
  end if;

  if v_status = 'registration' then
    if v_opens_at is not null and now() < v_opens_at then
      return query select false, 'closed'::text, 'Регистрация ещё не началась'::text;
      return;
    end if;
    if v_closes_at is not null and now() > v_closes_at then
      return query select false, 'closed'::text, 'Регистрация уже завершена'::text;
      return;
    end if;
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

create or replace function private.ensure_tournament_registration_open()
returns trigger
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_status text;
  v_opens_at timestamptz;
  v_closes_at timestamptz;
begin
  select status, registration_opens_at, registration_closes_at
    into v_status, v_opens_at, v_closes_at
  from public.tournaments where id = new.tournament_id;

  if v_status = 'registration' then
    if v_opens_at is not null and now() < v_opens_at then raise exception 'Регистрация ещё не началась'; end if;
    if v_closes_at is not null and now() > v_closes_at then raise exception 'Регистрация уже завершена'; end if;
    return new;
  end if;

  if v_status = 'draft' and auth.uid() is not null and exists (
    select 1 from private.tournament_testers tt
    where tt.tournament_id = new.tournament_id and tt.user_id = auth.uid()
  ) then
    return new;
  end if;

  raise exception 'Регистрация на этот турнир закрыта';
end;
$$;

create or replace function public.submit_tournament_application(p_tournament_id text, p_team_name text, p_tag text, p_roster jsonb)
returns table(team_id text, application_id uuid, application_status text)
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_user uuid := auth.uid();
  v_status text;
  v_team_size integer;
  v_max_reserves integer;
  v_opens_at timestamptz;
  v_closes_at timestamptz;
  v_allowed boolean := false;
  v_team_id text;
  v_application_id uuid;
  v_roster_count integer;
  v_main_count integer;
  v_reserve_count integer;
  v_captain_count integer;
  v_first_captain boolean;
begin
  if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if;
  if nullif(trim(p_team_name), '') is null then raise exception 'Укажите название команды'; end if;
  if nullif(trim(p_tag), '') is null or length(trim(p_tag)) < 2 or length(trim(p_tag)) > 5 then
    raise exception 'Тег команды должен содержать от 2 до 5 символов';
  end if;

  select status, team_size, max_reserves, registration_opens_at, registration_closes_at
    into v_status, v_team_size, v_max_reserves, v_opens_at, v_closes_at
  from public.tournaments where id = p_tournament_id;
  if v_status is null then raise exception 'Турнир не найден'; end if;

  if v_status = 'registration' then
    if v_opens_at is not null and now() < v_opens_at then raise exception 'Регистрация ещё не началась'; end if;
    if v_closes_at is not null and now() > v_closes_at then raise exception 'Регистрация уже завершена'; end if;
    v_allowed := true;
  elsif v_status = 'draft' and exists (
    select 1 from private.tournament_testers tt
    where tt.tournament_id = p_tournament_id and tt.user_id = v_user
  ) then
    v_allowed := true;
  end if;
  if not v_allowed then raise exception 'Регистрация на этот турнир закрыта'; end if;

  if jsonb_typeof(p_roster) <> 'array' then raise exception 'Некорректный формат состава'; end if;
  v_roster_count := jsonb_array_length(p_roster);
  if v_team_size is null then v_team_size := 5; end if;
  if v_max_reserves is null then v_max_reserves := 0; end if;

  select count(*) filter (where coalesce((x->>'reserve')::boolean,false) = false),
         count(*) filter (where coalesce((x->>'reserve')::boolean,false) = true),
         count(*) filter (where coalesce((x->>'captain')::boolean,false) = true)
  into v_main_count, v_reserve_count, v_captain_count
  from jsonb_array_elements(p_roster) x;

  select coalesce((p_roster->0->>'captain')::boolean,false) into v_first_captain;

  if v_main_count <> v_team_size then raise exception 'Основной состав должен содержать ровно % игроков', v_team_size; end if;
  if v_reserve_count > v_max_reserves then raise exception 'Допускается не более % запасных игроков', v_max_reserves; end if;
  if v_roster_count > v_team_size + v_max_reserves then raise exception 'Превышен максимальный размер состава'; end if;
  if v_captain_count <> 1 or not v_first_captain then raise exception 'Капитаном должен быть только первый игрок'; end if;

  if exists (select 1 from public.tournament_applications where tournament_id=p_tournament_id and submitted_by=v_user) then
    raise exception 'Вы уже подали заявку на этот турнир';
  end if;
  if exists (select 1 from public.teams where tournament_id=p_tournament_id and upper(tag)=upper(trim(p_tag))) then
    raise exception 'Команда с таким тегом уже существует в этом турнире';
  end if;

  insert into public.teams (tournament_id,name,tag,logo,region,owner_id,roster_public,registration_status)
  values (p_tournament_id,trim(p_team_name),upper(trim(p_tag)),upper(left(trim(p_tag),3)),'Россия',v_user,'[]'::jsonb,'pending')
  returning id into v_team_id;

  insert into public.tournament_applications (tournament_id,team_id,submitted_by,roster_private,status)
  values (p_tournament_id,v_team_id,v_user,p_roster,'pending') returning id into v_application_id;

  return query select v_team_id,v_application_id,'pending'::text;
end;
$$;
