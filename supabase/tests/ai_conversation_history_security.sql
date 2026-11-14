begin;

select plan(14);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.ai_conversations'::regclass),
  'RLS is enabled for AI conversations'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.ai_messages'::regclass),
  'RLS is enabled for AI messages'
);

select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'ai_conversations'
      and policyname = 'Users read their own AI conversations'
      and qual like '%auth.uid%'
  ),
  'conversation reads are owner-scoped'
);

select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'ai_conversations'
      and policyname = 'Users create their own AI conversations'
      and with_check like '%auth.uid%'
  ),
  'conversation inserts are owner-scoped'
);

select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'ai_conversations'
      and policyname = 'Users update their own AI conversations'
      and qual like '%auth.uid%'
      and with_check like '%auth.uid%'
  ),
  'conversation updates are owner-scoped'
);

select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'ai_messages'
      and policyname = 'Users read their own AI messages'
      and qual like '%auth.uid%'
      and qual like '%ai_conversations%'
  ),
  'message reads require the authenticated conversation owner'
);

select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'ai_messages'
      and policyname = 'Users create their own AI messages'
      and with_check like '%auth.uid%'
      and with_check like '%ai_conversations%'
  ),
  'message inserts require the authenticated conversation owner'
);

select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'ai_messages'
      and policyname = 'Users update their own AI messages'
      and qual like '%auth.uid%'
      and qual like '%ai_conversations%'
      and with_check like '%auth.uid%'
      and with_check like '%ai_conversations%'
  ),
  'message updates require the authenticated conversation owner'
);

select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'ai_conversations'
      and column_name = 'deleted_at'
  ),
  'conversation deletion tombstones are persisted'
);

select ok(
  exists (
    select 1 from pg_trigger
    where tgname = 'prevent_deleted_ai_conversation_restore'
      and not tgisinternal
  ),
  'deleted conversations cannot be restored by a later upsert'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.delete_ai_conversation(uuid)',
    'EXECUTE'
  ),
  'authenticated users can request secure conversation deletion'
);

select ok(
  not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename in ('ai_conversations', 'ai_messages')
      and policyname in (
        'Users delete their own AI conversations',
        'Users delete their own AI messages'
      )
  ),
  'conversation and message deletion is only available through the RPC'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'public.ai_conversations',
    'DELETE'
  ),
  'authenticated users cannot directly delete conversation tombstones'
);

select ok(
  not has_table_privilege('authenticated', 'public.ai_messages', 'DELETE'),
  'authenticated users cannot directly delete conversation messages'
);

select * from finish();

rollback;
