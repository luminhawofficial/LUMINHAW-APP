create table if not exists public.ai_conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  title text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ai_conversations_id_user_id_key unique (id, user_id),
  constraint ai_conversations_title_length check (
    char_length(title) between 1 and 120
  )
);

create table if not exists public.ai_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null check (role in ('user', 'assistant')),
  message text not null check (char_length(message) between 1 and 131072),
  created_at timestamptz not null default now(),
  constraint ai_messages_conversation_owner_fkey
    foreign key (conversation_id, user_id)
    references public.ai_conversations (id, user_id)
    on delete cascade
);

create index if not exists ai_conversations_user_updated_idx
  on public.ai_conversations (user_id, updated_at desc);

create index if not exists ai_messages_conversation_created_idx
  on public.ai_messages (conversation_id, user_id, created_at, id);

alter table public.ai_conversations enable row level security;
alter table public.ai_messages enable row level security;

revoke all on public.ai_conversations, public.ai_messages
  from public, anon;
grant select, insert, update on public.ai_conversations, public.ai_messages
  to authenticated;

drop policy if exists "Users read their own AI conversations"
  on public.ai_conversations;
create policy "Users read their own AI conversations"
  on public.ai_conversations for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "Users create their own AI conversations"
  on public.ai_conversations;
create policy "Users create their own AI conversations"
  on public.ai_conversations for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "Users update their own AI conversations"
  on public.ai_conversations;
create policy "Users update their own AI conversations"
  on public.ai_conversations for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

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
    )
  )
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1
      from public.ai_conversations conversation
      where conversation.id = ai_messages.conversation_id
        and conversation.user_id = (select auth.uid())
    )
  );
