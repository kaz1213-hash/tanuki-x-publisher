# Clinic Cockpit minimal Windows job

Runs the already-transferred exact RC3 R2 package on Spectre.

The job scans only common user locations plus C:\\TanukiFactory for an exact package whose
tools/V080_RC3_READY.json identifies:
- candidate: v0.8.0 RC3
- frozen_product_commit: 70ec03be3de89548bf61ceea2661bffb03dab18a
- ready_branch: release-ready/v0.8.0-rc3-no-github-r2

Then it invokes the existing release_v080_rc3_bootstrap.ps1 directly and accepts PASS only when
BUILD_RESULT.json reports Windows Candidate PASS, all six required runtime/privacy gates pass,
the final ZIP exists, and its SHA256 matches BUILD_RESULT when supplied.

No Factory v1, feed, HMAC, DPAPI, queue, scheduled task or retry state is used.
