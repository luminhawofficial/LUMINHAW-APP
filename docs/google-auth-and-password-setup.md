# LUMINHAW Google authentication and password policy

## Google OAuth provider setup

LUMINHAW uses Supabase Auth's browser-based Google OAuth flow on Android and
Flutter Web. The app does not collect Google passwords or use a separate Google
authentication system.

1. In Google Cloud Console, configure the OAuth consent screen and create a
   **Web application** OAuth client.
2. Add this exact **Authorized redirect URI** to that client:

   `https://ccxzjjsxggrxiaaehxxu.supabase.co/auth/v1/callback`

   This is the Supabase provider callback. Do not use the Android deep link as
   Google's provider callback.
3. In Supabase Dashboard, open **Authentication → Sign In / Providers → Google**,
   enable Google, and enter the Web client ID and client secret from Google
   Cloud. Keep the client secret only in Supabase; it does not belong in this
   Flutter repository.
4. In Supabase **Authentication → URL Configuration → Redirect URLs**, allow:

   - `https://luminhawofficial.github.io/LUMINHAW-APP/`
   - `com.luminhaw.plantcare://auth-callback`

   The production Flutter Web URL is the GitHub Pages app path. Android returns
   through the existing `com.luminhaw.plantcare` app-link scheme. The GitHub
   Pages Administrator URL remains the Site URL for the existing email
   verification and password-recovery flows.
5. In Google Cloud, add `https://luminhawofficial.github.io` as an authorized
   JavaScript origin if the OAuth client setup requests an origin. This app uses
   the Web OAuth client and system-browser redirect flow on Android; it does not
   require a separate native Google SDK client or signing certificate.

For local development or a different web deployment URL, add that exact
redirect URL to Supabase's allowlist and update the app's
`googleOAuthRedirectUri` accordingly.

## Profile and database behavior

The existing `public.profiles` table, unique `id` key, auth-user trigger, and
row-level security policies are reused. The migration
`20261113230000_google_profile_metadata.sql` reads Google's name metadata and
uses an idempotent upsert, so OAuth sign-in cannot create duplicate profile
rows. It also fills display names for existing profiles that are blank. No
service-role key, new authentication table, or account email-change path is
added. The Edit Profile page stores date of birth, gender, phone, location,
bio, username, and gardening preferences in the same owner-protected profile
record. Age is calculated from date of birth and is not stored. Name and
location are also synchronized to Auth user metadata for existing app behavior.
Usernames are normalized to lowercase and enforced as case-insensitively
unique by a database index; the username-availability RPC returns only whether
the requested name is free for the signed-in user.

Apply `20261114093000_profile_completion_fields.sql` before using the expanded
profile form. It adds these fields and the photo-removal flag to the existing
`public.profiles` table, while leaving its current row-level security policies
unchanged.

My Garden, care activities, growth observations, scan history, AI conversations,
and payments retain their existing storage and access rules. Cloud
garden/care/growth reads explicitly filter by the current authenticated user ID
in addition to the database's RLS policies. Saved Library plant details remain
local, with separate account-scoped storage when signed in; they are not
uploaded or shared across devices. Existing device-only data is not
automatically attributed to an account.

## Password behavior

Registration, password reset, and change-password screens share the same
minimum-eight-character policy: uppercase, lowercase, number, and special
symbol. The GitHub Pages password-recovery form enforces the same policy.
Supabase Auth remains responsible for password storage and verification.
In Supabase Dashboard, set the Auth minimum password length to at least eight
characters and require digits, lowercase and uppercase letters, and symbols.
Client-side validation improves feedback but is not a substitute for this
server-side Auth policy. Consider enabling leaked-password protection when the
project plan supports it.
Google-only accounts can continue signing in without setting a password; adding
one from Settings is optional.

The yearly Premium price is unchanged at **₱499** to match the existing payment
plan and administrator approval configuration.

## Verification notes

Automated tests cover password policy cases, validation controls, navigation,
and callback handling. End-to-end Google sign-in requires the Google OAuth
client to be configured in Google Cloud and Supabase, then must be exercised
with a real Google account on Android and Flutter Web. Provider credentials are
intentionally not stored in the repository.
