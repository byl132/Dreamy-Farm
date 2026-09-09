#!/usr/bin/env node
// ============================================================
// tests/gate/static-gate.cjs
// 梦境农场 QA · 静态质量门（CI 可直接跑，无需 Lua 运行时）
// ------------------------------------------------------------
// 作用：
//   1) luaparse 语法检查 scripts/ 与 tests/ 下所有 .lua
//   2) 反模式护栏（来自 Phase 6 入场 QA 评估 §9 + 避雷清单）：
//      A. 模块级 _ctx 裸访问（仅 InteriorPanels 允许）
//      B. 经济双数据源回潮（game.money / GameState.game.money 代码级）
//      C. HasBlockingGameplayOverlay 重新引入 UI.GetTopOverlay 兜底
//      D. 直接 clientCloud:Get/Set（应全经 CloudOpQueue）
//      E. [信息/决策项] GameFlow 联机初始化方向（RS-11 vs N1 冲突）
//      F. [警告] 静默 pcall 无日志（heuristic）
// 退出码：出现 FAIL → 1；仅警告/信息 → 0。
// 用法：node tests/gate/static-gate.cjs
// ============================================================
const fs = require("fs");
const path = require("path");
const luaparse = require("luaparse");

const ROOT = path.resolve(__dirname, "..", "..");
const TARGET_DIRS = ["scripts", "tests"];
const SKIP = new Set(["node_modules", ".git", "_backup_736d8ec", "_diff", "_cache_mdl", ".cache_mdl", "raw_model_backup", "_uploads"]);

function walk(dir, out) {
  let ents;
  try { ents = fs.readdirSync(dir, { withFileTypes: true }); }
  catch { return; }
  for (const e of ents) {
    if (SKIP.has(e.name)) continue;
    const full = path.join(dir, e.name);
    if (e.isDirectory()) walk(full, out);
    else if (e.isFile() && e.name.endsWith(".lua")) out.push(full);
  }
}

const files = [];
for (const d of TARGET_DIRS) walk(path.join(ROOT, d), files);
files.sort();

// 生产代码护栏（A/B/D）只针对 scripts/，避免测试脚手架自身引用被测字段造成误报
const scriptFiles = files.filter((f) => f.startsWith(path.join(ROOT, "scripts")));

const cases = []; // {name, status:'PASS'|'FAIL'|'WARN'|'INFO', detail}
function rec(name, status, detail) { cases.push({ name, status, detail: detail || "" }); }

function isCommentLine(line) {
  const t = line.trim();
  return t === "" || t.startsWith("--");
}

// ---- 1) 语法检查 ----
let syntaxFails = 0;
for (const f of files) {
  const code = fs.readFileSync(f, "utf8");
  try {
    luaparse.parse(code, { comments: false, scope: false, luaVersion: "5.3" });
  } catch (err) {
    syntaxFails++;
    const loc = err.line ? `:${err.line}` : "";
    rec(`syntax ${path.relative(ROOT, f)}${loc}`, "FAIL", String(err.message || err));
  }
}
rec("luaparse syntax sweep", syntaxFails === 0 ? "PASS" : "FAIL",
  `${files.length} files, ${syntaxFails} error(s)`);

// ---- 2) 反模式 A：_ctx. 裸访问（仅 InteriorPanels 允许） ----
{
  let hits = [];
  for (const f of scriptFiles) {
    if (f.endsWith(path.join("interior", "InteriorPanels.lua"))) continue;
    const lines = fs.readFileSync(f, "utf8").split("\n");
    lines.forEach((ln, i) => {
      if (isCommentLine(ln)) return;
      if (/_ctx\./.test(ln)) hits.push(`${path.relative(ROOT, f)}:${i + 1}`);
    });
  }
  rec("anti-pattern A: module-level _ctx bare access (except InteriorPanels)",
    hits.length === 0 ? "PASS" : "FAIL",
    hits.length ? hits.join("; ") : "no violations");
}

// ---- 3) 反模式 B：经济双数据源回潮 ----
{
  let hits = [];
  for (const f of scriptFiles) {
    const lines = fs.readFileSync(f, "utf8").split("\n");
    lines.forEach((ln, i) => {
      if (isCommentLine(ln)) return;
      if (/game\.money|GameState\.game\.money/.test(ln)) hits.push(`${path.relative(ROOT, f)}:${i + 1}`);
    });
  }
  rec("anti-pattern B: dual currency source (game.money / GameState.game.money)",
    hits.length === 0 ? "PASS" : "FAIL",
    hits.length ? hits.join("; ") : "game.gold is single authority");
}

// ---- 4) 反模式 C：HasBlockingGameplayOverlay 重引 GetTopOverlay ----
{
  const mainPath = path.join(ROOT, "scripts", "main.lua");
  const lines = fs.readFileSync(mainPath, "utf8").split("\n");
  let start = -1;
  for (let i = 0; i < lines.length; i++) {
    if (/function\s+HasBlockingGameplayOverlay\s*\(/.test(lines[i])) { start = i; break; }
  }
  let body = [];
  if (start >= 0) {
    for (let j = start + 1; j < lines.length; j++) {
      if (lines[j].trim() === "end") break;
      body.push(lines[j]);
    }
  }
  const has = body.some((l) => /GetTopOverlay/.test(l));
  rec("anti-pattern C: HasBlockingGameplayOverlay re-introduces GetTopOverlay",
    has ? "FAIL" : "PASS",
    has ? "GetTopOverlay fallback found in overlay judge" : "uses overlayPanelCount_ only");
}

// ---- 5) 反模式 D：直接 clientCloud:Get/Set（应经 CloudOpQueue） ----
{
  let hits = [];
  for (const f of scriptFiles) {
    if (f.endsWith("CloudOpQueue.lua")) continue;
    const lines = fs.readFileSync(f, "utf8").split("\n");
    lines.forEach((ln, i) => {
      if (isCommentLine(ln)) return;
      if (/clientCloud:(Get|Set)\(/.test(ln)) hits.push(`${path.relative(ROOT, f)}:${i + 1}`);
    });
  }
  rec("anti-pattern D: direct clientCloud:Get/Set (must route via CloudOpQueue)",
    hits.length === 0 ? "PASS" : "FAIL",
    hits.length ? hits.join("; ") : "all cloud I/O via CloudOpQueue (P0-k Y remediation)");
}

// ---- 6) 信息项 E：GameFlow 联机初始化方向（RS-11 vs N1） ----
{
  const gf = path.join(ROOT, "scripts", "core", "GameFlow.lua");
  const lines = fs.readFileSync(gf, "utf8").split("\n");
  let line = "", idx = -1;
  for (let i = 0; i < lines.length; i++) {
    if (/if\s+network\s+then\s+InitMultiplayer/.test(lines[i])) { line = lines[i]; idx = i + 1; break; }
  }
  const hasGuard = /hasFeature\(\s*"multiplayer"\s*\)/.test(line);
  rec("decision E: GameFlow multiplayer init guard (RS-11 vs N1)",
    "INFO",
    idx > 0
      ? `GameFlow.lua:${idx} \`${line.trim()}\` ${hasGuard ? "HAS" : "LACKS"} hasFeature("multiplayer") guard — ${hasGuard ? "aligned w/ N1" : "conflicts w/ RS-11 (AB-015); N1 pending 主理人 decision"}`
      : "if network then InitMultiplayer() not found");
}

// ---- 7) 警告 F：静默 pcall 无日志（heuristic） ----
{
  let warns = [];
  for (const f of files) {
    const lines = fs.readFileSync(f, "utf8").split("\n");
    for (let i = 0; i < lines.length; i++) {
      if (/pcall\(\s*function\s*\(/.test(lines[i])) {
        let hasPrint = false;
        for (let k = i; k < Math.min(i + 8, lines.length); k++) {
          if (/print\(/.test(lines[k])) { hasPrint = true; break; }
        }
        if (!hasPrint) warns.push(`${path.relative(ROOT, f)}:${i + 1}`);
      }
    }
  }
  const shown = warns.slice(0, 10);
  const extra = warns.length - shown.length;
  rec("warn F: silent pcall without log (heuristic)",
    warns.length ? "WARN" : "PASS",
    warns.length ? shown.join("; ") + (extra > 0 ? ` (+${extra} more)` : "") : "no silent pcall detected");
}

// ---- 报告 ----
const fails = cases.filter((c) => c.status === "FAIL");
const warns = cases.filter((c) => c.status === "WARN");
const infos = cases.filter((c) => c.status === "INFO");
const passes = cases.filter((c) => c.status === "PASS");

console.log("\n=== [STATIC-GATE] " + (fails.length ? "FAIL" : "PASS") + " ===");
console.log(`PASS=${passes.length} FAIL=${fails.length} WARN=${warns.length} INFO=${infos.length}`);
for (const c of cases) {
  console.log(`  [${c.status}] ${c.name}${c.detail ? " :: " + c.detail : ""}`);
}
console.log(`[STATIC-GATE-JSON] {"verdict":"${fails.length ? "FAIL" : "PASS"}","pass":${passes.length},"fail":${fails.length},"warn":${warns.length},"info":${infos.length}}`);

process.exit(fails.length ? 1 : 0);
