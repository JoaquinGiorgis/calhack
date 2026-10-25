var __defProp = Object.defineProperty;
var __defNormalProp = (obj, key, value) => key in obj ? __defProp(obj, key, { enumerable: true, configurable: true, writable: true, value }) : obj[key] = value;
var __publicField = (obj, key, value) => __defNormalProp(obj, typeof key !== "symbol" ? key + "" : key, value);

// app.jsx
import React from "react";
import { createRoot } from "react-dom/client";
import * as echarts from "echarts";

// module_bindings/index.ts
import {
  DbConnectionBuilder as __DbConnectionBuilder,
  DbConnectionImpl as __DbConnectionImpl,
  SubscriptionBuilderImpl as __SubscriptionBuilderImpl,
  convertToAccessorMap as __convertToAccessorMap,
  makeQueryBuilder as __makeQueryBuilder,
  procedures as __procedures,
  reducerSchema as __reducerSchema,
  reducers as __reducers,
  schema as __schema,
  table as __table
} from "spacetimedb";

// module_bindings/clear_simulated_reducer.ts
import {
  t as __t
} from "spacetimedb";
var clear_simulated_reducer_default = {
  key: __t.string()
};

// module_bindings/heartbeat_reducer.ts
import {
  t as __t2
} from "spacetimedb";
var heartbeat_reducer_default = {
  key: __t2.string(),
  deviceId: __t2.string(),
  name: __t2.string(),
  level: __t2.u8(),
  link: __t2.string(),
  wristbandConnected: __t2.bool()
};

// module_bindings/seed_demo_reducer.ts
import {
  t as __t3
} from "spacetimedb";
var seed_demo_reducer_default = {
  key: __t3.string(),
  days: __t3.u32(),
  tzOffsetMin: __t3.i32()
};

// module_bindings/set_simulation_reducer.ts
import {
  t as __t4
} from "spacetimedb";
var set_simulation_reducer_default = {
  key: __t4.string(),
  enabled: __t4.bool()
};

// module_bindings/submit_alert_reducer.ts
import {
  t as __t5
} from "spacetimedb";
var submit_alert_reducer_default = {
  key: __t5.string(),
  deviceId: __t5.string(),
  atMs: __t5.u64(),
  event: __t5.string(),
  score: __t5.f32(),
  level: __t5.u8(),
  delivered: __t5.bool()
};

// module_bindings/alert_event_table.ts
import {
  t as __t6
} from "spacetimedb";
var alert_event_table_default = __t6.row({
  id: __t6.u64().primaryKey(),
  deviceId: __t6.string().name("device_id"),
  atMs: __t6.u64().name("at_ms"),
  event: __t6.string(),
  label: __t6.string(),
  priority: __t6.u8(),
  score: __t6.f32(),
  level: __t6.u8(),
  delivered: __t6.bool(),
  simulated: __t6.bool()
});

// module_bindings/device_table.ts
import {
  t as __t7
} from "spacetimedb";
var device_table_default = __t7.row({
  deviceId: __t7.string().primaryKey().name("device_id"),
  name: __t7.string(),
  lastSeenMs: __t7.u64().name("last_seen_ms"),
  level: __t7.u8(),
  link: __t7.string(),
  wristbandConnected: __t7.bool().name("wristband_connected"),
  eventCount: __t7.u64().name("event_count"),
  simulated: __t7.bool()
});

// module_bindings/hourly_stat_table.ts
import {
  t as __t8
} from "spacetimedb";
var hourly_stat_table_default = __t8.row({
  key: __t8.string().primaryKey(),
  hourMs: __t8.u64().name("hour_ms"),
  event: __t8.string(),
  priority: __t8.u8(),
  simulated: __t8.bool(),
  count: __t8.u32(),
  deliveredCount: __t8.u32().name("delivered_count"),
  sumLevel: __t8.f64().name("sum_level"),
  maxLevel: __t8.u8().name("max_level")
});

// module_bindings/sim_state_table.ts
import {
  t as __t9
} from "spacetimedb";
var sim_state_table_default = __t9.row({
  id: __t9.u32().primaryKey(),
  enabled: __t9.bool(),
  phase: __t9.f64()
});

// module_bindings/index.ts
var tablesSchema = __schema({
  alertEvent: __table({
    name: "alert_event",
    indexes: [
      { accessor: "atMs", name: "alert_event_at_ms_idx_btree", algorithm: "btree", columns: [
        "atMs"
      ] },
      { accessor: "deviceId", name: "alert_event_device_id_idx_btree", algorithm: "btree", columns: [
        "deviceId"
      ] },
      { accessor: "id", name: "alert_event_id_idx_btree", algorithm: "btree", columns: [
        "id"
      ] }
    ],
    constraints: [
      { name: "alert_event_id_key", constraint: "unique", columns: ["id"] }
    ]
  }, alert_event_table_default),
  device: __table({
    name: "device",
    indexes: [
      { accessor: "deviceId", name: "device_device_id_idx_btree", algorithm: "btree", columns: [
        "deviceId"
      ] }
    ],
    constraints: [
      { name: "device_device_id_key", constraint: "unique", columns: ["deviceId"] }
    ]
  }, device_table_default),
  hourlyStat: __table({
    name: "hourly_stat",
    indexes: [
      { accessor: "hourMs", name: "hourly_stat_hour_ms_idx_btree", algorithm: "btree", columns: [
        "hourMs"
      ] },
      { accessor: "key", name: "hourly_stat_key_idx_btree", algorithm: "btree", columns: [
        "key"
      ] }
    ],
    constraints: [
      { name: "hourly_stat_key_key", constraint: "unique", columns: ["key"] }
    ]
  }, hourly_stat_table_default),
  simState: __table({
    name: "sim_state",
    indexes: [
      { accessor: "id", name: "sim_state_id_idx_btree", algorithm: "btree", columns: [
        "id"
      ] }
    ],
    constraints: [
      { name: "sim_state_id_key", constraint: "unique", columns: ["id"] }
    ]
  }, sim_state_table_default)
});
var reducersSchema = __reducers(
  __reducerSchema("clear_simulated", clear_simulated_reducer_default),
  __reducerSchema("heartbeat", heartbeat_reducer_default),
  __reducerSchema("seed_demo", seed_demo_reducer_default),
  __reducerSchema("set_simulation", set_simulation_reducer_default),
  __reducerSchema("submit_alert", submit_alert_reducer_default)
);
var proceduresSchema = __procedures();
var REMOTE_MODULE = {
  versionInfo: {
    cliVersion: "2.13.0"
  },
  tables: tablesSchema.schemaType.tables,
  reducers: reducersSchema.reducersType.reducers,
  ...proceduresSchema
};
var tables = __makeQueryBuilder(tablesSchema.schemaType);
var reducers = __convertToAccessorMap(reducersSchema.reducersType.reducers);
var procedures = __convertToAccessorMap(proceduresSchema.procedures);
var SubscriptionBuilder = class extends __SubscriptionBuilderImpl {
};
var DbConnectionBuilder = class extends __DbConnectionBuilder {
};
var _DbConnection = class _DbConnection extends __DbConnectionImpl {
  constructor() {
    super(...arguments);
    /** Creates a new {@link SubscriptionBuilder} to configure a subscription to the remote SpacetimeDB instance. */
    __publicField(this, "subscriptionBuilder", () => {
      return new SubscriptionBuilder(this);
    });
  }
};
/** Creates a new {@link DbConnectionBuilder} to configure and connect to the remote SpacetimeDB instance. */
__publicField(_DbConnection, "builder", () => {
  return new DbConnectionBuilder(REMOTE_MODULE, (config) => new _DbConnection(config));
});
var DbConnection = _DbConnection;

// app.jsx
var RAW_WINDOW_MS = 24 * 36e5;
var ALERTS = {
  alarm: ["Alarm", 3],
  car_horn: ["Car horn", 3],
  glass: ["Glass breaking", 3],
  shout: ["Shout", 3],
  baby: ["Baby crying", 2],
  knock: ["Knock", 2],
  doorbell: ["Doorbell", 2],
  phone: ["Phone ringing", 2],
  dog: ["Dog barking", 1],
  speech: ["Speech", 0]
};
var PRI = {
  3: { label: "Safety", light: "#E8654A", dark: "#F07A60", r: 126 },
  2: { label: "Attention", light: "#C08A2E", dark: "#D9A441", r: 104 },
  1: { label: "Low", light: "#8B8B93", dark: "#A1A1AA", r: 82 },
  0: { label: "Speech", light: "#4F5F80", dark: "#8EA0C4", r: 60 }
};
var PRI_ORDER = [3, 2, 1, 0];
var evLabel = (e) => ALERTS[e] ? ALERTS[e][0] : e.replace(/_/g, " ").replace(/^./, (c) => c.toUpperCase());
var PERIODS = [
  { id: "live", label: "Live", ms: 15 * 6e4, bucket: 3e4, src: "raw" },
  { id: "1h", label: "1H", ms: 36e5, bucket: 6e4, src: "raw" },
  { id: "24h", label: "24H", ms: 24 * 36e5, bucket: 36e5, src: "raw" },
  { id: "7d", label: "7D", ms: 7 * 864e5, bucket: 3 * 36e5, src: "stat" },
  { id: "30d", label: "30D", ms: 30 * 864e5, bucket: 864e5, src: "stat" }
];
var TZ_OFF = -(/* @__PURE__ */ new Date()).getTimezoneOffset() * 6e4;
var alignLocal = (t, b) => Math.floor((t + TZ_OFF) / b) * b - TZ_OFF;
var num = (v) => typeof v === "bigint" ? Number(v) : v;
var DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
function fmtAgo(ms) {
  const s = Math.max(0, Math.round(ms / 1e3));
  if (s < 5) return "now";
  if (s < 60) return s + "s ago";
  if (s < 3600) return Math.floor(s / 60) + "m ago";
  if (s < 86400) return Math.floor(s / 3600) + "h ago";
  return Math.floor(s / 86400) + "d ago";
}
function fmtBucket(t, period) {
  const d = new Date(t);
  if (period.id === "30d") return d.toLocaleDateString(void 0, { month: "short", day: "numeric" });
  if (period.id === "7d") return d.toLocaleDateString(void 0, { weekday: "short" }) + " " + d.toLocaleTimeString(void 0, { hour: "numeric" });
  if (period.id === "24h") return d.toLocaleTimeString(void 0, { hour: "numeric" });
  return d.toLocaleTimeString(void 0, { hour: "numeric", minute: "2-digit", second: period.id === "live" ? "2-digit" : void 0 });
}
function palette(isDark) {
  return {
    isDark,
    ink: isDark ? "#F4F4F5" : "#1C1D19",
    muted: isDark ? "rgba(244,244,245,0.55)" : "rgba(28,29,25,0.52)",
    hair: isDark ? "rgba(244,244,245,0.10)" : "rgba(28,29,25,0.09)",
    soft: isDark ? "rgba(244,244,245,0.05)" : "rgba(28,29,25,0.04)",
    accent: isDark ? "#F07A60" : "#E8654A",
    pri: (p) => PRI[p] ? PRI[p][isDark ? "dark" : "light"] : isDark ? "#A1A1AA" : "#8B8B93",
    mono: "ui-monospace, SFMono-Regular, Menlo, monospace"
  };
}
function useFortWatchData(DbConnection2, wsUrl, dbName) {
  const [status, setStatus] = React.useState("connecting");
  const [err, setErr] = React.useState("");
  const [ver, setVer] = React.useState(0);
  const [attempt, setAttempt] = React.useState(0);
  const connRef = React.useRef(null);
  React.useEffect(() => {
    if (!wsUrl || !DbConnection2) return;
    let disposed = false, pending = false, applied = false;
    const watchdog = setTimeout(() => {
      if (!disposed && !applied) setAttempt((a) => a + 1);
    }, 12e3);
    const bump = () => {
      if (pending) return;
      pending = true;
      setTimeout(() => {
        pending = false;
        if (!disposed) setVer((v) => v + 1);
      }, 250);
    };
    const since = Date.now() - RAW_WINDOW_MS;
    setStatus("connecting");
    setErr("");
    let conn2;
    try {
      conn2 = DbConnection2.builder().withUri(wsUrl.replace(/\/?$/, "/")).withDatabaseName(dbName).onConnect((c) => {
        if (disposed) return;
        setStatus("syncing");
        c.subscriptionBuilder().onApplied(() => {
          applied = true;
          if (!disposed) {
            setStatus("live");
            bump();
          }
        }).onError((ctx) => {
          if (!disposed) {
            setStatus("error");
            setErr(String(ctx && ctx.event && ctx.event.message || "Subscription failed"));
          }
        }).subscribe([`SELECT * FROM alert_event WHERE at_ms > ${since}`, "SELECT * FROM hourly_stat", "SELECT * FROM device", "SELECT * FROM sim_state"]);
      }).onDisconnect(() => {
        if (!disposed) {
          setStatus("offline");
          setTimeout(() => !disposed && setAttempt((a) => a + 1), 3e3);
        }
      }).onConnectError((_c, e) => {
        if (!disposed) {
          setStatus("error");
          setErr(String(e && e.message || e || "Connection failed"));
        }
      }).build();
    } catch (e) {
      setStatus("error");
      setErr(String(e && e.message || e));
      return;
    }
    const t = conn2.db;
    [t.alertEvent, t.hourlyStat, t.device, t.simState].forEach((tbl) => {
      tbl.onInsert(bump);
      tbl.onDelete(bump);
      if (tbl.onUpdate) tbl.onUpdate(bump);
    });
    connRef.current = conn2;
    return () => {
      disposed = true;
      clearTimeout(watchdog);
      connRef.current = null;
      try {
        conn2.disconnect();
      } catch (e) {
      }
    };
  }, [DbConnection2, wsUrl, dbName, attempt]);
  const conn = connRef.current;
  const snap = React.useMemo(() => {
    if (!conn || status !== "live") return null;
    const db = conn.db;
    const alerts = [...db.alertEvent.iter()].map((r) => ({
      id: String(r.id),
      device: r.deviceId,
      t: num(r.atMs),
      event: r.event,
      label: r.label,
      priority: r.priority,
      score: r.score,
      level: r.level,
      delivered: r.delivered,
      sim: r.simulated
    })).sort((a, b) => b.t - a.t);
    const stats = [...db.hourlyStat.iter()].map((s) => ({ hour: num(s.hourMs), event: s.event, priority: s.priority, sim: s.simulated, count: s.count, delivered: s.deliveredCount, sumLevel: s.sumLevel, maxLevel: s.maxLevel }));
    const devices = [...db.device.iter()].map((d) => ({ id: d.deviceId, name: d.name, lastSeen: num(d.lastSeenMs), level: d.level, link: d.link, wristband: d.wristbandConnected, count: num(d.eventCount), sim: d.simulated }));
    const sim = [...db.simState.iter()][0] || null;
    return { alerts, stats, devices, sim };
  }, [conn, status, ver]);
  return { conn, status, err, snap };
}
function EChart({ option, height }) {
  const ref = React.useRef(null);
  const chart = React.useRef(null);
  React.useEffect(() => {
    if (!ref.current) return;
    chart.current = echarts.init(ref.current, null, { renderer: "svg" });
    const ro = new ResizeObserver(() => chart.current && chart.current.resize());
    ro.observe(ref.current);
    return () => {
      ro.disconnect();
      chart.current && chart.current.dispose();
      chart.current = null;
    };
  }, []);
  React.useEffect(() => {
    if (chart.current && option) chart.current.setOption(option, { notMerge: true, lazyUpdate: true });
  }, [option]);
  return /* @__PURE__ */ React.createElement("div", { ref, style: { width: "100%", height } });
}
function LiveRing({ alerts, device, online, P }) {
  const [now, setNow] = React.useState(Date.now());
  React.useEffect(() => {
    const i = setInterval(() => setNow(Date.now()), 1e3);
    return () => clearInterval(i);
  }, []);
  const WINDOW = 18e4;
  const recent = alerts.filter((a) => now - a.t < WINDOW && now - a.t >= 0);
  const level = online && device ? device.level : 0;
  const core = 16 + level / 100 * 26;
  const tick = (deg, label) => {
    const a = deg * Math.PI / 180;
    return /* @__PURE__ */ React.createElement("g", { key: deg }, /* @__PURE__ */ React.createElement("line", { x1: 136 * Math.sin(a), y1: -136 * Math.cos(a), x2: 142 * Math.sin(a), y2: -142 * Math.cos(a), stroke: P.muted, strokeWidth: "1" }), /* @__PURE__ */ React.createElement("text", { x: 152 * Math.sin(a), y: -152 * Math.cos(a) + 3, textAnchor: "middle", fontSize: "9", fill: P.muted }, label));
  };
  return /* @__PURE__ */ React.createElement("div", { className: "w-full flex flex-col items-center" }, /* @__PURE__ */ React.createElement("svg", { viewBox: "-165 -165 330 330", style: { width: "100%", maxWidth: 330, overflow: "visible" }, role: "img", "aria-label": "Alerts in the last three minutes" }, PRI_ORDER.map((p) => /* @__PURE__ */ React.createElement("circle", { key: p, r: PRI[p].r, fill: "none", stroke: P.hair, strokeWidth: "1" })), tick(0, "now"), tick(120, "1 min"), tick(240, "2 min"), /* @__PURE__ */ React.createElement("line", { x1: "0", y1: "-20", x2: "0", y2: "-134", stroke: P.ink, strokeOpacity: "0.18", strokeWidth: "1" }), /* @__PURE__ */ React.createElement("circle", { r: core, fill: P.isDark ? "rgba(244,244,245,0.07)" : "rgba(28,29,25,0.06)", style: { transition: "r 600ms ease" } }), /* @__PURE__ */ React.createElement("text", { y: "5", textAnchor: "middle", fontSize: "15", fill: P.ink, style: { fontVariantNumeric: "tabular-nums", fontWeight: 400 } }, online ? level : "\u2014"), recent.map((a) => {
    const age = (now - a.t) / WINDOW;
    const ang = age * 2 * Math.PI;
    const r = (PRI[a.priority] || PRI[1]).r;
    const x = r * Math.sin(ang), y = -r * Math.cos(ang);
    const col = P.pri(a.priority);
    const size = a.priority === 3 ? 6 : a.priority === 2 ? 5 : 4;
    const fresh = now - a.t < 6e3;
    return /* @__PURE__ */ React.createElement("g", { key: a.id, transform: `translate(${x.toFixed(1)} ${y.toFixed(1)})`, style: { transition: "transform 1s linear" } }, fresh && /* @__PURE__ */ React.createElement("circle", { r: size, fill: "none", stroke: col, strokeWidth: "1.5", className: "fw-ripple" }), /* @__PURE__ */ React.createElement("circle", { r: size, fill: a.delivered ? col : "none", stroke: col, strokeWidth: a.delivered ? 0 : 1.5, opacity: Math.max(0.25, 1 - age * 0.75) }), fresh && /* @__PURE__ */ React.createElement("text", { x: size + 6, y: "4", fontSize: "11", fill: P.ink, style: { fontWeight: 500 } }, a.label));
  })), /* @__PURE__ */ React.createElement("div", { className: "mt-1 text-center", style: { fontSize: 11, color: P.muted, lineHeight: 1.6 } }, /* @__PURE__ */ React.createElement("div", null, "mic level 0\u2013100 \xB7 ", recent.length ? `${recent.length} alert${recent.length > 1 ? "s" : ""} in the last 3 min` : "quiet for 3 min"), /* @__PURE__ */ React.createElement("div", null, !device ? "No listener connected yet" : !online ? `${device.name} \xB7 offline` : device.wristband ? `Wristband connected over ${device.link === "usb" ? "USB" : "Bluetooth"}` : "Wristband not connected")));
}
function Dashboard({ data, P, headerRight, below }) {
  const { status, err, snap } = data;
  const [periodId, setPeriodId] = React.useState("24h");
  const [showSim, setShowSim] = React.useState(true);
  const [deviceFilter, setDeviceFilter] = React.useState("all");
  const [now, setNow] = React.useState(Date.now());
  React.useEffect(() => {
    const i = setInterval(() => setNow(Date.now()), 2e3);
    return () => clearInterval(i);
  }, []);
  const period = PERIODS.find((p) => p.id === periodId);
  const statusLabel = { connecting: "Connecting to SpacetimeDB\u2026", syncing: "Syncing\u2026", live: "Live", offline: "Reconnecting\u2026", error: "Connection error" }[status];
  const view = React.useMemo(() => {
    if (!snap) return null;
    const from = now - period.ms;
    const all = snap.alerts.filter((a) => (showSim || !a.sim) && (deviceFilter === "all" || a.device === deviceFilter));
    const inWin = all.filter((a) => a.t >= from);
    const useStats = period.src === "stat" && deviceFilter === "all";
    const statsWin = snap.stats.filter((s) => (showSim || !s.sim) && s.hour + 36e5 > from);
    const hasSim = snap.alerts.some((a) => a.sim) || snap.stats.some((s) => s.sim) || snap.devices.some((d) => d.sim);
    let alertsN = 0, safety = 0, speech = 0, delivered = 0, sumLevel = 0, total = 0, peak = 0;
    const byEvent = {};
    const add = (ev, pri, count, del, lvlSum, lvlMax) => {
      total += count;
      sumLevel += lvlSum;
      peak = Math.max(peak, lvlMax);
      if (pri === 0) speech += count;
      else {
        alertsN += count;
        delivered += del;
      }
      if (pri === 3) safety += count;
      byEvent[ev] = byEvent[ev] || { count: 0, pri };
      byEvent[ev].count += count;
    };
    if (useStats) statsWin.forEach((s) => add(s.event, s.priority, s.count, s.priority === 0 ? 0 : s.delivered, s.sumLevel, s.maxLevel));
    else inWin.forEach((a) => add(a.event, a.priority, 1, a.delivered ? 1 : 0, a.level, a.level));
    const events = Object.entries(byEvent).sort((a, b) => b[1].pri - a[1].pri || b[1].count - a[1].count);
    const start = alignLocal(from, period.bucket);
    const nb = Math.ceil((now - start) / period.bucket);
    const buckets = Array.from({ length: nb }, (_, i) => ({ t: start + i * period.bucket, 3: 0, 2: 0, 1: 0, 0: 0, lvl: 0, c: 0 }));
    const put = (t, pri, count, lvlSum) => {
      const i = Math.floor((t - start) / period.bucket);
      if (i < 0 || i >= nb) return;
      buckets[i][pri in PRI ? pri : 1] += count;
      buckets[i].lvl += lvlSum;
      buckets[i].c += count;
    };
    if (useStats) statsWin.forEach((s) => put(s.hour, s.priority, s.count, s.sumLevel));
    else inWin.forEach((a) => put(a.t, a.priority, 1, a.level));
    const hmFrom = now - (periodId === "30d" ? 30 : 7) * 864e5;
    const hm = Array.from({ length: 7 }, () => Array(24).fill(0));
    snap.stats.forEach((s) => {
      if ((showSim || !s.sim) && s.hour >= hmFrom && s.priority > 0) {
        const d = new Date(s.hour);
        hm[(d.getDay() + 6) % 7][d.getHours()] += s.count;
      }
    });
    return { all, alertsN, safety, speech, delivered, avgLevel: total ? sumLevel / total : 0, peak, total, events, buckets, hm, hasSim };
  }, [snap, now, periodId, showSim, deviceFilter]);
  const timelineOption = React.useMemo(() => {
    if (!view) return null;
    return {
      animation: false,
      grid: { left: 36, right: 36, top: 16, bottom: 28 },
      tooltip: { trigger: "axis", backgroundColor: P.isDark ? "#18181b" : "#fff", borderColor: P.hair, textStyle: { color: P.ink, fontSize: 12 }, axisPointer: { type: "shadow", shadowStyle: { color: P.soft } } },
      xAxis: { type: "category", data: view.buckets.map((b) => fmtBucket(b.t, period)), axisLine: { lineStyle: { color: P.hair } }, axisTick: { show: false }, axisLabel: { color: P.muted, fontSize: 10, hideOverlap: true } },
      yAxis: [
        { type: "value", minInterval: 1, splitLine: { lineStyle: { color: P.hair } }, axisLabel: { color: P.muted, fontSize: 10 } },
        { type: "value", min: 0, max: 100, splitLine: { show: false }, axisLabel: { color: P.muted, fontSize: 10 } }
      ],
      series: [
        ...PRI_ORDER.map((p, i) => ({ name: PRI[p].label, type: "bar", stack: "n", barCategoryGap: "28%", itemStyle: { color: P.pri(p), borderRadius: i === PRI_ORDER.length - 1 ? [2, 2, 0, 0] : 0 }, data: view.buckets.map((b) => b[p]) })),
        { name: "Avg mic level", type: "line", yAxisIndex: 1, smooth: true, symbol: "none", connectNulls: true, lineStyle: { width: 1.5, color: P.ink, opacity: 0.5 }, data: view.buckets.map((b) => b.c ? +(b.lvl / b.c).toFixed(1) : null) }
      ]
    };
  }, [view, P.isDark]);
  const heatOption = React.useMemo(() => {
    if (!view) return null;
    const d = [];
    let max = 1;
    view.hm.forEach((row, y) => row.forEach((v, x) => {
      d.push([x, y, v]);
      max = Math.max(max, v);
    }));
    return {
      animation: false,
      grid: { left: 34, right: 8, top: 6, bottom: 22 },
      tooltip: { formatter: (p) => `${DAYS[p.value[1]]} ${p.value[0]}:00 \xB7 ${p.value[2]} alerts`, backgroundColor: P.isDark ? "#18181b" : "#fff", borderColor: P.hair, textStyle: { color: P.ink, fontSize: 12 } },
      xAxis: { type: "category", data: Array.from({ length: 24 }, (_, h) => h % 6 === 0 ? `${h}:00` : ""), axisLine: { show: false }, axisTick: { show: false }, axisLabel: { color: P.muted, fontSize: 10, interval: 0 } },
      yAxis: { type: "category", inverse: true, data: DAYS, axisLine: { show: false }, axisTick: { show: false }, axisLabel: { color: P.muted, fontSize: 10 } },
      visualMap: { show: false, min: 0, max, inRange: { color: [P.isDark ? "#1f1f22" : "#F4F4F2", P.accent] } },
      series: [{ type: "heatmap", data: d, itemStyle: { borderColor: P.isDark ? "#09090b" : "#fff", borderWidth: 2, borderRadius: 3 } }]
    };
  }, [view, P.isDark]);
  const devices = snap ? snap.devices.filter((d) => showSim || !d.sim) : [];
  const liveDevice = devices.slice().sort((a, b) => b.lastSeen - a.lastSeen)[0];
  const online = (d) => !!d && now - d.lastSeen < 3e4;
  const card = { border: `1px solid ${P.hair}`, borderRadius: 14 };
  const h2 = { fontSize: 12, color: P.muted, letterSpacing: "0.04em" };
  const pct = view && view.alertsN ? Math.round(view.delivered / view.alertsN * 100) + "%" : "\u2014";
  return /* @__PURE__ */ React.createElement("div", { className: "w-full", style: { color: P.ink } }, /* @__PURE__ */ React.createElement("style", null, `
        @keyframes fw-rip { from { r: 4px; opacity: .9 } to { r: 24px; opacity: 0 } }
        .fw-ripple { animation: fw-rip 1.6s ease-out infinite; }
        @media (prefers-reduced-motion: reduce) { .fw-ripple { animation: none } }
      `), /* @__PURE__ */ React.createElement("div", { className: "w-full max-w-[1180px] mx-auto px-4 sm:px-6 py-6 flex flex-col gap-5" }, /* @__PURE__ */ React.createElement("div", { className: "flex flex-wrap items-end gap-x-6 gap-y-3" }, /* @__PURE__ */ React.createElement("div", { className: "min-w-0" }, /* @__PURE__ */ React.createElement("div", { style: { fontSize: 26, fontWeight: 400, letterSpacing: "-0.02em", lineHeight: 1.1 } }, "FortWatch analytics"), /* @__PURE__ */ React.createElement("div", { className: "mt-1.5 flex flex-wrap items-center gap-2", style: { fontSize: 12, color: P.muted } }, /* @__PURE__ */ React.createElement("span", { style: { width: 7, height: 7, borderRadius: 99, background: status === "live" ? P.ink : "transparent", border: `1.5px solid ${status === "error" ? P.accent : P.ink}`, display: "inline-block", opacity: status === "live" ? 1 : 0.6 } }), /* @__PURE__ */ React.createElement("span", null, statusLabel), /* @__PURE__ */ React.createElement("span", null, "\xB7"), /* @__PURE__ */ React.createElement("span", null, "SpacetimeDB realtime subscription"), snap && snap.sim && snap.sim.enabled && /* @__PURE__ */ React.createElement(React.Fragment, null, /* @__PURE__ */ React.createElement("span", null, "\xB7"), /* @__PURE__ */ React.createElement("span", null, "simulation running")))), /* @__PURE__ */ React.createElement("div", { className: "flex-1" }), /* @__PURE__ */ React.createElement("div", { className: "flex flex-wrap items-center gap-2" }, snap && snap.devices.length > 1 && /* @__PURE__ */ React.createElement("select", { value: deviceFilter, onChange: (e) => setDeviceFilter(e.target.value), className: "rounded-full px-3 py-1.5 bg-transparent", style: { fontSize: 12, color: P.ink, border: `1px solid ${P.hair}` } }, /* @__PURE__ */ React.createElement("option", { value: "all" }, "All listeners"), snap.devices.map((d) => /* @__PURE__ */ React.createElement("option", { key: d.id, value: d.id }, d.name))), /* @__PURE__ */ React.createElement("div", { className: "flex items-center rounded-full p-0.5", style: { border: `1px solid ${P.hair}` }, role: "tablist", "aria-label": "Time period" }, PERIODS.map((p) => /* @__PURE__ */ React.createElement("button", { key: p.id, role: "tab", "aria-selected": p.id === periodId, onClick: () => setPeriodId(p.id), className: "rounded-full px-3 py-1", style: { fontSize: 12, color: p.id === periodId ? P.isDark ? "#09090b" : "#fff" : P.muted, background: p.id === periodId ? P.ink : "transparent", transition: "background 160ms" } }, p.label))), headerRight)), below, view && view.hasSim && /* @__PURE__ */ React.createElement("div", { className: "flex flex-wrap items-center gap-2", style: { fontSize: 12, color: P.muted } }, /* @__PURE__ */ React.createElement("span", null, showSim ? "Includes simulated demo data." : "Simulated demo data hidden."), /* @__PURE__ */ React.createElement("button", { onClick: () => setShowSim((s) => !s), className: "underline underline-offset-2", style: { color: P.ink } }, showSim ? "Show real data only" : "Show simulated too")), status === "error" && /* @__PURE__ */ React.createElement("div", { className: "w-full p-4", style: { ...card, fontSize: 13 } }, /* @__PURE__ */ React.createElement("div", null, "Can\u2019t reach the SpacetimeDB server."), /* @__PURE__ */ React.createElement("div", { style: { color: P.muted, marginTop: 4, fontSize: 12 } }, err)), !view && status !== "error" && /* @__PURE__ */ React.createElement("div", { className: "w-full py-24 text-center", style: { fontSize: 13, color: P.muted } }, statusLabel), view && /* @__PURE__ */ React.createElement(React.Fragment, null, /* @__PURE__ */ React.createElement("div", { className: "w-full flex flex-wrap gap-5" }, /* @__PURE__ */ React.createElement("div", { className: "p-5 flex flex-col min-w-0", style: { ...card, flex: "1 1 300px" } }, /* @__PURE__ */ React.createElement("div", { className: "flex items-center justify-between mb-2" }, /* @__PURE__ */ React.createElement("span", { style: h2 }, "LAST 3 MINUTES"), /* @__PURE__ */ React.createElement("span", { style: { fontSize: 11, color: P.muted } }, liveDevice ? liveDevice.name : "")), /* @__PURE__ */ React.createElement("div", { className: "flex-1 flex items-center justify-center" }, /* @__PURE__ */ React.createElement(LiveRing, { alerts: view.all, device: liveDevice, online: online(liveDevice), P }))), /* @__PURE__ */ React.createElement("div", { className: "p-5 flex flex-col gap-4 min-w-0", style: { ...card, flex: "2 1 440px" } }, /* @__PURE__ */ React.createElement("div", { className: "grid gap-4", style: { gridTemplateColumns: "repeat(auto-fit, minmax(104px, 1fr))" } }, [
    ["Alerts", view.alertsN.toLocaleString(), "excluding speech"],
    ["Safety", view.safety.toLocaleString(), "alarm, horn, glass, shout", view.safety > 0],
    ["Reached wristband", pct, "wristband was connected"],
    ["Speech", view.speech.toLocaleString(), "moments detected"],
    ["Peak mic level", view.total ? String(view.peak) : "\u2014", "of 100"]
  ].map(([l, v, hint, hot]) => /* @__PURE__ */ React.createElement("div", { key: l, className: "min-w-0", title: hint }, /* @__PURE__ */ React.createElement("div", { style: { fontSize: 11, color: P.muted } }, l), /* @__PURE__ */ React.createElement("div", { style: { fontSize: 26, fontWeight: 300, letterSpacing: "-0.02em", fontVariantNumeric: "tabular-nums", color: hot ? P.accent : P.ink } }, v)))), /* @__PURE__ */ React.createElement("div", { className: "flex flex-wrap items-center gap-x-4 gap-y-1", style: { fontSize: 11, color: P.muted } }, PRI_ORDER.map((p) => /* @__PURE__ */ React.createElement("span", { key: p, className: "flex items-center gap-1.5" }, /* @__PURE__ */ React.createElement("span", { style: { width: 8, height: 8, borderRadius: 2, background: P.pri(p), display: "inline-block" } }), PRI[p].label)), /* @__PURE__ */ React.createElement("span", { className: "flex items-center gap-1.5" }, /* @__PURE__ */ React.createElement("span", { style: { width: 12, height: 1.5, background: P.ink, opacity: 0.5, display: "inline-block" } }), "Avg mic level (right axis)")), /* @__PURE__ */ React.createElement(EChart, { option: timelineOption, height: 240 }))), /* @__PURE__ */ React.createElement("div", { className: "w-full grid gap-5", style: { gridTemplateColumns: "repeat(auto-fit, minmax(320px, 1fr))" } }, /* @__PURE__ */ React.createElement("div", { className: "p-5", style: card }, /* @__PURE__ */ React.createElement("div", { className: "mb-4", style: h2 }, "WHAT WAS HEARD \xB7 ", period.id === "live" ? "LAST 15 MIN" : period.label), view.events.length === 0 && /* @__PURE__ */ React.createElement("div", { style: { fontSize: 13, color: P.muted } }, "Nothing in this period."), /* @__PURE__ */ React.createElement("div", { className: "flex flex-col gap-2.5" }, view.events.map(([ev, v]) => {
    const max = Math.max(...view.events.map((x) => x[1].count));
    return /* @__PURE__ */ React.createElement("div", { key: ev, className: "flex items-center gap-3", style: { fontSize: 12 } }, /* @__PURE__ */ React.createElement("div", { className: "w-28 shrink-0 truncate" }, evLabel(ev)), /* @__PURE__ */ React.createElement("div", { className: "flex-1 h-2 rounded-full overflow-hidden", style: { background: P.soft } }, /* @__PURE__ */ React.createElement("div", { className: "h-full rounded-full", style: { width: `${v.count / max * 100}%`, background: P.pri(v.pri), transition: "width 400ms ease" } })), /* @__PURE__ */ React.createElement("div", { className: "w-12 text-right shrink-0", style: { color: P.muted, fontVariantNumeric: "tabular-nums" } }, v.count.toLocaleString()));
  }))), /* @__PURE__ */ React.createElement("div", { className: "p-5", style: card }, /* @__PURE__ */ React.createElement("div", { className: "mb-2", style: h2 }, "WEEKLY RHYTHM \xB7 ALERTS \xB7 ", periodId === "30d" ? "LAST 30 DAYS" : "LAST 7 DAYS"), /* @__PURE__ */ React.createElement(EChart, { option: heatOption, height: 210 }))), /* @__PURE__ */ React.createElement("div", { className: "w-full flex flex-wrap gap-5" }, /* @__PURE__ */ React.createElement("div", { className: "p-5 min-w-0", style: { ...card, flex: "2 1 440px" } }, /* @__PURE__ */ React.createElement("div", { className: "mb-3", style: h2 }, "LATEST ALERTS"), view.all.length === 0 && /* @__PURE__ */ React.createElement("div", { style: { fontSize: 13, color: P.muted } }, "No alerts in the last 24 hours."), /* @__PURE__ */ React.createElement("div", { className: "flex flex-col" }, view.all.slice(0, 14).map((a, i) => /* @__PURE__ */ React.createElement("div", { key: a.id, className: "flex items-center gap-3 py-2.5", style: { borderTop: i ? `1px solid ${P.hair}` : "none" } }, /* @__PURE__ */ React.createElement("span", { className: "shrink-0", style: { width: 8, height: 8, borderRadius: 99, background: P.pri(a.priority) } }), /* @__PURE__ */ React.createElement("div", { className: "flex-1 min-w-0 flex flex-wrap items-baseline gap-x-2", style: { fontSize: 13 } }, /* @__PURE__ */ React.createElement("span", { style: { fontWeight: a.priority === 3 ? 600 : 400 } }, a.label), /* @__PURE__ */ React.createElement("span", { style: { fontSize: 11, color: P.muted } }, (PRI[a.priority] || PRI[1]).label.toLowerCase()), !a.delivered && a.priority > 0 && /* @__PURE__ */ React.createElement("span", { style: { fontSize: 11, color: P.accent } }, "wristband not connected"), a.sim && /* @__PURE__ */ React.createElement("span", { style: { fontSize: 11, color: P.muted } }, "\xB7 simulated")), /* @__PURE__ */ React.createElement("div", { className: "shrink-0 text-right", style: { fontSize: 11, color: P.muted, fontVariantNumeric: "tabular-nums" } }, /* @__PURE__ */ React.createElement("div", null, fmtAgo(now - a.t)), /* @__PURE__ */ React.createElement("div", null, "score ", Math.round(a.score * 100), " \xB7 level ", a.level)))))), /* @__PURE__ */ React.createElement("div", { className: "p-5 min-w-0", style: { ...card, flex: "1 1 280px" } }, /* @__PURE__ */ React.createElement("div", { className: "mb-3", style: h2 }, "LISTENERS"), devices.length === 0 && /* @__PURE__ */ React.createElement("div", { style: { fontSize: 13, color: P.muted, lineHeight: 1.5 } }, "No listener has reported yet. Run mac_listener.py with analytics turned on."), /* @__PURE__ */ React.createElement("div", { className: "flex flex-col gap-4" }, devices.map((d) => /* @__PURE__ */ React.createElement("div", { key: d.id, className: "flex flex-col gap-1.5" }, /* @__PURE__ */ React.createElement("div", { className: "flex items-center gap-2", style: { fontSize: 13 } }, /* @__PURE__ */ React.createElement("span", { style: { width: 7, height: 7, borderRadius: 99, display: "inline-block", background: online(d) ? P.ink : "transparent", border: `1.5px solid ${P.ink}`, opacity: online(d) ? 1 : 0.5 } }), /* @__PURE__ */ React.createElement("span", { className: "truncate" }, d.name), /* @__PURE__ */ React.createElement("span", { className: "ml-auto shrink-0", style: { fontSize: 11, color: P.muted } }, online(d) ? "online" : "seen " + fmtAgo(now - d.lastSeen))), /* @__PURE__ */ React.createElement("div", { className: "h-1.5 rounded-full overflow-hidden", style: { background: P.soft }, title: "Mic level, 0\u2013100" }, /* @__PURE__ */ React.createElement("div", { className: "h-full rounded-full", style: { width: `${d.level}%`, background: P.ink, opacity: online(d) ? 0.75 : 0.25, transition: "width 600ms ease" } })), /* @__PURE__ */ React.createElement("div", { className: "flex flex-wrap gap-x-3", style: { fontSize: 11, color: P.muted, fontVariantNumeric: "tabular-nums" } }, /* @__PURE__ */ React.createElement("span", null, "level ", d.level), /* @__PURE__ */ React.createElement("span", null, d.link ? `link ${d.link}` : "link unknown", d.link && d.link !== "none" ? d.wristband ? " \xB7 wristband connected" : " \xB7 wristband not connected" : ""), /* @__PURE__ */ React.createElement("span", null, d.count.toLocaleString(), " alerts"))))))))));
}
function toWs(server) {
  const s = server.trim().replace(/\/+$/, "");
  if (s.startsWith("https://")) return "wss://" + s.slice(8);
  if (s.startsWith("http://")) return "ws://" + s.slice(7);
  return s;
}
function usePrefersDark() {
  const q = window.matchMedia("(prefers-color-scheme: dark)");
  const [dark, setDark] = React.useState(q.matches);
  React.useEffect(() => {
    const f = (e) => setDark(e.matches);
    q.addEventListener("change", f);
    return () => q.removeEventListener("change", f);
  }, []);
  return dark;
}
function App() {
  const params = new URLSearchParams(window.location.search);
  const [server, setServer] = React.useState(params.get("server") || localStorage.getItem("fortwatch.server") || "");
  const [draft, setDraft] = React.useState(server);
  const db = params.get("db") || "fortwatch";
  const P = palette(usePrefersDark());
  React.useEffect(() => {
    document.body.style.background = P.isDark ? "#09090b" : "#ffffff";
  }, [P.isDark]);
  const data = useFortWatchData(DbConnection, server ? toWs(server) : null, db);
  if (!server) {
    return /* @__PURE__ */ React.createElement("form", { className: "max-w-md mx-auto mt-24 px-6 flex flex-col gap-3", style: { color: P.ink }, onSubmit: (e) => {
      e.preventDefault();
      localStorage.setItem("fortwatch.server", draft.trim());
      setServer(draft.trim());
    } }, /* @__PURE__ */ React.createElement("div", { style: { fontSize: 22 } }, "FortWatch analytics"), /* @__PURE__ */ React.createElement("label", { style: { fontSize: 13, color: P.muted }, htmlFor: "server" }, "SpacetimeDB server, e.g. http://localhost:3000 or https://maincloud.spacetimedb.com"), /* @__PURE__ */ React.createElement("input", { id: "server", value: draft, onChange: (e) => setDraft(e.target.value), className: "rounded-lg px-3 py-2 bg-transparent", style: { border: `1px solid ${P.hair}`, fontSize: 13 }, placeholder: "http://localhost:3000" }), /* @__PURE__ */ React.createElement("button", { className: "rounded-full px-4 py-2 self-start", style: { background: P.ink, color: P.isDark ? "#09090b" : "#fff", fontSize: 13 } }, "Connect"));
  }
  return /* @__PURE__ */ React.createElement(
    Dashboard,
    {
      data,
      P,
      headerRight: /* @__PURE__ */ React.createElement("button", { onClick: () => {
        localStorage.removeItem("fortwatch.server");
        setServer("");
        window.history.replaceState({}, "", window.location.pathname);
      }, className: "rounded-full px-3.5 py-1.5", style: { fontSize: 12, color: P.ink, border: `1px solid ${P.hair}` } }, "Change server")
    }
  );
}
createRoot(document.getElementById("root")).render(/* @__PURE__ */ React.createElement(App, null));
