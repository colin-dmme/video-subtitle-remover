# Phase 03 — GUI Warning System

## Context Links

- Parent plan: [plan.md](./plan.md)
- Depends on: [Phase 01](./phase-01-frame-prefetcher-resilience.md), [Phase 02](./phase-02-propainter-skip-logic.md)
- Target files: `backend/main.py`, `backend/inpaint/sttn_auto_inpaint.py`

## Overview

- **Date:** 2026-05-22
- **Description:** Route frame-skip warnings to GUI via existing `append_output()` instead of console-only `print()`. Cover both propainter and sttn-auto paths.
- **Priority:** Medium
- **Implementation status:** completed
- **Review status:** approved
- **Completion date:** 2026-05-22

## Key Insights

- `append_output()` (main.py:125) already routes messages to GUI listeners — no new plumbing needed.
- `sttn_auto_inpaint.__call__` receives `input_sub_remover` — has access to `append_output` when present.
- Existing `print(f"Warning: Failed to read frame {j}.")` (sttn_auto_inpaint.py:260) is the only console-only warning.
- FFmpeg/OpenCV NAL-unit stderr is emitted by C-level libs — Python redirection limited; document only.

## Requirements

- Replace `print` warning in `sttn_auto_inpaint` with `append_output` when caller passes `input_sub_remover`.
- Emit summary message at end of `propainter_mode` (covered partially in Phase 02).
- Emit summary at end of sttn-auto loop too.
- Use Vietnamese for user-facing messages (per project i18n convention).
- Gracefully fall back to `print` when no `input_sub_remover` (CLI mode).

## Architecture / Proposed Changes

### Change 1: `backend/inpaint/sttn_auto_inpaint.py` line 260

Replace:
```python
print(f"Warning: Failed to read frame {j}.")
break
```

With:
```python
warn_msg = f"⚠ Khung hình {j} bị bỏ qua (lỗi đọc)"
if input_sub_remover is not None:
    input_sub_remover.append_output(warn_msg)
else:
    print(warn_msg)
# Do NOT break — let prefetcher's skip propagate; track count via prefetcher.failed_count
continue
```

Note: `break` removed so subsequent valid frames in `start_f..end_f` range can still load. Use `prefetcher.failed_count` snapshot to detect new failures.

### Change 2: End-of-method summary in sttn_auto_inpaint

After main `for i in range(rec_time)` loop exits, before `finally`:

```python
if prefetcher.failed_count > 0:
    preview = prefetcher.failed_frames[:10]
    suffix = ' ...' if prefetcher.failed_count > 10 else ''
    msg = (f"⚠ Tổng cộng {prefetcher.failed_count} khung hình lỗi đã bị bỏ qua. "
           f"Đầu ra có thể bị thiếu tại khung: {preview}{suffix}")
    if input_sub_remover is not None:
        input_sub_remover.append_output(msg)
    else:
        print(msg)
```

### Change 3: i18n keys (optional)

Check `backend/translations.py` (or wherever `tr` dict lives) for structure. If straightforward, add:
- `tr['Main']['FrameSkippedWarning']`
- `tr['Main']['FrameSkippedSummary']`

Otherwise inline literals are acceptable.

### Change 4: FFmpeg stderr (document only)

NAL-unit errors emitted by libav are below Python's reach without subprocess wrapping. Document caveat in code comment near `FramePrefetcher`:

```python
# Note: FFmpeg/libav decoder errors (e.g. "Invalid NAL unit") print directly
# to stderr at C level and cannot be captured here. Python-level frame failures
# are tracked via failed_frames.
```

## Related Code Files

- `backend/main.py` line 125 — `append_output` method
- `backend/main.py` end of `propainter_mode` (~line 254) — add summary
- `backend/inpaint/sttn_auto_inpaint.py` line 199 — `__call__` signature has `input_sub_remover`
- `backend/inpaint/sttn_auto_inpaint.py` line 260 — print warning to replace
- `backend/inpaint/sttn_auto_inpaint.py` end of `for i in range(rec_time)` loop — add summary

## Implementation Steps

1. Open `backend/inpaint/sttn_auto_inpaint.py`.
2. Replace `print` warning at line 260 with `append_output` routing (Change 1).
3. Remove the unconditional `break` — convert to skip-and-continue using `prefetcher.failed_count` delta tracking.
4. After main rec_time loop, add summary block (Change 2).
5. Open `backend/main.py`, end of `propainter_mode`, add summary block (covered in Phase 02 but verify).
6. Check `tr` dict — if simple, add i18n keys; else inline Vietnamese strings.
7. Add documentation comment near `FramePrefetcher` re: FFmpeg stderr (Change 4).
8. Manual test: corrupt video via GUI — confirm warning appears in output panel.
9. Manual test: corrupt video via CLI — confirm warning prints to console.

## Todo List

- [x] Replace `print` warning in `sttn_auto_inpaint.py:260` with `append_output`
- [x] Remove unconditional `break` in inner read loop; use skip-and-continue
- [x] Add end-of-loop summary in `sttn_auto_inpaint`
- [x] Verify propainter end-of-mode summary present (from Phase 02)
- [x] Add i18n keys if `tr` dict structure permits (else inline)
- [x] Add code comment re: FFmpeg stderr unrecoverability
- [x] Test GUI warning visibility
- [x] Test CLI fallback print

## Success Criteria

- GUI output panel displays warning when frames are skipped.
- CLI mode prints same warning to stdout.
- No `print` warnings remain in inpaint pipeline that don't also reach GUI.
- Summary message at end of processing lists skipped count + preview indices.
- FFmpeg stderr behavior documented but not changed.

## Risk Assessment

- **Risk:** `append_output` might be called from non-GUI thread → race condition with Qt/Tk listeners.
  - Mitigation: `notify_progress_listeners` already iterates listeners with try/except (line 152); `append_output` likely follows same pattern. Verify before merge.
- **Risk:** Vietnamese strings hard-coded may not be translated for other locales.
  - Mitigation: prefer `tr` dict if available; inline acceptable as fallback per scope.
- **Risk:** Removing `break` in sttn loop changes count semantics (`valid_frames_count` may not match `end_f - start_f`).
  - Mitigation: keep `valid_frames_count` incrementing only on success; downstream batch logic already tolerates short batches.

## Security Considerations

- Frame indices in warnings are integers from internal counter — no injection risk.
- No file paths or PII leaked into warnings.

## Next Steps

- After all three phases land: end-to-end QA pass with intentionally corrupted MP4.
- Consider adding test fixture: small truncated MP4 in `test/` for regression.

## Unresolved Questions

- Does `tr` dict already have a generic "Warning" key we should reuse for prefix? Need to grep `translations`.
- Should we expose `failed_frames` on the parent `SubtitleRemover` (e.g. `self.last_run_failed_frames`) for programmatic access by CLI callers / batch scripts?
- Acceptable to ship Vietnamese-only strings, or must we add English + Chinese variants now?
