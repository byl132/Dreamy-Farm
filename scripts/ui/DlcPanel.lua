local UI = require("urhox-libs/UI")
local PaymentSystem = require("core.PaymentSystem")

local DlcPanel = {}

local function call(callbacks, name, ...)
    local fn = callbacks[name]
    if fn then return fn(...) end
end

local DLC_DATA = {
    {
        id = "town",
        name = "🏰 繁华城镇",
        subtitle = "城镇DLC",
        price = "¥6.00",
        status = "coming",
        description = "扩建你的农场周边，探索繁华的村庄城镇！与更多NPC互动，解锁新的商店和任务。",
        features = {
            "🗺️ 全新城镇地图区域",
            "👥 10+ 新NPC登场",
            "🏪 更多商店与交易",
            "📜 丰富的主线任务",
            "🎁 专属奖励与成就",
        },
        color = { 200, 140, 80, 255 },
        bgColor = { 180, 90, 40, 30 },
    },
    {
        id = "island",
        name = "🏝️ 海岛探险",
        subtitle = "海岛DLC",
        price = "¥8.00",
        status = "onsale",
        badge = "🔥 首发推荐 · 付费内容",
        description = "乘船前往神秘海岛，发现稀有资源和独特物种！开启海上冒险新篇章。",
        features = {
            "⛵ 全新海岛地图",
            "🐠 海洋生物养殖",
            "💎 稀有资源采集",
            "🏝️ 沙滩度假玩法",
            "⚓ 船只系统",
        },
        color = { 80, 160, 220, 255 },
        bgColor = { 40, 100, 180, 30 },
    },
    {
        id = "ranch",
        name = "🐑 全牧场物语",
        subtitle = "牧场DLC",
        price = "¥6.00",
        status = "coming",
        description = "扩展你的牧场，养殖更多珍稀动物！解锁全新养殖玩法和动物产品。",
        features = {
            "🐄 更多珍稀动物",
            "🏡 牧场扩建升级",
            "🎂 动物产品加工",
            "🏆 养殖成就系统",
            "🐾 动物互动玩法",
        },
        color = { 120, 200, 100, 255 },
        bgColor = { 60, 140, 60, 30 },
    },
}

function DlcPanel.Create(callbacks)
    callbacks = callbacks or {}

    -- 构建所有 DLC 卡片
    local dlcCards = {}
    for i, dlc in ipairs(DLC_DATA) do
        local trialInfo = call(callbacks, "getDlcTrialInfo", dlc.id)

        -- 构建特性标签
        local featItems = {}
        for j, feat in ipairs(dlc.features) do
            featItems[j] = UI.Panel {
                paddingLeft = 8, paddingRight = 8, paddingTop = 4, paddingBottom = 4,
                borderRadius = 6, backgroundColor = { 40, 35, 28, 200 },
                children = {
                    UI.Label { text = feat, fontSize = 11, fontColor = { 190, 180, 150, 220 } },
                }
            }
        end

        -- 〔DLC 商店化 2026-09-07〕状态从 PaymentSystem 单一数据源读取（已购/试用/在售/即将推出）
        local purchased = PaymentSystem.isDLCPurchased and PaymentSystem.isDLCPurchased(dlc.id)
        local statusItems = {}
        if purchased then
            statusItems[1] = UI.Label { text = "✅ 已永久解锁", fontSize = 15, fontWeight = "bold", fontColor = { 120, 230, 150, 255 } }
        else
            statusItems[1] = UI.Label { text = dlc.price, fontSize = 16, fontWeight = "bold", fontColor = { 255, 200, 100, 255 } }
        end
        if purchased then
            statusItems[2] = UI.Label { text = "感谢支持，尽情探索！", fontSize = 11, fontColor = { 160, 200, 170, 220 }, marginTop = 2 }
        elseif trialInfo and trialInfo.remaining > 0 then
            local mins = math.floor(trialInfo.remaining / 60)
            statusItems[2] = UI.Label {
                text = "✨ 体验中 (" .. mins .. "分钟)", fontSize = 11,
                fontColor = { 100, 220, 150, 230 }, marginTop = 2,
            }
        elseif dlc.status == "onsale" then
            statusItems[2] = UI.Label {
                text = dlc.badge or "🔥 在售", fontSize = 11, fontColor = { 255, 150, 90, 230 }, marginTop = 2,
            }
        else
            statusItems[2] = UI.Label {
                text = "即将推出", fontSize = 11, fontColor = { 200, 180, 100, 200 }, marginTop = 2,
            }
        end

        dlcCards[i] = UI.Panel {
            width = "100%", borderRadius = 12,
            backgroundColor = dlc.bgColor,
            borderWidth = 1, borderColor = { dlc.color[1] or 100, dlc.color[2] or 100, dlc.color[3] or 100, 100 },
            padding = 16,
            children = {
                UI.Panel {
                    width = "100%", flexDirection = "row", justifyContent = "space-between",
                    alignItems = "center", marginBottom = 10,
                    children = {
                        UI.Panel {
                            flexDirection = "column",
                            children = {
                                UI.Label { text = dlc.name, fontSize = 18, fontWeight = "bold", fontColor = dlc.color },
                                UI.Label { text = dlc.subtitle, fontSize = 11, fontColor = { 160, 150, 120, 200 }, marginTop = 2 },
                            }
                        },
                        UI.Panel {
                            flexDirection = "column", alignItems = "flex-end",
                            children = statusItems,
                        },
                    }
                },
                UI.Label {
                    text = dlc.description, fontSize = 13, fontColor = { 210, 200, 170, 230 },
                    marginBottom = 12,
                },
                UI.Panel {
                    width = "100%", flexWrap = "wrap", gap = 8,
                    children = featItems,
                },
                UI.Panel {
                    width = "100%", flexDirection = "row", gap = 8, marginTop = 12,
                    children = (purchased and {
                        UI.Button {
                            text = "✅ 已拥有", flex = 1, height = 40, fontSize = 14,
                            backgroundColor = { 55, 90, 65, 200 },
                            textColor = { 180, 235, 190, 255 },
                            borderRadius = 8,
                            onClick = function() end,
                        },
                    } or {
                        UI.Button {
                            text = "🛒 立即购买", flex = 1, height = 40, fontSize = 14,
                            backgroundColor = { 205, 125, 35, 240 },
                            textColor = { 255, 245, 228, 255 },
                            borderRadius = 8,
                            onClick = function()
                                call(callbacks, "purchaseDlc", dlc.id, dlc.name)
                            end,
                        },
                        UI.Button {
                            text = "📺 看广告体验", flex = 1, height = 40, fontSize = 14,
                            backgroundColor = { 60, 80, 100, 200 },
                            textColor = { 200, 220, 255, 255 },
                            borderRadius = 8,
                            onClick = function()
                                call(callbacks, "showAdForDlc", dlc.id, dlc.name)
                            end,
                        },
                    }),
                },
            }
        }
    end

    -- 手动拼接 children 数组，避免 table.unpack 在表构造器中的兼容问题
    local scrollChildren = {
        UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "space-between",
            alignItems = "center", marginBottom = 20,
            children = {
                UI.Label { text = "🏝️ DLC 商店", fontSize = 24, fontWeight = "bold", fontColor = { 255, 230, 150, 255 } },
                UI.Button {
                    text = "✕", width = 42, height = 42, fontSize = 20,
                    backgroundColor = { 100, 40, 35, 220 }, textColor = { 255, 200, 200, 255 },
                    borderRadius = 21,
                    onClick = function() call(callbacks, "hideDlcPanel") end,
                },
            }
        },
        UI.Label {
            text = "购买永久解锁 · 广告试用免费体验 5 分钟 · 新内容持续追加",
            fontSize = 13, fontColor = { 180, 170, 140, 220 },
            marginBottom = 20, textAlign = "center",
        },
    }
    -- 逐个插入 DLC 卡片
    for _, card in ipairs(dlcCards) do
        scrollChildren[#scrollChildren + 1] = card
    end
    -- 底部贴士
    scrollChildren[#scrollChildren + 1] = UI.Panel {
        width = "100%", marginTop = 20, paddingTop = 16,
        borderTopWidth = 1, borderTopColor = { 60, 55, 45, 100 },
        children = {
            UI.Label {
                text = "💡 小贴士：购买任意DLC可解锁专属头像框和称号！",
                fontSize = 12, fontColor = { 160, 180, 200, 200 },
            },
        }
    }

    local panel = UI.Panel {
        id = "dlcPanel",
        width = "100%", height = "100%",
        position = "absolute", top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 10, 8, 5, 245 },
        justifyContent = "center", alignItems = "center",
        pointerEvents = "auto",
        visible = false,
        children = {
            UI.Panel {
                width = "94%", maxWidth = 700, height = "90%",
                borderRadius = 16, backgroundColor = { 28, 24, 18, 255 },
                padding = 24,
                overflow = "auto",
                children = scrollChildren,
            }
        }
    }

    return panel
end

return DlcPanel
