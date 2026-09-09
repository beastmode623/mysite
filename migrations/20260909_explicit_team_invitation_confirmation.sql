alter table private.team_member_claims
  add column if not exists status text not null default 'pending',
  add column if not exists responded_at timestamptz null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'team_member_claims_status_check'
      and conrelid = 'private.team_member_claims'::regclass
  ) then
    alter table private.team_member_claims
      add constraint team_member_claims_status_check
      check (status in ('pending','accepted','declined'));
  end if;
end $$;

create or replace function public.claim_my_team_memberships()
returns integer
language plpgsql
security definer
set search_path = public, private, auth
as $$
begin
  if auth.uid() is null then raise exception 'Необходимо войти в аккаунт'; end if;
  return 0;
end;
$$;
grant execute on function public.claim_my_team_memberships() to authenticated;

create or replace function public.get_my_team_memberships()
returns table(
  member_id uuid,
  team_id text,
  team_name text,
  team_tag text,
  tournament_id text,
  tournament_name text,
  game text,
  tournament_status text,
  registration_status text,
  display_name text,
  role text,
  roster_position smallint,
  is_captain boolean
)
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if;
  return query
  select tm.id,t.id,t.name,t.tag,tr.id,tr.name,tr.game,tr.status,t.registration_status,
         tm.display_name,tm.role,tm.roster_position,(tm.role='captain')
  from public.team_members tm
  join public.teams t on t.id=tm.team_id
  join public.tournaments tr on tr.id=tm.tournament_id
  where tm.user_id=v_user
  order by tm.created_at desc;
end;
$$;
grant execute on function public.get_my_team_memberships() to authenticated;

create or replace function public.get_my_team_invitations()
returns table(
  member_id uuid,
  team_id text,
  team_name text,
  team_tag text,
  tournament_id text,
  tournament_name text,
  game text,
  display_name text,
  role text,
  roster_position smallint,
  invitation_status text
)
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_user uuid := auth.uid();
  v_email text;
begin
  if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if;
  select lower(email) into v_email from auth.users where id=v_user;
  if v_email is null then return; end if;

  return query
  select tm.id,t.id,t.name,t.tag,tr.id,tr.name,tr.game,tm.display_name,tm.role,tm.roster_position,c.status
  from private.team_member_claims c
  join public.team_members tm on tm.id=c.member_id
  join public.teams t on t.id=tm.team_id
  join public.tournaments tr on tr.id=tm.tournament_id
  where lower(c.email)=v_email
    and c.status='pending'
    and tm.user_id is null
    and t.registration_status='approved'
    and not exists (
      select 1 from public.team_members mine
      where mine.team_id=tm.team_id and mine.user_id=v_user
    )
  order by c.created_at desc;
end;
$$;
grant execute on function public.get_my_team_invitations() to authenticated;

create or replace function public.respond_to_team_invitation(p_member_id uuid, p_accept boolean)
returns text
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_user uuid := auth.uid();
  v_email text;
  v_team_id text;
  v_claim_email text;
  v_status text;
begin
  if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if;
  select lower(email) into v_email from auth.users where id=v_user;
  if v_email is null then raise exception 'У аккаунта нет email'; end if;

  select tm.team_id, lower(c.email), c.status
    into v_team_id, v_claim_email, v_status
  from public.team_members tm
  join private.team_member_claims c on c.member_id=tm.id
  join public.teams t on t.id=tm.team_id
  where tm.id=p_member_id
    and tm.user_id is null
    and t.registration_status='approved'
  for update of tm, c;

  if v_team_id is null then raise exception 'Приглашение не найдено или уже обработано'; end if;
  if v_claim_email <> v_email then raise exception 'Это приглашение предназначено другому пользователю'; end if;
  if v_status <> 'pending' then raise exception 'Приглашение уже обработано'; end if;

  if p_accept then
    if exists (select 1 from public.team_members where team_id=v_team_id and user_id=v_user) then
      raise exception 'Ваш аккаунт уже связан с этой командой';
    end if;
    update public.team_members set user_id=v_user, linked_at=now()
    where id=p_member_id and user_id is null;
    update private.team_member_claims set status='accepted', responded_at=now()
    where member_id=p_member_id;
    return 'accepted';
  else
    update private.team_member_claims set status='declined', responded_at=now()
    where member_id=p_member_id;
    return 'declined';
  end if;
end;
$$;
grant execute on function public.respond_to_team_invitation(uuid, boolean) to authenticated;

create or replace function public.get_team_member_management(p_team_id text)
returns table(
  member_id uuid,
  display_name text,
  role text,
  roster_position smallint,
  linked boolean,
  invitation_status text
)
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if;
  if not exists (select 1 from public.teams where id=p_team_id and owner_id=v_user) then
    raise exception 'Недостаточно прав';
  end if;

  return query
  select tm.id,tm.display_name,tm.role,tm.roster_position,(tm.user_id is not null),
         case when tm.user_id is not null then 'accepted' else coalesce(c.status,'pending') end
  from public.team_members tm
  left join private.team_member_claims c on c.member_id=tm.id
  where tm.team_id=p_team_id
  order by tm.roster_position;
end;
$$;
grant execute on function public.get_team_member_management(text) to authenticated;