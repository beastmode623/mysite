create or replace function public.get_public_player_profile(p_user_id uuid)
returns table(
  user_id uuid,
  nickname text,
  avatar_url text,
  city text,
  country text,
  steam_profile_url text,
  member_since timestamptz,
  is_own_profile boolean
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if;

  return query
  select p.id,p.nickname,p.avatar_url,p.city,p.country,p.steam_profile_url,p.created_at,(p.id=v_user)
  from public.profiles p
  where p.id=p_user_id and (p.profile_visibility='public' or p.id=v_user);
end;
$$;

grant execute on function public.get_public_player_profile(uuid) to authenticated;

create or replace function public.get_public_player_memberships(p_user_id uuid)
returns table(team_id text,team_name text,team_tag text,tournament_id text,tournament_name text,game text,role text,roster_position smallint)
language plpgsql
security definer
set search_path = public, auth
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if;
  if not exists(select 1 from public.profiles p where p.id=p_user_id and (p.profile_visibility='public' or p.id=v_user)) then return; end if;
  return query
  select t.id,t.name,t.tag,tr.id,tr.name,tr.game,tm.role,tm.roster_position
  from public.team_members tm
  join public.teams t on t.id=tm.team_id and t.registration_status='approved'
  join public.tournaments tr on tr.id=tm.tournament_id
  where tm.user_id=p_user_id
  order by tm.created_at desc;
end;
$$;

grant execute on function public.get_public_player_memberships(uuid) to authenticated;

drop function if exists public.get_public_team_roster(text);
create function public.get_public_team_roster(p_team_id text)
returns table(roster_position smallint,display_name text,role text,avatar_url text,account_linked boolean,profile_id uuid)
language sql
stable security definer
set search_path = public
as $$
  select tm.roster_position,
         case when tm.user_id is not null then coalesce(nullif(trim(p.nickname),''),tm.display_name) else tm.display_name end,
         tm.role,
         case when tm.user_id is not null then p.avatar_url else null end,
         (tm.user_id is not null),
         tm.user_id
  from public.team_members tm
  join public.teams t on t.id=tm.team_id
  left join public.profiles p on p.id=tm.user_id
  where tm.team_id=p_team_id and t.registration_status='approved'
  order by tm.roster_position;
$$;

grant execute on function public.get_public_team_roster(text) to anon, authenticated;

drop function if exists public.get_team_member_management(text);
create function public.get_team_member_management(p_team_id text)
returns table(member_id uuid,display_name text,role text,roster_position smallint,linked boolean,invitation_status text,invitation_email text,profile_id uuid)
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if;
  if not exists(select 1 from public.teams where id=p_team_id and owner_id=v_user) then raise exception 'Недостаточно прав'; end if;
  return query
  select tm.id,
         case when tm.user_id is not null then coalesce(nullif(trim(p.nickname),''),tm.display_name) else tm.display_name end,
         tm.role,tm.roster_position,(tm.user_id is not null),
         case when tm.user_id is not null then 'accepted' else coalesce(c.status,'pending') end,
         case when tm.user_id is null then c.email else null end,
         tm.user_id
  from public.team_members tm
  left join public.profiles p on p.id=tm.user_id
  left join private.team_member_claims c on c.member_id=tm.id
  where tm.team_id=p_team_id
  order by tm.roster_position;
end;
$$;

grant execute on function public.get_team_member_management(text) to authenticated;

create or replace function public.admin_list_applications(p_tournament_id text default null)
returns table(application_id uuid,tournament_id text,tournament_name text,team_id text,team_name text,team_tag text,application_status text,submitted_at timestamptz,reviewed_at timestamptz,roster_private jsonb,submitter_nickname text,submitter_email text)
language plpgsql
security definer
set search_path = public, private, auth
as $$
begin
  if not public.is_tournament_admin() then raise exception 'Недостаточно прав'; end if;
  return query
  select a.id,a.tournament_id,tr.name,a.team_id,tm.name,tm.tag,a.status,a.submitted_at,a.reviewed_at,
         coalesce(r.current_roster,a.roster_private),p.nickname,u.email::text
  from public.tournament_applications a
  join public.tournaments tr on tr.id=a.tournament_id
  join public.teams tm on tm.id=a.team_id
  left join public.profiles p on p.id=a.submitted_by
  left join auth.users u on u.id=a.submitted_by
  left join lateral (
    select jsonb_agg(
      case when tmem.user_id is not null then
        jsonb_set(jsonb_set(player.item,'{full_name}',to_jsonb(coalesce(nullif(trim(pp.nickname),''),player.item->>'full_name')),true),'{profile_id}',to_jsonb(tmem.user_id::text),true)
      else jsonb_set(player.item,'{profile_id}','null'::jsonb,true) end
      order by player.ord
    ) current_roster
    from jsonb_array_elements(coalesce(a.roster_private,'[]'::jsonb)) with ordinality player(item,ord)
    left join public.team_members tmem on tmem.team_id=a.team_id and tmem.roster_position=player.ord::smallint
    left join public.profiles pp on pp.id=tmem.user_id
  ) r on true
  where p_tournament_id is null or a.tournament_id=p_tournament_id
  order by a.submitted_at desc;
end;
$$;

grant execute on function public.admin_list_applications(text) to authenticated;
