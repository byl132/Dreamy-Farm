---@diagnostic disable: undefined-global
-- ============================================================
-- ZoneGuide · 区域活动引导（矿洞 / 遗迹 / 等）
-- 复用于新手引导同款卡片样式，但以【当前活动 UI 根】为挂载点，
-- 因此在矿洞 / 遗迹（已进入 SetRoot 替换了农场 UI 的场景）内也能正常显形。
-- 与 GuidePanel 的区别：按 zone 维度独立记忆、内容随区域不同，且不依附于“仅户外”门控。
-- ============================================================

local ZoneGuide = {}
local GUIDE_VERSION = 6  -- 5→6：强制重弹，让玩家在各自场景首入时重新看到教程（含新增 ranch 独立引导）；看过即不再弹。

-- 各区域引导内容（标题 + 正文）。可在此增删区域 / 步骤。
local ZONE_STEPS = {
    mine = {
        { title = "⛏️ 矿洞探险", text = "矿洞里可以挖矿赚钱、击败怪物。每层都有矿石和怪物；越往下层越深，挑战也越大。挖到的矿石与击败怪物掉落的战利品，都能换成金币。" },
        { title = "🕹️ 怎么操作", text = "移动方式和农场一致：PC 用 WASD，手机拖动左下角摇杆。走近矿石或怪物，角色会自动锁定最近目标；也可直接点右下角 ⛏️采矿 / ⚔️攻击，或点 🔄自动 让角色自动对最近目标出手。" },
        { title = "⬇️ 下层 / 离开", text = "采矿或打怪时，有几率让梯子显形（位置固定、向外侧凸出）。看到“⬇️ 梯子出现了”提示后走过去，即可下到下一层。随时点 🏃离开矿洞，会回到农场原来的位置。" },
    },
    ruins = {
        { title = "🏛️ 远古遗迹", text = "遗迹里要收集 3 块符文碎片、击败守卫，最后走到传送阵离开。小心陷阱和敌人，注意屏幕左上角的血量。" },
        { title = "🕹️ 怎么操作", text = "移动方式与农场一致：PC 用 WASD，手机拖动左下角摇杆。靠近符文 / 宝箱 / 敌人会自动互动；遇到敌人会进入战斗，点⚔️攻击、🛡️防御或🏃逃跑。" },
        { title = "🚪 结束探险", text = "完成目标后走到传送阵即可离开；任何时候都可点🏃放弃返回农场。血量归零会探险失败、返回农场，量力而行。" },
    },
    forest = {
        { title = "🌲 神秘森林", text = "森林深处藏着一颗远古种子，找到它并带回出口即可完成探险。沿途有宝箱、草药、怪物与陷阱；留意屏幕左上角的血量，生命归零会探险失败并返回农场。" },
        { title = "🕹️ 怎么操作", text = "移动方式与农场一致：PC 用 WASD，手机拖动左下角摇杆。靠近宝箱、草药或怪物会自动互动；遇到怪物会进入战斗，点击出现的攻击 / 防御 / 逃跑按钮应对。采集草药可以回复体力。" },
        { title = "🚪 结束探险", text = "拿到远古种子后走到出口（🚪）即可离开；任何时间都可点 🏃 返回农场。还没拿到种子时出口不会开启，量力而行、注意绕开陷阱。" },
    },
    interior = {
        { title = "🏠 室内空间", text = "这里是你的家园：房屋里可以烹饪料理、使用家具（储存与整理）；牧场里可以照顾动物，并从后院门进入放牧区喂养、收集产物。" },
        { title = "🕹️ 怎么操作", text = "移动方式与户外一致：PC 用 WASD，手机拖动左下角摇杆。靠近灶台、家具或动物栏会弹出“💬 交互”气泡（第一视角点“交互”按钮或按 F），点击即可使用。右上角“📷 视角”可切换第一 / 第三视角。" },
        { title = "🚪 离开房间", text = "随时点右上角“🚪 离开”返回农场；牧场内点“↩ 返回”回到室内。料理与动物产出会自动入库，放心探索。" },
    },
    -- 〔A5〕牧场独立引导：玩家从广场穿过牧场边界门进入放牧区时首入弹出。
    -- 与 interior（家园）区分：interior 偏“屋内/烹饪/家具”，ranch 偏“户外动物养殖/产物收集”。
    ranch = {
        { title = "🐄 牧场养殖区", text = "欢迎来到牧场！这里有鸡、鸭、牛等动物，每天可以喂养、收集鸡蛋 / 牛奶等产物。动物好感度越高，产物越多、还能繁殖。" },
        { title = "🕹️ 怎么操作", text = "移动方式与农场一致：PC 用 WASD，手机拖动左下角摇杆。靠近动物栏 / 饲料槽会弹出“💬 交互”气泡，点击即可喂养或收集。右上角“📷 视角”可切换第一 / 第三视角。" },
        { title = "🚪 返回广场", text = "随时点牧场边界的“🏡 返回”即可回到广场；产物会自动入库。量力而行、每天来照看，牧场会越来越热闹~" },
    },
}

local function getSeenFileName(ctx, zone)
    local mode = (ctx.loginMode == "guest") and "guest" or "online"
    return "zone_guide_" .. tostring(zone) .. "_" .. mode .. ".txt"
end

-- [USER-FIX] zone guide turned world-scoped: only ctx.game._zoneGuide[zone] in-memory flag,
-- no longer writes zone_guide_*.txt (old logic persisted across worlds so veterans never saw it again).
-- GameFlow clears _zoneGuide on new world, so first entry to mine/ruins/forest each world re-pops.
function ZoneGuide.IsSeen(ctx, zone)
    if ctx.game and ctx.game._zoneGuide and ctx.game._zoneGuide[zone] == GUIDE_VERSION then return true end
    return false
end

-- [USER-FIX] only in-memory (world-scoped) flag, no file write.
function ZoneGuide.MarkSeen(ctx, zone, saveCloud)
    if not ctx.game._zoneGuide then ctx.game._zoneGuide = {} end
    ctx.game._zoneGuide[zone] = GUIDE_VERSION
    if saveCloud and ctx.SaveCloudData then ctx.SaveCloudData() end
end

ZoneGuide.overlay = nil

function ZoneGuide.Close(ctx)
    if ZoneGuide.overlay and ctx then
        pcall(function()
            if ctx.UI and ctx.UI.PopOverlay then ctx.UI.PopOverlay(ZoneGuide.overlay) end
            ZoneGuide.overlay:Remove()
        end)
    end
    ZoneGuide.overlay = nil
end

local function renderStep(ctx, zone, steps, step, rootPanel)
    ZoneGuide.Close(ctx)
    local UI = ctx.UI
    local isMobile = ctx.isMobile == true
    local safe = (ctx.getSafeArea and ctx.getSafeArea()) or { bottom = 0 }
    local cardWidth = isMobile and "90%" or 380
    local cardLeft = isMobile and 16 or 18
    local cardBottom = isMobile and (140 + (safe.bottom or 0)) or 110
    local data = steps[math.max(1, math.min(#steps, step))]
    local isLast = step >= #steps

    ZoneGuide.overlay = UI.Panel {
        width = "100%", height = "100%", position = "absolute",
        pointerEvents = "box-none",
        children = {
            UI.Panel {
                position = "absolute", left = cardLeft, bottom = cardBottom,
                width = cardWidth, maxWidth = 400, padding = 16,
                backgroundColor = { 24, 22, 18, 242 },
                borderRadius = 14,
                borderWidth = 2, borderColor = { 150, 170, 90, 230 },
                pointerEvents = "auto",
                children = {
                    UI.Label { text = data.title, fontSize = 17, fontWeight = "bold", fontColor = {245, 230, 173, 255}, marginBottom = 8 },
                    UI.Label { text = data.text, fontSize = 13, fontColor = {225, 218, 195, 240}, lineHeight = 1.4, marginBottom = 12 },
                    UI.Panel { flexDirection = "row", gap = 10, children = {
                        UI.Button { text = "跳过", width = 86, height = 36, fontSize = 12, backgroundColor = {70, 62, 52, 220}, borderRadius = 8,
                            onClick = function()
                                ZoneGuide.MarkSeen(ctx, zone, true)
                                ZoneGuide.Close(ctx)
                            end },
                        UI.Button { text = isLast and "开始" or "下一步", width = 120, height = 36, fontSize = 13, variant = "primary", borderRadius = 8,
                            onClick = function()
                                if isLast then
                                    ZoneGuide.MarkSeen(ctx, zone, true)
                                    ZoneGuide.Close(ctx)
                                else
                                    renderStep(ctx, zone, steps, step + 1, rootPanel)
                                end
                            end },
                    }},
                },
            },
        },
    }
    -- 关键修复：必须挂到【当前活动 UI 根】（矿洞=state.mineHUD / 遗迹=st.exploreOverlay_），
    -- 不能走 ctx.ShowOverlayPanel（它只认 gameUIRoot_；矿洞/遗迹下 gameUIRoot_ 已被 SetRoot 替换，
    -- 会导致引导在场景内不可见、退出后才显形）。
    local target = rootPanel
    if target and target.AddChild then
        if not ZoneGuide.overlay.parent or ZoneGuide.overlay.parent ~= target then
            target:AddChild(ZoneGuide.overlay)
        end
    end
    if UI and UI.PushOverlay then pcall(function() UI.PushOverlay(ZoneGuide.overlay) end) end
end

-- 显示某区域的引导（不论是否已看过）。
function ZoneGuide.Show(ctx, zone, rootPanel)
    local steps = ZONE_STEPS[zone]
    if not steps or not ctx or not ctx.UI then return end
    renderStep(ctx, zone, steps, 1, rootPanel)
    -- 仅当引导真正挂到有效根（可见）后才记“看过”，避免“标记了却没弹”
    if ZoneGuide.overlay and ZoneGuide.overlay.parent then
        ZoneGuide.MarkSeen(ctx, zone, true)
    end
end

-- 首次进入某区域时自动弹引导；看过则跳过。rootPanel 必须是当前活动 UI 根。
function ZoneGuide.MaybeShow(ctx, zone, rootPanel)
    local steps = ZONE_STEPS[zone]
    if not steps or not ctx or not ctx.UI then return false end
    if ZoneGuide.IsSeen(ctx, zone) then return false end
    ZoneGuide.Show(ctx, zone, rootPanel)
    return true
end

return ZoneGuide
