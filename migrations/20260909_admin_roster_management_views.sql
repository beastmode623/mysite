-- Applied to Supabase production on 2026-09-09.
create or replace function public.admin_list_approved_teams(p_tournament_id text)
returns table(team_id text,team_name text,team_tag text,owner_id uuid)
language plpgsql security definer set search_path='public','private','auth' as $$
begin
  if not public.is_tournament_admin() then raise exception 'Недостаточно прав'; end if;
  return query select t.id,t.name,t.tag,t.owner_id from public.teams t where t.tournament_id=p_tournament_id and t.registration_status='approved' order by t.name;
end;$$;
grant execute on function public.admin_list_approved_teams(text) to authenticated;

create or replace function public.admin_get_team_members(p_team_id text)
returns table(member_id uuid,display_name text,role text,roster_position smallint,linked boolean,profile_id uuid)
language plpgsql security definer set search_path='public','private','auth' as $$
begin
  if not public.is_tournament_admin() then raise exception 'Недостаточно прав'; end if;
  return query select tm.id,case when tm.user_id is not null then coalesce(nullif(trim(p.nickname),''),tm.display_name) else tm.display_name end,tm.role,tm.roster_position,(tm.user_id is not null),tm.user_id
  from public.team_members tm left join public.profiles p on p.id=tm.user_id where tm.team_id=p_team_id order by tm.roster_position;
end;$$;
grant execute on function public.admin_get_team_members(text) to authenticated;