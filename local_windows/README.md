# Tanuki X Local Windows Fallback

This is the zero-additional-cost fallback for the direct Tanuki X publisher when GitHub Actions cannot queue runs at the account level.

## What it preserves

- Same `publisher.py` and X API v2 OAuth1 path.
- Same private `tanuki-growth/tanuki-x/queue` source.
- Only `status=ready` and due posts are eligible.
- At most one text post per run.
- Same public `state/published.jsonl` receipt semantics.
- No Metricool.
- No subscription or hosted runtime.

## Local security

The four X OAuth1 credentials are entered once and stored with Windows DPAPI for the current Windows user. The runner decrypts them only in-process and removes the environment variables at the end of the run. The GitHub read token is taken from the already-authenticated local GitHub CLI session rather than copied out of Actions secrets.

## Install

Run `local_windows/install_local_publisher.ps1` from an authenticated Windows account that has GitHub CLI and Python available. The installer:

1. clones/updates the public publisher repo under `%LOCALAPPDATA%\TanukiXPublisher\repo`;
2. creates a local Python venv and installs dependencies;
3. asks once for the four X credentials if the DPAPI store is missing;
4. registers `Tanuki X Local Publisher` every 30 minutes;
5. immediately runs one publication cycle.

If the X credentials are not available, do not invent or extract them from GitHub Actions: GitHub intentionally does not expose secret values.
