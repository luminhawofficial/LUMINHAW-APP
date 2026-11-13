# Manual Premium payments

LUMINHAW uses manual GCash payments; it does not call a GCash gateway API.
Monthly Premium is PHP 49 for 30 days and yearly Premium is PHP 499 for 365
days. Both plan rows remain disabled until the owner explicitly authorizes
activation.

## Customer submission

- The authenticated, verified account supplies the full name and GCash mobile
  number. The server reads the registered account email from Supabase Auth and
  obtains the selected amount from the enabled plan; the client cannot choose
  another user ID or amount.
- Customers upload or photograph a private JPEG/PNG receipt, preview or remove
  it, enter the transaction date, optionally enter the transaction time, enter
  the amount paid, and enter a 13-digit reference shown as `0000 000 000000`.
- A customer may change plans only while a request is still pending and before
  sending payment. Changing plans cancels the pending request through the
  authenticated payment endpoint and records the cancellation in the payment
  event log. Submitted requests cannot be cancelled from checkout.
- The backend validates the reference format, transaction date, optional time,
  positive amount against the selected plan, private storage path, and JPEG/PNG
  file signature, structure, and size. It does not use OCR, AI, or image
  analysis to extract or validate transaction details.
- A database unique index on the normalized numeric reference and a
  transactional submission function prevent reuse across accounts, including
  concurrent submissions.

The submission screen confirms that the receipt was sent for review. This is
not proof that funds arrived and does not activate Premium. An administrator
must compare the entered reference, date, optional time, and amount with the
receipt, then verify the transaction in authorized GCash merchant or provider
records before approving. The screenshot and entered details alone are not
sufficient evidence.

## Administrator review

The GCash payment review page is available only to the single active account
with the `admin` role. It lists
customer name/email, reference, entered date/time,
amount, private receipt, submission time, and status; administrators can search
references, filter by status, review prior submissions, and open the receipt
full-size. Approval requires explicit confirmation of verification against
authorized merchant/provider records. Rejection requires a reason shown to the
customer.

Submitting a receipt gives the customer an immediate in-app confirmation and
places the payment in the manual-review queue. Approved and rejected decisions
queue customer email notifications; payment history shows the current status
and rejection reason. Optional single-use email review links also require
confirmation for approval and a reason for rejection. Tokens are bound to one
payment and action, expire, and become unusable after a decision.

The authenticated payment-status endpoint retries pending, failed, and stale
in-progress notifications using an atomic database claim. Notifications already
marked sent cannot be claimed again, and each delivery claim uses its unique
claim token as the email-provider idempotency key. A retry replaces the prior
unused action tokens atomically, leaving at most one active approval/rejection
pair. Known delivered notifications are not retried. Admin notifications can
only be sent to the configured reviewer; customer review notifications must
match the email stored on that payment request. Email HTML declares UTF-8.

Email-link possession is the authorization mechanism. The recorded reviewer
identity is the configured mailbox address, not an independently authenticated
individual. Protect access to that mailbox.

Premium activation occurs only inside an authorized transactional review
function after approval. It locks the payment, records the decision, and
activates or extends the entitlement by the selected plan's configured
duration: exactly 30 or 365 days. Rejection never activates Premium, and users
cannot approve their own payments.

The checkout readiness gate reports each missing environment variable,
provider setting, plan record, and private QR object separately. It requires
The explicit GCash enable flag, complete merchant details, Resend configuration,
both required plans enabled at their confirmed
prices/durations/QR paths, successful short-lived signing of both private QR
objects, and the manual-review submission RPC. OCR configuration is not
required. These checks do not prove that Resend, deployed RPCs, or the
end-to-end review workflow are operational; verify those with a non-production
integration test before enabling checkout.

## Production-readiness checklist

Code-level checks are not production verification. Flutter payment tests and
analysis, and the relevant Deno checks and unit tests, pass locally. The GCash
pgTAP test could not run because the local Docker network is unavailable. No
production migration, function deployment, secret change, or checkout
activation is part of these checks. Local tests do not verify a staging or
production integration.

Complete and record each gate before requesting production activation:

1. **Verify the database in an isolated non-production project.**
   - Apply the reviewed migration only to a disposable local or dedicated
     staging database. Never pass `--remote` to local database test commands.
   - Run the pgTAP receipt-review test and the full database test suite.
   - Verify invalid references, duplicate references across accounts, missing
     receipts, invalid/future dates, optional transaction time, incorrect
     amounts, and proof that submission alone never activates Premium.
   - Exercise approval and rejection using valid, expired, consumed, and
     revoked tokens. Verify a token can be used once, the sibling action is
     revoked, approval requires explicit receipt confirmation, rejection
     requires a reason, and only approval creates or extends the exact plan
     entitlement.
   - Confirm anon/authenticated roles cannot call privileged RPCs or read
     tokens/notification rows, while `service_role` can call only the intended
     server-side functions. Database unique constraints must protect concurrent
     duplicate submissions.

   With the local Supabase stack running and the reviewed migration applied
   locally, run:

   ```powershell
   supabase test db supabase/tests/gcash_receipt_review_security.sql
   supabase test db
   ```

   Do not treat either command as a production migration check; omit `--remote`.
   Do not run these commands against a database containing data that must be
   retained unless its effects are understood and authorized.

2. **Verify Resend and payment review using controlled mailboxes.**
   - Configure a non-production API key and a sender verified by Resend.
     Send test messages only to controlled reviewer/customer mailboxes.
   - Verify reviewer-only submission notifications, correct customer status
     notifications, private receipt access, action-link expiry and single-use
     behavior, retries/idempotency, and that opening a GET link does not
     approve or reject a payment.
   - Confirm approval/rejection notification failures remain retryable and
     do not falsely report successful delivery.

3. **Complete non-production end-to-end checkout tests.**
   - Use seeded test accounts, plans, QR assets and test payment records.
     Walk through readiness, plan/QR display, request creation, receipt
     upload, submission, review email, explicit approval and rejection,
     retries, status polling, and customer notifications.
   - Verify pending/manual-review submissions never grant Premium; test an
     approved payment grants exactly 30 or 365 days and correctly extends an
     existing entitlement. Confirm rejected payments do not grant access.
   - Recheck database permissions, private storage policies, Edge Function
     configuration, email recipients, logs, and rollback/recovery procedures.

4. **Authorize production activation separately.**
   - Recheck the live migration state, both plan rows and prices, merchant
     instructions, private QR objects and signed reads, production secrets,
     Resend sender status, function versions, and backups/change window.
     Historical production observations below are not a substitute for a
     current read-only verification.
   - Apply the reviewed migration and deploy reviewed functions only under
     separate explicit authorization. Keep both plan rows disabled and
     `GCASH_PAYMENTS_ENABLED=false` until the release owner approves a final
     smoke test and separately authorizes activation. Never use live customer
     funds or receipts as test data.

## Current production setup

- The last recorded production check found these price and QR settings:
  - `premium_30_days`: 4900 centavos, `plans/GCash-MyQR-49.PNG.jpg`
  - `premium_365_days`: 149900 centavos, `plans/GCash-MyQR-1499.PNG.jpg`
- Both production plans were disabled at that check.
- Migration
  `20261110120000_update_yearly_premium_price.sql` updates the local yearly
  plan to 49900 centavos and changes its QR path. This migration has not been
  deployed; the production yearly price remains unverified until deployment.
- The private `gcash-payment-assets` bucket exists, but QR objects were absent
  at the last recorded check. The 365-day price has since changed from PHP 1,499
  to PHP 499, so do not reuse the old 1,499 QR. Before enabling yearly checkout,
  provide and verify a QR that accepts the PHP 499 payment, then upload it as
  `plans/GCash-MyQR-499.PNG.jpg` through Supabase Dashboard → Storage →
  `gcash-payment-assets`. The monthly QR is `plans/GCash-MyQR-49.PNG.jpg`.
- The local migration
  `20261106230000_email_payment_approval_and_strict_receipts.sql` is not applied
  to production. It adds email-action tokens and hash-keyed rate limits, adds
  payment/receipt timestamps and delivery claims, tightens submission and
  approval RPCs, atomically replaces action tokens on retry, and restores the
  missing enabled-plan read policy and review notification trigger observed in
  production. Review its SQL and impact before applying it.
- The local migrations
  `20261112150000_gcash_receipt_manila_time_validation.sql` and
  `20261112200000_manual_payment_review_without_ocr.sql` update date validation
  and submission for no-OCR manual review. They have not been deployed.
- The no-OCR submission, admin payment review, and notification changes are
  local only and have not been deployed.

## Required Edge Function configuration

Set these only after the receiving account and sender are approved:

```dotenv
GCASH_PAYMENTS_ENABLED=false
GCASH_MERCHANT_NAME=
GCASH_MERCHANT_ACCOUNT=
GCASH_PAYMENT_INSTRUCTIONS=
RESEND_API_KEY=
RESEND_EMAIL_MODE=
RESEND_TEST_RECIPIENT=
RESEND_FROM_EMAIL=
PREMIUM_EMAIL_FROM=
RESEND_VERIFIED_DOMAIN=
LUMINHAW_APP_URL=https://luminhawofficial.github.io/LUMINHAW-APP/
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided by Supabase to Edge
Functions. Keep `RESEND_API_KEY`, service-role credentials, and all other
provider keys exclusively in Supabase Edge Function secrets; never put them in
Flutter defines or client-side code.

`RESEND_EMAIL_MODE` is required and must be explicitly set to `development` or
`production`; there is no default or production fallback. Development mode uses
`LUMINHAW <onboarding@resend.dev>` and requires `RESEND_TEST_RECIPIENT` to be
the email address associated with the Resend account. It routes all queued
payment-notification test sends only to that address and sends generic content
without customer/payment details, proof links, or action tokens. Production
mode requires a valid sender and verified domain.

`RESEND_FROM_EMAIL` is the primary production sender setting;
`PREMIUM_EMAIL_FROM` is a compatibility fallback, and if both are set they
must match exactly. The sender display name is normalized to `LUMINHAW`.
`RESEND_VERIFIED_DOMAIN` must be the exact verified sender domain, and the
sender's address domain must match it. `LUMINHAW_APP_URL` is the official HTTPS
app URL and base path. Customer links and the app-hosted payment confirmation
bridge use this value. The bridge keeps action tokens in the URL fragment,
removes the fragment from browser history before use, and sends the token in a
POST body to the configured Edge Function. The only review recipient is
`luminhawofficial@gmail.com`.

The email-action function is intentionally configured with JWT verification
disabled because its expiring, single-use token is its authorization; do not
remove token validation or expose service-role credentials.

## Review SQL and deploy manually

No production migration or function deployment is performed automatically.
Before applying the pending migration, inspect the SQL, confirm current remote
migration state, and review its effects on payment review constraints,
notification delivery claims, reference validation, and email action tokens.
It preserves existing payment records and does not enable plans.

The last read-only production migration check showed
`20261106230000_email_payment_approval_and_strict_receipts.sql` pending. Use
the explicit project reference below for every remote operation; none of these
commands are run by local tests. The dry run must show only the reviewed
migration before proceeding. `--skip-vault` prevents a database push from
updating Vault configuration.

```powershell
supabase migration list --remote=ccxzjjsxggrxiaaehxxu
supabase db push --dry-run --skip-vault --remote=ccxzjjsxggrxiaaehxxu
# Stop here and review the dry-run output. Apply only after separate authorization.
supabase db push --skip-vault --remote=ccxzjjsxggrxiaaehxxu

supabase --experimental storage cp --content-type image/jpeg --remote=ccxzjjsxggrxiaaehxxu `
  .\supabase\private-assets\gcash\GCash-MyQR-49.PNG.jpg `
  ss:///gcash-payment-assets/plans/GCash-MyQR-49.PNG.jpg
supabase --experimental storage cp --content-type image/jpeg --remote=ccxzjjsxggrxiaaehxxu `
  .\supabase\private-assets\gcash\GCash-MyQR-499.PNG.jpg `
  ss:///gcash-payment-assets/plans/GCash-MyQR-499.PNG.jpg

# Only after owner-provided, verified Resend credentials and merchant
# details are available in a protected local file (never commit that file):
supabase secrets set --env-file .\supabase\.env.production `
  --remote=ccxzjjsxggrxiaaehxxu

supabase functions deploy create-premium-payment --remote=ccxzjjsxggrxiaaehxxu
supabase functions deploy submit-premium-payment --remote=ccxzjjsxggrxiaaehxxu
supabase functions deploy get-premium-payment-status --remote=ccxzjjsxggrxiaaehxxu
supabase functions deploy admin-api --remote=ccxzjjsxggrxiaaehxxu
supabase functions deploy payment-email-action --no-verify-jwt `
  --remote=ccxzjjsxggrxiaaehxxu
```

The legacy admin-review function is retained as a `410 Gone` response for
compatibility; it no longer exposes dashboard operations. Do not enable either
plan or set `GCASH_PAYMENTS_ENABLED=true` until the QR assets, merchant
configuration, email delivery, and review actions are verified and the
owner explicitly authorizes activation. Keep `GCASH_PAYMENTS_ENABLED=false`
and both plan rows disabled throughout migration, storage, and function rollout.
Afterward, verify the migration list, private object metadata and signed reads,
function list, and a complete staging payment/review/entitlement flow before
requesting separate authorization to enable checkout. Do not run these commands
against production without an approved maintenance window and backup plan.

## Local checks

Install Deno on Windows from PowerShell, then open a new PowerShell window:

```powershell
irm https://deno.land/install.ps1 | iex
deno --version
```

From the project root, run the payment Edge Function checks:

```powershell
deno check supabase/functions/create-premium-payment/index.ts
deno check supabase/functions/submit-premium-payment/index.ts
deno check supabase/functions/get-premium-payment-status/index.ts
deno check supabase/functions/payment-email-action/index.ts
deno check supabase/functions/admin-api/index.ts
deno test --allow-all supabase/functions/_shared
```

The Resend adapter tests inject mocked fetch responses. They verify request
shape and provider error handling without using credentials or contacting the
provider; they are not live delivery integration tests. No OCR or AI provider
is used for receipt handling.

For local HTTP testing, start the local Supabase stack and serve the functions
with local-only provider settings. Supabase CLI loads the git-ignored
`supabase/functions/.env` by default; `--env-file` can select that file
explicitly. Do not copy production credentials or invent merchant details.
Keep `GCASH_PAYMENTS_ENABLED=false` throughout local checkout-readiness tests.

```powershell
supabase start
supabase functions serve --env-file supabase/functions/.env
```

In another PowerShell window, this safe smoke test verifies the email-action
route responds without changing payment data:

```powershell
curl.exe -i "http://127.0.0.1:54321/functions/v1/payment-email-action?token=invalid"
```

Only test successful submission/approval with a dedicated local project,
explicitly seeded test data, and non-production credentials. Do not test with
real customer receipts or point local commands at production. These commands
do not apply migrations or deploy functions.

Run focused Flutter checks from the workspace:

```powershell
flutter analyze
flutter test test/premium_payment_service_test.dart
```

These local checks cannot establish that Resend delivers email actions in
production. Complete the production-readiness checklist above with an approved
non-production setup before enabling payments. Never use a receipt screenshot
or manually entered values as proof that funds were received.
