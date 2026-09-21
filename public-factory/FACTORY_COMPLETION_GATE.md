# Tanuki Windows Factory — Completion Gate

Status: **P0 / PROJECT-WIDE WINDOWS BLOCKER**

The Factory is not complete merely because a watcher process exists or a job can be dispatched.
It is complete only when the following end-to-end run environment is proven on Spectre without using the Director as a build/debug/runtime operator.

## Required PASS gates

1. **Boot / persistence**
   - Factory starts automatically after Windows restart/logon.
   - No manual PowerShell / CMD / Task Scheduler operation.

2. **Visible liveness**
   - Human-visible status shows watcher alive, last poll, active job/phase, last result, and next queued job.
   - No log inspection required.

3. **Queue pickup**
   - The active encrypted Factory job is acquired automatically.
   - target_factory_id, SHA, HMAC and payload identity remain fail-closed.

4. **Windows execution**
   - Factory creates isolated WORK.
   - Entrypoint runs automatically.
   - Product build/runtime gate executes on Windows.

5. **Result generation**
   - PASS/FAIL/HOLD always produces a privacy-safe result bundle in OUTBOX.
   - No silent exit path.

6. **Notification**
   - Job started and terminal PASS/FAIL/HOLD state are visible to the Director.
   - Notification occurs on state transition only.

7. **Result return**
   - AI can receive/inspect the privacy-safe result without requiring repeated Director polling/debugging.
   - Until authenticated outbound return exists, a single bounded upload may be used only as the final physical bridge.

8. **Queue advancement**
   - ONE_AT_A_TIME ordering is preserved.
   - Cockpit -> Comic -> FX.
   - Next job is not started before active job reaches a terminal state.

9. **Reboot regression**
   - After one Windows restart, Factory resumes autonomously and preserves queue/runtime behavior.

10. **Director burden**
   - Director is not asked to type PowerShell, edit files, run Git, interpret logs, repeatedly rerun packages, or act as runtime verifier.

## Current acceptance canary

Clinic Cockpit RC3 job:
`clinic-cockpit-rc3-r2-20260921-001`

Factory completion is earned only after this canary proves the infrastructure gates above. Product Release PASS is a separate downstream gate.

## Project rule

Until this Factory Completion Gate passes:
- do not start additional Director-facing Windows qualification for Comic / FX / Contact / Expense / Reply / Staff Documents / Security / Butler Windows;
- do not bypass Factory by returning to GitHub Actions/PAT/OAuth or Director-as-runner;
- AI-side source work may continue only when it does not require a Windows physical gate.
