# Tanuki Windows Factory — Status

> Controller view. This page is intentionally fail-closed: it does **not** claim Spectre is live unless a machine heartbeat exists.

## Factory

- Factory: `spectre-win11`
- Install: ✅ PASS
- Self-test: ✅ PASS
- Auto-start: ✅ at Windows logon
- GitHub Actions: not used
- Live machine heartbeat: ⚪ **NOT CONNECTED YET**
- Outbound result return: ⚪ **NOT CONNECTED YET**

## Queue

| Order | Product | State |
|---|---|---|
| 1 | Clinic Cockpit Lite v0.8.0 RC3 | 🟡 ACTIVE — dispatched, awaiting local OUTBOX result |
| 2 | Tanuki Comic Gate A / known-good v0.8 | 🕒 QUEUED — starts only after Cockpit is resolved |
| 3 | FX University Windows/native gate | 🕒 QUEUED — after Comic |

## Tanuki Comic queued artifact

- Canonical issue: `kaz1213-hash/tanuki-comic#31`
- Recovery head: `1d928cb9e1c73e160a7e5ccfb53856e1c8b03b8a`
- Known-good baseline: `cd170861f8318af9795db4f8dd5f52472d0acc91`
- Source ZIP SHA-256: `3f32c97f523fa41c58175a9fada0cc9a1c3fd92f837677081aaf51bde79f781b`
- Historical EXE SHA-256: `67ca1fdb3e097ace77e4ea61352ddef49ed42ef0b052aa85dfb952b248684164`
- Gate: ordinary Windows + headed ordinary Google Chrome full v0.8 buyer flow

## v1.1 visibility requirement

Spectre itself should visibly show:
- watcher alive/dead;
- last poll time;
- current job;
- current phase;
- last PASS/FAIL;
- next queued job.

Preferred UX: a tiny always-available local status window or tray indicator. No PowerShell/log inspection for the Director.
