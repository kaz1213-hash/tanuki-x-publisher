# RC3 direct-run follow-up

Canonical lane re-read: PR #3 at c76c573db7673d6b10e93ad092f7833e949ca2ad; PR #2 is closed, unmerged and superseded. Do not resume old encrypted-feed recovery.
Cockpit release-ready current ref is still 203a2a3775dc06671de4733ec01cb9d4f503ce87, frozen product 70ec03be3de89548bf61ceea2661bffb03dab18a.

The latest tracker evidence reports a real minimal-runner attempt reaching the builder and failing on the stale START_HERE_WINDOWS.bat. Its existing staging repair was executed in the AI-side test and generated the exact pinned Git blob 5be7c5c73d20122bdd3226d2f65d2275c066a1bd.

Corrections in this follow-up:
- Mandatory final SHA, exact candidate/schema/frozen identity, strictly boolean Windows PASS, exactly one PASS for each required gate, declared safe filename and copied-artifact SHA check.
- Separate product artifacts from returned diagnostic ZIP. Raw BUILD_RESULT details are replaced with fixed-field gate summary; source, medical data and raw logs are not added to return output.
- Retain process handles and reject missing exit codes. Builder stdout/stderr use separate local files, avoiding native stderr interruption before reading BUILD_RESULT under PS5.1 ErrorActionPreference=Stop.
- UTF8 BOM/CRLF package PowerShell source.

Validation: Acceptance.Smoke.ps1 11 assertions PASS on Microsoft PowerShell 7.4.19 Linux: exact frozen launcher bytes, complete synthetic acceptance, missing/wrong SHA, string false, wrong candidate/schema, traversal, duplicate/missing gate and raw-detail exclusion. Parser and PS5.1 syntax/command profile PASS. These are not Windows runtime qualification.

No connected callable Windows executor or Spectre remote execution tool is exposed in this Work. Therefore no current final candidate EXE/ZIP runtime PASS, USER_TESTABLE_ARTIFACT_READY or Factory Completion is declared. No new diagnostic trial is requested from Director. Product source/UI was not changed, old Factory PR #2 was not reopened, and Comic/FX were not started.
