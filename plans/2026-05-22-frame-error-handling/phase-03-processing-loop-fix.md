# Phase 03 — Fix Processing Loops

**Parent:** [plan.md](plan.md)
**Depends on:** [Phase 01](phase-01-resilient-frame-prefetcher.md), [Phase 02](phase-02-warning-system.md)
**Date:** 2026-05-22
**Priority:** Trung bình
**Status:** Proposed

---

## Context

Sau Phase 01, `FramePrefetcher` đã xử lý hầu hết lỗi bằng ghost frame — tức là các processing loop sẽ ít gặp `ret=False` hơn nhiều. Tuy nhiên, vẫn có trường hợp prefetcher trả `(False, None)` (khi thật sự hết video hoặc corrupt hoàn toàn không recover được). Phase này đảm bảo các loop xử lý đúng cả hai tình huống.

**Vấn đề hiện tại trong từng mode:**

| Mode | File | Vấn đề |
|---|---|---|
| `propainter_mode` | `main.py:185-219` | `break` ngay cả khi đang giữa batch — frame đã read vào batch bị xử lý thiếu nhưng không track số frame thực tế |
| `video_inpaint` | `main.py:290-342` | `break` ngay cả giữa segment — nhưng `frames_need_inpaint` vẫn được xử lý với số frame thực có → ổn hơn |
| `sttn_auto_inpaint` | `sttn_auto_inpaint.py:257-276` | Đã có `continue` cho segment rỗng — OK, chỉ cần expose failed_frames |

---

## Key Insights

- Sau Phase 01, `(False, None)` chỉ xảy ra khi **thật sự hết video** hoặc **toàn bộ phần cuối bị corrupt không recovery được**. `break` vẫn là hành vi đúng trong trường hợp này.
- Vấn đề thực sự: khi frame cuối của một batch lỗi, batch bị thiếu frame → `propainter_inpaint` nhận ít frame hơn expected → có thể gây lỗi model hoặc output lệch sync.
- Fix đơn giản nhất cho `propainter_mode`: track `actual_count` trong batch và only write `actual_count` frames.

---

## Architecture

### `propainter_mode` — inner batch read loop

**Hiện tại (main.py:216-221):**
```python
while index < end_frame_no:
    ret, frame = reader.read()
    if not ret:
        break
    index += 1
    temp_frames.append(frame)
```

**Sau sửa:**
```python
while index < end_frame_no:
    ret, frame = reader.read()
    if not ret:
        # Phase 01 đã xử lý ghost frame; nếu vẫn False = hết video thật
        break
    index += 1
    temp_frames.append(frame)
# Không thay đổi logic — Phase 01 handle upstream
# Chỉ cần đảm bảo batch_generator và propainter nhận đúng số frame thực
```

> **Kết luận:** Sau Phase 01, loop này về cơ bản không cần sửa nhiều vì ghost frame đã giữ `ret=True`. Chỉ cần đảm bảo Phase 01 chạy đúng.

---

### `video_inpaint` — outer loop

**Hiện tại (main.py:290-294):**
```python
while True:
    ret, frame = reader.read()
    if not ret:
        break
    current_frame_index += 1
```

**Sau sửa — không break ngay, track rõ hơn:**
```python
while True:
    ret, frame = reader.read()
    if not ret:
        break  # Giữ nguyên — Phase 01 đảm bảo đây là EOF thật
    current_frame_index += 1
```

> **Kết luận:** Không cần sửa logic, Phase 01 handle upstream.

---

### `STTNAutoInpaint` — expose failed_frames

**File:** `backend/inpaint/sttn_auto_inpaint.py`

Hiện tại `__call__` không trả gì (`None`). Sửa để trả `list[int]`:

```python
def __call__(self, ...) -> list[int]:
    failed = []
    ...
    reader = FramePrefetcher(video_cap)
    ...
    # Sau khi xong:
    failed.extend(reader.failed_frames)
    reader.release()
    return failed
```

Trong `sttn_auto_mode` (`main.py:267`):
```python
# Trước:
sttn_video_inpaint(input_mask=mask, input_sub_remover=self, tbar=tbar)

# Sau:
failed = sttn_video_inpaint(input_mask=mask, input_sub_remover=self, tbar=tbar)
if failed:
    self._failed_frame_indices.extend(failed)
```

---

## Related Code Files

- `backend/main.py` — `propainter_mode()`, `video_inpaint()`, `sttn_auto_mode()`
- `backend/inpaint/sttn_auto_inpaint.py` — `STTNAutoInpaint.__call__()`

---

## Implementation Steps

1. Sửa `STTNAutoInpaint.__call__()` để trả `list[int]` failed frames
2. Sửa `sttn_auto_mode()` nhận return value và extend `_failed_frame_indices`
3. Trong `propainter_mode` và `video_inpaint`: sau `reader.stop()`, gọi `_collect_frame_errors(reader)` (từ Phase 02)
4. Verify: với video corrupt mid-file, output vẫn được tạo ra

---

## Todo

- [ ] Sửa `STTNAutoInpaint.__call__` return type → `list[int]`
- [ ] Sửa `sttn_auto_mode` nhận + propagate failed frames
- [ ] Verify `propainter_mode` hoạt động đúng sau Phase 01 (smoke test)
- [ ] Verify `video_inpaint` hoạt động đúng sau Phase 01 (smoke test)

---

## Success Criteria

- Với video có frame lỗi giữa file: processing tiếp tục, output được tạo
- `_failed_frame_indices` chứa đúng frame lỗi từ tất cả modes
- Không regression với video bình thường

---

## Risk Assessment

| Risk | Mức độ | Mitigation |
|---|---|---|
| `STTNAutoInpaint` có nhiều exit path (exception) | Trung bình | Dùng try/finally để đảm bảo return failed frames |
| Propainter batch size không match với frame count | Thấp | Ghost frame từ Phase 01 giữ count đúng |

---

## Unresolved Questions

- `STTNAutoInpaint` hiện wrap toàn bộ trong try/except — nếu exception xảy ra trước khi reader được tạo, `failed` sẽ rỗng. Có cần phân biệt "exception" vs "frame error" không?
