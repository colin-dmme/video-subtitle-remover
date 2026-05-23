# Phase 02 — Warning System lên GUI

**Parent:** [plan.md](plan.md)
**Depends on:** [Phase 01](phase-01-resilient-frame-prefetcher.md)
**Date:** 2026-05-22
**Priority:** Cao
**Status:** Proposed

---

## Context

`SubtitleRemover.append_output()` tại `backend/main.py:125-130` chỉ làm `print(*args)`. Subclass GUI override method này để hiển thị lên UI.

Hiện tại không có warning nào được gửi lên GUI khi frame lỗi. Cần:
1. Nơi tích lũy warnings trong suốt quá trình xử lý
2. Hiển thị summary sau khi xử lý xong (hoặc ngay lập tức khi phát hiện)

---

## Key Insights

- `append_output()` là kênh output duy nhất đến GUI — chỉ cần gọi nó với message warning là đủ, không cần thêm listener mới.
- Nên show warning **sau khi processing xong** (trong `run()`) thay vì mid-processing để không spam GUI.
- Warning message cần đủ thông tin: số frame lỗi + danh sách frame index (tối đa 10 frame đầu, còn lại ghi "...").
- Không raise exception — chỉ warn, processing vẫn hoàn thành.

---

## Architecture

### Thêm field vào `SubtitleRemover.__init__`:
```python
self._failed_frame_indices: list[int] = []
```

### Thêm method `_collect_frame_errors`:
```python
def _collect_frame_errors(self, prefetcher: FramePrefetcher):
    """Thu thập failed frames từ prefetcher sau khi processing xong."""
    if prefetcher.has_errors:
        self._failed_frame_indices.extend(prefetcher.failed_frames)
```

### Thêm method `_warn_frame_errors`:
```python
def _warn_frame_errors(self):
    """Gửi warning lên GUI nếu có frame lỗi."""
    if not self._failed_frame_indices:
        return
    count = len(self._failed_frame_indices)
    preview = self._failed_frame_indices[:10]
    preview_str = ", ".join(str(f) for f in preview)
    if count > 10:
        preview_str += f", ... ({count - 10} more)"
    self.append_output(
        tr['Main'].get('FrameReadWarning',
            f"Warning: {count} frame(s) could not be read and were skipped: [{preview_str}]. "
            f"Output may have brief frozen/repeated frames at those positions."
        )
    )
```

### Sửa `run()` để gọi warning sau processing:
```python
def run(self):
    ...
    # Sau khi processing xong, trước khi merge audio:
    self._warn_frame_errors()
    self.video_cap.release()
    ...
```

### Sửa các processing loops để collect errors:
Trong `propainter_mode`, `video_inpaint`, `sttn_auto_mode`:
```python
reader = FramePrefetcher(self.video_cap)
# ... processing loop ...
reader.stop()
self._collect_frame_errors(reader)  # Thu thập errors sau khi stop
```

---

## Translation Key

Thêm vào i18n (nếu có translation system):
```
'FrameReadWarning': 'Warning: {count} frame(s) skipped due to read errors: [{frames}]. Output may have brief frozen frames.'
```

Nếu không có i18n, dùng hardcoded English message là ổn.

---

## Related Code Files

- `backend/main.py` — `SubtitleRemover.__init__`, `run()`, `propainter_mode()`, `video_inpaint()`, `sttn_auto_mode()`

---

## Implementation Steps

1. Thêm `_failed_frame_indices: list[int] = []` vào `__init__`
2. Thêm methods `_collect_frame_errors()` và `_warn_frame_errors()`
3. Sau `reader.stop()` trong mỗi mode, gọi `_collect_frame_errors(reader)`
4. Trong `run()`, gọi `_warn_frame_errors()` trước `self.video_cap.release()`
5. Thêm translation key `FrameReadWarning` nếu project có i18n

---

## Todo

- [ ] Thêm `_failed_frame_indices` field
- [ ] Implement `_collect_frame_errors()`
- [ ] Implement `_warn_frame_errors()`
- [ ] Hook vào `propainter_mode` sau `reader.stop()`
- [ ] Hook vào `video_inpaint` sau `reader.stop()`
- [ ] Hook vào `sttn_auto_mode` (qua STTNAutoInpaint — xem note)
- [ ] Gọi `_warn_frame_errors()` trong `run()`

> **Note cho sttn_auto_mode:** `STTNAutoInpaint` quản lý prefetcher nội bộ. Cần expose `failed_frames` ra ngoài hoặc nhận callback. Đơn giản nhất: `STTNAutoInpaint.__call__` trả về `list[int]` failed frames, `sttn_auto_mode` pass vào `_collect_frame_errors`.

---

## Success Criteria

- Sau khi processing xong, nếu có frame lỗi → GUI hiển thị warning với số lượng và vị trí frame
- Nếu không có frame lỗi → không có message thừa
- Warning xuất hiện trong cùng output panel với các message khác

---

## Risk Assessment

| Risk | Mức độ | Mitigation |
|---|---|---|
| `STTNAutoInpaint` khó expose failed_frames | Trung bình | Thêm return value hoặc callback param |
| Translation key thiếu → KeyError | Thấp | Dùng `.get()` với fallback string |

---

## Next Steps

→ [Phase 03](phase-03-processing-loop-fix.md): Fix processing loops để không `break` khi còn frame hợp lệ.
