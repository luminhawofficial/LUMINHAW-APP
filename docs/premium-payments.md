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
  it, enter the transaction date/time, and enter a 13-digit reference shown as
  `0000 000 000000`.
- A customer may change plans only while a request is still pending and before
  sending payment. Changing plans cancels the pending request through the
  authenticated payment endpoint and records the cancellation in the payment
  event log. Submitted requests cannot be cancelled from checkout.
- The backend verifies file signatures and image structure, sends the image to
  OCR.space and requires transaction markers, required transaction fields,
  and a successful transaction status. Clearly identified GCash receipts
  continue through field checks; explicit other-wallet receipts are rejected.
  Likely GCash OCR misreads such as `GCa5h` are sent to manual review, while
  missing provider identification or incomplete details are inconclusive.
  Exact matches from OCR.space are also sent to manual review because the
  provider does not supply numeric confidence. The OCR-extracted recipient is
  shown to the reviewer when available, but is not treated as verified proof of
  the merchant.
- A database uniqueness index and transactional checks prevent reuse of the
  normalized reference. OCR is not proof that funds arrived and never activates
  Premium.

OCR text matching cannot prove that a receipt is genuine, detect every fake
template, or reliably measure blur/cropping. The email reviewer must compare
the submitted transaction against the official GCash merchant records before
approving. Do not describe the OCR result as payment verification.

The strict
`20261106230000_email_payment_approval_and_strict_receipts.sql` RPC requires a
numeric confidence of at least `0.75` for automatic matches. Its local
definition accepts a missing confidence only for `manual_review`, requires
transaction markers and complete required fields, records the absent score as
null, and marks image quality for manual review. Ambiguous provider
identification can never be automatically matched. This does not fabricate
confidence or grant Premium; approval still requires the separate reviewer
action. Apply and test migrations only in a dedicated local project before
considering any non-production or production rollout.

## Email-only review

Submissions that pass image/receipt checks notify
`luminhawofficial@gmail.com` with customer and payment details, OCR results and
a short-lived signed link to the private receipt. Separate
cryptographically random approve/reject tokens are generated for each action;
only SHA-256 token hashes are stored. Tokens expire after 48 hours, are bound
to one payment and one action, and become unusable after the first decision.
The email-action endpoint uses a separate hash-keyed rate-limit table rather
than the auth-user rate-limit table.
Opening a link only displays a confirmation form. Approval requires an explicit
confirmation that the actual GCash transaction was received; rejection requires
a reason. The database records the reviewer email and decision in the payment
row and audit log. No admin dashboard or extra Supabase Auth user is required.

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

Premium activation occurs only inside the transactional email-review database
function after a valid approval. The operation locks the payment/token,
consumes the token, revokes sibling tokens, records the decision, and activates
or extends the entitlement by the selected plan's configured duration: exactly
30 or 365 days. Rejection never activates Premium.

The checkout readiness gate reports each missing environment variable,
provider setting, plan record, and private QR object separately. It requires
the explicit GCash enable flag, complete merchant details, Resend and OCR
configuration, both required plans enabled at their confirmed
prices/durations/QR paths, successful short-lived signing of both private QR
objects, and a submission RPC that supports confidence-free manual review.
These checks do not prove that Resend, deployed RPCs, or the end-to-end review
workflow are operational; verify those with a non-production integration test
before enabling checkout.

## Production-readiness checklist

Code-level checks are not production verification. In this environment, all
local migrations were replayed and `supabase test db` passed all 69 pgTAP
tests, including the receipt-review security cases. Flutter tests and analysis
also passed in prior local verification. Deno is not installed in the current
shell, so Edge Function unit tests and type checks were not rerun here. No
production migration, function deployment, secret change, or checkout
activation is part of these checks. Local database tests do not verify a
staging or production integration.

Complete and record each gate before requesting production activation:

1. **Verify the database in an isolated non-production project.**
   - Apply the reviewed migration only to a disposable local or dedicated
     staging database. Never pass `--remote` to local database test commands.
   - Run the pgTAP receipt-review test and the full database test suite.
   - Add/verify database-level cases for malformed or missing transaction
     fields, explicit non-GCash and ambiguous providers, matching GCash
     manual-review submissions with null confidence, matched submissions with
     null confidence, confidence below `0.75` or above `1.0`, mismatched OCR
     fields, duplicate references, and proof that submission alone never
     activates Premium.
   - Exercise approval and rejection using valid, expired, consumed, and
     revoked tokens. Verify a token can be used once, the sibling action is
     revoked, approval requires explicit receipt confirmation, rejection
     requires a reason, and only approval creates or extends the exact plan
     entitlement.
   - Confirm anon/authenticated roles cannot call privileged RPCs or read
     tokens/notification rows, while `service_role` can call only the intended
     server-side functions. The current pgTAP file covers RPC grants and
     confidence-free ambiguous and clearly identified manual review, plus
     matched-null and out-of-range confidence rejection. It does not by itself
     prove the full approval/token lifecycle above.

   With the local Supabase stack running and the reviewed migration applied
   locally, run:

   ```powershell
   supabase test db supabase/tests/gcash_receipt_review_security.sql
   supabase test db
   ```

   Do not treat either command as a production migration check; omit `--remote`.
   Do not run these commands against a database containing data that must be
   retained unless its effects are understood and authorized.

2. **Verify OCR.space with controlled samples.**
   - Use a dedicated non-production API key and a small set of authorized,
     redacted/test receipts; do not upload real customer receipts for testing.
   - Check clear GCash, likely OCR misread, other-wallet, unknown-provider,
     missing-time, unsuccessful, and incomplete cases. Confirm only a clearly
     identified GCash receipt with all required fields can pass the local
     field checks. OCR.space supplies no confidence, so its results must
     remain manual-review-only; do not turn that status into automatic
     approval or infer confidence from text matching.
   - Record provider errors, timeout behavior, and quota usage without
     retaining API keys or full receipt contents in logs.

3. **Verify Resend and email review using controlled mailboxes.**
   - Configure a non-production API key and a sender verified by Resend.
     Send test messages only to controlled reviewer/customer mailboxes.
   - Verify reviewer-only submission notifications, correct customer status
     notifications, private receipt access, action-link expiry and single-use
     behavior, retries/idempotency, and that opening a GET link does not
     approve or reject a payment.
   - Confirm approval/rejection notification failures remain retryable and
     do not falsely report successful delivery.

4. **Complete non-production end-to-end checkout tests.**
   - Use seeded test accounts, plans, QR assets and test payment records.
     Walk through readiness, plan/QR display, request creation, receipt
     upload, submission, review email, explicit approval and rejection,
     retries, status polling, and customer notifications.
   - Verify pending/manual-review submissions never grant Premium; test an
     approved payment grants exactly 30 or 365 days and correctly extends an
     existing entitlement. Confirm rejected payments do not grant access.
   - Recheck database permissions, private storage policies, Edge Function
     configuration, email recipients, logs, and rollback/recovery procedures.

5. **Authorize production activation separately.**
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
- The email-review and strict-validation Edge Function changes are local only
  and have not been deployed.

## Required Edge Function configuration

Set these only after the receiving account and sender are approved:

```dotenv
GCASH_PAYMENTS_ENABLED=false
GCASH_MERCHANT_NAME=
GCASH_MERCHANT_ACCOUNT=
GCASH_PAYMENT_INSTRUCTIONS=
OCR_SPACE_API_KEY=
RESEND_API_KEY=
RESEND_FROM_EMAIL=
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided by Supabase to Edge
Functions. Keep all service-role and provider keys server-side. The sender must
be verified with Resend. The only review recipient is
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

# Only after owner-provided, verified Resend/OCR.space credentials and merchant
# details are available in a protected local file (never commit that file):
supabase secrets set --env-file .\supabase\.env.production `
  --remote=ccxzjjsxggrxiaaehxxu

supabase functions deploy create-premium-payment --remote=ccxzjjsxggrxiaaehxxu
supabase functions deploy submit-premium-payment --remote=ccxzjjsxggrxiaaehxxu
supabase functions deploy get-premium-payment-status --remote=ccxzjjsxggrxiaaehxxu
supabase functions deploy payment-email-action --no-verify-jwt `
  --remote=ccxzjjsxggrxiaaehxxu
supabase functions deploy admin-review-premium-payment `
  --remote=ccxzjjsxggrxiaaehxxu
```

The legacy admin-review function is retained as a `410 Gone` response for
compatibility; it no longer exposes dashboard operations. Do not enable either
plan or set `GCASH_PAYMENTS_ENABLED=true` until the QR assets, merchant
configuration, OCR, email delivery, and email actions are verified and the
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
deno check supabase/functions/admin-review-premium-payment/index.ts
deno test --allow-all supabase/functions/_shared
```

The OCR.space and Resend adapter tests inject mocked fetch responses. They
verify request shape and provider error handling without using credentials or
contacting either provider; they are not live delivery/OCR integration tests.

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

These local checks cannot establish that OCR.space classifies genuine receipts
accurately or that Resend delivers email actions in production. Complete the
production-readiness checklist above with an approved non-production setup
before enabling payments. Never use fabricated receipt results as successful
integration tests.
