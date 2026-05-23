# Phase 01 — Resilient FramePrefetcher

**Parent:** [plan.md](plan.md)
**Date:** 2026-05-22
**Priority:** Cao
**Status:** Proposed

---

## Context

`FramePrefetcher` tại `backend/tools/video_io.py:25-30` là điểm đọc frame duy nhất trong toàn bộ pipeline. Hiện tại:

```python
def _read_loop(self):
    while not self._stopped:
        ret, frame = self.cap.read()
        self._buffer.put((ret, frame))
        if not ret:
            break  # Dừng hẳn tại frame lỗi đầu tiên
```

Khi OpenCV/FFmpeg gặp NAL unit lỗi → `cap.read()` trả về `(False, None)` → thread dừng → consumer nhận `False` → mọi processing loop `break`.

---

## Key Insights

- `cap.read()` = `cap.grab()` + `cap.retrieve()`. Khi frame bị corrupt, `grab()` vẫn có thể thành công (advance position) nhưng `retrieve()` fail.
- `cap.set(cv2.CAP_PROP_POS_FRAMES, next_pos)` có thể seek qua frame lỗi nhưng chậm và không đáng tin với mọi codec.
- Cách hiệu quả nhất: thử `grab()` nhiều lần để skip qua frame corrupt, dùng frame trước đó (ghost frame) để giữ sync.
- Cần track `failed_frames` để Phase 02 dùng cho warning.

---

## Architecture

### Thêm vào `FramePrefetcher.__init__`:
```python
self._failed_frames: list[int] = []   # list frame index bị lỗi
self._frame_index: int = 0            # đếm frame hiện tại
self._max_skip: int = max_skip        # số lần grab-skip tối đa (default 5)
```

### Logic mới trong `_read_loop`:
```python
def _read_loop(self):
    last_good_frame = None
    while not self._stopped:
        self._frame_index += 1
        ret, frame = self.cap.read()

        if ret:
            last_good_frame = frame
            self._buffer.put((True, frame))
        else:
            # Thử skip qua frame corrupt bằng grab()
            recovered = False
            for attempt in range(self._max_skip):
                if self.cap.grab():
                    ret2, frame2 = self.cap.retrieve()
                    if ret2 and frame2 is not None:
                        # Có frame hợp lệ sau skip
                        self._failed_frames.append(self._frame_index)
                        self._frame_index += attempt  # đã skip qua vài frame
                        last_good_frame = frame2
                        self._buffer.put((True, frame2))
                        recovered = True
                        break

            if not recovered:
                # Hết video thật sự hoặc corrupt nặng không recovery được
                # Kiểm tra còn frame không
                current_pos = int(self.cap.get(cv2.CAP_PROP_POS_FRAMES))
                total = int(self.cap.get(cv2.CAP_PROP_FRAME_COUNT))
                if current_pos < total - 1 and last_good_frame is not None:
                    # Còn frame nhưng corrupt — dùng ghost frame giữ sync
                    self._failed_frames.append(self._frame_index)
                    self._buffer.put((True, last_good_frame.copy()))
                else:
                    # Thật sự hết video
                    self._buffer.put((False, None))
                    break
```

### Thêm property:
```python
@property
def failed_frames(self) -> list[int]:
    return list(self._failed_frames)

@property
def has_errors(self) -> bool:
    return len(self._failed_frames) > 0
```

---

## Related Code Files

- `backend/tools/video_io.py` — file duy nhất cần sửa trong phase này

---

## Implementation Steps

1. Thêm param `max_skip: int = 5` vào `FramePrefetcher.__init__`
2. Thêm tracking fields: `_failed_frames`, `_frame_index`, `_max_skip`
3. Rewrite `_read_loop` với logic retry/ghost frame
4. Thêm properties `failed_frames`, `has_errors`
5. Không thay đổi interface `read()`, `stop()`, `release()` — backward compatible

---

## Todo

- [ ] Sửa `FramePrefetcher.__init__` thêm params + fields
- [ ] Rewrite `_read_loop` với retry + ghost frame logic
- [ ] Thêm properties `failed_frames`, `has_errors`
- [ ] Test với video bình thường (không regression)
- [ ] Test với video corrupt (validate retry hoạt động)

---

## Success Criteria

- Frame lỗi không làm dừng `_read_loop` khi còn frame hợp lệ phía sau
- `failed_frames` trả đúng list index frame bị lỗi
- Video bình thường không bị ảnh hưởng (zero overhead khi không lỗi)

---

## Risk Assessment

| Risk | Mức độ | Mitigation |
|---|---|---|
| Ghost frame làm output trông "đứng hình" | Thấp | Chỉ xảy ra tại frame corrupt — hành vi tốt hơn crash |
| `CAP_PROP_POS_FRAMES` không chính xác | Thấp | Chỉ dùng để check "còn frame không", không seek |
| Infinite loop nếu `total` sai | Thấp | `_max_skip` giới hạn số lần thử |

---

## Next Steps

Sau phase này → [Phase 02](phase-02-warning-system.md): dùng `prefetcher.failed_frames` để show warning GUI.
