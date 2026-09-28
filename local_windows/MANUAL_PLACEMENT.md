# Manual Placement Console

Interim manual workflow while third-party auto-reply policy clarification is pending.

## What one launch does

1. Pulls the latest public publisher code.
2. Decrypts the already-stored X API key/secret with Windows DPAPI.
3. Runs one bounded Tanuki Scout scan.
4. Opens a Windows console showing the most active explicit self-promotion invitation threads first.
5. `Xで返信を開く` launches the official X Web Intent reply composer with:
   - the target post as `in_reply_to`;
   - the Tanuki draft already filled in.
6. The Director makes the final decision and presses X's **Post** button.

No browser scripting, automatic likes/follows/DMs, or automatic third-party reply submission is used.

Handled/skipped candidate IDs are stored only under:
`%LOCALAPPDATA%\TanukiXPublisher\placement-state\manual_placements.jsonl`

Canonical issue: #12.
