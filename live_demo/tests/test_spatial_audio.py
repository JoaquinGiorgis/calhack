"""Portable software checks. Synthetic FOA is not evidence of iPhone accuracy."""

import base64
import asyncio
import contextlib
import http.client
import io
import json
import math
import queue
from pathlib import Path
import sys
import threading
import unittest
import uuid

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from spatial_audio import (
    MAX_BODY, PacketError, SpatialReceiver, decode_packet, estimate_direction,
    make_server, wrap_angle,
)
from mac_listener import EVENTS, BleLink, SpatialEventProcessor


RATE = 16000
TOKEN = "test-token-with-enough-entropy"


def plane(angle=0, frames=1600, rate=RATE, elevation=0, phase=0):
    t = np.arange(frames) / rate
    w = (0.1 * np.sin(2 * np.pi * 431 * t + phase)).astype(np.float32)
    az, el = -math.radians(angle), math.radians(elevation)
    return np.column_stack((w, w * math.sin(az) * math.cos(el),
                            w * math.sin(el), w * math.cos(az) * math.cos(el)))


def payload(session, sequence, pts, samples=None, calibrate=False, rate=RATE):
    samples = plane() if samples is None else samples
    return {
        "version": 1, "session": session, "sequence": sequence, "sample_rate": rate,
        "frames": len(samples), "pts": pts, "layout": "ACN_SN3D",
        "pcm_f32le": base64.b64encode(samples.astype("<f4").tobytes()).decode(),
        "calibrate_front": calibrate,
    }


class Stream:
    def __init__(self):
        self.now = 100.0
        self.receiver = SpatialReceiver(TOKEN, clock=lambda: self.now)
        self.session = str(uuid.uuid4())
        self.sequence, self.pts = 0, 20.0

    def feed(self, angle=0, calibrate=False, samples=None):
        samples = plane(angle) if samples is None else samples
        packet = payload(self.session, self.sequence, self.pts, samples, calibrate)
        result = self.receiver.accept(json.dumps(packet).encode(), "Bearer " + TOKEN)
        self.sequence += 1
        duration = len(samples) / RATE
        self.pts += duration
        self.now += duration
        return result

    def calibrate(self, angle=0):
        for i in range(10):
            result = self.feed(angle, calibrate=i == 0)
        return result

    def window(self, angle=0):
        for _ in range(10):
            self.feed(angle)
        return self.receiver.next_window(timeout=0)


class DirectionTests(unittest.TestCase):
    def test_angles_wrap_and_quality(self):
        for angle in (-180, -179, -135, -90, -45, 0, 45, 90, 135, 179, 180):
            with self.subTest(angle=angle):
                estimate = estimate_direction(plane(angle, frames=RATE), RATE)
                self.assertAlmostEqual(wrap_angle(estimate.angle_deg - angle), 0, places=4)
                self.assertGreater(estimate.quality, 0.99)
        self.assertAlmostEqual(estimate_direction(plane(-175), RATE, zero=175).angle_deg, 10, places=4)

    def test_silence_diffuse_vertical_and_changing_source(self):
        rng = np.random.default_rng(121)
        fixtures = [np.zeros((RATE, 4), np.float32),
                    rng.normal(0, 0.1, (RATE, 4)),
                    plane(0, frames=RATE, elevation=89),
                    np.concatenate([plane(-90, frames=RATE // 2), plane(90, frames=RATE // 2)])]
        for samples in fixtures:
            with self.subTest(kind=str(samples[:1])):
                self.assertIsNone(estimate_direction(samples, RATE).angle_deg)


class TransportTests(unittest.TestCase):
    def test_calibration_and_exact_mono_window(self):
        stream = Stream()
        result = stream.calibrate(30)
        self.assertTrue(result["calibrated"])
        self.assertFalse(result["calibrating"])
        self.assertIsNone(stream.receiver.next_window(timeout=0))
        window = stream.window(75)
        self.assertEqual(window.samples.shape, (RATE, 4))
        self.assertAlmostEqual(window.direction().angle_deg, 45, places=4)
        np.testing.assert_allclose(window.mono(), window.samples[:, 0])

    def test_calibration_requires_consistent_sound(self):
        stream = Stream()
        for i in range(20):
            result = stream.feed(90 if i % 2 else -90, calibrate=i == 0)
        self.assertFalse(result["calibrated"])
        self.assertTrue(result["calibrating"])
        stream.feed(samples=np.zeros((1600, 4), np.float32))
        self.assertEqual(stream.receiver.calibration_duration, 0)

    def test_gap_discards_history_window_and_calibration(self):
        stream = Stream()
        stream.calibrate()
        old_window = stream.window(45)
        stream.sequence += 1
        stream.pts += 0.1
        stream.now += 0.1
        stream.feed(90)
        self.assertIsNone(stream.receiver.zero)
        self.assertIsNone(stream.receiver.next_window(timeout=0))
        self.assertFalse(stream.receiver.publish_if_current(old_window, lambda: self.fail("stale callback")))

    def test_recalibration_invalidates_in_flight_window(self):
        stream = Stream()
        stream.calibrate()
        old_window = stream.window(45)
        stream.feed(90, calibrate=True)
        self.assertFalse(stream.receiver.publish_if_current(old_window, lambda: self.fail("old epoch")))

    def test_network_and_inference_share_one_freshness_deadline(self):
        stream = Stream()
        stream.calibrate()
        for _ in range(9):
            stream.feed(45)
        stream.now += 0.60  # Delayed on network, but still accepted at ingress.
        stream.feed(45)
        window = stream.receiver.next_window(timeout=0)
        self.assertIsNotNone(window)
        stream.now += 0.60  # Inference must not receive a fresh TTL of its own.
        self.assertFalse(stream.receiver.is_current(window))
        self.assertFalse(stream.receiver.publish_if_current(window, lambda: self.fail("old capture")))
        self.assertIsNone(stream.receiver.status()["angle_deg"])

    def test_only_latest_bounded_window_and_expiry(self):
        stream = Stream()
        stream.calibrate()
        stream.window(-90)
        for _ in range(100):
            stream.feed(90)
        self.assertEqual(stream.receiver.frames, RATE)
        self.assertLessEqual(len(stream.receiver.chunks), 11)
        latest = stream.receiver.next_window(timeout=0)
        self.assertAlmostEqual(latest.direction().angle_deg, 90, places=4)
        stream.now += 1
        self.assertIsNone(stream.receiver.status()["angle_deg"])
        self.assertFalse(stream.receiver.publish_if_current(latest, lambda: self.fail("expired")))

    def test_duplicate_retired_and_delayed_audio(self):
        stream = Stream()
        stream.feed()
        with self.assertRaisesRegex(PacketError, "out_of_order"):
            stream.receiver.accept(json.dumps(payload(stream.session, 0, 20)).encode(), "Bearer " + TOKEN)
        old_session = stream.session
        stream.session, stream.sequence = str(uuid.uuid4()), 0
        stream.feed()
        with self.assertRaisesRegex(PacketError, "session_retired"):
            stream.receiver.accept(json.dumps(payload(old_session, 0, 0)).encode(), "Bearer " + TOKEN)
        stream.now += 2
        with self.assertRaisesRegex(PacketError, "stale_audio"):
            stream.feed()

    def test_schema_auth_and_malformed(self):
        base = payload(str(uuid.uuid4()), 0, 0)
        invalid = [dict(base, frames=0), dict(base, frames=RATE), dict(base, version=True),
                   dict(base, sample_rate=1), dict(base, sequence=-1), dict(base, pts=float("nan")),
                   dict(base, pts=10**1000), dict(base, session="not-uuid"),
                   dict(base, layout="WXYZ"), dict(base, pcm_f32le="a"),
                   dict(base, calibrate_front=1)]
        invalid.append(payload(str(uuid.uuid4()), 0, 0, np.full((1600, 4), np.nan)))
        invalid.append(payload(str(uuid.uuid4()), 0, 0, np.full((1600, 4), 9)))
        for item in invalid:
            with self.subTest(fields=list(item)), self.assertRaises(PacketError):
                decode_packet(json.dumps(item).encode())
        for body in (b"{", b"[]", b"[" * 10000, b"x" * (MAX_BODY + 1)):
            with self.assertRaises(PacketError):
                decode_packet(body)
        receiver = SpatialReceiver(TOKEN)
        for header in (None, "Bearer wrong", "Bearer \u00e1"):
            with self.assertRaisesRegex(PacketError, "unauthorized"):
                receiver.accept(json.dumps(base).encode(), header)

    def test_http_endpoint(self):
        receiver = SpatialReceiver(TOKEN)
        server = make_server(("127.0.0.1", 0), receiver)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            def request(body, authorization="Bearer " + TOKEN, path="/audio", content_length=None):
                connection = http.client.HTTPConnection(*server.server_address, timeout=3)
                try:
                    headers = {"Authorization": authorization, "Content-Type": "application/json"}
                    if content_length is not None:
                        headers["Content-Length"] = str(content_length)
                    connection.request("POST", path, body, headers)
                    response = connection.getresponse()
                    return response.status, json.loads(response.read())
                finally:
                    connection.close()
            body = json.dumps(payload(str(uuid.uuid4()), 0, 0)).encode()
            self.assertEqual(request(body, "Bearer bad")[0], 401)
            self.assertEqual(request(b"{")[0], 400)
            self.assertEqual(request(body, path="/elsewhere")[0], 404)
            # The receiver rejects the declared size before reading a body.
            # Do not race its connection close by transmitting oversized audio.
            self.assertEqual(request(b"", content_length=MAX_BODY + 1)[0], 413)
            status, result = request(body)
            self.assertEqual(status, 200)
            self.assertTrue(result["accepted"])
            self.assertFalse(result["calibrated"])
            self.assertIsNone(result["angle_deg"])
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)


class EventIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.names = sorted({name for event in EVENTS.values() for name in event.classes})
        self.sent = []
        self.link = type("FakeLink", (), {"connected": True,
                        "send": lambda _, line, valid=None: self.sent.append(line)})()

    def test_event_and_direction_share_audio_window(self):
        stream = Stream()
        stream.calibrate()
        window = stream.window(60)
        captured = []
        def classify(waveform):
            captured.append(waveform.copy())
            scores = np.zeros(len(self.names), np.float32)
            scores[self.names.index("Knock")] = 0.9
            return scores
        processor = SpatialEventProcessor(classify, self.names, self.link, quiet=True)
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertTrue(processor.process(window, stream.receiver))
        np.testing.assert_allclose(captured[0], window.samples[:, 0])
        self.assertIn("E,KNOCK,0.90,60,1.00", self.sent)

    def test_inference_finishing_after_expiry_cannot_send(self):
        stream = Stream()
        window = stream.window()
        def classify(waveform):
            stream.now += 2
            return np.ones(len(self.names), np.float32)
        processor = SpatialEventProcessor(classify, self.names, self.link, quiet=True)
        self.assertFalse(processor.process(window, stream.receiver))
        self.assertEqual(self.sent, [])

    def test_uncalibrated_events_keep_legacy_payload(self):
        stream = Stream()
        window = stream.window(45)
        scores = np.zeros(len(self.names), np.float32)
        scores[self.names.index("Knock")] = 0.9
        processor = SpatialEventProcessor(lambda _: scores, self.names, self.link, quiet=True)
        with contextlib.redirect_stdout(io.StringIO()):
            processor.process(window, stream.receiver)
        self.assertIn("E,KNOCK,0.90", self.sent)

    def test_ble_revalidates_at_write_after_gap_or_expiry(self):
        stream = Stream()
        stream.calibrate()
        window = stream.window(45)
        link = BleLink.__new__(BleLink)  # No hardware scanning in this test.
        link.connected = True
        link.outbox = queue.Queue(maxsize=20)
        writes = []
        class Client:
            async def write_gatt_char(self, uuid, data, response):
                writes.append(data)
        client = Client()
        link.send("E,KNOCK,0.90,45,1.00", valid=lambda: stream.receiver.is_current(window))
        stream.feed(0, calibrate=True)
        asyncio.run(link._write_next(client))
        self.assertEqual(writes, [])
        stream.calibrate()
        window = stream.window(45)
        link.send("E,KNOCK,0.90,45,1.00", valid=lambda: stream.receiver.is_current(window))
        stream.now += 1
        asyncio.run(link._write_next(client))
        self.assertEqual(writes, [])
        # Existing mono callers have no spatial freshness predicate.
        link.send("E,KNOCK,0.90")
        asyncio.run(link._write_next(client))
        self.assertEqual(writes, [b"E,KNOCK,0.90"])


if __name__ == "__main__":
    unittest.main()
