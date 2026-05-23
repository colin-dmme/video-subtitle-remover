import math
import re
from pathlib import Path
from typing import Iterable, List, Sequence, Tuple


TimeInterval = Tuple[float, float]
FrameSpan = Tuple[int, int]

_TIMECODE = r"\d{1,3}:\d{2}:\d{2}(?:[,.]\d{1,3})?"
_TIMELINE_RE = re.compile(rf"(?P<start>{_TIMECODE})\s*-->\s*(?P<end>{_TIMECODE})")


def parse_srt_timecode(value: str) -> float:
    """Convert an SRT timecode to seconds."""
    value = value.strip()
    if "," in value:
        body, fraction = value.split(",", 1)
    elif "." in value:
        body, fraction = value.split(".", 1)
    else:
        body, fraction = value, "0"

    hours, minutes, seconds = [int(part) for part in body.split(":")]
    milliseconds = int(fraction[:3].ljust(3, "0"))
    return hours * 3600 + minutes * 60 + seconds + milliseconds / 1000.0


def _read_text(path: str) -> str:
    last_error = None
    for encoding in ("utf-8-sig", "utf-16", "gb18030", "cp1252"):
        try:
            return Path(path).read_text(encoding=encoding)
        except UnicodeError as exc:
            last_error = exc
    if last_error:
        raise last_error
    return Path(path).read_text()


def parse_srt_intervals(path: str) -> List[TimeInterval]:
    """Return valid (start_seconds, end_seconds) intervals from an SRT file."""
    text = _read_text(path)
    intervals: List[TimeInterval] = []
    for match in _TIMELINE_RE.finditer(text):
        start = parse_srt_timecode(match.group("start"))
        end = parse_srt_timecode(match.group("end"))
        if end > start:
            intervals.append((start, end))
    return intervals


def merge_frame_spans(spans: Iterable[FrameSpan]) -> List[FrameSpan]:
    """Merge overlapping or adjacent half-open frame spans."""
    sorted_spans = sorted((start, stop) for start, stop in spans if stop > start)
    if not sorted_spans:
        return []

    merged = [sorted_spans[0]]
    for start, stop in sorted_spans[1:]:
        last_start, last_stop = merged[-1]
        if start <= last_stop:
            merged[-1] = (last_start, max(last_stop, stop))
        else:
            merged.append((start, stop))
    return merged


def intervals_to_frame_spans(
    intervals: Sequence[TimeInterval],
    fps: float,
    frame_count: int,
    backward_frames: int = 0,
    forward_frames: int = 0,
) -> List[FrameSpan]:
    """Convert subtitle time intervals to half-open, zero-based frame spans."""
    if fps <= 0:
        fps = 30

    spans: List[FrameSpan] = []
    for start_seconds, end_seconds in intervals:
        start = int(math.floor(start_seconds * fps)) - max(0, backward_frames)
        stop = int(math.ceil(end_seconds * fps)) + max(0, forward_frames)
        start = max(0, start)
        stop = min(frame_count, stop)
        if stop <= start and start < frame_count:
            stop = min(frame_count, start + 1)
        if stop > start:
            spans.append((start, stop))
    return merge_frame_spans(spans)


def spans_to_ranges(spans: Iterable[FrameSpan]) -> List[range]:
    return [range(start, stop) for start, stop in spans if stop > start]


def normalize_frame_sections(sections: Iterable, frame_count: int = None) -> List[FrameSpan]:
    spans: List[FrameSpan] = []
    if not sections:
        return spans

    for section in sections:
        if isinstance(section, range):
            start, stop = section.start, section.stop
        else:
            start, stop = int(section[0]), int(section[1])
        start = max(0, start)
        if frame_count is not None:
            stop = min(frame_count, stop)
        if stop > start:
            spans.append((start, stop))
    return merge_frame_spans(spans)


def intersect_frame_sections(
    primary_sections: Iterable,
    secondary_sections: Iterable,
    frame_count: int = None,
) -> List[range]:
    """Intersect two section lists and return ranges."""
    primary = normalize_frame_sections(primary_sections, frame_count)
    secondary = normalize_frame_sections(secondary_sections, frame_count)
    intersections: List[FrameSpan] = []

    i = j = 0
    while i < len(primary) and j < len(secondary):
        start = max(primary[i][0], secondary[j][0])
        stop = min(primary[i][1], secondary[j][1])
        if stop > start:
            intersections.append((start, stop))

        if primary[i][1] < secondary[j][1]:
            i += 1
        else:
            j += 1

    return spans_to_ranges(merge_frame_spans(intersections))

