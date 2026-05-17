# trip_planner_app

Trip planner app backed by Supabase.

## Local development

Create `app/.env` from `.env.example` and fill in:

```bash
SUPABASE_URL=...
SUPABASE_ANON_KEY=...
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

### Checks

```bash
dart analyze
flutter test
```
