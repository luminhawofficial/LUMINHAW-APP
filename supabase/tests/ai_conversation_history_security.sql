begin;

select plan(12);

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
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'ai_conversations'
      and policyname = 'Users delete their own AI conversations'
      and qual like '%auth.uid%'
  ),
  'conversation deletes are owner-scoped'
);

select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'ai_messages'
      and policyname = 'Users delete their own AI messages'
      and qual like '%auth.uid%'
      and qual like '%ai_conversations%'
  ),
  'message deletes require the authenticated conversation owner'
);

select ok(
  has_table_privilege('authenticated', 'public.ai_conversations', 'DELETE'),
  'authenticated users can request conversation deletion'
);

select ok(
  has_table_privilege('authenticated', 'public.ai_messages', 'DELETE'),
  'authenticated users can request message deletion'
);

select * from finish();

rollback;
