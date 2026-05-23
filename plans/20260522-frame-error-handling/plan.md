# Video Frame Read Error Handling — Implementation Plan

**Date:** 2026-05-22
**Status:** completed
**Owner:** backend
**Scope:** `backend/tools/video_io.py`, `backend/main.py`, `backend/inpaint/sttn_auto_inpaint.py`

## Problem Statement

Corrupt video frames (e.g. broken NAL units in H.264 streams) cause entire processing pipeline to abort early. `FramePrefetcher._read_loop` breaks on first `ret=False`, `propainter_mode` outer/inner loops `break` on read failure, and `sttn_auto_inpaint` only prints warning to console. User has no GUI feedback when frames are silently dropped.

## Goals

- Retry transient read failures, skip persistent corrupt frames, continue processing.
- Distinguish EOF vs corruption via position check.
- Surface skipped-frame counts/indices to GUI through existing `append_output()`.
- No new infrastructure; reuse existing patterns.

## Phases

| # | Phase | Status | Priority | Effort | File |
|---|-------|--------|----------|--------|------|
| 01 | FramePrefetcher Resilience | completed | High | M | [phase-01-frame-prefetcher-resilience.md](./phase-01-frame-prefetcher-resilience.md) |
| 02 | Propainter Skip Logic | completed | High | S | [phase-02-propainter-skip-logic.md](./phase-02-propainter-skip-logic.md) |
| 03 | GUI Warning System | completed | Med | S | [phase-03-gui-warning-system.md](./phase-03-gui-warning-system.md) |

## Dependencies

- Phase 02 depends on Phase 01 (`failed_frames` / `failed_count` properties).
- Phase 03 depends on Phase 01 (same properties) and consumes from Phase 02.

## Success Criteria

- Video with corrupt frames processes to completion (no early abort).
- GUI displays warning summary listing skipped frame indices.
- Existing call sites of `FramePrefetcher.read()` still work unchanged.
- No regressions on clean videos.

## Out of Scope

- FFmpeg stderr NAL unit log suppression (documented only).
- Reconstructing corrupt frames via interpolation.
- i18n keys (add only if `tr` dict structure supports easily).

## Unresolved Questions

- Does `cv2.VideoCapture.set(POS_FRAMES, ...)` reliably advance past corrupt frames in all backends (FFmpeg, MSMF, GStreamer)? Needs testing.
- Should `max_retries` be exposed via `config` module or kept as constructor arg?
