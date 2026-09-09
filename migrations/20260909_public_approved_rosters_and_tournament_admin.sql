create or replace function private.public_roster_from_private(p_roster jsonb)
returns jsonb
language sql
immutable
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'full_name', nullif(trim(item->>'full_name'), ''),
        'captain', coalesce((item->>'captain')::boolean, false),
        'reserve', coalesce((item->>'reserve')::boolean, false)
      ) order by ord
    ),
    '[]'::jsonb
  )
  from jsonb_array_elements(coalesce(p_roster, '[]'::jsonb)) with ordinality as x(item, ord)
  where nullif(trim(item->>'full_name'), '') is not null;
$$;

create or replace function public.admin_review_application(p_application_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path to 'public', 'private', 'auth'
as $$
declare
  v_team_id text;
  v_roster jsonb;
begin
  if not public.is_tournament_admin() then raise exception 'Недостаточно прав'; end if;
  if p_status not in ('approved','rejected') then raise exception 'Некорректный статус'; end if;

  select team_id, roster_private
  into v_team_id, v_roster
  from public.tournament_applications
  where id = p_application_id
  for update;

  if v_team_id is null then raise exception 'Заявка не найдена'; end if;

  update public.tournament_applications
  set status = p_status, reviewed_at = now()
  where id = p_application_id;

  update public.teams
  set registration_status = p_status,
      roster_public = case
        when p_status = 'approved' then private.public_roster_from_private(v_roster)
        else '[]'::jsonb
      end
  where id = v_team_id;
end;
$$;

grant execute on function public.admin_review_application(uuid,text) to authenticated;

create or replace function public.admin_update_tournament(
  p_tournament_id text,
  p_name text,
  p_description text,
  p_start_date date,
  p_end_date date,
  p_format text,
  p_max_teams integer,
  p_status text,
  p_registration_opens_at timestamptz,
  p_registration_closes_at timestamptz,
  p_team_size smallint,
  p_max_reserves smallint
)
returns public.tournaments
language plpgsql
security definer
set search_path to 'public', 'private', 'auth'
as $$
declare
  v_row public.tournaments;
begin
  if not public.is_tournament_admin() then raise exception 'Недостаточно прав'; end if;
  if p_status not in ('draft','upcoming','registration','ongoing','live','finished','cancelled') then raise exception 'Некорректный статус турнира'; end if;
  if p_name is null or length(trim(p_name)) < 2 then raise exception 'Укажите название турнира'; end if;
  if p_start_date is not null and p_end_date is not null and p_end_date < p_start_date then raise exception 'Дата окончания не может быть раньше даты начала'; end if;
  if p_registration_opens_at is not null and p_registration_closes_at is not null and p_registration_closes_at <= p_registration_opens_at then raise exception 'Окончание регистрации должно быть позже её начала'; end if;
  if p_max_teams is not null and p_max_teams < 2 then raise exception 'Лимит команд должен быть не меньше 2'; end if;
  if p_team_size is not null and p_team_size < 1 then raise exception 'Основной состав должен содержать минимум 1 игрока'; end if;
  if p_max_reserves is not null and p_max_reserves < 0 then raise exception 'Количество запасных не может быть отрицательным'; end if;

  update public.tournaments
  set name = trim(p_name),
      description = nullif(trim(coalesce(p_description,'')),''),
      start_date = p_start_date,
      end_date = p_end_date,
      format = nullif(trim(coalesce(p_format,'')),''),
      max_teams = p_max_teams,
      status = p_status,
      registration_opens_at = p_registration_opens_at,
      registration_closes_at = p_registration_closes_at,
      team_size = p_team_size,
      max_reserves = p_max_reserves,
      updated_at = now()
  where id = p_tournament_id
  returning * into v_row;

  if v_row.id is null then raise exception 'Турнир не найден'; end if;
  return v_row;
end;
$$;

grant execute on function public.admin_update_tournament(text,text,text,date,date,text,integer,text,timestamptz,timestamptz,smallint,smallint) to authenticated;

update public.teams t
set roster_public = private.public_roster_from_private(a.roster_private)
from public.tournament_applications a
where a.team_id = t.id
  and a.status = 'approved'
  and t.registration_status = 'approved';
