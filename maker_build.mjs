/**
 * Maker MCP 构建脚本
 * 通过 JSON-RPC 与 Maker MCP 服务器通信，执行云端构建
 *
 * 工作流程:
 *   1. 启动 Maker MCP 服务器子进程
 *   2. 发送 initialize 请求
 *   3. 获取工具列表 (tools/list)
 *   4. 调用 maker_build_current_directory 工具
 *   5. 输出构建结果
 */

import { spawn } from "node:child_process";

// ============================
// 配置
// ============================
// 〔跨平台适配 2026-08-21〕原脚本硬编码 Windows（E: 盘 + npx.cmd + Windows PATH），
// 沙盒/CI（Linux）无法使用。改为：环境变量 MAKER_PROJECT_DIR 优先，其次当前工作目录，
// 最后回退原 Windows 本机路径。NPX 命令按平台自动选择。
const IS_WINDOWS = process.platform === "win32";
const PROJECT_DIR =
  process.env.MAKER_PROJECT_DIR ||
  (IS_WINDOWS ? "E:/trae/dreamy farm" : process.cwd());
const NPX_CMD = IS_WINDOWS ? "npx.cmd" : "npx";
const PACKAGE = "@taptap/maker";

// 增强的 PATH，包含 Windows 系统和 Git 路径（仅 Windows 生效）
const ENHANCED_PATH = [
  process.env.PATH,
  ...(IS_WINDOWS
    ? [
        "C:\\Windows\\System32",
        "C:\\Windows",
        "C:\\Program Files\\Git\\cmd",
        "C:\\Program Files\\Git\\bin",
        process.env.LOCALAPPDATA + "\\Programs\\Git\\cmd",
        // npx 缓存路径
        process.env.APPDATA + "\\npm",
        process.env.LOCALAPPDATA + "\\npm-cache",
      ]
    : []),
]
  .filter(Boolean)
  .join(IS_WINDOWS ? ";" : ":");

// ============================
// JSON-RPC 通信
// ============================
let requestId = 0;

function createRequest(method, params = {}) {
  return JSON.stringify({
    jsonrpc: "2.0",
    id: ++requestId,
    method,
    params,
  }) + "\n";
}

/**
 * 通过子进程发送 JSON-RPC 请求并等待响应
 */
function sendRequest(proc, method, params = {}) {
  return new Promise((resolve, reject) => {
    const id = ++requestId;
    const request = JSON.stringify({
      jsonrpc: "2.0",
      id,
      method,
      params,
    }) + "\n";

    const buffer = [];
    const cleanup = () => {
      proc.stdout.removeListener("data", onData);
    };

    function onData(chunk) {
      buffer.push(chunk.toString());
      const full = buffer.join("");
      // 尝试解析完整的 JSON-RPC 响应（可能多行返回）
      const lines = full.split("\n");
      for (const line of lines) {
        if (!line.trim()) continue;
        try {
          const parsed = JSON.parse(line);
          if (parsed.id === id) {
            cleanup();
            resolve(parsed);
            return;
          }
        } catch {
          // 不完整的 JSON，继续累积
        }
      }
    }

    proc.stdout.on("data", onData);

    // 写入请求
    proc.stdin.write(request);

    // 超时处理
    setTimeout(() => {
      cleanup();
      reject(new Error(`请求超时: ${method} (id=${id})`));
    }, 900000); // 15分钟超时（云端构建耗时较长；原 2 分钟会掐断连接，拿不到最终二维码）
  });
}

/**
 * 读取所有来自子进程的 stdout 数据（用于最后获取完整构建日志）
 */
function readAllStdout(proc, timeoutMs = 30000) {
  return new Promise((resolve, reject) => {
    const buffer = [];
    const timer = setTimeout(() => {
      proc.stdout.removeListener("data", onData);
      resolve(buffer.join(""));
    }, timeoutMs);

    function onData(chunk) {
      buffer.push(chunk.toString());
    }

    proc.stdout.on("data", onData);
    proc.on("close", () => {
      clearTimeout(timer);
      resolve(buffer.join(""));
    });
  });
}

// ============================
// 主流程
// ============================
async function main() {
  console.log("=== Maker MCP 构建脚本 ===");
  console.log(`项目目录: ${PROJECT_DIR}`);
  console.log(`Node.js: ${process.version}`);
  console.log(`PATH: ${ENHANCED_PATH.substring(0, 200)}...\n`);

  console.log("[1/5] 启动 Maker MCP 服务器...");
  const proc = spawn(NPX_CMD, ["-y", PACKAGE], {
    cwd: PROJECT_DIR,
    stdio: ["pipe", "pipe", "inherit"],
    env: {
      ...process.env,
      PATH: ENHANCED_PATH,
      // 关闭颜色输出以便解析
      NO_COLOR: "1",
      FORCE_COLOR: "0",
    },
    windowsHide: false,
    shell: IS_WINDOWS,  // Windows 上 .cmd 文件需要 shell；Linux 直接 spawn npx
  });

  // 等待服务器启动
  await new Promise((resolve) => setTimeout(resolve, 3000));

  let exitCode = 1;
  try {
    // ============================
    // Step 2: initialize
    // ============================
    console.log("[2/5] 发送 initialize 请求...");
    const initResult = await sendRequest(proc, "initialize", {
      protocolVersion: "2024-11-05",
      capabilities: {},
      clientInfo: {
        name: "maker-build-script",
        version: "1.0.0",
      },
    });

    if (initResult.error) {
      throw new Error(`initialize 失败: ${JSON.stringify(initResult.error)}`);
    }
    console.log(`  -> 初始化成功, 协议版本: ${initResult.result?.protocolVersion || "unknown"}`);

    // 发送 initialized 通知
    proc.stdin.write(JSON.stringify({
      jsonrpc: "2.0",
      method: "notifications/initialized",
      params: {},
    }) + "\n");

    // ============================
    // Step 3: tools/list
    // ============================
    console.log("[3/5] 获取工具列表 (tools/list)...");
    const toolsResult = await sendRequest(proc, "tools/list");

    if (toolsResult.error) {
      throw new Error(`tools/list 失败: ${JSON.stringify(toolsResult.error)}`);
    }

    const tools = toolsResult.result?.tools || [];
    console.log(`  -> 获取到 ${tools.length} 个工具`);

    // 查找 maker_build_current_directory 工具
    const buildTool = tools.find((t) => t.name === "maker_build_current_directory");
    if (!buildTool) {
      console.error("  -> 未找到 maker_build_current_directory 工具，可用工具列表:");
      for (const t of tools) {
        console.error(`     - ${t.name}`);
      }
      throw new Error("maker_build_current_directory 工具不可用");
    }
    console.log(`  -> 找到构建工具: ${buildTool.name}`);
    if (buildTool.description) {
      console.log(`  -> 描述: ${buildTool.description}`);
    }

    // ============================
    // Step 4: 调用 maker_build_current_directory
    // ============================
    console.log("[4/5] 调用 maker_build_current_directory 发起云端构建...");
    console.log("  -> 正在等待构建完成，这可能需要几分钟...\n");

    const buildResult = await sendRequest(
      proc,
      "tools/call",
      {
        name: "maker_build_current_directory",
        arguments: {},
      }
    );

    // ============================
    // Step 5: 输出构建结果
    // ============================
    console.log("\n[5/5] 构建完成，结果如下:\n");

    if (buildResult.error) {
      console.error("!!! 构建失败 !!!");
      console.error(JSON.stringify(buildResult.error, null, 2));
      exitCode = 1;
    } else {
      const result = buildResult.result;
      console.log("=== 构建结果 (JSON) ===");
      console.log(JSON.stringify(result, null, 2));
      console.log("\n=== 构建结果摘要 ===");

      // 尝试提取关键信息
      if (result) {
        // 检查是否有 content 数组（MCP 工具结果的标准格式）
        if (Array.isArray(result.content)) {
          for (const item of result.content) {
            if (item.type === "text") {
              console.log(`[${item.type}]: ${item.text}`);
            } else {
              console.log(`[${item.type}]: ${JSON.stringify(item)}`);
            }
          }
        } else {
          // 直接输出结果对象
          console.log(JSON.stringify(result, null, 2));
        }

        // 检查 isError 标志
        if (result.isError) {
          console.error("\n!!! 构建报告了错误状态 !!!");
          exitCode = 1;
        } else {
          console.log("\n  -> 构建请求已成功提交");
          exitCode = 0;
        }
      }
    }
  } catch (err) {
    console.error("\n!!! 脚本执行出错 !!!");
    console.error(err.message);
    if (err.stack) {
      console.error(err.stack);
    }
    exitCode = 1;
  } finally {
    // 关闭子进程
    console.log("\n--- 清理: 关闭 MCP 服务器 ---");
    try {
      proc.stdin.end();
    } catch {}
    // 等待进程退出
    try {
      await new Promise((resolve) => {
        const timer = setTimeout(resolve, 5000);
        proc.on("exit", () => {
          clearTimeout(timer);
          resolve();
        });
        // 如果进程没有自动退出，强制终止
        setTimeout(() => {
          try { proc.kill(); } catch {}
        }, 3000);
      });
    } catch {}
  }

  console.log(`\n=== 脚本退出, 代码: ${exitCode} ===`);
  process.exit(exitCode);
}

main().catch((err) => {
  console.error("未捕获的异常:", err);
  process.exit(1);
});