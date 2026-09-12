create or replace function public.admin_queue_test_email()
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
declare
  v_user uuid := auth.uid();
  v_id uuid;
begin
  if v_user is null or not private.is_site_admin(v_user) then
    raise exception 'Недостаточно прав';
  end if;

  update private.email_delivery_queue
     set status = 'cancelled',
         updated_at = now(),
         last_error = 'Superseded by a newer admin test run'
   where user_id = v_user
     and kind = 'admin_email_test'
     and status in ('pending','failed');

  insert into private.user_notifications(user_id, kind, title, body, href)
  values (
    v_user,
    'admin_email_test',
    'Тест email-уведомлений',
    'Это тестовое уведомление отправлено через очередь Esports Platform → Supabase Edge Function → Resend.',
    'notifications.html'
  )
  returning id into v_id;

  update private.email_delivery_queue
     set recipient_email = 'sanekabramkin@gmail.com',
         updated_at = now()
   where notification_id = v_id;

  return v_id;
end;
$$;

revoke all on function public.admin_queue_test_email() from public, anon;
grant execute on function public.admin_queue_test_email() to authenticated;
