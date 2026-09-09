create table if not exists private.team_captain_transfers (
  id uuid primary key default gen_random_uuid(),
  team_id text not null references public.teams(id) on delete cascade,
  tournament_id text not null references public.tournaments(id) on delete cascade,
  from_user_id uuid not null references auth.users(id) on delete restrict,
  to_user_id uuid not null references auth.users(id) on delete restrict,
  transferred_at timestamptz not null default now()
);

create index if not exists team_captain_transfers_team_idx
  on private.team_captain_transfers(team_id, transferred_at desc);

create or replace function public.transfer_team_captaincy(
  p_team_id text,
  p_target_member_id uuid
)
returns text
language plpgsql
security definer
set search_path = public, private, auth
as $function$
declare
  v_user uuid := auth.uid();
  v_tournament_id text;
  v_target_user uuid;
  v_target_role text;
  v_old_member_id uuid;
begin
  if v_user is null then
    raise exception 'Необходимо войти в аккаунт';
  end if;

  select t.tournament_id
    into v_tournament_id
  from public.teams t
  where t.id = p_team_id
    and t.owner_id = v_user
  for update;

  if v_tournament_id is null then
    raise exception 'Команда не найдена или у вас нет прав капитана';
  end if;

  select tm.user_id, tm.role
    into v_target_user, v_target_role
  from public.team_members tm
  where tm.id = p_target_member_id
    and tm.team_id = p_team_id
  for update;

  if v_target_user is null then
    raise exception 'Передать капитанство можно только игроку с подтверждённым аккаунтом';
  end if;

  if v_target_user = v_user then
    raise exception 'Вы уже являетесь капитаном этой команды';
  end if;

  if v_target_role = 'reserve' then
    raise exception 'Сначала переведите запасного игрока в основной состав';
  end if;

  select tm.id
    into v_old_member_id
  from public.team_members tm
  where tm.team_id = p_team_id
    and tm.user_id = v_user
  for update;

  if v_old_member_id is null then
    raise exception 'Текущий капитан не найден в составе команды';
  end if;

  update public.team_members
  set role = case
    when id = v_old_member_id then 'main'
    when id = p_target_member_id then 'captain'
    else role
  end
  where team_id = p_team_id
    and id in (v_old_member_id, p_target_member_id);

  update public.teams
  set owner_id = v_target_user
  where id = p_team_id
    and owner_id = v_user;

  if not found then
    raise exception 'Не удалось передать права капитана';
  end if;

  insert into private.team_captain_transfers(
    team_id, tournament_id, from_user_id, to_user_id
  ) values (
    p_team_id, v_tournament_id, v_user, v_target_user
  );

  return 'transferred';
end;
$function$;

grant execute on function public.transfer_team_captaincy(text, uuid) to authenticated;
