# Spectre Factory — HOLD

Last machine evidence: 2026-09-21 12:29:37 JST real payload request. This is not a current heartbeat.

Runtime and local OUTBOX result: unobserved. Automatic result return: not connected. GitHub silence does not establish a Windows hang.

Source defect reproduced: HMACSHA256 construction expands a 32-byte array into 32 arguments. Repair and 24 synthetic PowerShell assertions are staged in [PR #2](https://github.com/kaz1213-hash/tanuki-x-publisher/pull/2). Not installed; Windows 5.1 and Spectre runtime not verified.

Queue: Cockpit HOLD -> Comic BLOCKED -> FX BLOCKED. Factory completion and USER_TESTABLE_ARTIFACT_READY remain false.

Director action: NONE. No repeat repair ZIP request. Remaining work: actual machine evidence/return channel, native Windows validation, Cockpit final artifact gate, visible liveness/notification, durable queue transport/progression, reboot regression.
