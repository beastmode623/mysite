create or replace function public.get_team_member_management(p_team_id text)
returns table(member_id uuid, display_name text, role text, roster_position smallint, linked boolean, invitation_status text, invitation_email text)
language plpgsql
security definer
set search_path to 'public', 'private', 'auth'
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if;
  if not exists (select 1 from public.teams where id=p_team_id and owner_id=v_user) then
    raise exception 'Недостаточно прав';
  end if;

  return query
  select tm.id,
         case when tm.user_id is not null then coalesce(nullif(trim(p.nickname),''), tm.display_name) else tm.display_name end,
         tm.role,
         tm.roster_position,
         (tm.user_id is not null),
         case when tm.user_id is not null then 'accepted' else coalesce(c.status,'pending') end,
         c.email
  from public.team_members tm
  left join public.profiles p on p.id=tm.user_id
  left join private.team_member_claims c on c.member_id=tm.id
  where tm.team_id=p_team_id
  order by tm.roster_position;
end;
$$;

create or replace function public.get_my_team_memberships()
returns table(member_id uuid,team_id text,team_name text,team_tag text,tournament_id text,tournament_name text,game text,tournament_status text,registration_status text,display_name text,role text,roster_position smallint,is_captain boolean)
language plpgsql
security definer
set search_path to 'public','private','auth'
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if;
  return query
  select tm.id,t.id,t.name,t.tag,tr.id,tr.name,tr.game,tr.status,t.registration_status,
         coalesce(nullif(trim(p.nickname),''),tm.display_name),tm.role,tm.roster_position,(tm.role='captain')
  from public.team_members tm
  join public.teams t on t.id=tm.team_id
  join public.tournaments tr on tr.id=tm.tournament_id
  left join public.profiles p on p.id=tm.user_id
  where tm.user_id=v_user
  order by tm.created_at desc;
end;
$$;

grant execute on function public.get_team_member_management(text) to authenticated;
grant execute on function public.get_my_team_memberships() to authenticated;
