# trip_planner_app

Trip planner app backed by Supabase.

## Local development

Create `app/.env` from `.env.example` and fill in:

```bash
SUPABASE_URL=...
SUPABASE_ANON_KEY=...
INVITE_BASE_URL=http://localhost:3000/
```

### Web development

For local Chrome testing, always use port `3000` so the Supabase OAuth redirect
URL matches the project setup:

```bash
flutter run -d chrome --web-port 3000 --dart-define-from-file=.env
```

Supabase Dashboard should include:

- Site URL: `http://localhost:3000`
- Redirect URL: `http://localhost:3000`

### Invitation links and GitHub Pages

Apply `supabase/migrations/20261003154139_trip_invite_links.sql` before releasing
the client. This retires the old share-code RPC; Email invitations remain available.
The Pages workflow sets `INVITE_BASE_URL` from the configured Pages URL. For
manual builds use:

```bash
flutter build web --base-href /trip-app/ --dart-define-from-file=.env \
  --dart-define=INVITE_BASE_URL=https://tanachu0409.github.io/trip-app/
```

Share URLs are `https://tanachu0409.github.io/trip-app/?invite=<token>`.
The Web entry converts this query to `#/invite/<token>` before Flutter starts,
so direct loading and refreshing work without server rewrites. Pending invites
are saved before OAuth and cleared on acceptance or cancellation. Only the
token is saved, never an arbitrary return URL. Configure Supabase's Site URL
and OAuth redirect allowlist with the exact project root URL including its
trailing slash. Keep the existing native `com.example.tripplannerapp://login-callback`.

#### Android and iOS association

Native builds must use the same `INVITE_BASE_URL`. Android defaults to host
`tanachu0409.github.io` and exact path `/trip-app/`; override Gradle properties
`INVITE_HOST` and `INVITE_PATH` for another site. For iOS override the `INVITE_HOST`
Xcode build setting (default in Debug/Release xcconfig). Associated Domains
must be enabled for the signing profile. Both platforms use `app_links` for
incoming invitations and keep Flutter's built-in deep link handler disabled
to preserve Supabase OAuth callbacks.

Publish the association files at the **host root**, not `/trip-app/.well-known/`.
For github.io use the `TanaChu0409.github.io` root-site repository or a custom
domain. Deploy the templates in `docs/invite-links/` after replacing the signing
fingerprint, Apple Team ID and actual bundle ID. GitHub Pages deployments must
include `.nojekyll` to serve `.well-known` assets. The project-root Pages workflow
cannot publish files at the account-site root.

Without association files the HTTPS link still opens the Web app. Verify real
links from another app on Android/iOS with the app closed and already running;
also verify Google OAuth returns to the same invite confirmation screen.
An iOS device can keep opening Safari based on its previous user preference.

### Checks

```bash
dart analyze
flutter test
```
