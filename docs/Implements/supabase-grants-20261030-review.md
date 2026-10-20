# Supabase explicit grants review — 2026-10-20

Baseline: `ec6640b1fe9aa3e540004c26422f384e367c3d70` on `main`.
Scope: all 27 migrations (`001`–`026` and `20261003154139`), Flutter Data API
call sites, database tests, local configuration and both deployment workflows.

## Finding

The requested permission repair already landed in PR #44 (`4d7c5fa`). No
additional grant migration is needed on this baseline. Adding broad grants or
reapplying `026` after the invite-link migration would be a regression.

Supabase's [official announcement](https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically)
states that the October 30 rollout changes defaults for **future** public
tables; existing objects retain their privileges. Grants determine object
access, while RLS determines accessible rows. A clean reset recreates objects,
so relying on historical hosted defaults would still be unsafe.

## Migration review

| Migrations | Final access and impact |
| --- | --- |
| `001`–`004` | Five core UUID tables have explicit authenticated/service CRUD grants and RLS. `001` removes future table/sequence defaults and global PUBLIC function execution; `004` provides a restricted owner helper to avoid recursive policies. No serial/identity sequences need client grants. |
| `005`–`007`, `009`–`013` | Colour/permission columns and join RPC replacements do not rely on new-table defaults. Editor trip UPDATE is replaced by a scoped RPC, and ultimately removed at the table privilege layer in `025`/`026`. |
| `008`, `015`, `017` | Profiles are trigger-created. Authenticated reads are column-scoped and exclude email; updates are restricted by column and self RLS. `profiles_public` is explicitly SELECT-granted and uses `security_invoker=true` after `017`; its policy helper has explicit EXECUTE. Service CRUD is explicit. |
| `014`, `016` | Attempt logs have RLS and no direct anon/authenticated access. Definer RPCs use owner privileges to write logs, with authentication/authorization checks. Purge execution and maintenance CRUD are service-only. |
| `018`–`020` | Photo metadata has explicit CRUD grants and row policies. Storage helpers explicitly grant authenticated EXECUTE, and the bucket remains private. Storage schema privileges are outside the announced public-schema change. |
| `021`–`023` | Palette RPCs have explicit execution grants. Trigger/internal helpers are revoked from API roles and run through trusted definer call paths. |
| `024`–`025` | Realtime publications add no table grants. Archived rows remain readable; child writes require an active trip. Trip colour/archive changes use scoped RPCs rather than direct UPDATE. |
| `026` | Existing-project normalization explicitly reapplies per-table, per-column and per-function allowlists. It is a forward migration for databases that previously ran the older migration contents. Historical-file edits alone cannot repair an already-provisioned database. |
| `20261003154139` | Invite hashes are service-only; five authenticated/service RPCs have explicit execution grants. Internal resolver/trigger remain private. Legacy share-code RPC execution and membership self-inserts are deliberately removed. |

`anon` has no direct application relation or RPC access. `authenticated` has
the grants required by Flutter's current table/view/RPC calls, subject to RLS.
`service_role` has explicit administrative CRUD; BYPASSRLS does not substitute
for object grants. Service RPCs which consult `auth.uid()` still require user
context and are not guaranteed to work with a bare service token.

## Changes in this branch

- Add a transactional pgTAP test that creates a future table, sequence and
  function as `postgres` and verifies all three API roles receive no implicit
  access. It also exercises actual anonymous permission errors, checks RLS
  across application tables, and checks caller permissions on readable views.
- Correct the rollout guide's stale assumption that remote history is empty,
  include the timestamped invite-link migration, and prevent reapplying `026`
  over newer invitation restrictions.
- No runtime schema, RLS policy, app, or production database change is needed.
  Therefore this branch intentionally adds no redundant migration.

## Reset, CI and deployment

`Supabase database` pins CLI 2.119.0, starts a disposable stack, runs
`db reset --local --no-seed`, pgTAP, and database lint. `001` revokes automatic
grants before application tables are created, so a successful reset verifies
explicit grants rather than legacy platform defaults. The new test is picked
up by the existing workflow without a workflow edit.

The Pages workflow builds/deploys Flutter only; it does not apply database
migrations. Production schema and migration history must be inspected
separately using the corrected rollout guide. No production state was read or
modified in this review; repository readiness is not proof that `026` has been
applied to the hosted project.

## Risks and limits

The changes here affect tests/documentation only. Remaining deployment risk is
unverified hosted schema/history drift. Applying old migrations out of order
could restore retired access. Future table, sequence, view or function changes
must ship their own least-privilege grants and relevant RLS tests. Existing
tests cover the explicit ACL matrix and owner/editor/viewer/stranger behaviour;
they do not replace end-to-end OAuth, Storage upload or browser smoke tests.

## Validation results

Validated with the CI-pinned CLI 2.119.0 and PostgreSQL 17 in a separate local
stack (`trip-app-grants-audit`, separate ports); the existing `trip-app` stack
was not reset or changed.

- Fresh `db reset --local --no-seed`: all 27 migrations applied successfully.
- `test db --local`: **4 files, 484 assertions, PASS**.
- `db lint --local --schema public --level warning --fail-on error`: no schema
  errors or warnings reported.
- `db advisors --local --type security --level warn --fail-on error`: no issues
  reported at warning/error level.
- `git diff --check`: passed.

No production migration was run. CI results for the draft PR are separate from
these local results and must be checked before merge.
