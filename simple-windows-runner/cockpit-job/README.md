# Clinic Cockpit minimal Windows job

Canonical runnable files now live directly under `../JOB/` so the `simple-windows-runner`
directory is a complete one-click package without an assembly/copy step.

The job scans common user locations plus `C:\TanukiFactory` for the already-transferred exact
RC3 R2 package identified by:
- candidate: `v0.8.0 RC3`
- frozen product commit: `70ec03be3de89548bf61ceea2661bffb03dab18a`
- ready branch: `release-ready/v0.8.0-rc3-no-github-r2`

It copies that package into an isolated TEMP staging directory, verifies its release-tool identity,
restores only the known stale `START_HERE_WINDOWS.bat` in the staging copy to the exact frozen Git
blob, then invokes the existing `release_v080_rc3_bootstrap.ps1`.

PASS requires the existing `BUILD_RESULT.json` to report Windows Candidate PASS, all six required
source/runtime/privacy gates to pass, exactly one final ZIP to exist, and the final ZIP SHA256 to
match the builder receipt when supplied. The discovered original package is not modified.

No Factory v1 feed, HMAC, DPAPI, queue, scheduled task, watcher, retry state, GitHub Actions,
PAT or OAuth is used by this reset lane.
