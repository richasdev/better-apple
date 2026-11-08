# BetterApple development rules

@/Users/uemuradev/.codex/RTK.md

Use `/opt/homebrew/bin/rtk` for shell commands, with `proxy` when needed. Keep the app native: Swift, SwiftUI, AppKit and public macOS 14+ APIs. Preserve existing layouts, notes and preferences.

## Judge every UI and motion change

The user explicitly requests critical evaluation while implementing and testing. For each change:

1. Identify the existing interaction problem and the purpose of the change.
2. Choose finite timing, easing, feedback and accessibility behavior deliberately. Use shared `WorkspaceMotion` values; respect personal animation preferences and system Reduce Motion/Transparency.
3. Test normal use, interruption/reversal, focus/keyboard, small sizes and relevant empty/error states. Use isolated preferences for runtime validation.
4. Review the result again, fix regressions, and record concrete evidence and remaining limitations in `UX_REVIEW.md` and validation reports.

Do not declare UI/UX perfect, 60 FPS achieved, or a flow visually verified from build success or state assertions. Distinguish actual native behavior checks, internal snapshots, profiling and external interaction. Do not add continuous decorative animations, global polling or permissions solely for visual QA.

## Integration and verification

- Keep file ownership explicit when splitting independent implementation/review across agents.
- Regenerate Xcode references with `python3 Scripts/generate_project.py` after adding/removing Swift files.
- Run Xcode builds sharing a derived-data directory sequentially; concurrent builds lock its database.
- Use `swift test`, `python3 Scripts/validate_native.py`, and the Debug app's `--validate` routine as appropriate. A failing runtime validation exits nonzero and writes its actual checks.
- Preserve native control semantics and input while animating. AppKit owns the geometry of explicit floating panels; hosting views must not impose contradictory minimum sizes.
- Keep raw Instruments traces and screenshots out of Git unless reviewed; traces can contain process environment data.
