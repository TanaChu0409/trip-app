# Supabase migration CI and deployment

`.github/workflows/supabase-database.yml` validates Supabase changes on pull
requests. Pushes to `main` that change `supabase/**` or the workflow itself
also deploy pending migrations after local replay, pgTAP tests, and lint pass.
This includes merging a PR into `main`.

## GitHub setup

Create the `supabase-production` GitHub Actions environment. Add the following
Actions secrets to that environment or the repository:

| Secret | Value |
| --- | --- |
| `SUPABASE_ACCESS_TOKEN` | Supabase personal access token with access to the target project |
| `SUPABASE_DB_PASSWORD` | Target project's database password |
| `SUPABASE_PROJECT_REF` | Project reference from the Supabase dashboard URL |

These are separate from the frontend's `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
Restrict the environment's deployment branches to `main`. Required reviewers
are optional; if configured, deployments wait for their approval.

Before the first deployment, verify the remote schema and migration history
agree. For the existing production database, follow the historical baseline
repair procedure in [issue-43-supabase-rollout.md](issue-43-supabase-rollout.md)
if it has not already been completed. Account for later migrations already
applied remotely as well. CI never repairs history automatically and does not
use `--include-all`.

## Execution and recovery

PR jobs never receive production credentials. The deployment job runs only on
`main`, after validation succeeds. It links the project, prints migration
history, runs a dry run, applies pending migrations, and prints history again.
Production jobs share a concurrency group and do not cancel an active migration.
GitHub may replace a pending deployment with a newer one; the newer checkout
contains previous migrations too.

To retry a failed deployment or deploy outstanding migrations without a new
commit, run **Supabase database** via **Run workflow**, selecting `main`.
Manual runs on other branches only validate locally. If a migration fails,
inspect the logs and remote state before retrying; fix schema problems with a
new forward migration. Never reset the remote database as part of recovery.

### Migration version mismatches

If deployment reports "Remote migration versions not found in local migrations
directory", compare `supabase migration list --linked` with the files in the
workflow's checked-out branch. Confirm missing files have been committed and
pushed before changing migration history.

The custom colour names migration was recorded remotely as
`20261101065801_custom_color_names`, while its repository filename used
`20261031064640`. After confirming the stored SQL matched the local SQL
(ignoring line endings and surrounding whitespace), the repository file was
renamed to `20261101065801_custom_color_names.sql`. The remote history and SQL
were preserved; do not keep both versions, which would replay the same change.

For a similar mismatch, inspect the remote migration's recorded SQL and compare
it with the candidate local file before aligning filenames. If the SQL differs,
stop and investigate rather than assuming the migrations are interchangeable.
Do not automatically run `migration repair`, `db pull`, or `--include-all` to
bypass the error. A repair changes history without undoing the applied SQL.

After this correction, the expected pending migration is
`20261126144040_edit_trip_details.sql`, provided no further migrations have
been deployed. Verify the current history and dry-run output before deployment.
Keep migration versions stable after deployment and use new forward migrations
for subsequent schema changes.

This workflow deploys SQL migrations only. Flutter Web deploys independently
through `deploy-web.yml`; application releases should remain compatible with
the database while both workflows run.

Reference: [Supabase managing environments](https://supabase.com/docs/guides/deployment/managing-environments).
