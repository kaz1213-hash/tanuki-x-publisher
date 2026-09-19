# Tanuki X Free Publisher

Free public GitHub Actions transport for the SCA-owned Tanuki X account.

- Drafts and future queue content remain private in `kaz1213-hash/tanuki-growth`.
- This public repository wakes every 30 minutes and reads only the private Tanuki X queue through a fine-grained read-only token.
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
