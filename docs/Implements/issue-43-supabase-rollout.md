# Issue #43 Supabase production rollout

This rollout is intentionally manual. The pull-request workflow validates a
fresh local database only and never connects to the production project.

## Preconditions

1. Merge the issue branch only after `Supabase database` is green.
2. Confirm the production schema matches migrations `001` through `025`.
   Compare tables, columns, constraints, policies, triggers, functions, views,
   Storage policies, and Realtime publication membership. Do not infer this
   from application behaviour alone.
3. In the Supabase Dashboard, disable automatic Data API grants for newly
   created tables and functions.
4. Link the CLI to the intended project and verify its project reference before
   running any write command.

The remote migration history is currently empty. Do **not** run a normal
`supabase db push` until the history has been repaired, because that would try
to replay migrations `001` through `025` against an existing schema.

## Repair migration history

After the schema comparison is approved, mark only the already-present
migrations as applied:

```shell
supabase migration repair --linked --status applied 001 002 003 004 005 006 007 008 009 010 011 012 013 014 015 016 017 018 019 020 021 022 023 024 025
```

Read the remote history back and stop if any version is missing or if migration
`026` is already marked as applied unexpectedly:

```shell
supabase migration list --linked
supabase db push --linked --dry-run
```

The dry run must list only
`026_explicit_data_api_grants.sql`. With an explicit production
approval, apply it through the normal migration flow:

```shell
supabase db push --linked
```

Do not use `--include-all`, and do not run this command from pull-request CI.

## Post-deployment verification

Verify all of the following before closing issue #43:

- `pg_default_acl` has no future public-schema table, sequence, or function
  grants for `anon`, `authenticated`, `service_role`, or `PUBLIC`.
- Table and column privileges match the pgTAP matrix in
  `supabase/tests/database/001_acl.test.sql`.
- Function `EXECUTE` privileges match the same allowlist.
- `profiles.email` cannot be selected or returned by an authenticated client.
- `join_code_attempts` and `invite_member_attempts` reject direct client access.
- The Data API exposes only the intended `public` schema and automatic grants
  remain disabled.
- Supabase Security Advisor has no client-executable internal
  `SECURITY DEFINER` functions from this application.

Run authenticated smoke tests for: creating a trip, joining by share code,
inviting editor/viewer members, changing member permissions, creating and
editing days/stops/parking, uploading and deleting stop photos, changing trip
and stop colours, archiving/restoring a trip, and updating a profile. Include
owner, editor, viewer, and unrelated-user cases, and confirm archived trips are
read-only.

If verification fails, pause application writes as appropriate and repair with
a new forward migration. Do not rewrite the migration history after `026` has
been deployed.
