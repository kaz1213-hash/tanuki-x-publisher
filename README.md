# Tanuki X Free Publisher

Free public GitHub Actions transport for the SCA-owned Tanuki X account.

- Drafts and future queue content remain private in `kaz1213-hash/tanuki-growth`.
- Publishing supports `workflow_dispatch`, a push under `wake/**`, and a bounded **every-3-hours schedule** for the Tanuki Promoter exposure sprint.
- The transport still publishes at most one due text item per run; the high cadence comes from more scheduled runs, not batch posting.
- It reads the private `tanuki-growth/tanuki-x/queue` via a fine-grained read-only token.
- Only entries with `status: "ready"` and due `publish_at` are eligible.
- In addition to the legacy file-per-post queue, the publisher reads `tanuki-x/promoter/EXPOSURE_SPRINT_V0_1.json` from the private Growth repo.
- At most one text post is published per run.
- Only receipts for already-public X posts are stored here.
- Image/Comic publishing is intentionally not handled by this v1 path.


## Eco mode

Automatic Tanuki X publishing is intentionally **URL-free**.

- Promoter and legacy queue text is sanitized before API publishing.
- Any `http://`, `https://`, or `www.` URL is removed from automatic posts.
- Manual Placement through the X website may still use product links.
- This keeps routine automated writes on the cheaper plain-Post path and avoids accidental URL-bearing API writes.

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


## Tanuki Scout v0.2

`scout.py` runs four times per day and uses X Recent Search to find:
- active threads that explicitly invite self-promotion/project sharing;
- market pain/comparison conversations for Producer research.

It writes public-observation state to `state/scout_candidates.jsonl` and `state/market_signals.jsonl`.

Third-party replies are intentionally **not sent** in v0.2. X's current automation rules require additional approval for brand auto-response campaigns; candidate rows therefore remain `BLOCKED_PENDING_X_AUTO_RESPONSE_APPROVAL`.
