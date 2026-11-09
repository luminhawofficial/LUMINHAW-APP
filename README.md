# Luminhaw

Luminhaw is a Flutter plant-care app organized by feature. It includes the
introduction/onboarding flow, five-destination app shell, local garden and
growth journal, camera/gallery image selection, Supabase authentication, and
server-side plant-analysis adapters.

Garden plants and journal entries are stored on the device for signed-out use
and sync to owner-scoped Supabase tables for signed-in users with verified
email. Existing device-only records are not automatically uploaded or assigned
to an account. The app uses a public Supabase project URL and publishable key.
Plant identification, health analysis, AI chat, and Google Play billing require
provider configuration; the app reports when a service is unavailable rather
than showing fabricated results or granting Premium. The plant catalog
displays provider results only; there are no bundled sample plant records. See the
[implementation checklist](docs/implementation-checklist.md) for known release
blockers.

## Project structure

- `lib/app/` — application setup, routing, and theme
- `lib/core/` — shared constants, widgets, services, and errors
- `lib/features/` — feature-specific screens and presentation widgets
- `lib/features/information/` — About and privacy disclosures
- `lib/models/` and `lib/repositories/` — shared data and repository layers
- `assets/` — app images, icons, and fonts
- `supabase/` — migration and edge-function locations
- `test/` and `integration_test/` — automated tests

## App setup

Run the app locally:

```powershell
flutter run
```

Supabase Auth uses the configured project by default. To run against a
different project, provide its URL and public publishable key (or legacy anon
key) at build/run time:

```powershell
flutter run `
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_KEY
```

The Supabase migrations create owner-scoped tables, row-level security
policies, a private `plant-photos` bucket, per-user Edge Function rate limits,
and server-managed subscription entitlements. Account deletion, plant
identification, catalog search, plant-health analysis, and AI chat are Edge
Functions. Apply the migrations and deploy the functions with the Supabase CLI:

```powershell
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
supabase functions deploy plant-identification
supabase functions deploy plant-catalog
supabase functions deploy plant-care
supabase functions deploy plant-health
supabase functions deploy assistant-chat
supabase functions deploy create-premium-payment
supabase functions deploy submit-premium-payment
supabase functions deploy get-premium-payment-status
supabase functions deploy admin-review-premium-payment
supabase functions deploy delete-account
supabase functions deploy plant-search
supabase functions deploy plant-sync
supabase functions deploy plant-details
supabase functions deploy plant-identify
supabase functions deploy plant-id-health
supabase functions deploy plant-perenual
supabase functions deploy plant-gemini
```

Keep all provider credentials in Supabase Edge Function secrets, never in the
Flutter app or source control. Plant identification uses `PLANT_ID_API_KEY`
and falls back to `PLANTNET_API_KEY` if Plant.ID is unavailable. The online
plant catalog uses `PERENUAL_API_KEY` when configured and falls back to the
public GBIF species search API. LUMIN AI uses `GEMINI_API_KEY` and optionally
`GEMINI_MODEL` (defaults to `gemini-flash-latest`). Add newly rotated
credentials privately with `supabase secrets set`; do not reuse keys pasted
into chat or place them in Dart `--dart-define` values. The Edge Functions also
require `SUPABASE_SERVICE_ROLE_KEY` to enforce rate limits and check
server-managed entitlements. Configure Supabase Auth email delivery and
redirect URLs before testing verification and password reset. The scanner is
wired to the plant-identification function; catalog searches use the
authenticated plant-catalog function. The assistant calls the Gemini-backed
function; free accounts can send 10 messages per UTC day, while accounts with
an active, server-verified Premium entitlement have no daily message quota. The
health checker accepts a camera or gallery photo only after
the user consents, stores it in the private per-user photo bucket, and invokes
the authenticated `plant-health` function. That function requires a verified
Premium entitlement and enforces a rate limit; configure `PLANT_ID_API_KEY` as
a Supabase Edge Function secret. Health results are advisory, not confirmed
diagnoses, and live requests require deployed functions/migrations and
provider configuration.

The optional GBIF database API stores shared taxonomy in `plant_catalog`.
This is deliberately separate from `plants`, which stores each user's garden,
and identification history continues to use `plant_identifications.owner_id`.
The auxiliary `plant-search`, `plant-sync`, `plant-details`, `plant-identify`,
`plant-id-health`, `plant-perenual`, and `plant-gemini` functions use that
catalog schema and verified-user rate limits. `plant-id-health` also checks the
server-verified Premium entitlement. They are separate from the app's
`plant-catalog`, `plant-identification`, and `plant-health` functions.

Do not deploy a package's alternate `plant-care` function over this project's
existing `plant-care` endpoint: the app endpoint provides Premium-gated
Perenual care data and has a different request/response contract. The database
API can return reviewed local care data through `plant-details`.

Detailed plant care is Premium-gated in the app and on the server. The
`plant-care` function finds an exact scientific-name match in Perenual's
species database, returns only care fields the provider supplies, and caches
matches for 24 hours per warm function instance. It requires the existing
server-side `PERENUAL_API_KEY`; unsupported details such as temperature or
humidity are omitted rather than inferred.

GBIF catalog photos are looked up from occurrence media using the GBIF
backbone taxon key. Only HTTPS photos marked CC0 or CC BY are used from GBIF;
the plant detail page shows available creator, license, and source reference.
The Edge Function caches occurrence images in each warm instance for six
hours (empty or failed lookups for two minutes) and limits each search to six
occurrence lookups. This cache is instance-local and is not shared across
function cold starts. If no suitable photo is available or a request fails,
the catalog keeps its image placeholder.

After rotating exposed provider keys, create `supabase/.env.local` on your
machine using the variable names above and the new values, then run:

```powershell
supabase secrets set --env-file supabase/.env.local
```

That local env file is excluded from source control. Never paste replacement
credentials into source files, command history, or chat.

Premium remains locked until a trusted server verifies a configured manual
payment or a future billing integration and writes a valid record to
`subscription_entitlements`. No client-side action can grant the entitlement.
Account deletion requires password reauthentication and a server-verified JWT
with a recent authentication time; the deletion function removes the user's
private photos before deleting the account.
The Android application ID is `com.luminhaw.plantcare`; confirm its
availability in the Play Console before publishing.

Manual Premium payments are implemented but disabled until GCash approves the
merchant receiving method and the server is configured. The currently
configured plan prices are PHP 49 for 30 days and PHP 1,499 for 365 days;
confirm the merchant terms and obtain owner approval before activation. See
[manual Premium payment setup](docs/premium-payments.md) for the production
readiness checklist, migration, function deployment, and configuration
requirements. No GCash API or live webhook is implemented.

### Local payment-provider tests

The payment Edge Functions use `OCR_SPACE_API_KEY` for OCR.space and
`RESEND_API_KEY` plus `RESEND_FROM_EMAIL` for Resend (`PREMIUM_EMAIL_FROM`
remains supported). GCash requires `GCASH_MERCHANT_NAME`,
`GCASH_MERCHANT_ACCOUNT`, `GCASH_PAYMENT_INSTRUCTIONS`, and an explicit
`GCASH_PAYMENTS_ENABLED=true`; do not enable it until the merchant and the
receipt-validation flow are approved. Supabase supplies its URL and local
service-role key to locally served functions. The placeholders in
[supabase/functions/.env.example](supabase/functions/.env.example) are for
local setup only. Add provider or approved merchant values to
`supabase/functions/.env` without replacing existing secrets; that file is
ignored by Git. Use a Resend-verified sender address when testing delivery.

Run the mocked provider tests from the project root:

```powershell
deno test supabase/functions/_shared/receipt-ocr_test.ts supabase/functions/_shared/payment-email_test.ts
```

These tests replace both provider HTTP calls with mocks and do not use API
quotas. Supabase CLI loads `supabase/functions/.env` when serving functions
locally; run `supabase functions serve --env-file supabase/functions/.env`.
Keep `GCASH_PAYMENTS_ENABLED=false` to leave checkout disabled. Do not deploy
functions or apply production migrations as part of local testing.

## Android release signing

Install the Android NDK version required by the current Flutter SDK through
Android Studio's SDK Manager. Create an upload keystore, copy
`android/key.properties.example` to the ignored `android/key.properties`, and
fill in the real values locally. Never commit or share the keystore or
`key.properties`.

```powershell
keytool -genkey -v -keystore android/upload-keystore.jks `
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
flutter build appbundle --release
```

The Android release task intentionally fails until valid release signing
properties and the referenced keystore are present. Publish a reviewed,
publicly hosted privacy policy and confirm the application ID in Play Console
before submitting a release.

## Run and test

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```
#   L U M I N H A W - A P P  
 #   L U M I N H A W - A P P  
 #   L U M I N H A W - A P P  
 #   L U M I N H A W - A P P  
 #   L U M I N H A W - A P P  
 #   L U M I N H A W - A P P  
 