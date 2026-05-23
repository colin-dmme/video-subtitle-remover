import os
import queue
import subprocess
import threading

import cv2
import numpy as np

from .ffmpeg_cli import FFmpegCLI


class FramePrefetcher:
    """
    后台线程预解码视频帧，使 I/O 与模型推理重叠。
    接口兼容 cv2.VideoCapture（read/release）。

    Corrupt-frame resilience:
    - Retries each frame up to `max_retries` times before giving up.
    - Distinguishes true EOF from mid-stream corruption via CAP_PROP_POS_FRAMES.
    - On corruption: records frame index in `_failed_frames`, pushes sentinel
      (False, None), seeks past the bad frame and continues.
    - Callers can inspect `failed_count` / `failed_frames` after processing.

    Note: FFmpeg/libav decoder errors (e.g. "Invalid NAL unit") are printed
    directly to stderr at C level and cannot be captured here. Python-level
    frame failures are tracked via failed_frames.
    """

    def __init__(self, video_cap, buffer_size=10, max_retries=3):
        self.cap = video_cap
        self._buffer = queue.Queue(maxsize=buffer_size)
        self._stopped = False
        self._max_retries = max_retries
        # CPython GIL makes list.append/len atomic; revisit if running free-threaded (PEP 703).
        self._failed_frames = []   # attempt-ordinal indices of frames that could not be decoded
        self._frame_index = 0      # monotone attempt counter (increments on success or skip)
        self._thread = threading.Thread(target=self._read_loop, daemon=True)
        self._thread.start()

    def _read_loop(self):
        while not self._stopped:
            # --- retry loop ---
            ret, frame = False, None
            for _ in range(self._max_retries):
                ret, frame = self.cap.read()
                if ret:
                    break

            if ret:
                self._buffer.put((True, frame))
                self._frame_index += 1
                continue

            # --- ret=False: distinguish EOF vs corruption ---
            total   = self.cap.get(cv2.CAP_PROP_FRAME_COUNT)
            current = self.cap.get(cv2.CAP_PROP_POS_FRAMES)

            if total > 0 and current < total - 1:
                # Mid-stream failure — record, push sentinel, seek past bad frame.
                self._failed_frames.append(self._frame_index)
                self._buffer.put((False, None))
                self._frame_index += 1
                try:
                    seek_ok = self.cap.set(cv2.CAP_PROP_POS_FRAMES, current + 1)
                except Exception:
                    seek_ok = False
                if not seek_ok:
                    # Seek failed — cannot advance; treat rest of stream as unrecoverable.
                    self._buffer.put((False, None))
                    break
                continue

            # True EOF — push final sentinel and stop
            self._buffer.put((False, None))
            break

    # ------------------------------------------------------------------
    # Public API (unchanged from original)
    # ------------------------------------------------------------------

    def read(self):
        """读取下一帧，接口与 cv2.VideoCapture.read() 一致。"""
        return self._buffer.get()

    @property
    def failed_frames(self):
        """Return a snapshot list of 0-based frame indices that failed to decode."""
        return list(self._failed_frames)

    @property
    def failed_count(self):
        """Return number of frames that could not be decoded and were skipped."""
        return len(self._failed_frames)

    def get(self, propId):
        return self.cap.get(propId)

    def stop(self):
        """停止预读取，不释放底层 video_cap。"""
        self._stopped = True
        try:
            while not self._buffer.empty():
                self._buffer.get_nowait()
        except queue.Empty:
            pass
        self._thread.join(timeout=5)

    def release(self):
        self.stop()
        self.cap.release()


class FFmpegVideoWriter:
    """
    通过 FFmpeg 管道写入帧，使用 libx264 编码。
    接口兼容 cv2.VideoWriter（write/release）。
    """

    def __init__(self, output_path, fps, size):
        w, h = size
        cmd = [
            FFmpegCLI.instance().ffmpeg_path,
            '-y',
            '-f', 'rawvideo',
            '-vcodec', 'rawvideo',
            '-s', f'{w}x{h}',
            '-pix_fmt', 'bgr24',
            '-r', str(fps),
            '-i', '-',
            '-c:v', 'libx264',
            '-pix_fmt', 'yuv420p',
            '-crf', '18',
            '-preset', 'fast',
            '-loglevel', 'error',
            output_path
        ]
        self._process = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    def write(self, frame):
        """写入一帧（numpy BGR 数组）。"""
        if frame.dtype != np.uint8:
            frame = np.clip(frame, 0, 255).astype(np.uint8)
        try:
            self._process.stdin.write(frame.tobytes())
        except BrokenPipeError:
            pass

    def release(self):
        """关闭管道并等待编码完成。"""
        try:
            self._process.stdin.close()
        except BrokenPipeError:
            pass
        try:
            self._process.wait(timeout=600)
        except subprocess.TimeoutExpired:
            self._process.terminate()
            self._process.wait(timeout=5)
