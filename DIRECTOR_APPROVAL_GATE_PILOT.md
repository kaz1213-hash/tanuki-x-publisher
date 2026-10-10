# Director Approval Gate — Public X Publisher PILOT

**Draft only. Do not merge or enable live posting without Director authorization.**

The public Publisher is a separate source of X API side effects from the private Growth Auto Mine and local Poster. The code in `tanuki-growth` does not automatically protect this runtime.

This patch:
- Verifies the exact Director approval receipt for generated `auto-mine-story`/`media-lab-story` items and all Promoter sprint rows.
- Matches the signature and text digest from `tanuki-growth/tanuki-x/director_approval.py` (including a pinned golden receipt test).
- Skips unapproved rows **before** selecting a due item so they cannot starve a valid approved queue.
- For approved generated items, prevents URL stripping, short_text fallback or auto-trimming from changing Director-approved copy.
- Keeps older manually queued campaigns on the legacy migration path. These still need a manual approval audit; the guard is **not universal yet**.
- Does not send X posts as part of the pilot. Unit tests stub network actions.

**Trust and rollout blockers**:
- The runtime needs `TANUKI_MEDIA_APPROVAL_HMAC_KEY` via Actions secrets for verification. It is intentionally **not configured by this PR**. Missing key = generated/promoter item blocked.
- The private signing/approval service must authenticate the actual Director decision before issuing a content-bound receipt. The signature is proof only if signing authority is isolated; this is not implemented by the pilot.
- Existing Promoter rows with `ready` but no approval will be skipped after merge (intentionally). Do not merge until legacy approvals and schedule are reconciled.
- The existing `3-hour` schedule is unchanged in this draft. It is not equivalent to the Director's 08:00/19:00 editorial review workflow.
- A POST succeeded but receipt persistence failed can still produce an ambiguous outcome; idempotent reconciliation before retry requires further work.

Run: `python -m unittest discover -s tests -p "test_*.py"`

**No X / Netlify / website / user content changes are authorized by this PR.**
