# Server image CI: build only

Workflow: `.github/workflows/owner-server-build.yml`.

The first verification runs on pushes to `ci/owner-server-build`, without
merging into main. Once the workflow is reviewed and merged, it is also
available through Actions > Owner server image (build only) > Run workflow.
It does not run automatically on main pushes or deploy to Cloudflare.

This change builds the committed repository revision. Uncommitted local iOS,
Club, ASO and owner-account migration changes are deliberately not bundled into
the CI-only branch. Its SHA identifies exactly which code the image contains.

## Checks

1. Install the frozen Bun dependency lockfile, typecheck and run Worker tests.
2. Bundle the checked-in Worker configuration using Wrangler dry-run with
   container rollout disabled. No Cloudflare login or secrets are supplied.
3. Build `Dockerfile.server` for Linux amd64 on the hosted Docker runner.
4. Start the image locally on the runner and verify `/health` plus a real
   `/v1/games` request using the committed test fixture.
5. Export the image archive, its SHA-256 checksum, Docker image ID and source
   commit as a 14-day GitHub Actions artifact. No registry push is performed.

No source-account traffic, migration, production deployment, app endpoint
change, paid Cloudflare plan activation or IAP operation occurs in this workflow.
Repository permission is limited to `contents: read`; no Cloudflare credentials
are needed or should be added for this build-only job.

## Artifact usage

Download the successful run's artifact and extract it. On a machine/CI runner
with Docker, verify `sha256sum -c SHA256SUMS`, then load with
`docker load -i preferans-engine-linux-amd64.tar.gz`. Confirm the source commit
and image ID before any separately authorized deployment.

Artifacts expire after 14 days. A future deployment must use the verified image
or rebuild the exact reviewed commit, not silently substitute another revision.
Running the server on Cloudflare still requires Workers Paid and a separately
configured destination; producing an image does not activate that service.
