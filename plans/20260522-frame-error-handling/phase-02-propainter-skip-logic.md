# Phase 02 — Propainter Skip Logic

## Context Links

- Parent plan: [plan.md](./plan.md)
- Depends on: [Phase 01](./phase-01-frame-prefetcher-resilience.md) (`failed_count` / `failed_frames`)
- Target file: `backend/main.py` (`propainter_mode`)

## Overview

- **Date:** 2026-05-22
- **Completion date:** 2026-05-22
- **Description:** Change `propainter_mode` outer + inner loops from "break on read failure" to "skip-and-continue", using `FramePrefetcher.failed_count` to distinguish EOF vs corruption.
- **Priority:** High
- **Implementation status:** completed
- **Review status:** approved

## Key Insights

- Two `break` sites cause early termination: outer loop (line ~187) terminates whole video; inner batch loop (line ~218) silently drops remaining batch frames.
- After Phase 01, `(False, None)` from prefetcher means either skipped corrupt frame OR true EOF — discriminate via `reader.failed_count` growth.
- Inner-batch skip must increment `index` to stay in sync with `sub_list` keys.
- `temp_frames` may be shorter than batch length after skips — existing handlers (`len==1`, `len>1`) already cope.

## Requirements

- Outer loop must not abort on single corrupt frame; only on true EOF.
- Inner batch loop must skip corrupt frames within range and continue to `end_frame_no`.
- Maintain `index` increment parity with read attempts (frame number tracking).
- Surface final skipped count to GUI at end of mode (handled jointly with Phase 03).

## Architecture / Proposed Changes

Track previous failed count locally to detect new failures vs EOF:

```python
def propainter_mode(self, tbar):
    ...
    reader = FramePrefetcher(self.video_cap)
    last_failed = 0
    while True:
        ret, frame = reader.read()
        if not ret:
            if reader.failed_count > last_failed:
                # Corrupt frame — skip and continue
                last_failed = reader.failed_count
                index += 1
                self.update_progress(tbar, increment=1)
                continue
            break  # True EOF
        index += 1
        # ... existing per-frame logic ...

        # Inner batch loop:
        while index < end_frame_no:
            ret, frame = reader.read()
            if not ret:
                if reader.failed_count > last_failed:
                    last_failed = reader.failed_count
                    index += 1
                    continue  # skip corrupt frame in batch
                break  # EOF inside batch
            index += 1
            temp_frames.append(frame)
```

After loop completes, emit summary (Phase 03):

```python
if reader.failed_count > 0:
    preview = reader.failed_frames[:10]
    suffix = ' ...' if reader.failed_count > 10 else ''
    self.append_output(
        f"⚠ Cảnh báo: {reader.failed_count} khung hình không đọc được đã bị bỏ qua. "
        f"Đầu ra có thể bị thiếu tại khung: {preview}{suffix}"
    )
```

## Related Code Files

- `backend/main.py` line 168 — `propainter_mode` start
- `backend/main.py` line 184 — `reader = FramePrefetcher(self.video_cap)`
- `backend/main.py` lines 185–188 — outer loop `break`
- `backend/main.py` lines 216–221 — inner batch loop `break`
- `backend/main.py` line 125 — `append_output` definition

## Implementation Steps

1. Open `backend/main.py`, locate `propainter_mode` (line 168).
2. Add `last_failed = 0` after `reader = FramePrefetcher(...)`.
3. Replace outer `if not ret: break` with corruption-vs-EOF discrimination block.
4. Replace inner batch `if not ret: break` with same pattern.
5. Ensure `index` increments correctly on skip paths.
6. Add tbar progress increment on outer skip so progress bar stays accurate.
7. At end of method (after main loop completes), append warning if `reader.failed_count > 0`.
8. Test with clean video — no behavioral change.
9. Test with corrupt video — confirm all clean frames written, skipped frames logged.

## Todo List

- [x] Add `last_failed = 0` tracker
- [x] Replace outer-loop break with skip logic
- [x] Replace inner-batch break with skip logic
- [x] Ensure progress bar accounts for skipped frames
- [x] Append warning summary at end of `propainter_mode`
- [x] Smoke test on clean video
- [x] Test on corrupt video sample
- [x] Verify `index` stays in sync with `sub_list` keys

## Success Criteria

- Outer loop only terminates on true EOF (`reader.failed_count` not advancing).
- Inner batch loop skips corrupt frames, continues to `end_frame_no`.
- Output video frame count = total_frames - failed_count.
- GUI shows warning summary on completion if any frames skipped.
- Clean videos: zero behavioral change.

## Risk Assessment

- **Risk:** `index` drift if skip path doesn't increment consistently.
  - Mitigation: explicit `index += 1` on every skip; unit-test by counting writes.
- **Risk:** Skipped frame falls inside a sub_list range — batch becomes non-contiguous.
  - Mitigation: existing `temp_frames` handling tolerates length variance; propainter batch processes whatever frames are present.
- **Risk:** Progress bar de-syncs from actual frame count.
  - Mitigation: increment tbar on skip path too.

## Security Considerations

- No new attack surface. Skipped-frame indices are integers, safe to display in GUI.

## Next Steps

- Proceed to [Phase 03](./phase-03-gui-warning-system.md) for sttn warning routing and final polish.

## Unresolved Questions

- If corrupt frame is the start frame of a sub_list range, downstream `find_frame_no_end` / mask lookup may behave oddly. Should we drop entire range or attempt anyway? Default: attempt; risk is artifacts on that range only.
- Should `update_preview_with_comp` be called on skip path with placeholder, or remain silent?
