// FortWatch analytics: SpacetimeDB module.
//
// Every alert the Mac listener (live_demo/mac_listener.py) detects is stored here, plus a
// heartbeat with the live microphone level. Dashboards subscribe in real time.
// Writes require the device key (private `config` table); reads are public.
import {
  schema, table, t, SenderError, Router, SyncResponse, Range,
  type InferSchema, type ReducerCtx,
} from 'spacetimedb/server';
import { ScheduleAt } from 'spacetimedb';

// ─── Tables ──────────────────────────────────────────────────────────────────
// One row per listener (a Mac running mac_listener.py).
const device = table({ name: 'device', public: true }, {
  deviceId: t.string().primaryKey(),
  name: t.string(),
  lastSeenMs: t.u64(),
  level: t.u8(),                 // mic level 0-100, the same value as the wristband level bar
  link: t.string(),              // 'ble' | 'usb' | 'none'
  wristbandConnected: t.bool(),
  eventCount: t.u64(),
  simulated: t.bool(),
});

// One row per alert sent to the wristband (E,<EVENT>,<score>).
const alertEvent = table({ name: 'alert_event', public: true }, {
  id: t.u64().primaryKey().autoInc(),
  deviceId: t.string().index('btree'),
  atMs: t.u64().index('btree'),
  event: t.string(),             // alarm, car_horn, glass, shout, baby, knock, doorbell, phone, dog, speech
  label: t.string(),
  priority: t.u8(),              // 3 safety, 2 attention, 1 low, 0 speech (same as mac_listener.py)
  score: t.f32(),                // YAMNet score that triggered the alert
  level: t.u8(),                 // mic level 0-100 at detection
  delivered: t.bool(),           // wristband link was connected when the alert was sent
  simulated: t.bool(),
});

// Hourly rollup kept by the server so 7- and 30-day views stay cheap.
const hourlyStat = table({ name: 'hourly_stat', public: true }, {
  key: t.string().primaryKey(), // `${hourMs}:${event}:${sim}`
  hourMs: t.u64().index('btree'),
  event: t.string(),
  priority: t.u8(),
  simulated: t.bool(),
  count: t.u32(),
  deliveredCount: t.u32(),
  sumLevel: t.f64(),
  maxLevel: t.u8(),
});

// Private: the device key. Read it as the database owner: spacetime sql <db> "SELECT * FROM config"
const config = table({ name: 'config' }, {
  id: t.u32().primaryKey(),
  ingestKey: t.string(),
  retentionDays: t.u32(),
});

const simState = table({ name: 'sim_state', public: true }, {
  id: t.u32().primaryKey(),
  enabled: t.bool(),
  phase: t.f64(),
});

const simTick = table({ name: 'sim_tick' }, {
  scheduledId: t.u64().primaryKey().autoInc(),
  scheduledAt: t.scheduleAt(),
});
const cleanupTimer = table({ name: 'cleanup_timer' }, {
  scheduledId: t.u64().primaryKey().autoInc(),
  scheduledAt: t.scheduleAt(),
});

const spacetimedb = schema({ device, alertEvent, hourlyStat, config, simState, simTick, cleanupTimer });
export default spacetimedb;
type Ctx = ReducerCtx<InferSchema<typeof spacetimedb>>;

// ─── FortWatch alerts (keep in sync with EVENTS in live_demo/mac_listener.py) ─
const ALERTS: Record<string, { label: string; priority: number }> = {
  alarm: { label: 'Alarm', priority: 3 },
  car_horn: { label: 'Car horn', priority: 3 },
  glass: { label: 'Glass breaking', priority: 3 },
  shout: { label: 'Shout', priority: 3 },
  baby: { label: 'Baby crying', priority: 2 },
  knock: { label: 'Knock', priority: 2 },
  doorbell: { label: 'Doorbell', priority: 2 },
  phone: { label: 'Phone ringing', priority: 2 },
  dog: { label: 'Dog barking', priority: 1 },
  speech: { label: 'Speech', priority: 0 },
};

// ─── Helpers ─────────────────────────────────────────────────────────────────
const HOUR = 3_600_000n;
const SIM_DEVICE = 'demo-sim';

function nowMs(ctx: Ctx): bigint { return ctx.timestamp.microsSinceUnixEpoch / 1000n; }
function clamp(n: number, lo: number, hi: number) { return Math.max(lo, Math.min(hi, n)); }

function checkKey(ctx: Ctx, key: string) {
  const c = ctx.db.config.id.find(1);
  if (!c || !key || key !== c.ingestKey) throw new SenderError('invalid device key');
}

// Device-supplied timestamps (alerts buffered while offline) are kept if within the last 7 days.
function resolveAt(ctx: Ctx, atMs: bigint): bigint {
  const now = nowMs(ctx);
  if (atMs > 0n && atMs <= now + 60_000n && atMs >= now - 7n * 24n * HOUR) return atMs;
  return now;
}

type DevicePatch = { name?: string; level?: number; link?: string; wristbandConnected?: boolean; addEvent?: boolean };
function touchDevice(ctx: Ctx, deviceId: string, simulated: boolean, p: DevicePatch) {
  const ex = ctx.db.device.deviceId.find(deviceId);
  const seen = nowMs(ctx);
  if (ex) {
    ctx.db.device.deviceId.update({
      ...ex,
      lastSeenMs: seen,
      name: p.name || ex.name,
      level: p.level ?? ex.level,
      link: p.link || ex.link,
      wristbandConnected: p.wristbandConnected ?? ex.wristbandConnected,
      eventCount: ex.eventCount + (p.addEvent ? 1n : 0n),
    });
  } else {
    ctx.db.device.insert({
      deviceId, name: p.name || deviceId, lastSeenMs: seen, level: p.level ?? 0,
      link: p.link || '', wristbandConnected: p.wristbandConnected ?? false,
      eventCount: p.addEvent ? 1n : 0n, simulated,
    });
  }
}

type AlertIn = { deviceId: string; atMs: bigint; event: string; label?: string; priority?: number; score: number; level: number; delivered: boolean; simulated: boolean };
function recordAlert(ctx: Ctx, a: AlertIn) {
  const event = (a.event || 'other').trim().toLowerCase().replace(/[^a-z0-9_]+/g, '_').slice(0, 32) || 'other';
  const known = ALERTS[event];
  const priority = clamp(Math.round(a.priority ?? (known ? known.priority : 1)), 0, 3);
  const row = ctx.db.alertEvent.insert({
    id: 0n,
    deviceId: a.deviceId.slice(0, 64),
    atMs: a.atMs,
    event,
    label: (a.label || (known ? known.label : event)).slice(0, 80),
    priority,
    score: clamp(a.score, 0, 1),
    level: clamp(Math.round(a.level), 0, 100),
    delivered: a.delivered,
    simulated: a.simulated,
  });
  const hourMs = (row.atMs / HOUR) * HOUR;
  const key = `${hourMs}:${event}:${a.simulated ? 1 : 0}`;
  const s = ctx.db.hourlyStat.key.find(key);
  if (s) {
    ctx.db.hourlyStat.key.update({
      ...s,
      count: s.count + 1,
      deliveredCount: s.deliveredCount + (row.delivered ? 1 : 0),
      sumLevel: s.sumLevel + row.level,
      maxLevel: Math.max(s.maxLevel, row.level),
    });
  } else {
    ctx.db.hourlyStat.insert({
      key, hourMs, event, priority, simulated: a.simulated, count: 1,
      deliveredCount: row.delivered ? 1 : 0, sumLevel: row.level, maxLevel: row.level,
    });
  }
  return row;
}

// ─── Simulator: demo data only, always flagged simulated=true ───────────────
type Kind = { event: string; w: number; night: number; level: [number, number]; score: [number, number] };
const KINDS: Kind[] = [
  { event: 'speech', w: 30, night: 0.1, level: [35, 60], score: [0.5, 0.95] },
  { event: 'dog', w: 5, night: 0.5, level: [40, 75], score: [0.3, 0.9] },
  { event: 'knock', w: 4, night: 0.05, level: [40, 70], score: [0.35, 0.85] },
  { event: 'doorbell', w: 3, night: 0.05, level: [45, 70], score: [0.3, 0.9] },
  { event: 'phone', w: 4, night: 0.1, level: [40, 65], score: [0.5, 0.95] },
  { event: 'baby', w: 1, night: 1.2, level: [50, 80], score: [0.5, 0.95] },
  { event: 'shout', w: 2, night: 0.3, level: [55, 85], score: [0.4, 0.9] },
  { event: 'alarm', w: 0.8, night: 0.6, level: [65, 95], score: [0.5, 0.98] },
  { event: 'car_horn', w: 2.5, night: 0.2, level: [60, 95], score: [0.3, 0.9] },
  { event: 'glass', w: 0.3, night: 0.3, level: [60, 95], score: [0.5, 0.9] },
];
const DIURNAL = [0.15, 0.1, 0.08, 0.08, 0.1, 0.2, 0.45, 0.8, 1.0, 0.95, 0.9, 0.95, 1.0, 0.95, 0.9, 0.9, 0.95, 1.0, 1.0, 0.9, 0.75, 0.6, 0.4, 0.25];

function between(ctx: Ctx, [a, b]: [number, number]) { return a + ctx.random() * (b - a); }
function synthAlert(ctx: Ctx, atMs: bigint, localHour: number) {
  const night = localHour < 7 || localHour >= 23;
  const ws = KINDS.map(k => k.w * (night ? k.night : 1));
  let r = ctx.random() * ws.reduce((a, b) => a + b, 0);
  let k = KINDS[0];
  for (let i = 0; i < KINDS.length; i++) { r -= ws[i]; if (r <= 0) { k = KINDS[i]; break; } }
  recordAlert(ctx, {
    deviceId: SIM_DEVICE, atMs, event: k.event, score: between(ctx, k.score),
    level: between(ctx, k.level), delivered: ctx.random() < 0.95, simulated: true,
  });
}

// ─── Lifecycle ───────────────────────────────────────────────────────────────
export const init = spacetimedb.init(ctx => {
  const bytes = ctx.random.fill(new Uint8Array(18));
  let key = 'sk_';
  for (const b of bytes) key += b.toString(16).padStart(2, '0');
  ctx.db.config.insert({ id: 1, ingestKey: key, retentionDays: 90 });
  ctx.db.simState.insert({ id: 1, enabled: false, phase: 0 });
  ctx.db.simTick.insert({ scheduledId: 0n, scheduledAt: ScheduleAt.interval(1_500_000n) });
  ctx.db.cleanupTimer.insert({ scheduledId: 0n, scheduledAt: ScheduleAt.interval(3_600_000_000n) });
});

// ─── Reducers (for SDK clients; microcontrollers and scripts use HTTP below) ─
export const submitAlert = spacetimedb.reducer({
  key: t.string(), deviceId: t.string(), atMs: t.u64(), event: t.string(), score: t.f32(), level: t.u8(), delivered: t.bool(),
}, (ctx, a) => {
  checkKey(ctx, a.key);
  recordAlert(ctx, { ...a, atMs: resolveAt(ctx, a.atMs), simulated: false });
  touchDevice(ctx, a.deviceId, false, { addEvent: true });
});

export const heartbeat = spacetimedb.reducer({
  key: t.string(), deviceId: t.string(), name: t.string(), level: t.u8(), link: t.string(), wristbandConnected: t.bool(),
}, (ctx, a) => {
  checkKey(ctx, a.key);
  touchDevice(ctx, a.deviceId, false, { name: a.name, level: a.level, link: a.link, wristbandConnected: a.wristbandConnected });
});

export const setSimulation = spacetimedb.reducer({ key: t.string(), enabled: t.bool() }, (ctx, { key, enabled }) => {
  checkKey(ctx, key);
  const s = ctx.db.simState.id.find(1);
  if (s) ctx.db.simState.id.update({ ...s, enabled });
  if (enabled) touchDevice(ctx, SIM_DEVICE, true, { name: 'Demo listener (simulated)', link: 'ble', wristbandConnected: true });
});

export const seedDemo = spacetimedb.reducer({ key: t.string(), days: t.u32(), tzOffsetMin: t.i32() }, (ctx, { key, days, tzOffsetMin }) => {
  checkKey(ctx, key);
  const d = clamp(days, 1, 30);
  const now = nowMs(ctx);
  const startHour = ((now - BigInt(d) * 24n * HOUR) / HOUR) * HOUR;
  touchDevice(ctx, SIM_DEVICE, true, { name: 'Demo listener (simulated)', link: 'ble', wristbandConnected: true });
  for (let h = startHour; h < now; h += HOUR) {
    const localHour = (((Number(h / HOUR) * 60 - tzOffsetMin) / 60) % 24 + 24) % 24;
    const n = Math.round(120 * DIURNAL[Math.floor(localHour)] * (0.8 + ctx.random() * 0.5));
    for (let i = 0; i < n; i++) {
      const at = h + BigInt(Math.floor(ctx.random() * 3_600_000));
      if (at < now) synthAlert(ctx, at, localHour);
    }
  }
});

export const clearSimulated = spacetimedb.reducer({ key: t.string() }, (ctx, { key }) => {
  checkKey(ctx, key);
  for (const e of [...ctx.db.alertEvent.iter()]) if (e.simulated) ctx.db.alertEvent.id.delete(e.id);
  for (const s of [...ctx.db.hourlyStat.iter()]) if (s.simulated) ctx.db.hourlyStat.key.delete(s.key);
  for (const dv of [...ctx.db.device.iter()]) if (dv.simulated) ctx.db.device.deviceId.delete(dv.deviceId);
  const st = ctx.db.simState.id.find(1);
  if (st) ctx.db.simState.id.update({ ...st, enabled: false });
});

// ─── Scheduled work ─────────────────────────────────────────────────────────
export const onSimTick = spacetimedb.reducer({ onSchedule: simTick }, { timer: simTick.rowType }, (ctx, _a) => {
  const s = ctx.db.simState.id.find(1);
  if (!s || !s.enabled) return;
  const phase = s.phase + 0.07;
  ctx.db.simState.id.update({ ...s, phase });
  const level = clamp(Math.round(30 + 10 * Math.sin(phase) + (ctx.random() - 0.5) * 12), 0, 100);
  if (ctx.random() < 0.075) {
    const localHour = ((new Date(Number(nowMs(ctx))).getUTCHours() - 7) % 24 + 24) % 24;
    synthAlert(ctx, nowMs(ctx), localHour);
    touchDevice(ctx, SIM_DEVICE, true, { level: Math.min(100, level + 25), addEvent: true });
  } else {
    touchDevice(ctx, SIM_DEVICE, true, { level });
  }
});

export const onCleanup = spacetimedb.reducer({ onSchedule: cleanupTimer }, { timer: cleanupTimer.rowType }, (ctx, _a) => {
  const c = ctx.db.config.id.find(1);
  const cutoff = nowMs(ctx) - BigInt(c ? c.retentionDays : 90) * 24n * HOUR;
  const old = [...ctx.db.alertEvent.atMs.filter(new Range({ tag: 'included', value: 0n }, { tag: 'excluded', value: cutoff }))];
  for (const e of old) ctx.db.alertEvent.id.delete(e.id);
});

// ─── HTTP ingest: <server>/v1/database/<db>/route/{health,alert,heartbeat} ──
function json(body: unknown, status = 200) {
  return new SyncResponse(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
}
function keyOf(req: { headers: { get(n: string): string | null } }, body: any): string {
  return req.headers.get('x-device-key') || (body && body.key) || '';
}
function num(v: any, d: number) { const n = Number(v); return Number.isFinite(n) ? n : d; }
function fail(err: any) {
  const msg = String((err && err.message) || err);
  return json({ ok: false, error: msg }, msg.includes('device key') ? 401 : 400);
}

export const httpHealth = spacetimedb.httpHandler((_ctx, _req) => json({ ok: true, service: 'fortwatch-analytics' }));

// Body: one alert, or {"deviceId": "...", "alerts": [ ... ]} (max 200; for alerts buffered while offline).
// Alert: {"event": "KNOCK", "score": 0.62, "level": 54, "delivered": true, "atMs": 1730000000000, "deviceId": "..."}
export const httpAlert = spacetimedb.httpHandler((ctx, req) => {
  let body: any;
  try { body = req.json(); } catch { return json({ ok: false, error: 'body must be JSON' }, 400); }
  const list: any[] = Array.isArray(body.alerts) ? body.alerts : [body];
  if (list.length > 200) return json({ ok: false, error: 'max 200 alerts per request' }, 413);
  try {
    const ids = ctx.withTx(tx => {
      checkKey(tx, keyOf(req, body));
      const out: string[] = [];
      for (const a of list) {
        const deviceId = String(a.deviceId || body.deviceId || 'listener-1');
        const row = recordAlert(tx, {
          deviceId,
          atMs: resolveAt(tx, BigInt(Math.max(0, Math.floor(num(a.atMs, 0))))),
          event: String(a.event || ''),
          label: a.label ? String(a.label) : undefined,
          priority: a.priority === undefined ? undefined : num(a.priority, 1),
          score: num(a.score, 0), level: num(a.level, 0), delivered: !!a.delivered, simulated: false,
        });
        touchDevice(tx, deviceId, false, { addEvent: true });
        out.push(String(row.id));
      }
      return out;
    });
    return json({ ok: true, ids });
  } catch (err) { return fail(err); }
});

// Body: {"deviceId": "...", "name": "Pedro's Mac", "level": 37, "link": "ble", "wristbandConnected": true}
export const httpHeartbeat = spacetimedb.httpHandler((ctx, req) => {
  let body: any;
  try { body = req.json(); } catch { return json({ ok: false, error: 'body must be JSON' }, 400); }
  try {
    ctx.withTx(tx => {
      checkKey(tx, keyOf(req, body));
      touchDevice(tx, String(body.deviceId || 'listener-1'), false, {
        name: String(body.name || ''), level: clamp(Math.round(num(body.level, 0)), 0, 100),
        link: String(body.link || ''), wristbandConnected: !!body.wristbandConnected,
      });
    });
    return json({ ok: true });
  } catch (err) { return fail(err); }
});

export const routes = spacetimedb.httpRouter(
  new Router().get('/health', httpHealth).post('/alert', httpAlert).post('/heartbeat', httpHeartbeat)
);
