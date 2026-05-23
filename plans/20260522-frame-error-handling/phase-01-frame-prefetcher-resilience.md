# Phase 01 — FramePrefetcher Resilience

## Context Links

- Parent plan: [plan.md](./plan.md)
- Target file: `backend/tools/video_io.py`
- Consumers: `backend/main.py` (propainter_mode), `backend/inpaint/sttn_auto_inpaint.py`

## Overview

- **Date:** 2026-05-22
- **Description:** Add retry + error-tracking to `FramePrefetcher` so corrupt frames don't terminate the read loop. Expose `failed_frames` / `failed_count` for callers.
- **Priority:** High
- **Implementation status:** completed
- **Review status:** approved
- **Completion timestamp:** 2026-05-22

## Key Insights

- Current `_read_loop` `break`s on first `ret=False` — treats every failure as EOF.
- `cv2.VideoCapture` exposes `CAP_PROP_POS_FRAMES` and `CAP_PROP_FRAME_COUNT`; comparing them distinguishes EOF vs mid-stream failure.
- Public API stays the same (`read()` returns `(ret, frame)` tuple); callers opt into new properties.
- Sentinel `(False, None)` pushed for skipped frames so caller knows to advance and continue.

## Requirements

- Retry transient failure up to `max_retries` (default 3).
- Track failed frame indices in `_failed_frames` list.
- Distinguish EOF (true end) vs corruption (mid-stream).
- Seek past bad frame via `CAP_PROP_POS_FRAMES` then continue.
- Keep `read()` signature unchanged — backward compatible.
- Expose `failed_frames` (list[int]) and `failed_count` (int) read-only properties.

## Architecture / Proposed Changes

Modify `FramePrefetcher.__init__` and `_read_loop` in `backend/tools/video_io.py`:

```python
class FramePrefetcher:
    def __init__(self, video_cap, buffer_size=10, max_retries=3):
        self.cap = video_cap
        self._buffer = queue.Queue(maxsize=buffer_size)
        self._stopped = False
        self._max_retries = max_retries
        self._failed_frames = []       # frame indices that failed
        self._frame_index = 0          # 0-based index of next frame
        self._thread = threading.Thread(target=self._read_loop, daemon=True)
        self._thread.start()

    def _read_loop(self):
        while not self._stopped:
            ret, frame = False, None
            for _ in range(self._max_retries):
                ret, frame = self.cap.read()
                if ret:
                    break
            if ret:
                self._buffer.put((True, frame))
                self._frame_index += 1
                continue

            # Distinguish EOF vs corruption
            total = self.cap.get(cv2.CAP_PROP_FRAME_COUNT)
            current = self.cap.get(cv2.CAP_PROP_POS_FRAMES)
            if total > 0 and current < total - 1:
                # Corrupt frame mid-stream — record, push sentinel, advance
                self._failed_frames.append(self._frame_index)
                self._buffer.put((False, None))
                self._frame_index += 1
                try:
                    self.cap.set(cv2.CAP_PROP_POS_FRAMES, current + 1)
                except Exception:
                    pass
                continue
            # True EOF
            self._buffer.put((False, None))
            break

    @property
    def failed_frames(self):
        return list(self._failed_frames)

    @property
    def failed_count(self):
        return len(self._failed_frames)
```

## Related Code Files

- `backend/tools/video_io.py` lines 12–51 — `FramePrefetcher` class
- `backend/main.py` line 184 — first consumer (`reader = FramePrefetcher(self.video_cap)`)
- `backend/inpaint/sttn_auto_inpaint.py` line 206 — second consumer (`prefetcher = FramePrefetcher(reader)`)

## Implementation Steps

1. Open `backend/tools/video_io.py`.
2. Add `max_retries=3` param to `FramePrefetcher.__init__`; init `_max_retries`, `_failed_frames=[]`, `_frame_index=0`.
3. Rewrite `_read_loop` per architecture block above.
4. Add `failed_frames` and `failed_count` properties.
5. Verify `read()`, `get()`, `stop()`, `release()` untouched.
6. Manual smoke test: run on a clean video — no behavior change expected.
7. Manual test with intentionally corrupted MP4 (e.g. truncated file) — confirm processing continues past corruption.

## Todo List

- [ ] Add `max_retries` param + state fields to `__init__`
- [ ] Rewrite `_read_loop` with retry + EOF/corruption discrimination
- [ ] Add `failed_frames` property
- [ ] Add `failed_count` property
- [ ] Smoke test on clean video
- [ ] Test on corrupt video sample (truncated / NAL-broken)
- [ ] Document caveat: `set(POS_FRAMES, ...)` may not work for all codecs

## Success Criteria

- Clean videos process identically to before (no regression).
- Corrupt video continues past bad frames, total frames written ≈ total - failed_count.
- `failed_frames` returns list of 0-based indices that were skipped.
- Thread terminates cleanly at EOF.

## Risk Assessment

- **Risk:** `cv2.VideoCapture.set(POS_FRAMES, ...)` is unreliable on some codecs/backends — may re-fail or jump to wrong frame.
  - Mitigation: wrap in try/except, fall through to next iteration; loop bounded by total frame count.
- **Risk:** Retrying transient failure on truly broken stream wastes CPU.
  - Mitigation: `max_retries=3` keeps overhead minimal; per-frame retry budget.
- **Risk:** Sentinel `(False, None)` may be misinterpreted by callers as EOF.
  - Mitigation: documented in Phase 02 — callers must check `failed_count` before assuming EOF.

## Security Considerations

- No new I/O surface; no user input parsed. Reads existing video file.
- No memory unbounded growth: `_failed_frames` bounded by total frame count.

## Next Steps

- Proceed to [Phase 02](./phase-02-propainter-skip-logic.md) once `failed_frames` property landed.

## Unresolved Questions

- Should `max_retries` come from `backend/config.py` for tunability? Default 3 likely fine.
- For very-short videos where `CAP_PROP_FRAME_COUNT == 0` (live streams), corruption-vs-EOF check falls back to EOF. Acceptable?
