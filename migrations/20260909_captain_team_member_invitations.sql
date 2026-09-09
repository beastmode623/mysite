drop function if exists public.get_team_member_management(text);

create or replace function public.get_team_member_management(p_team_id text)
returns table(
  member_id uuid,
  display_name text,
  role text,
  roster_position smallint,
  linked boolean,
  invitation_status text,
  invitation_email text
)
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if;
  if not exists (select 1 from public.teams where id=p_team_id and owner_id=v_user) then
    raise exception 'Недостаточно прав';
  end if;

  return query
  select tm.id, tm.display_name, tm.role, tm.roster_position,
         (tm.user_id is not null),
         case when tm.user_id is not null then 'accepted' else coalesce(c.status,'pending') end,
         c.email
  from public.team_members tm
  left join private.team_member_claims c on c.member_id=tm.id
  where tm.team_id=p_team_id
  order by tm.roster_position;
end;
$$;
grant execute on function public.get_team_member_management(text) to authenticated;

create or replace function public.captain_invite_team_member(p_member_id uuid, p_email text)
returns text
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_user uuid := auth.uid();
  v_email text := lower(trim(p_email));
  v_team_id text;
  v_role text;
  v_linked_user uuid;
  v_target_user uuid;
begin
  if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if;
  if v_email is null or v_email = '' then raise exception 'Укажите email игрока'; end if;
  if v_email !~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$' then raise exception 'Некорректный email'; end if;

  select tm.team_id, tm.role, tm.user_id
    into v_team_id, v_role, v_linked_user
  from public.team_members tm
  join public.teams t on t.id = tm.team_id
  where tm.id = p_member_id
    and t.owner_id = v_user
    and t.registration_status = 'approved'
  for update of tm;

  if v_team_id is null then raise exception 'Место в составе не найдено или недоступно'; end if;
  if v_role = 'captain' then raise exception 'Капитан уже связан с владельцем команды'; end if;
  if v_linked_user is not null then raise exception 'Это место уже подтверждено игроком'; end if;

  select u.id into v_target_user from auth.users u where lower(u.email)=v_email limit 1;
  if v_target_user is not null and exists (
    select 1 from public.team_members tm2 where tm2.team_id=v_team_id and tm2.user_id=v_target_user
  ) then
    raise exception 'Этот аккаунт уже состоит в команде';
  end if;

  insert into private.team_member_claims(member_id,email,status,created_at,responded_at)
  values (p_member_id,v_email,'pending',now(),null)
  on conflict (member_id) do update
    set email=excluded.email,
        status='pending',
        created_at=now(),
        responded_at=null;

  return 'pending';
end;
$$;
grant execute on function public.captain_invite_team_member(uuid,text) to authenticated;
