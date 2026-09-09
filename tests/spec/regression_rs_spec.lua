---@diagnostic disable: undefined-global
-- ============================================================
-- tests/spec/regression_rs_spec.lua
-- 避雷清单 → 回归场景库（RS-01..RS-14）映射
--   * 可在 Maker/真机内自动断言的：RS-14（requireCtx 契约）在此实跑；
--     其余核心契约由 requirectx/addmoney/multiplayer 三个 spec 覆盖。
--   * 依赖真实 UI / 设备 / 网络的：标记为 SKIP，并指向 qa-plan.md
--     冒烟清单中的手动/集成验证步骤（真机走查）。
-- 运行环境：Maker / 真机
-- ============================================================

return function(QATest)
    local InteriorPanels = require("interior.InteriorPanels")

    -- RS-14（自动）：requireCtx 漏接 Init 必须明确报错
    QATest.assertRequireCtxGuards(InteriorPanels, "ShowFireplacePanel", "RS-14 requireCtx guard :: ShowFireplacePanel")

    -- RS-11（决策待定 / 信息项）：GameFlow.lua:897 当前为
    --   `if network then InitMultiplayer()`，未加 hasFeature("multiplayer") 守卫。
    --   与 memory-index AB-015（联机以 network 为准）方向冲突；N1 修复待主理人裁定。
    --   此处不自动判定通过/失败，仅作为已知决策项上报，避免质量门误放/误拦。
    QATest.record("RS-11 multiplayer init guard (N1 pending decision)", nil,
        "GameFlow.lua:897 `if network then InitMultiplayer()` WITHOUT hasFeature('multiplayer'); 待主理人裁定 RS-11 vs N1")

    -- 以下 RS 需在 Maker/真机内手动或集成验证（真机走查步骤见 qa-plan.md §冒烟清单）：
    local manual = {
        ["RS-01"] = "顶/底浮层存在时点击世界：游戏层不响应；移动端 TouchEnd 跳过 UI 接管触点",
        ["RS-02"] = "后台匹配启动即连须订阅 ServerReady 后发 ClientReady（见 multiplayer_spec）",
        ["RS-03"] = "激励广告 ad.status!=1：不接真实视频、不虚构奖励（PlatformAdapter）",
        ["RS-04"] = "广告回调同步拒绝/重复/迟到/90s 超时：一次性完成态，仅 success 发奖一次",
        ["RS-05"] = "服务端日志拼接未注入全局：用安全默认值不崩（server_main GetConnectionKey）",
        ["RS-06"] = "设置页固定双栏 + 安全区：两栏完整各自滚动、异形屏不遮挡",
        ["RS-07"] = "云端身份只用 clientCloud.userId/TapUser/lobby，不读本地文件/随机 UID",
        ["RS-08"] = "SetVisible 开关浮层经统一 overlay 栈；HUD/小地图读实时可见态",
        ["RS-09"] = "官方身份未就绪回退页保留 TapTap 登录/重试入口",
        ["RS-10"] = "进游戏/回主菜单清零 overlayPanelCount_ + 重置 Tab 鼠标态（main.lua:1986/ResetCameraState）",
        ["RS-12"] = "H5 隐藏 MM_ABSOLUTE 鼠标：以 input.mousePosition 连续差补齐相机增量",
        ["RS-13"] = "身份异步就绪重试 clientCloud.userId/TapUser/lobby，超时回可重试主菜单",
    }
    for id, why in pairs(manual) do
        QATest.record(id .. " (manual/integration)", nil, why)
    end
end
