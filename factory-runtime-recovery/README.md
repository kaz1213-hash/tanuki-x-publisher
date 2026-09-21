# Spectre self-qualification and guarded recovery

PR #2 stays draft/open. Distribution state is READY_FOR_GUARDED_SPECTRE_SELF_QUALIFICATION, following the Director's explicit authorization to use Spectre's isolated shadow environment before modifying Factory.

The single START_FACTORY_RECOVERY.cmd performs package verification → Windows PS5.1 shadow qualification → current machine diagnosis → eligible HMAC pre-spawn repair → one task restart → Clinic Cockpit canary → one privacy-safe result ZIP. Qualification failure stops before installed Factory mutation. No Python, GitHub download, Actions or token is needed for this recovery.

See SHADOW_QUALIFICATION_CONTRACT.md for the enforced boundaries, tests and remaining gates. Both controller and installer require a current PASS receipt tied to the same manifest SHA and run nonce. Real Factory private keys are never collected; only the normal repaired watcher uses its existing local DPAPI key during the actual canary.

The screen shows QUALIFYING, DIAGNOSING, REPAIRING, RESTARTING FACTORY, RUNNING COCKPIT and terminal state. The result is copied to Desktop/TanukiFactory_Result/RESULT.zip and selected automatically; a button also selects the actual available result. Archive failure retains JSON. Only FACTORY_RESULT.json is inside the ZIP. Local logs/paths/source/private keys/medical data are excluded.

This is permitted manual result return C, not automatic-return PASS. A subsequent natural logon resumes observation without reapplying the installer. Factory Completion, reboot regression, automatic return and queue progression remain incomplete; Comic/FX stay blocked.

Build with `python build_package.py --output-directory <output-directory>` on the AI side. Python is only a packaging tool, not a Spectre dependency. AI tests do not claim Windows PASS; the fresh Windows qualification occurs first inside the one-shot.
