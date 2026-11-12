begin;

grant delete on public.ai_conversations, public.ai_messages to authenticated;

drop policy if exists "Users delete their own AI conversations"
  on public.ai_conversations;
create policy "Users delete their own AI conversations"
  on public.ai_conversations for delete to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "Users delete their own AI messages"
  on public.ai_messages;
create policy "Users delete their own AI messages"
  on public.ai_messages for delete to authenticated
  using (
    user_id = (select auth.uid())
    and exists (
      select 1
      from public.ai_conversations conversation
      where conversation.id = ai_messages.conversation_id
        and conversation.user_id = (select auth.uid())
    )
  );

commit;
