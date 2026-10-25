"""Local FOA transport and experimental dominant-sound direction estimation.

The four input channels are ACN/SN3D W,Y,Z,X, not individual microphones.
Quality is a coherence heuristic, not an accuracy probability. This does not
separate simultaneous sources or establish which source YAMNet recognized.
No audio is written to disk or forwarded to an external service.
"""

from __future__ import annotations

import base64
import binascii
from collections import deque
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import math
import secrets
import threading
import time
import uuid

import numpy as np

MIN_QUALITY = 0.60
MAX_BODY = 530_000
MAX_AGE = 0.75
MIN_RMS = 0.0001
CALIBRATION_SECONDS = 1.0


def wrap_angle(angle: float) -> float:
    return (angle + 180.0) % 360.0 - 180.0


@dataclass(frozen=True)
class Direction:
    angle_deg: float | None
    quality: float | None
    reason: str


def estimate_direction(samples: np.ndarray, rate: int, zero: float = 0.0) -> Direction:
    """Estimate azimuth from the mean FOA intensity vector; right is positive.

The phone must stay upright and fixed. Physical axis/sign validation is still
required; calibration only supplies a rotation about the assumed vertical axis.
"""
    if len(samples) == 0:
        return Direction(None, None, "warming_up")
    audio = np.asarray(samples, dtype=np.float64)
    w = audio[:, 0]
    xyz = audio[:, [3, 1, 2]]
    power = float(np.mean(w * w))
    if power < MIN_RMS * MIN_RMS:
        return Direction(None, None, "quiet")
    vector = np.mean(w[:, None] * xyz, axis=0)
    magnitude = float(np.linalg.norm(vector))
    energy = power + float(np.mean(np.sum(xyz * xyz, axis=1)))
    coherence = min(1.0, 2.0 * magnitude / max(energy, 1e-20))
    horizontal = float(np.linalg.norm(vector[:2])) / max(magnitude, 1e-20)
    if horizontal < 0.5:
        return Direction(None, None, "vertical_or_diffuse")

    # A moving source or inconsistent blocks must not become a precise arrow.
    block_size = max(1, int(rate * 0.025))
    vectors = []
    for start in range(0, len(audio), block_size):
        stop = min(start + block_size, len(audio))
        if stop - start < block_size // 2:
            continue
        block = np.mean(w[start:stop, None] * xyz[start:stop], axis=0)
        length = float(np.linalg.norm(block))
        if float(np.mean(w[start:stop] ** 2)) >= MIN_RMS**2 and length > 1e-20:
            vectors.append(block / length)
    stability = float(np.linalg.norm(np.mean(vectors, axis=0))) if vectors else 0.0
    quality = float(np.clip(coherence * horizontal * stability, 0.0, 1.0))
    if quality < MIN_QUALITY:
        return Direction(None, None, "diffuse_or_moving")
    angle = wrap_angle(-math.degrees(math.atan2(vector[1], vector[0])) - zero)
    return Direction(angle, quality, "direction_ready")


class PacketError(ValueError):
    def __init__(self, reason: str, status: int = 400):
        super().__init__(reason)
        self.reason, self.status = reason, status


@dataclass(frozen=True)
class AudioPacket:
    session: str
    sequence: int
    sample_rate: int
    pts: float
    samples: np.ndarray
    calibrate_front: bool

    @property
    def duration(self) -> float:
        return len(self.samples) / self.sample_rate

    @property
    def end_pts(self) -> float:
        return self.pts + self.duration


def decode_packet(body: bytes) -> AudioPacket:
    if len(body) > MAX_BODY:
        raise PacketError("body_too_large", 413)
    try:
        data = json.loads(body)
    except (ValueError, UnicodeDecodeError, RecursionError):
        raise PacketError("invalid_json") from None
    if not isinstance(data, dict):
        raise PacketError("expected_object")
    for key in ("version", "sequence", "sample_rate", "frames"):
        if type(data.get(key)) is not int:
            raise PacketError("invalid_" + key)
    if data["version"] != 1 or data.get("layout") != "ACN_SN3D":
        raise PacketError("unsupported_format")
    if not 0 <= data["sequence"] <= 2**53 - 1:
        raise PacketError("invalid_sequence")
    rate, frames = data["sample_rate"], data["frames"]
    if rate not in (16000, 24000, 32000, 44100, 48000, 96000):
        raise PacketError("unsupported_sample_rate")
    if not 1 <= frames <= rate // 4:
        raise PacketError("invalid_frames")
    pts = data.get("pts")
    if type(pts) not in (float, int) or pts < 0 or pts > 1e12 or not math.isfinite(pts):
        raise PacketError("invalid_pts")
    if type(data.get("calibrate_front")) is not bool:
        raise PacketError("invalid_calibrate_front")
    session = data.get("session")
    try:
        if not isinstance(session, str):
            raise ValueError
        session = str(uuid.UUID(session))
    except (ValueError, AttributeError):
        raise PacketError("invalid_session") from None
    encoded = data.get("pcm_f32le")
    expected = frames * 4 * 4
    if not isinstance(encoded, str) or len(encoded) != 4 * ((expected + 2) // 3):
        raise PacketError("invalid_pcm_length")
    try:
        raw = base64.b64decode(encoded, validate=True)
    except (ValueError, binascii.Error):
        raise PacketError("invalid_base64") from None
    if len(raw) != expected:
        raise PacketError("invalid_pcm_length")
    audio = np.frombuffer(raw, dtype="<f4").reshape(frames, 4)
    if not np.isfinite(audio).all() or np.max(np.abs(audio)) > 8.0:
        raise PacketError("invalid_pcm_values")
    return AudioPacket(session, data["sequence"], rate, float(pts), audio, data["calibrate_front"])


@dataclass(frozen=True)
class SpatialWindow:
    samples: np.ndarray
    sample_rate: int
    epoch: int
    end_pts: float
    received_at: float
    captured_at: float
    zero: float | None

    def direction(self) -> Direction:
        if self.zero is None:
            return Direction(None, None, "needs_calibration")
        return estimate_direction(self.samples, self.sample_rate, self.zero)

    def mono(self, target_rate: int = 16000) -> np.ndarray:
        from scipy.signal import resample_poly
        divisor = math.gcd(self.sample_rate, target_rate)
        # W is omnidirectional. Do NOT average all four Ambisonic channels.
        return resample_poly(self.samples[:, 0], target_rate // divisor,
                             self.sample_rate // divisor).astype(np.float32)


class SpatialReceiver:
    """One bounded rolling second; consumers always take the newest window.

    A generation counter prevents in-flight inference from publishing after a
    gap, recalibration, replacement session, or stream expiry.
    """
    def __init__(self, token: str, connected=lambda: False, clock=time.monotonic):
        self.token = token
        self.connected = connected
        self.clock = clock
        self.lock = threading.RLock()
        self.wake = threading.Event()
        self.session: str | None = None
        self.retired: set[str] = set()
        self.sequence = -1
        self.rate = 0
        self.end_pts = 0.0
        self.received_at = 0.0
        self.anchor_pts = 0.0
        self.anchor_time = 0.0
        self.epoch = 0
        self.chunks: deque[np.ndarray] = deque()
        self.frames = 0
        self.last_window_pts = -math.inf
        self.zero: float | None = None
        self.calibrating = False
        self.calibration_vector = np.zeros(2, np.float64)
        self.calibration_duration = 0.0
        self.calibration_start = 0.0
        self.latest = Direction(None, None, "waiting_for_audio")

    def _clear_audio(self) -> None:
        self.epoch += 1
        self.chunks.clear()
        self.frames = 0
        self.last_window_pts = -math.inf

    def _reset(self, reason: str) -> None:
        self._clear_audio()
        self.zero = None
        self.calibrating = False
        self.calibration_vector[:] = 0
        self.calibration_duration = 0.0
        self.latest = Direction(None, None, reason)

    def status(self, accepted=True, reason=None) -> dict:
        with self.lock:
            direction = self.latest
            captured_at = self.anchor_time + self.end_pts - self.anchor_pts
            stale = self.session is not None and self.clock() - captured_at > MAX_AGE
            return {
                "accepted": accepted,
                "calibrated": self.zero is not None and not stale,
                "calibrating": self.calibrating and not stale,
                "angle_deg": None if stale else direction.angle_deg,
                "direction_quality": None if stale else direction.quality,
                "reason": reason or ("stale_audio" if stale else direction.reason),
                "wristband_connected": bool(self.connected()),
            }

    def accept(self, body: bytes, authorization: str | None) -> dict:
        if not authorized(authorization, self.token):
            raise PacketError("unauthorized", 401)
        packet = decode_packet(body)
        now = self.clock()
        with self.lock:
            new_session = packet.session != self.session
            if new_session:
                if packet.session in self.retired:
                    raise PacketError("session_retired", 409)
                if packet.sequence != 0:
                    raise PacketError("session_must_start_at_zero", 409)
                # Bound session bookkeeping without permitting retired sessions to replay.
                if len(self.retired) >= 64:
                    raise PacketError("restart_receiver", 409)
                if self.session:
                    self.retired.add(self.session)
                self.session = packet.session
                self._reset("needs_calibration")
                self.anchor_time, self.anchor_pts = now, packet.end_pts
            else:
                if packet.sequence <= self.sequence or packet.pts < self.end_pts - 1 / packet.sample_rate:
                    raise PacketError("out_of_order", 409)
                predicted = self.anchor_time + packet.end_pts - self.anchor_pts
                if now - predicted > MAX_AGE:
                    self._reset("stale_audio")
                    raise PacketError("stale_audio", 409)
                if predicted - now > 0.5:
                    self._reset("invalid_timing")
                    raise PacketError("invalid_timing", 409)
                gap = (packet.sequence != self.sequence + 1 or packet.sample_rate != self.rate
                       or abs(packet.pts - self.end_pts) > 2 / packet.sample_rate
                       or now - self.received_at > MAX_AGE)
                if gap:
                    self._reset("stream_gap_recalibrate")
            self.sequence, self.rate = packet.sequence, packet.sample_rate
            self.end_pts, self.received_at = packet.end_pts, now
            if packet.calibrate_front:
                self._reset("calibrating")
                self.calibrating = True
                self.calibration_start = now
            raw_direction = estimate_direction(packet.samples, packet.sample_rate)
            if self.calibrating:
                self._calibrate(raw_direction, packet.duration, now)
            else:
                self._append(packet.samples)
                self.latest = (estimate_direction(packet.samples, packet.sample_rate, self.zero)
                               if self.zero is not None else Direction(None, None, "needs_calibration"))
            self.wake.set()
            return self.status()

    def _calibrate(self, direction: Direction, duration: float, now: float) -> None:
        if now - self.calibration_start > 10:
            self.calibrating = False
            self.latest = Direction(None, None, "calibration_failed_retry")
            return
        if direction.angle_deg is None:
            self.calibration_vector[:] = 0
            self.calibration_duration = 0.0
            self.latest = Direction(None, None, "calibration_needs_clear_sound")
            return
        angle = math.radians(direction.angle_deg)
        if self.calibration_duration:
            previous = math.degrees(math.atan2(self.calibration_vector[1], self.calibration_vector[0]))
            if abs(wrap_angle(direction.angle_deg - previous)) > 15:
                self.calibration_vector[:] = 0
                self.calibration_duration = 0.0
        self.calibration_vector += np.array([math.cos(angle), math.sin(angle)]) * duration
        self.calibration_duration += duration
        self.latest = Direction(None, None, "calibrating")
        if self.calibration_duration + 1e-8 >= CALIBRATION_SECONDS:
            self.zero = math.degrees(math.atan2(self.calibration_vector[1], self.calibration_vector[0]))
            self.calibrating = False
            self.calibration_vector[:] = 0
            self._clear_audio()  # Do not classify the sounds used for calibration.
            self.latest = Direction(None, None, "calibrated_waiting_for_audio")

    def _append(self, audio: np.ndarray) -> None:
        self.chunks.append(audio)
        self.frames += len(audio)
        while self.frames > self.rate:
            excess = self.frames - self.rate
            first = self.chunks.popleft()
            if len(first) > excess:
                self.chunks.appendleft(first[excess:].copy())
                self.frames -= excess
            else:
                self.frames -= len(first)

    def next_window(self, hop: float = 0.5, timeout: float = 0.2) -> SpatialWindow | None:
        self.wake.wait(timeout)
        with self.lock:
            self.wake.clear()
            if (self.frames < self.rate or self.rate == 0 or self.calibrating
                    or self.end_pts - self.last_window_pts < hop - 1e-8
                    or self.clock() - (self.anchor_time + self.end_pts - self.anchor_pts) > MAX_AGE):
                return None
            self.last_window_pts = self.end_pts
            return SpatialWindow(np.concatenate(self.chunks), self.rate, self.epoch,
                                 self.end_pts, self.received_at,
                                 self.anchor_time + self.end_pts - self.anchor_pts, self.zero)

    def is_current(self, window: SpatialWindow) -> bool:
        with self.lock:
            return (window.epoch == self.epoch and self.clock() - window.captured_at <= MAX_AGE
                    and self.end_pts - window.end_pts <= MAX_AGE)

    def publish_if_current(self, window: SpatialWindow, callback) -> bool:
        with self.lock:
            if not self.is_current(window):
                return False
            callback()
            return True


def authorized(header: str | None, token: str) -> bool:
    return bool(header) and secrets.compare_digest(header.encode("utf8"), ("Bearer " + token).encode("utf8"))


def make_server(address: tuple[str, int], receiver: SpatialReceiver) -> HTTPServer:
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.0"

        def setup(self):
            super().setup()
            self.connection.settimeout(2.0)

        def log_message(self, *args):
            pass  # Never log the token, request payload, or raw audio.

        def respond(self, status: int, payload: dict):
            body = json.dumps(payload, allow_nan=False).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def do_POST(self):
            try:
                if self.path != "/audio":
                    raise PacketError("not_found", 404)
                authorization = self.headers.get("Authorization")
                if not authorized(authorization, receiver.token):
                    raise PacketError("unauthorized", 401)
                if self.headers.get("Transfer-Encoding") is not None:
                    raise PacketError("unsupported_transfer_encoding")
                if self.headers.get_content_type() != "application/json":
                    raise PacketError("expected_application_json", 415)
                lengths = self.headers.get_all("Content-Length", [])
                if len(lengths) != 1 or not lengths[0].isascii() or not lengths[0].isdigit():
                    raise PacketError("invalid_content_length")
                if len(lengths[0]) > 8:
                    raise PacketError("body_too_large", 413)
                length = int(lengths[0])
                if not 0 < length <= MAX_BODY:
                    raise PacketError("body_too_large", 413)
                body = self.rfile.read(length)
                if len(body) != length:
                    raise PacketError("incomplete_body")
                self.respond(200, receiver.accept(body, authorization))
            except PacketError as error:
                payload = receiver.status(False, error.reason)
                # An unsuccessful upload must never retain an apparently usable arrow.
                payload.update(calibrated=False, calibrating=False, angle_deg=None, direction_quality=None)
                self.respond(error.status, payload)
            except (TimeoutError, ConnectionError, BrokenPipeError):
                return

    # Deliberately one request at a time: bounded memory and no concurrent stream
    # mutations. The app keeps only one upload in flight and drops old chunks.
    return HTTPServer(address, Handler)
