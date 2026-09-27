# Tanuki X Free Publisher

Free public GitHub Actions transport for the SCA-owned Tanuki X account.

- Drafts and future queue content remain private in `kaz1213-hash/tanuki-growth`.
- Publishing is deliberate and wake-triggered only: `workflow_dispatch` or a push under `wake/**`.
- Scheduled polling is intentionally disabled so idle checks do not consume GitHub Actions.
- It reads the private `tanuki-growth/tanuki-x/queue` via a fine-grained read-only token.
- Only entries with `status: "ready"` and due `publish_at` are eligible.
- At most one text post is published per run.
- Only receipts for already-public X posts are stored here.
- Image/Comic publishing is intentionally not handled by this v1 path.

## Required Actions secrets

- `TANUKI_GROWTH_READ_TOKEN`
- `X_API_KEY`
- `X_API_SECRET`
- `X_ACCESS_TOKEN`
- `X_ACCESS_TOKEN_SECRET`

`TANUKI_GROWTH_READ_TOKEN` should be a fine-grained GitHub personal access token limited to:

- repository: `kaz1213-hash/tanuki-growth`
- permission: **Contents — Read-only**

Do not grant write, Actions, administration, or additional repository access.

No credential belongs in this public source tree.


## Runner-local fallback

GitHub Actions may be unavailable or account-restricted. Tanuki X can now run locally on a Windows Tanuki Runner without depending on GitHub Actions.

Local mode:
- uses the authenticated official GitHub CLI to read the private `kaz1213-hash/tanuki-growth` queue;
- does not require `TANUKI_GROWTH_READ_TOKEN` when GitHub CLI auth is available;
- supports `publisher.py --dry-run` for zero-post queue validation;
- stores X API credentials with Windows CurrentUser DPAPI through `tools/Configure-TanukiXCredentials.ps1`;
- runs continuously with `tools/Run-TanukiXLocal.ps1 -Continuous`;
- can be enabled at Windows sign-in with `tools/Enable-TanukiXAutostart.ps1`;
- keeps at most one post per polling run;
- writes a local receipt and, when GitHub CLI is available, also updates the private canonical publication receipt.

### Local credential boundary

GitHub Actions secret values cannot be read back from GitHub. The existing X API credentials must therefore be entered once on the Runner PC (or regenerated in the X developer portal) before live local posting can begin. They are not stored in plaintext by the local setup.

### Dogfood evidence

On DESKTOP-E57JK4I:
- GitHub Actions manual dispatch returned `Actions has been disabled for this user`.
- Runner-local private queue access succeeded with no Actions and no GitHub PAT.
- `publisher.py --dry-run` found the next due text item successfully.
- DPAPI credential round-trip with fake credentials passed and plaintext was absent from the saved file.
- local publisher autostart enable/disable passed against a temporary Startup folder.
- the wrapper `Run-TanukiXLocal.ps1 -DryRun` passed end-to-end.
