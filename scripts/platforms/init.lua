-- ============================================================
-- platforms/init.lua — 平台初始化调度器
-- 根据 build_target 加载对应平台模块
-- ============================================================

local PlatformAdapter = require("core.PlatformAdapter")
local target = PlatformAdapter.getBuildTarget()

-- 尝试加载对应平台模块，失败时回退到 taptap_maker
local ok, platformModule = pcall(require, "platforms." .. target)
if not ok then
    print("[Platforms] 平台模块 '" .. target .. "' 加载失败，回退到 taptap_maker: " .. tostring(platformModule))
    platformModule = require("platforms.taptap_maker")
end

print("[Platforms] 已加载平台模块: " .. platformModule.name .. " v" .. platformModule.version)

return platformModule
