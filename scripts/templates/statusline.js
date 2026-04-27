// Claude Code status line script (Windows / Node.js)
// Reads JSON from stdin, outputs formatted multi-line status bar with ANSI colors.
const { execSync } = require("child_process");
const os = require("os");

// ANSI color codes
const C = {
  cyan: "\x1b[36m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  magenta: "\x1b[35m",
  blue: "\x1b[34m",
  white: "\x1b[97m",
  red: "\x1b[31m",
  bold: "\x1b[1m",
  r: "\x1b[0m",
};

function getGitBranch(cwd) {
  try {
    return execSync("git rev-parse --abbrev-ref HEAD", {
      cwd,
      encoding: "utf8",
      stdio: ["pipe", "pipe", "ignore"],
    }).trim();
  } catch {
    return "?";
  }
}

function progressBar(pct, width = 10) {
  const filled = Math.round((pct / 100) * width);
  const empty = width - filled;
  // Green for filled, dim gray for empty
  let color = C.green;
  if (pct >= 80) color = C.red;
  else if (pct >= 50) color = C.yellow;
  return color + "\u25b0".repeat(filled) + C.cyan + "\u25b1".repeat(empty) + C.r;
}

function formatDuration(ms) {
  const totalSec = Math.floor(ms / 1000);
  const hours = Math.floor(totalSec / 3600);
  const minutes = Math.floor((totalSec % 3600) / 60);
  if (hours > 0) return `${hours}h ${String(minutes).padStart(2, "0")}m`;
  return `${minutes}m`;
}

function formatResetTime(epoch) {
  if (!epoch) return "";
  const dt = new Date(epoch * 1000);
  const now = new Date();
  const timeStr = dt
    .toLocaleString("en-US", {
      hour: "numeric",
      hour12: true,
      timeZone: "Asia/Tokyo",
    })
    .toLowerCase();
  const sameDay =
    dt.toLocaleDateString("en-US", { timeZone: "Asia/Tokyo" }) ===
    now.toLocaleDateString("en-US", { timeZone: "Asia/Tokyo" });
  if (sameDay) return `Resets ${timeStr} (Asia/Tokyo)`;
  const dateStr = dt.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    timeZone: "Asia/Tokyo",
  });
  return `Resets ${dateStr} at ${timeStr} (Asia/Tokyo)`;
}

let raw = "";
process.stdin.on("data", (chunk) => (raw += chunk));
process.stdin.on("end", () => {
  if (!raw.trim()) return;

  let data;
  try {
    data = JSON.parse(raw);
  } catch {
    return;
  }

  const model = data.model || {};
  const modelName = model.display_name || model.id || "?";

  const cwd = data.cwd || "";
  const project = cwd ? require("path").basename(cwd) : "?";

  const branch = getGitBranch(cwd || ".");
  const osName = os.platform() === "win32" ? "Windows" : os.platform();

  const ctx = data.context_window || {};
  const ctxPct = ctx.used_percentage || 0;

  const cost = data.cost || {};
  const linesAdded = cost.total_lines_added || 0;
  const linesRemoved = cost.total_lines_removed || 0;
  const durationMs = cost.total_duration_ms || 0;

  const rateLimits = data.rate_limits || {};
  const fiveHour = rateLimits.five_hour || {};
  const sevenDay = rateLimits.seven_day || {};

  const sep = ` ${C.blue}\u2502${C.r} `;

  // Line 1: Model / Project / Branch / OS
  const line1 = [
    `${C.magenta}\ud83e\udd16 ${C.bold}${modelName}${C.r}`,
    `${C.yellow}\ud83d\udcc1 ${project}${C.r}`,
    `${C.green}\ud83c\udf3f ${branch}${C.r}`,
    `${C.cyan}\ud83d\udda5  ${osName}${C.r}`,
  ].join(sep);
  console.log(line1);

  // Line 2: Context % / File changes / Duration
  const ctxBar = progressBar(ctxPct);
  const line2Parts = [
    `${C.blue}\ud83d\udcca ${C.white}${Math.round(ctxPct)}%${C.r} ${ctxBar}`,
    `${C.cyan}\u270f\ufe0f  ${C.green}+${linesAdded}${C.r}/${C.red}-${linesRemoved}${C.r}`,
  ];
  if (durationMs > 0)
    line2Parts.push(`${C.blue}\u23f1  ${C.white}${formatDuration(durationMs)}${C.r}`);
  console.log(line2Parts.join(sep));

  // Line 3: 5-hour rate limit (Pro/Max only)
  const fivePct = fiveHour.used_percentage;
  if (fivePct != null) {
    const fiveBar = progressBar(fivePct);
    const fiveReset = formatResetTime(fiveHour.resets_at);
    console.log(
      `${C.blue}\u23f1  5h${C.r}  ${fiveBar}  ${C.white}${Math.round(fivePct)}%${C.r}     ${C.cyan}${fiveReset}${C.r}`
    );
  }

  // Line 4: 7-day rate limit (Pro/Max only)
  const sevenPct = sevenDay.used_percentage;
  if (sevenPct != null) {
    const sevenBar = progressBar(sevenPct);
    const sevenReset = formatResetTime(sevenDay.resets_at);
    console.log(
      `${C.blue}\ud83d\udcc5 7d${C.r}  ${sevenBar}  ${C.white}${Math.round(sevenPct)}%${C.r}  ${C.cyan}\u5168\u30e2\u30c7\u30eb${C.r}     ${C.cyan}${sevenReset}${C.r}`
    );
  }
});
