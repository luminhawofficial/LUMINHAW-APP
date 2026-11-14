begin;

alter table public.ai_conversations
  add column if not exists deleted_at timestamptz;

create index if not exists ai_conversations_active_user_updated_idx
  on public.ai_conversations (user_id, updated_at desc)
  where deleted_at is null;

create or replace function public.prevent_deleted_ai_conversation_restore()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and old.deleted_at is not null then
    raise exception using
      errcode = '23514',
      message = 'A deleted AI conversation cannot be restored.';
  end if;

  if tg_op = 'INSERT' and exists (
    select 1
    from public.ai_conversations conversation
    where conversation.id = new.id
      and conversation.user_id = new.user_id
      and conversation.deleted_at is not null
  ) then
    raise exception using
      errcode = '23514',
      message = 'A deleted AI conversation cannot be restored.';
  end if;

  return new;
end;
$$;

revoke all on function public.prevent_deleted_ai_conversation_restore()
  from public, anon, authenticated;

drop trigger if exists prevent_deleted_ai_conversation_restore
  on public.ai_conversations;
create trigger prevent_deleted_ai_conversation_restore
  before insert or update on public.ai_conversations
  for each row
  execute function public.prevent_deleted_ai_conversation_restore();

drop policy if exists "Users read their own AI messages"
  on public.ai_messages;
create policy "Users read their own AI messages"
  on public.ai_messages for select to authenticated
  using (
    user_id = (select auth.uid())
    and exists (
      select 1
      from public.ai_conversations conversation
      where conversation.id = ai_messages.conversation_id
        and conversation.user_id = (select auth.uid())
        and conversation.deleted_at is null
    )
  );

drop policy if exists "Users create their own AI messages"
  on public.ai_messages;
create policy "Users create their own AI messages"
  on public.ai_messages for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1
      from public.ai_conversations conversation
      where conversation.id = ai_messages.conversation_id
        and conversation.user_id = (select auth.uid())
        and conversation.deleted_at is null
    )
  );

drop policy if exists "Users update their own AI messages"
  on public.ai_messages;
create policy "Users update their own AI messages"
  on public.ai_messages for update to authenticated
  using (
    user_id = (select auth.uid())
    and exists (
      select 1
      from public.ai_conversations conversation
      where conversation.id = ai_messages.conversation_id
        and conversation.user_id = (select auth.uid())
        and conversation.deleted_at is null
    )
  )
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1
      from public.ai_conversations conversation
      where conversation.id = ai_messages.conversation_id
        and conversation.user_id = (select auth.uid())
        and conversation.deleted_at is null
    )
  );

drop policy if exists "Users delete their own AI conversations"
  on public.ai_conversations;
drop policy if exists "Users delete their own AI messages"
  on public.ai_messages;
revoke delete on public.ai_conversations, public.ai_messages
  from public, anon, authenticated;

create or replace function public.delete_ai_conversation(
  p_conversation_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required to delete an AI conversation.';
  end if;

  update public.ai_conversations
  set deleted_at = pg_catalog.clock_timestamp(),
      title = 'Deleted conversation',
      updated_at = pg_catalog.clock_timestamp()
  where id = p_conversation_id
    and user_id = v_user_id
    and deleted_at is null;

  if not found then
    return;
  end if;

  delete from public.ai_messages
  where conversation_id = p_conversation_id
    and user_id = v_user_id;
end;
$$;

revoke all on function public.delete_ai_conversation(uuid)
  from public, anon;
grant execute on function public.delete_ai_conversation(uuid)
  to authenticated;

commit;
