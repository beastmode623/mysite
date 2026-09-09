create or replace function public.get_public_player_directory(
  p_search text default null,
  p_game text default null
)
returns table(
  profile_id uuid,
  nickname text,
  avatar_url text,
  city text,
  country text,
  games text[],
  teams_count bigint,
  current_team_id text,
  current_team_name text,
  current_team_tag text,
  team_role text
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_user uuid := auth.uid();
  v_search text := nullif(lower(trim(coalesce(p_search,''))), '');
  v_game text := nullif(lower(trim(coalesce(p_game,''))), '');
begin
  if v_user is null then
    raise exception 'Необходимо войти в аккаунт';
  end if;

  return query
  with memberships as (
    select tm.user_id,
           array_agg(distinct lower(tr.game) order by lower(tr.game)) as games,
           count(distinct tm.team_id) as teams_count
    from public.team_members tm
    join public.teams t on t.id = tm.team_id and t.registration_status = 'approved'
    join public.tournaments tr on tr.id = tm.tournament_id
    where tm.user_id is not null
    group by tm.user_id
  ), latest_membership as (
    select distinct on (tm.user_id)
      tm.user_id, t.id as team_id, t.name as team_name, t.tag as team_tag, tm.role
    from public.team_members tm
    join public.teams t on t.id = tm.team_id and t.registration_status = 'approved'
    where tm.user_id is not null
    order by tm.user_id, tm.linked_at desc nulls last, tm.created_at desc
  )
  select p.id, p.nickname, p.avatar_url, p.city, p.country,
         coalesce(m.games, array[]::text[]), coalesce(m.teams_count,0),
         lm.team_id, lm.team_name, lm.team_tag, lm.role
  from public.profiles p
  left join memberships m on m.user_id = p.id
  left join latest_membership lm on lm.user_id = p.id
  where p.profile_visibility = 'public'
    and (v_search is null or lower(p.nickname) like '%' || v_search || '%')
    and (v_game is null or exists (
      select 1
      from public.team_members tm2
      join public.teams t2 on t2.id = tm2.team_id and t2.registration_status = 'approved'
      join public.tournaments tr2 on tr2.id = tm2.tournament_id
      where tm2.user_id = p.id and lower(tr2.game) = v_game
    ))
  order by lower(p.nickname), p.id;
end;
$$;

grant execute on function public.get_public_player_directory(text,text) to authenticated;

create or replace function public.get_public_team_directory(
  p_search text default null,
  p_game text default null
)
returns table(
  team_id text,
  team_name text,
  team_tag text,
  logo text,
  region text,
  tournament_id text,
  tournament_name text,
  game text,
  tournament_status text,
  linked_players bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select t.id, t.name, t.tag, t.logo, t.region,
         tr.id, tr.name, tr.game, tr.status,
         count(tm.user_id) filter (where tm.user_id is not null)
  from public.teams t
  join public.tournaments tr on tr.id = t.tournament_id
  left join public.team_members tm on tm.team_id = t.id
  where t.registration_status = 'approved'
    and (
      nullif(trim(coalesce(p_search,'')), '') is null
      or lower(t.name) like '%' || lower(trim(p_search)) || '%'
      or lower(t.tag) like '%' || lower(trim(p_search)) || '%'
    )
    and (
      nullif(trim(coalesce(p_game,'')), '') is null
      or lower(tr.game) = lower(trim(p_game))
    )
  group by t.id,t.name,t.tag,t.logo,t.region,tr.id,tr.name,tr.game,tr.status
  order by lower(t.name), t.id;
$$;

grant execute on function public.get_public_team_directory(text,text) to anon, authenticated;
