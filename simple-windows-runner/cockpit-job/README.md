# Clinic Cockpit minimal Windows job

Canonical runnable files live directly under `../JOB/` so the `simple-windows-runner` directory is a complete one-click package without an assembly/copy step.

The job scans common user locations plus `C:\TanukiFactory` for an already-transferred RC3 R2 package identified by:
- candidate: `v0.8.0 RC3`
- ready branch: `release-ready/v0.8.0-rc3-no-github-r2`
- frozen product commit: either legacy `70ec03be3de89548bf61ceea2661bffb03dab18a` or corrected `33fffccf66ab66f4bf161af8f07797576a6379b7`

It copies the located package into isolated TEMP, overlays the bounded corrected RC3 staging patch, restores the exact frozen `START_HERE_WINDOWS.bat`, verifies the corrected identity, and invokes the existing RC3 release gate. The discovered original package is never modified.

PASS requires exact corrected frozen identity `33fffccf66ab66f4bf161af8f07797576a6379b7`, Windows Candidate PASS, all six required source/runtime/privacy gates, a valid final ZIP SHA256 and copied-artifact SHA verification.

No Factory v1 feed, HMAC, DPAPI, queue, scheduled task, watcher, retry state, GitHub Actions, PAT or OAuth is used by this reset lane.
