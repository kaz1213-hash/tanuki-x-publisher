# Tanuki X Publisher — Media Lab editorial gate (2026-10-18)

The existing scheduled GitHub Actions transport now routes through `media_lab_transport.py`.
**No new automation was created.** Legacy automated Promoter / marketing queue publication
is HOLD; the historical parsing/test helpers are retained only for regression coverage.

- The **sole** eligible source is the private
  `kaz1213-hash/tanuki-growth/tanuki-x/media-lab/x_approved_queue.json`
  (`tanuki-media-lab-x-approved/v1`), populated only after the Director approves
  the exact English X short. No other Media Lab platform is implicitly approved.
- The submitted UTF-8 text must exactly match the SHA-256 fixed in that private
  approval record. It is never shortened, translated, amended or auto-threaded.
- The transport first joins the public/private published receipts and reads the
  authenticated owner's live X API timeline. Unknown/empty/mismatched responses HOLD.
  Any X post during the same JST day blocks the next one.
- Immediately before the single X POST, the transport commits and pushes an
  immutable, text-free `state/attempts/<id>.json` intent. If that push fails,
  no X POST occurs. If POST/readback is uncertain, this intent prevents replay.
  A later run may **reconcile** an exact X timeline match and write its verified
  public receipt, but must not send the same text again.
- Published public receipt is committed by the pre-existing workflow step;
  the private Growth published ledger is read-only for this public transport and
  must be reconciled by the existing Media Lab owner after independent verification.
- **X official API is metered (prepaid credits).** With no private approval manifest or
  without its explicit `allow_prepaid_api_usage: true`, the transport makes **zero X API calls**.
  No purchase, top-up, or billing settings are changed by this code. A maximum of 10 owned
  posts are read at each permitted preflight. Read/write entitlements, actual credit balance,
  auto-recharge setting, workflow execution and real publication remain **unverified**.
  Unit tests do not authorize a publish on their own.

## Historical design (not active for new posts)


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
