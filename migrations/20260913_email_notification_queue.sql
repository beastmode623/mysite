create table if not exists private.email_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  enabled boolean not null default true,
  tournament_updates boolean not null default true,
  team_updates boolean not null default true,
  match_updates boolean not null default true,
  admin_updates boolean not null default true,
  updated_at timestamptz not null default now()
);

create table if not exists private.email_delivery_queue (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null unique references private.user_notifications(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  recipient_email text not null,
  kind text not null,
  subject text not null,
  body text,
  href text,
  status text not null default 'pending' check (status in ('pending','processing','sent','failed','cancelled')),
  attempts smallint not null default 0,
  next_attempt_at timestamptz not null default now(),
  locked_at timestamptz,
  sent_at timestamptz,
  provider_message_id text,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists email_delivery_queue_pending_idx on private.email_delivery_queue(status,next_attempt_at,created_at) where status in ('pending','failed');
create index if not exists email_delivery_queue_user_idx on private.email_delivery_queue(user_id,created_at desc);

create or replace function private.email_category_for_kind(p_kind text)
returns text language sql immutable set search_path='pg_catalog' as $$
  select case
    when coalesce(p_kind,'') ilike '%match%' then 'match_updates'
    when coalesce(p_kind,'') in ('captaincy','roster_change','team_invite','team_update','role_change') or coalesce(p_kind,'') ilike '%team%' or coalesce(p_kind,'') ilike '%roster%' then 'team_updates'
    when coalesce(p_kind,'') ilike '%admin%' then 'admin_updates'
    else 'tournament_updates'
  end;
$$;

create or replace function private.enqueue_email_for_notification()
returns trigger language plpgsql security definer set search_path='pg_catalog','private','auth' as $$
declare v_email text; v_enabled boolean := true; v_category text; v_category_enabled boolean := true;
begin
  select u.email into v_email from auth.users u where u.id=new.user_id;
  if v_email is null or btrim(v_email)='' then return new; end if;
  v_category := private.email_category_for_kind(new.kind);
  select p.enabled,
         case v_category when 'team_updates' then p.team_updates when 'match_updates' then p.match_updates when 'admin_updates' then p.admin_updates else p.tournament_updates end
    into v_enabled,v_category_enabled
  from private.email_preferences p where p.user_id=new.user_id;
  if coalesce(v_enabled,true) is false or coalesce(v_category_enabled,true) is false then return new; end if;
  insert into private.email_delivery_queue(notification_id,user_id,recipient_email,kind,subject,body,href)
  values(new.id,new.user_id,v_email,new.kind,new.title,new.body,new.href)
  on conflict(notification_id) do nothing;
  return new;
end;
$$;

drop trigger if exists user_notifications_enqueue_email on private.user_notifications;
create trigger user_notifications_enqueue_email after insert on private.user_notifications for each row execute function private.enqueue_email_for_notification();

create or replace function public.get_my_email_preferences()
returns table(enabled boolean,tournament_updates boolean,team_updates boolean,match_updates boolean,admin_updates boolean)
language plpgsql security definer set search_path='pg_catalog','private','auth' as $$
declare v_user uuid:=auth.uid();
begin
  if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if;
  insert into private.email_preferences(user_id) values(v_user) on conflict(user_id) do nothing;
  return query select p.enabled,p.tournament_updates,p.team_updates,p.match_updates,p.admin_updates from private.email_preferences p where p.user_id=v_user;
end;
$$;

create or replace function public.update_my_email_preferences(p_enabled boolean,p_tournament_updates boolean,p_team_updates boolean,p_match_updates boolean,p_admin_updates boolean)
returns void language plpgsql security definer set search_path='pg_catalog','private','auth' as $$
declare v_user uuid:=auth.uid();
begin
  if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if;
  insert into private.email_preferences(user_id,enabled,tournament_updates,team_updates,match_updates,admin_updates,updated_at)
  values(v_user,coalesce(p_enabled,true),coalesce(p_tournament_updates,true),coalesce(p_team_updates,true),coalesce(p_match_updates,true),coalesce(p_admin_updates,true),now())
  on conflict(user_id) do update set enabled=excluded.enabled,tournament_updates=excluded.tournament_updates,team_updates=excluded.team_updates,match_updates=excluded.match_updates,admin_updates=excluded.admin_updates,updated_at=now();
end;
$$;

grant execute on function public.get_my_email_preferences() to authenticated;
grant execute on function public.update_my_email_preferences(boolean,boolean,boolean,boolean,boolean) to authenticated;
revoke all on function public.get_my_email_preferences() from anon;
revoke all on function public.update_my_email_preferences(boolean,boolean,boolean,boolean,boolean) from anon;

create or replace function public.email_claim_delivery_jobs(p_limit integer default 25)
returns table(id uuid,recipient_email text,kind text,subject text,body text,href text,attempts smallint)
language plpgsql security definer set search_path='pg_catalog','private','auth' as $$
begin
  if auth.role() <> 'service_role' then raise exception 'Недостаточно прав'; end if;
  return query with picked as (
    select q.id from private.email_delivery_queue q where q.status in ('pending','failed') and q.next_attempt_at<=now() and (q.locked_at is null or q.locked_at<now()-interval '10 minutes') order by q.created_at for update skip locked limit greatest(1,least(coalesce(p_limit,25),100))
  ), upd as (
    update private.email_delivery_queue q set status='processing',locked_at=now(),attempts=q.attempts+1,updated_at=now() from picked where q.id=picked.id returning q.*
  ) select u.id,u.recipient_email,u.kind,u.subject,u.body,u.href,u.attempts from upd u;
end;
$$;

create or replace function public.email_mark_delivery_sent(p_id uuid,p_provider_message_id text)
returns void language plpgsql security definer set search_path='pg_catalog','private','auth' as $$
begin
  if auth.role() <> 'service_role' then raise exception 'Недостаточно прав'; end if;
  update private.email_delivery_queue set status='sent',sent_at=now(),provider_message_id=p_provider_message_id,last_error=null,locked_at=null,updated_at=now() where id=p_id;
end;
$$;

create or replace function public.email_mark_delivery_failed(p_id uuid,p_error text)
returns void language plpgsql security definer set search_path='pg_catalog','private','auth' as $$
declare v_attempts smallint;
begin
  if auth.role() <> 'service_role' then raise exception 'Недостаточно прав'; end if;
  select attempts into v_attempts from private.email_delivery_queue where id=p_id for update;
  update private.email_delivery_queue set status=case when coalesce(v_attempts,0)>=5 then 'cancelled' else 'failed' end,next_attempt_at=now()+make_interval(mins=>least(60,greatest(2,power(2,least(coalesce(v_attempts,1),5))::int))),last_error=left(coalesce(p_error,'Unknown error'),2000),locked_at=null,updated_at=now() where id=p_id;
end;
$$;

revoke all on function public.email_claim_delivery_jobs(integer) from public,anon,authenticated;
revoke all on function public.email_mark_delivery_sent(uuid,text) from public,anon,authenticated;
revoke all on function public.email_mark_delivery_failed(uuid,text) from public,anon,authenticated;
grant execute on function public.email_claim_delivery_jobs(integer) to service_role;
grant execute on function public.email_mark_delivery_sent(uuid,text) to service_role;
grant execute on function public.email_mark_delivery_failed(uuid,text) to service_role;

create or replace function public.admin_email_delivery_overview()
returns jsonb language plpgsql security definer set search_path='pg_catalog','private','public' as $$
begin
  if not private.is_site_admin(auth.uid()) then raise exception 'Недостаточно прав'; end if;
  return (select jsonb_build_object('pending',count(*) filter(where status='pending'),'processing',count(*) filter(where status='processing'),'sent',count(*) filter(where status='sent'),'failed',count(*) filter(where status='failed'),'cancelled',count(*) filter(where status='cancelled'),'total',count(*)) from private.email_delivery_queue);
end;
$$;
grant execute on function public.admin_email_delivery_overview() to authenticated;
revoke all on function public.admin_email_delivery_overview() from anon;
