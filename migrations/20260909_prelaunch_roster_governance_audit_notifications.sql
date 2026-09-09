-- Applied to Supabase production on 2026-09-09.
-- Adds roster governance, audit, admin recovery, lifecycle locks and in-site notifications.

alter table public.tournament_applications add column if not exists reviewed_by uuid references auth.users(id) on delete set null;

create table if not exists private.team_activity_log (
  id uuid primary key default gen_random_uuid(),
  team_id text not null references public.teams(id) on delete cascade,
  tournament_id text not null references public.tournaments(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  target_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists team_activity_log_team_time_idx on private.team_activity_log(team_id,created_at desc);
create index if not exists team_activity_log_tournament_time_idx on private.team_activity_log(tournament_id,created_at desc);

create table if not exists private.user_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null,
  title text not null,
  body text,
  href text,
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index if not exists user_notifications_user_time_idx on private.user_notifications(user_id,created_at desc);
create index if not exists user_notifications_unread_idx on private.user_notifications(user_id,read_at) where read_at is null;

create table if not exists private.team_roster_change_requests (
  id uuid primary key default gen_random_uuid(),
  team_id text not null references public.teams(id) on delete cascade,
  tournament_id text not null references public.tournaments(id) on delete cascade,
  requested_by uuid not null references auth.users(id) on delete cascade,
  main_member_id uuid not null references public.team_members(id) on delete cascade,
  reserve_member_id uuid not null references public.team_members(id) on delete cascade,
  status text not null default 'pending' check(status in('pending','approved','rejected')),
  requested_at timestamptz not null default now(),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  review_note text,
  check(main_member_id<>reserve_member_id)
);
create unique index if not exists one_pending_roster_change_per_team on private.team_roster_change_requests(team_id) where status='pending';

create or replace function private.ensure_team_changes_open(p_tournament_id text)
returns void language plpgsql security definer set search_path='public','private' as $$
declare v_status text;
begin
  select status into v_status from public.tournaments where id=p_tournament_id;
  if v_status is null then raise exception 'Турнир не найден'; end if;
  if v_status in('ongoing','live','finished','cancelled') then raise exception 'Изменения состава заблокированы на текущей стадии турнира'; end if;
end;$$;

create or replace function private.notify_user(p_user uuid,p_kind text,p_title text,p_body text,p_href text default null)
returns void language plpgsql security definer set search_path='private' as $$
begin
  if p_user is not null then insert into private.user_notifications(user_id,kind,title,body,href) values(p_user,p_kind,p_title,p_body,p_href); end if;
end;$$;

create or replace function public.get_my_notifications()
returns table(notification_id uuid,kind text,title text,body text,href text,created_at timestamptz,read_at timestamptz)
language plpgsql security definer set search_path='public','private','auth' as $$
declare v_user uuid:=auth.uid();
begin
  if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if;
  return query select n.id,n.kind,n.title,n.body,n.href,n.created_at,n.read_at from private.user_notifications n where n.user_id=v_user order by n.created_at desc limit 100;
end;$$;
grant execute on function public.get_my_notifications() to authenticated;

create or replace function public.mark_notification_read(p_notification_id uuid)
returns void language plpgsql security definer set search_path='public','private','auth' as $$
begin
  if auth.uid() is null then raise exception 'Необходимо войти в аккаунт'; end if;
  update private.user_notifications set read_at=coalesce(read_at,now()) where id=p_notification_id and user_id=auth.uid();
end;$$;
grant execute on function public.mark_notification_read(uuid) to authenticated;

create or replace function public.get_my_roster_change_requests(p_team_id text)
returns table(request_id uuid,status text,requested_at timestamptz,reviewed_at timestamptz,review_note text,main_member_id uuid,main_name text,reserve_member_id uuid,reserve_name text)
language plpgsql security definer set search_path='public','private','auth' as $$
declare v_user uuid:=auth.uid();
begin
  if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if;
  if not exists(select 1 from public.teams where id=p_team_id and owner_id=v_user) then raise exception 'Недостаточно прав'; end if;
  return query
  select r.id,r.status,r.requested_at,r.reviewed_at,r.review_note,r.main_member_id,coalesce(pm.nickname,mm.display_name),r.reserve_member_id,coalesce(pr.nickname,rm.display_name)
  from private.team_roster_change_requests r
  join public.team_members mm on mm.id=r.main_member_id
  join public.team_members rm on rm.id=r.reserve_member_id
  left join public.profiles pm on pm.id=mm.user_id
  left join public.profiles pr on pr.id=rm.user_id
  where r.team_id=p_team_id order by r.requested_at desc limit 20;
end;$$;
grant execute on function public.get_my_roster_change_requests(text) to authenticated;

create or replace function public.captain_request_role_swap(p_team_id text,p_main_member_id uuid,p_reserve_member_id uuid)
returns uuid language plpgsql security definer set search_path='public','private','auth' as $$
declare v_user uuid:=auth.uid();v_tid text;v_main_role text;v_res_role text;v_id uuid;v_team_name text;
begin
  if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if;
  select tournament_id,name into v_tid,v_team_name from public.teams where id=p_team_id and owner_id=v_user and registration_status='approved' for update;
  if v_tid is null then raise exception 'Команда не найдена или недоступна'; end if;
  perform private.ensure_team_changes_open(v_tid);
  if exists(select 1 from private.team_roster_change_requests where team_id=p_team_id and status='pending') then raise exception 'У команды уже есть изменение состава на рассмотрении'; end if;
  select role into v_main_role from public.team_members where id=p_main_member_id and team_id=p_team_id;
  select role into v_res_role from public.team_members where id=p_reserve_member_id and team_id=p_team_id;
  if v_main_role<>'main' then raise exception 'Первый игрок должен быть из основного состава'; end if;
  if v_res_role<>'reserve' then raise exception 'Второй игрок должен быть запасным'; end if;
  insert into private.team_roster_change_requests(team_id,tournament_id,requested_by,main_member_id,reserve_member_id) values(p_team_id,v_tid,v_user,p_main_member_id,p_reserve_member_id) returning id into v_id;
  insert into private.team_activity_log(team_id,tournament_id,actor_user_id,action,details) values(p_team_id,v_tid,v_user,'role_swap_requested',jsonb_build_object('request_id',v_id));
  insert into private.user_notifications(user_id,kind,title,body,href)
  select a.user_id,'roster_change','Изменение состава ожидает проверки','Команда «'||v_team_name||'» отправила запрос на обмен основного и запасного игрока.','admin.html?tournament='||v_tid from private.tournament_admins a;
  return v_id;
end;$$;
grant execute on function public.captain_request_role_swap(text,uuid,uuid) to authenticated;

create or replace function public.admin_list_roster_change_requests(p_tournament_id text)
returns table(request_id uuid,team_id text,team_name text,status text,requested_at timestamptz,main_member_id uuid,main_name text,reserve_member_id uuid,reserve_name text,review_note text)
language plpgsql security definer set search_path='public','private','auth' as $$
begin
  if not public.is_tournament_admin() then raise exception 'Недостаточно прав'; end if;
  return query
  select r.id,r.team_id,t.name,r.status,r.requested_at,r.main_member_id,coalesce(pm.nickname,mm.display_name),r.reserve_member_id,coalesce(pr.nickname,rm.display_name),r.review_note
  from private.team_roster_change_requests r join public.teams t on t.id=r.team_id join public.team_members mm on mm.id=r.main_member_id join public.team_members rm on rm.id=r.reserve_member_id left join public.profiles pm on pm.id=mm.user_id left join public.profiles pr on pr.id=rm.user_id
  where r.tournament_id=p_tournament_id order by(r.status='pending') desc,r.requested_at desc;
end;$$;
grant execute on function public.admin_list_roster_change_requests(text) to authenticated;

create or replace function public.admin_review_roster_change_request(p_request_id uuid,p_status text,p_note text default null)
returns text language plpgsql security definer set search_path='public','private','auth' as $$
declare v_admin uuid:=auth.uid();v_team text;v_tid text;v_owner uuid;v_main uuid;v_res uuid;v_team_name text;
begin
  if not public.is_tournament_admin() then raise exception 'Недостаточно прав'; end if;
  if p_status not in('approved','rejected') then raise exception 'Некорректный статус'; end if;
  select r.team_id,r.tournament_id,t.owner_id,r.main_member_id,r.reserve_member_id,t.name into v_team,v_tid,v_owner,v_main,v_res,v_team_name from private.team_roster_change_requests r join public.teams t on t.id=r.team_id where r.id=p_request_id and r.status='pending' for update of r;
  if v_team is null then raise exception 'Запрос не найден или уже обработан'; end if;
  if p_status='approved' then
    perform private.ensure_team_changes_open(v_tid);
    if(select role from public.team_members where id=v_main and team_id=v_team)<>'main' or(select role from public.team_members where id=v_res and team_id=v_team)<>'reserve' then raise exception 'Состав уже изменился, запрос устарел'; end if;
    update public.team_members set role=case when id=v_main then 'reserve' when id=v_res then 'main' else role end where id in(v_main,v_res);
  end if;
  update private.team_roster_change_requests set status=p_status,reviewed_by=v_admin,reviewed_at=now(),review_note=nullif(trim(coalesce(p_note,'')),'') where id=p_request_id;
  insert into private.team_activity_log(team_id,tournament_id,actor_user_id,action,details) values(v_team,v_tid,v_admin,case when p_status='approved' then 'role_swap_approved' else 'role_swap_rejected' end,jsonb_build_object('request_id',p_request_id,'note',p_note));
  perform private.notify_user(v_owner,'roster_change',case when p_status='approved' then 'Изменение состава одобрено' else 'Изменение состава отклонено' end,'Команда «'||v_team_name||'»: запрос на обмен основного и запасного игрока '||case when p_status='approved' then 'одобрен.' else 'отклонён.' end,'my-team.html');
  return p_status;
end;$$;
grant execute on function public.admin_review_roster_change_request(uuid,text,text) to authenticated;

create or replace function public.admin_reassign_team_captain(p_team_id text,p_target_member_id uuid)
returns text language plpgsql security definer set search_path='public','private','auth' as $$
declare v_admin uuid:=auth.uid();v_tid text;v_old_owner uuid;v_target uuid;v_target_role text;v_old_member uuid;v_name text;
begin
  if not public.is_tournament_admin() then raise exception 'Недостаточно прав'; end if;
  select tournament_id,owner_id,name into v_tid,v_old_owner,v_name from public.teams where id=p_team_id for update;
  if v_tid is null then raise exception 'Команда не найдена'; end if;
  select user_id,role into v_target,v_target_role from public.team_members where id=p_target_member_id and team_id=p_team_id for update;
  if v_target is null then raise exception 'Новый капитан должен иметь подтверждённый аккаунт'; end if;
  if v_target_role='reserve' then raise exception 'Сначала переведите игрока в основной состав'; end if;
  select id into v_old_member from public.team_members where team_id=p_team_id and role='captain' limit 1 for update;
  if v_old_member is not null then update public.team_members set role='main' where id=v_old_member; end if;
  update public.team_members set role='captain' where id=p_target_member_id;
  update public.teams set owner_id=v_target where id=p_team_id;
  insert into private.team_activity_log(team_id,tournament_id,actor_user_id,target_user_id,action,details) values(p_team_id,v_tid,v_admin,v_target,'admin_captain_reassigned',jsonb_build_object('old_owner',v_old_owner));
  perform private.notify_user(v_target,'captaincy','Вы назначены капитаном','Администратор назначил вас капитаном команды «'||v_name||'».','my-team.html');
  perform private.notify_user(v_old_owner,'captaincy','Капитан команды изменён','Администратор назначил нового капитана команды «'||v_name||'».','profile.html');
  return 'reassigned';
end;$$;
grant execute on function public.admin_reassign_team_captain(text,uuid) to authenticated;

create or replace function public.admin_release_team_slot(p_member_id uuid)
returns text language plpgsql security definer set search_path='public','private','auth' as $$
declare v_admin uuid:=auth.uid();v_team text;v_tid text;v_user uuid;v_role text;v_name text;v_team_name text;
begin
  if not public.is_tournament_admin() then raise exception 'Недостаточно прав'; end if;
  select tm.team_id,tm.tournament_id,tm.user_id,tm.role,coalesce(p.nickname,tm.display_name),t.name into v_team,v_tid,v_user,v_role,v_name,v_team_name from public.team_members tm join public.teams t on t.id=tm.team_id left join public.profiles p on p.id=tm.user_id where tm.id=p_member_id for update of tm;
  if v_team is null then raise exception 'Место в составе не найдено'; end if;
  if v_role='captain' then raise exception 'Сначала назначьте другого капитана'; end if;
  delete from private.team_member_claims where member_id=p_member_id;
  update public.team_members set user_id=null,linked_at=null,display_name='Свободное место' where id=p_member_id;
  insert into private.team_activity_log(team_id,tournament_id,actor_user_id,target_user_id,action,details) values(v_team,v_tid,v_admin,v_user,'admin_slot_released',jsonb_build_object('player',v_name,'role',v_role));
  perform private.notify_user(v_user,'team','Место в составе освобождено','Администратор освободил ваше место в команде «'||v_team_name||'».','profile.html');
  return 'released';
end;$$;
grant execute on function public.admin_release_team_slot(uuid) to authenticated;

create or replace function public.admin_get_team_activity(p_team_id text)
returns table(action text,actor_nickname text,target_nickname text,details jsonb,created_at timestamptz)
language plpgsql security definer set search_path='public','private','auth' as $$
begin
  if not public.is_tournament_admin() then raise exception 'Недостаточно прав'; end if;
  return query select l.action,pa.nickname,pt.nickname,l.details,l.created_at from private.team_activity_log l left join public.profiles pa on pa.id=l.actor_user_id left join public.profiles pt on pt.id=l.target_user_id where l.team_id=p_team_id order by l.created_at desc limit 100;
end;$$;
grant execute on function public.admin_get_team_activity(text) to authenticated;

create or replace function public.captain_invite_team_member(p_member_id uuid,p_email text)
returns text language plpgsql security definer set search_path='public','private','auth' as $$
declare v_user uuid:=auth.uid();v_email text:=lower(trim(p_email));v_team_id text;v_tid text;v_role text;v_linked_user uuid;v_target_user uuid;v_team_name text;
begin
  if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if;
  if v_email is null or v_email='' then raise exception 'Укажите email игрока'; end if;
  if v_email!~*'^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$' then raise exception 'Некорректный email'; end if;
  select tm.team_id,tm.tournament_id,tm.role,tm.user_id,t.name into v_team_id,v_tid,v_role,v_linked_user,v_team_name from public.team_members tm join public.teams t on t.id=tm.team_id where tm.id=p_member_id and t.owner_id=v_user and t.registration_status='approved' for update of tm;
  if v_team_id is null then raise exception 'Место в составе не найдено или недоступно'; end if;
  perform private.ensure_team_changes_open(v_tid);
  if v_role='captain' then raise exception 'Капитан уже связан с владельцем команды'; end if;
  if v_linked_user is not null then raise exception 'Это место уже подтверждено игроком'; end if;
  select u.id into v_target_user from auth.users u where lower(u.email)=v_email limit 1;
  if v_target_user is not null and exists(select 1 from public.team_members where team_id=v_team_id and user_id=v_target_user) then raise exception 'Этот аккаунт уже состоит в команде'; end if;
  insert into private.team_member_claims(member_id,email,status,created_at,responded_at) values(p_member_id,v_email,'pending',now(),null) on conflict(member_id) do update set email=excluded.email,status='pending',created_at=now(),responded_at=null;
  insert into private.team_activity_log(team_id,tournament_id,actor_user_id,target_user_id,action,details) values(v_team_id,v_tid,v_user,v_target_user,'invitation_sent',jsonb_build_object('member_id',p_member_id));
  perform private.notify_user(v_target_user,'invitation','Приглашение в команду','Капитан команды «'||v_team_name||'» пригласил вас в состав.','profile.html');
  return 'pending';
end;$$;

create or replace function public.respond_to_team_invitation(p_member_id uuid,p_accept boolean)
returns text language plpgsql security definer set search_path='public','private','auth' as $$
declare v_user uuid:=auth.uid();v_email text;v_team_id text;v_tid text;v_claim_email text;v_status text;v_owner uuid;v_team_name text;
begin
  if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if;
  select lower(email) into v_email from auth.users where id=v_user;
  if v_email is null then raise exception 'У аккаунта нет email'; end if;
  select tm.team_id,tm.tournament_id,lower(c.email),c.status,t.owner_id,t.name into v_team_id,v_tid,v_claim_email,v_status,v_owner,v_team_name from public.team_members tm join private.team_member_claims c on c.member_id=tm.id join public.teams t on t.id=tm.team_id where tm.id=p_member_id and tm.user_id is null and t.registration_status='approved' for update of tm,c;
  if v_team_id is null then raise exception 'Приглашение не найдено или уже обработано'; end if;
  perform private.ensure_team_changes_open(v_tid);
  if v_claim_email<>v_email then raise exception 'Это приглашение предназначено другому пользователю'; end if;
  if v_status<>'pending' then raise exception 'Приглашение уже обработано'; end if;
  if p_accept then
    if exists(select 1 from public.team_members where team_id=v_team_id and user_id=v_user) then raise exception 'Ваш аккаунт уже связан с этой командой'; end if;
    update public.team_members set user_id=v_user,linked_at=now() where id=p_member_id and user_id is null;
    update private.team_member_claims set status='accepted',responded_at=now() where member_id=p_member_id;
    insert into private.team_activity_log(team_id,tournament_id,actor_user_id,action,details) values(v_team_id,v_tid,v_user,'invitation_accepted',jsonb_build_object('member_id',p_member_id));
    perform private.notify_user(v_owner,'invitation','Игрок принял приглашение','Игрок присоединился к команде «'||v_team_name||'».','my-team.html');
    return 'accepted';
  end if;
  update private.team_member_claims set status='declined',responded_at=now() where member_id=p_member_id;
  insert into private.team_activity_log(team_id,tournament_id,actor_user_id,action,details) values(v_team_id,v_tid,v_user,'invitation_declined',jsonb_build_object('member_id',p_member_id));
  perform private.notify_user(v_owner,'invitation','Игрок отклонил приглашение','Приглашение в команду «'||v_team_name||'» было отклонено.','my-team.html');
  return 'declined';
end;$$;

create or replace function public.transfer_team_captaincy(p_team_id text,p_target_member_id uuid)
returns text language plpgsql security definer set search_path='public','private','auth' as $$
declare v_user uuid:=auth.uid();v_tid text;v_target_user uuid;v_target_role text;v_old_member uuid;v_name text;
begin
  if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if;
  select tournament_id,name into v_tid,v_name from public.teams where id=p_team_id and owner_id=v_user for update;
  if v_tid is null then raise exception 'Команда не найдена или у вас нет прав капитана'; end if;
  perform private.ensure_team_changes_open(v_tid);
  select user_id,role into v_target_user,v_target_role from public.team_members where id=p_target_member_id and team_id=p_team_id for update;
  if v_target_user is null then raise exception 'Передать капитанство можно только игроку с подтверждённым аккаунтом'; end if;
  if v_target_user=v_user then raise exception 'Вы уже являетесь капитаном этой команды'; end if;
  if v_target_role='reserve' then raise exception 'Сначала переведите запасного игрока в основной состав'; end if;
  select id into v_old_member from public.team_members where team_id=p_team_id and user_id=v_user for update;
  if v_old_member is null then raise exception 'Текущий капитан не найден в составе команды'; end if;
  update public.team_members set role=case when id=v_old_member then 'main' when id=p_target_member_id then 'captain' else role end where team_id=p_team_id and id in(v_old_member,p_target_member_id);
  update public.teams set owner_id=v_target_user where id=p_team_id and owner_id=v_user;
  if not found then raise exception 'Не удалось передать права капитана'; end if;
  insert into private.team_captain_transfers(team_id,tournament_id,from_user_id,to_user_id) values(p_team_id,v_tid,v_user,v_target_user);
  insert into private.team_activity_log(team_id,tournament_id,actor_user_id,target_user_id,action) values(p_team_id,v_tid,v_user,v_target_user,'captaincy_transferred');
  perform private.notify_user(v_target_user,'captaincy','Вы стали капитаном','Вам переданы права капитана команды «'||v_name||'».','my-team.html');
  perform private.notify_user(v_user,'captaincy','Капитанство передано','Вы передали права капитана команды «'||v_name||'».','profile.html');
  return 'transferred';
end;$$;

create or replace function public.leave_team_member(p_member_id uuid)
returns text language plpgsql security definer set search_path='public','private','auth' as $$
declare v_user uuid:=auth.uid();v_team text;v_tid text;v_role text;v_pos smallint;v_display text;v_owner uuid;v_name text;
begin
  if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if;
  select tm.team_id,tm.tournament_id,tm.role,tm.roster_position,coalesce(nullif(trim(p.nickname),''),tm.display_name),t.owner_id,t.name into v_team,v_tid,v_role,v_pos,v_display,v_owner,v_name from public.team_members tm join public.teams t on t.id=tm.team_id left join public.profiles p on p.id=tm.user_id where tm.id=p_member_id and tm.user_id=v_user for update of tm,t;
  if v_team is null then raise exception 'Участие в команде не найдено'; end if;
  perform private.ensure_team_changes_open(v_tid);
  if v_owner=v_user or v_role='captain' then raise exception 'Капитан не может покинуть команду, пока не передаст капитанство другому подтверждённому игроку'; end if;
  insert into private.team_member_departures(team_id,tournament_id,member_id,user_id,role,roster_position,display_name) values(v_team,v_tid,p_member_id,v_user,v_role,v_pos,v_display);
  delete from private.team_member_claims where member_id=p_member_id;
  update public.team_members set user_id=null,linked_at=null,display_name='Свободное место' where id=p_member_id and user_id=v_user;
  if not found then raise exception 'Не удалось покинуть команду'; end if;
  insert into private.team_activity_log(team_id,tournament_id,actor_user_id,action,details) values(v_team,v_tid,v_user,'player_left',jsonb_build_object('role',v_role,'position',v_pos));
  perform private.notify_user(v_owner,'team','Игрок покинул команду',v_display||' покинул команду «'||v_name||'».','my-team.html');
  return 'left';
end;$$;

create or replace function public.admin_review_application(p_application_id uuid,p_status text)
returns void language plpgsql security definer set search_path='public','private','auth' as $$
declare v_team text;v_tid text;v_owner uuid;v_name text;v_admin uuid:=auth.uid();
begin
  if not public.is_tournament_admin() then raise exception 'Недостаточно прав'; end if;
  if p_status not in('approved','rejected') then raise exception 'Некорректный статус'; end if;
  select a.team_id,a.tournament_id,t.owner_id,t.name into v_team,v_tid,v_owner,v_name from public.tournament_applications a join public.teams t on t.id=a.team_id where a.id=p_application_id for update of a;
  if v_team is null then raise exception 'Заявка не найдена'; end if;
  update public.tournament_applications set status=p_status,reviewed_at=now(),reviewed_by=v_admin where id=p_application_id;
  update public.teams set registration_status=p_status where id=v_team;
  if p_status='approved' then perform private.sync_team_members_from_application(p_application_id); else delete from public.team_members where team_id=v_team; end if;
  insert into private.team_activity_log(team_id,tournament_id,actor_user_id,action,details) values(v_team,v_tid,v_admin,case when p_status='approved' then 'application_approved' else 'application_rejected' end,jsonb_build_object('application_id',p_application_id));
  perform private.notify_user(v_owner,'application',case when p_status='approved' then 'Заявка команды одобрена' else 'Заявка команды отклонена' end,'Команда «'||v_name||'»: заявка '||case when p_status='approved' then 'одобрена.' else 'отклонена.' end,'profile.html');
end;$$;
