# Plan: Frame Error Handling

**Date:** 2026-05-22
**Status:** Proposed

## Problem Summary

Khi video input bị corrupt (NAL unit errors, partial file), phần mềm:
1. Dừng xử lý âm thầm khi gặp frame lỗi (`if not ret: break`)
2. Không retry đọc lại frame
3. Không cảnh báo user qua GUI — chỉ `print()` ra console (STTN mode) hoặc hoàn toàn im lặng (Propainter/video_inpaint)

## Phương án tổng thể

3 phase độc lập, có thể implement tuần tự hoặc song song:

| Phase | Mô tả | Độ ưu tiên | File thay đổi |
|---|---|---|---|
| [01](phase-01-resilient-frame-prefetcher.md) | Retry + skip trong FramePrefetcher | **Cao** | `backend/tools/video_io.py` |
| [02](phase-02-warning-system.md) | Warning system lên GUI | **Cao** | `backend/main.py` |
| [03](phase-03-processing-loop-fix.md) | Fix processing loops dùng ghost frame | **Trung bình** | `backend/main.py`, `backend/inpaint/sttn_auto_inpaint.py` |

## Thứ tự implement

```
Phase 01 → Phase 02 → Phase 03
```

Phase 01 là nền tảng — sau khi có retry/tracking trong FramePrefetcher,
Phase 02 và 03 dùng thông tin đó để hiển thị warning và xử lý đúng.

## Success Criteria

- [ ] Frame lỗi được retry tối đa N lần trước khi bỏ qua
- [ ] Frame lỗi bị bỏ qua không làm dừng toàn bộ pipeline
- [ ] User nhìn thấy cảnh báo rõ ràng trong GUI (số frame lỗi, vị trí)
- [ ] Output video vẫn được tạo ra dù có frame lỗi
- [ ] Không regression với video bình thường (không lỗi)
