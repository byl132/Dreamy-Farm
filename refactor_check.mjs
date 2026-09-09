#!/usr/bin/env node
/**
 * refactor_check.mjs — 重构一致性门控脚本
 *
 * 依据 docs/tech/refactor-failure-analysis.md 建议 #1：
 * 过去四轮"云端重构→回归→回滚"的根因是盲搬(A)/漏引用(B)/无门控(C)。
 * 本脚本在**推送前/提交前**本地跑，把"进游戏才崩"提前到"合并前阻断"。
 *
 * 检查项：
 *   1. 全量 Lua 语法检查（luaparse，覆盖 scripts 下所有 .lua）
 *   2. require 路径存在性：所有 require("a.b") 能解析到真实文件
 *   3. 跨模块引用一致性：文件内 `Alias.Func(` 调用，Alias 来自
 *      require，则目标模块必须定义了 Func（覆盖 function M.f / M.f = function / M.f = 字面量）
 *
 * 用法：
 *   node refactor_check.mjs            # 全量检查
 *   node refactor_check.mjs path1 path2...  # 只检查指定文件（语法+它发起的跨模块调用）
 *
 * 退出码：0=通过，1=有错误
 */

import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { join, dirname, resolve, relative } from "node:path";
import { fileURLToPath } from "node:url";
import luaparse from "luaparse";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = __dirname;
const SCRIPTS = join(ROOT, "scripts");
const LUA_DIR = join(ROOT, "node_modules", "luaparse");

// luaparse 是 CJS，import 默认拿到函数或 .parse；两者都兼容
const parseLua = (src) =>
  (luaparse.parse || luaparse)(src, { luaVersion: "5.3", comments: false });

// ============================
// 文件收集
// ============================
const SKIP_DIRS = new Set([".archive", ".deprecated", "node_modules", "urhox-libs"]);

function collectLuaFiles(dir, out = []) {
  for (const name of readdirSync(dir)) {
    if (name.endsWith(".meta")) continue;
    const full = join(dir, name);
    const st = statSync(full);
    if (st.isDirectory()) {
      if (SKIP_DIRS.has(name)) continue;
      collectLuaFiles(full, out);
    } else if (name.endsWith(".lua")) {
      out.push(full);
    }
  }
  return out;
}

// ============================
// 模块解析：require("a.b") -> scripts/a/b.lua
// ============================
// 引擎/运行时内置库（不在 scripts/ 下，解析不到不算错）
const EXTERNAL_LIB_RE = /^(urhox-libs|json|cjson|LuaScripts|Utilities)\b/;

function resolveRequirePath(path) {
  // 相对 scripts/ 目录（require("core.GameFlow") => scripts/core/GameFlow.lua）
  const candidates = [
    join(SCRIPTS, ...path.split(".")) + ".lua",
    join(SCRIPTS, ...path.split("."), "init.lua"),
  ];
  for (const c of candidates) if (existsSync(c)) return c;
  return null;
}

function isExternalLib(path) {
  return EXTERNAL_LIB_RE.test(path) || path.includes("/");
}

/** 提取一个 .lua 文件"对外提供"的成员名集合 */
function extractExports(src, basename) {
  const exports = new Set();
  const addFor = (tbl) => {
    if (!tbl) return;
    // function M.f(...) / M.f = function / M.f = <任意字面量开头（非 , ); 换行）>
    const re1 = new RegExp(`(?:^|[^\\w.])function\\s+${tbl}\\.([A-Za-z_]\\w*)\\s*\\(`, "g");
    const re2 = new RegExp(`(?:^|[^\\w.])${tbl}\\.([A-Za-z_]\\w*)\\s*=\\s*[^,;)\\n]`, "g");
    let m;
    while ((m = re1.exec(src))) exports.add(m[1]);
    while ((m = re2.exec(src))) exports.add(m[1]);
  };
  // 候选主表 = 文件内所有 `X = {}` 声明 ∪ require 别名同名的表。
  // 不依赖 `return X`（函数体内 return data 会误导首匹配——实测踩坑）。
  const tblRe = /(?:^|\n)\s*(?:local\s+)?([A-Za-z_]\w*)\s*=\s*\{\s*\}/g;
  const candidates = new Set();
  let tm;
  while ((tm = tblRe.exec(src))) candidates.add(tm[1]);
  if (basename) candidates.add(basename);
  for (const c of candidates) addFor(c);
  return exports;
}

/** 提取文件内的 require 别名：alias -> require path */
function extractRequireAliases(src) {
  const map = new Map(); // alias -> { path, file }
  const re = /(?:^|\n)\s*(?:local\s+)?([A-Za-z_]\w*)\s*=\s*require\s*\(\s*["']([^"']+)["']\s*\)/g;
  let m;
  while ((m = re.exec(src))) {
    map.set(m[1], m[2]);
  }
  return map;
}

// ============================
// 主流程
// ============================
const args = process.argv.slice(2);
const explicit = args.filter((a) => !a.startsWith("-"));
const allFiles = collectLuaFiles(SCRIPTS);
const files = explicit.length
  ? explicit.map((p) => resolve(ROOT, p)).filter((p) => existsSync(p))
  : allFiles;

let errors = 0;
const problems = [];
const err = (file, msg) => {
  problems.push(`${relative(ROOT, file)}: ${msg}`);
  errors++;
};

// Pass 1: 语法
const srcByFile = new Map();
for (const f of allFiles) {
  let src;
  try {
    src = readFileSync(f, "utf-8");
  } catch (e) {
    err(f, `读取失败 ${e.message}`);
    continue;
  }
  srcByFile.set(f, src);
  try {
    parseLua(src);
  } catch (e) {
    err(f, `语法错误 ${e.message}`);
  }
}

// Pass 2/3: require 路径 + 跨模块引用（只对"受影响文件"全量跑别名扫描——
// 跨模块调用是文件级属性，改动方负责自己发起的调用合法性）
const scope = explicit.length ? files : allFiles;
const exportsCache = new Map();
const getExports = (file, basename) => {
  if (!exportsCache.has(file)) {
    exportsCache.set(file, extractExports(srcByFile.get(file) || "", basename));
  }
  return exportsCache.get(file);
};

for (const f of scope) {
  const src = srcByFile.get(f);
  if (!src) continue;
  const aliases = extractRequireAliases(src);
  for (const [alias, path] of aliases) {
    const target = resolveRequirePath(path);
    if (!target) {
      if (!isExternalLib(path)) {
        err(f, `require("${path}") 解析不到文件（别名 ${alias}）`);
      }
      continue;
    }
    const provided = getExports(target, path.split(".").pop());
    if (provided.size === 0) continue; // 目标模块导出提取失败时不误报
    // 扫描 alias.Member( 调用（排除 alias.Member = 赋值定义）
    const useRe = new RegExp(`(?:^|[^\\w."'])${alias}\\.([A-Za-z_]\\w*)\\s*\\(`, "g");
    let m;
    while ((m = useRe.exec(src))) {
      const fn = m[1];
      if (!provided.has(fn)) {
        if (process.env.RC_DEBUG) {
          console.error(`[debug] target=${relative(ROOT, target)} basename=${path.split(".").pop()} exportsSize=${provided.size} sample=${[...provided].slice(0, 6).join(",")}`);
        }
        err(f, `调用了 ${alias}.${fn}( 但目标模块 ${relative(ROOT, target)} 未定义该成员`);
      }
    }
  }
}

// ============================
// 输出
// ============================
const OK = "\x1b[32m", RED = "\x1b[31m", DIM = "\x1b[2m", RST = "\x1b[0m";
console.log(`refactor_check: 语法检查 ${files.length} 个文件，跨模块引用扫描 ${scope.length} 个文件`);
if (errors === 0) {
  console.log(`${OK}✓ 全部通过${RST}`);
  process.exit(0);
} else {
  console.log(`${RED}✗ 发现 ${errors} 个问题:${RST}`);
  for (const p of problems) console.log(`${RED}  - ${p}${RST}`);
  console.log(`${DIM}提示：以上问题会在云端构建/平台校验时同样暴露，请先修复再推送。${RST}`);
  process.exit(1);
}
