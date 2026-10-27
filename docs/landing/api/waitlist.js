// POST /api/waitlist — stores a waitlist email in Upstash Redis (Vercel Marketplace).
// Body: { email, locale?, company? }  ("company" is a honeypot: real people leave it empty)
// Redis layout:
//   waitlist:emails   hash  email -> {"at","country","locale"}   (HSETNX: first signup wins)
//   waitlist:by_time  zset  score = signup ms, member = email   (for exporting in order)
//   waitlist:rl:<h>   int   signups from one client in the last hour (h = salted hash, not the IP)
const crypto = require("crypto");

const URL_ = process.env.KV_REST_API_URL || process.env.UPSTASH_REDIS_REST_URL;
const TOKEN = process.env.KV_REST_API_TOKEN || process.env.UPSTASH_REDIS_REST_TOKEN;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const MAX_PER_HOUR = 10;

async function redis(commands) {
  const res = await fetch(`${URL_}/pipeline`, {
    method: "POST",
    headers: { Authorization: `Bearer ${TOKEN}`, "Content-Type": "application/json" },
    body: JSON.stringify(commands),
  });
  if (!res.ok) throw new Error(`Upstash ${res.status}`);
  const out = await res.json();
  const failed = out.find((r) => r.error);
  if (failed) throw new Error(failed.error);
  return out.map((r) => r.result);
}

module.exports = async (req, res) => {
  res.setHeader("Cache-Control", "no-store");
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed." });
  }
  if (!URL_ || !TOKEN) return res.status(500).json({ error: "The waitlist isn't configured yet." });

  let body = req.body;
  if (typeof body === "string") { try { body = JSON.parse(body); } catch { body = {}; } }
  body = body || {};

  if (body.company) return res.status(200).json({ ok: true }); // bot filled the hidden field

  const email = String(body.email || "").trim().toLowerCase();
  if (email.length > 254 || !EMAIL_RE.test(email)) return res.status(400).json({ error: "Please enter a valid email address." });
  const locale = String(body.locale || "").slice(0, 10);
  const country = String(req.headers["x-vercel-ip-country"] || "").slice(0, 2);

  // Rate limit per client without storing the IP: salted hash, expires after an hour.
  const ip = String(req.headers["x-forwarded-for"] || "").split(",")[0].trim() || "unknown";
  const rlKey = "waitlist:rl:" + crypto.createHash("sha256").update(ip + (TOKEN || "")).digest("hex").slice(0, 32);

  try {
    const [count] = await redis([["INCR", rlKey], ["EXPIRE", rlKey, 3600]]);
    if (count > MAX_PER_HOUR) return res.status(429).json({ error: "Too many tries. Please wait a bit and try again." });

    const now = Date.now();
    const record = JSON.stringify({ at: new Date(now).toISOString(), country, locale });
    const [added] = await redis([["HSETNX", "waitlist:emails", email, record], ["ZADD", "waitlist:by_time", "NX", now, email]]);
    return res.status(200).json({ ok: true, already: added === 0 });
  } catch (err) {
    console.error("waitlist error:", err.message);
    return res.status(502).json({ error: "Couldn't save your email. Please try again." });
  }
};
