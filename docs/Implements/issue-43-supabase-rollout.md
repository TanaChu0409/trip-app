# Issue #43 Supabase production rollout

This rollout is intentionally manual. The pull-request workflow validates a
fresh local database only and never connects to the production project.

## Preconditions

1. Merge the issue branch only after `Supabase database` is green.
2. Read the current remote migration history and compare the production schema
   with every migration claimed as applied, including the timestamped
   `20261003154139_trip_invite_links.sql` when present.
   Compare tables, columns, constraints, policies, triggers, functions, views,
   Storage policies, and Realtime publication membership. Do not infer this
   from application behaviour alone.
3. In the Supabase Dashboard, disable automatic Data API grants for newly
   created tables and functions.
4. Link the CLI to the intended project and verify its project reference before
   running any write command.

The issue #43 investigation found an empty remote migration history at that
time; this is not evidence of its current state. Read `supabase migration list
--linked` first. If history is missing, do **not** run a normal `supabase db push`
until it has been repaired: it could replay old migrations against an existing
schema. Do not reset the remote database.

## Repair migration history

Only if schema comparison confirms `001` through `025` are already present
and their history is missing, mark those versions as applied:

```shell
supabase migration repair --linked --status applied 001 002 003 004 005 006 007 008 009 010 011 012 013 014 015 016 017 018 019 020 021 022 023 024 025
```

Apply the same evidence requirement to `026` and `20261003154139`: repair them
only when their complete effects already exist. Never mark a missing schema
change as applied. Never rerun `026` on top of the invite-link migration:
`026` grants the legacy `join_trip_by_code` RPC, while the later migration
deliberately revokes it and removes self-join membership inserts.

Read the remote history back and stop if it disagrees with the inspected schema:

```shell
supabase migration list --linked
supabase db push --linked --dry-run
```

For a project genuinely at `025`, the dry run must list `026` followed by
`20261003154139_trip_invite_links.sql`. For a project at `026`, only the latter
is expected; for an up-to-date project, neither should be pending. Review any
future migrations separately. With an explicit production approval, apply
only the verified pending migrations through the normal migration flow:

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
- `join_code_attempts`, `invite_member_attempts`, and `trip_invite_links` reject
  direct client access.
- Legacy `join_trip_by_code` execution and direct membership self-inserts are
  denied; authenticated invite-link RPCs remain available.
- The Data API exposes only the intended `public` schema and automatic grants
  remain disabled.
- Supabase Security Advisor has no client-executable internal
  `SECURITY DEFINER` functions from this application.

Run authenticated smoke tests for: creating a trip, creating/previewing/accepting
and revoking invite links (including rejecting the legacy share-code RPC),
inviting editor/viewer members, changing member permissions, creating and
editing days/stops/parking, uploading and deleting stop photos, changing trip
and stop colours, archiving/restoring a trip, and updating a profile. Include
owner, editor, viewer, and unrelated-user cases, and confirm archived trips are
read-only.

If verification fails, pause application writes as appropriate and repair with
a new forward migration. Do not rewrite the migration history after `026` has
been deployed.
