create table if not exists private.team_member_departures (
  id uuid primary key default gen_random_uuid(),
  team_id text not null references public.teams(id) on delete cascade,
  tournament_id text not null references public.tournaments(id) on delete cascade,
  member_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null,
  roster_position smallint not null,
  display_name text,
  left_at timestamptz not null default now()
);

create index if not exists team_member_departures_team_idx on private.team_member_departures(team_id, left_at desc);
create index if not exists team_member_departures_user_idx on private.team_member_departures(user_id, left_at desc);

create or replace function public.leave_team_member(p_member_id uuid)
returns text
language plpgsql
security definer
set search_path = 'public', 'private', 'auth'
as $$
declare
  v_user uuid := auth.uid();
  v_team_id text;
  v_tournament_id text;
  v_role text;
  v_position smallint;
  v_display_name text;
  v_owner uuid;
begin
  if v_user is null then
    raise exception 'Необходимо войти в аккаунт';
  end if;

  select tm.team_id, tm.tournament_id, tm.role, tm.roster_position,
         coalesce(nullif(trim(p.nickname), ''), tm.display_name), t.owner_id
    into v_team_id, v_tournament_id, v_role, v_position, v_display_name, v_owner
  from public.team_members tm
  join public.teams t on t.id = tm.team_id
  left join public.profiles p on p.id = tm.user_id
  where tm.id = p_member_id
    and tm.user_id = v_user
  for update of tm, t;

  if v_team_id is null then
    raise exception 'Участие в команде не найдено';
  end if;

  if v_owner = v_user or v_role = 'captain' then
    raise exception 'Капитан не может покинуть команду, пока не передаст капитанство другому подтверждённому игроку';
  end if;

  insert into private.team_member_departures(
    team_id, tournament_id, member_id, user_id, role, roster_position, display_name
  ) values (
    v_team_id, v_tournament_id, p_member_id, v_user, v_role, v_position, v_display_name
  );

  delete from private.team_member_claims
  where member_id = p_member_id;

  update public.team_members
  set user_id = null,
      linked_at = null,
      display_name = 'Свободное место'
  where id = p_member_id
    and user_id = v_user;

  if not found then
    raise exception 'Не удалось покинуть команду';
  end if;

  return 'left';
end;
$$;

grant execute on function public.leave_team_member(uuid) to authenticated;

create or replace function public.admin_list_applications(p_tournament_id text default null::text)
returns table(application_id uuid, tournament_id text, tournament_name text, team_id text, team_name text, team_tag text, application_status text, submitted_at timestamptz, reviewed_at timestamptz, roster_private jsonb, submitter_nickname text, submitter_email text)
language plpgsql
security definer
set search_path to 'public', 'private', 'auth'
as $$
begin
  if not public.is_tournament_admin() then
    raise exception 'Недостаточно прав';
  end if;

  return query
  select
    a.id,
    a.tournament_id,
    tr.name,
    a.team_id,
    tm.name,
    tm.tag,
    a.status,
    a.submitted_at,
    a.reviewed_at,
    coalesce(r.current_roster, a.roster_private),
    p.nickname,
    u.email::text
  from public.tournament_applications a
  join public.tournaments tr on tr.id = a.tournament_id
  join public.teams tm on tm.id = a.team_id
  left join public.profiles p on p.id = a.submitted_by
  left join auth.users u on u.id = a.submitted_by
  left join lateral (
    select jsonb_agg(
      case
        when tmem.user_id is not null and nullif(trim(pp.nickname), '') is not null
          then jsonb_set(player.item, '{full_name}', to_jsonb(pp.nickname), true)
        when tmem.user_id is null and tmem.display_name = 'Свободное место'
          then jsonb_set(player.item, '{full_name}', to_jsonb('Свободное место'::text), true)
        else player.item
      end
      order by player.ord
    ) as current_roster
    from jsonb_array_elements(coalesce(a.roster_private, '[]'::jsonb)) with ordinality as player(item, ord)
    left join public.team_members tmem
      on tmem.team_id = a.team_id
     and tmem.roster_position = player.ord::smallint
    left join public.profiles pp on pp.id = tmem.user_id
  ) r on true
  where p_tournament_id is null or a.tournament_id = p_tournament_id
  order by a.submitted_at desc;
end;
$$;
