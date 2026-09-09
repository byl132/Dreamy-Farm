---@diagnostic disable: undefined-global
-- ============================================================
-- BookSystem - 在家看书增强（Sprint3）
-- 书架 / 阅读器 / 图鉴；奖励经验·体力·解锁配方；持久化进 game 表。
-- DI 模式：BookSystem.Init(ctx) 注入依赖；公开函数以 _ctx 为回退。
-- 视觉 token 取自 design/art/book-ui.md。
-- ============================================================

local BookSystem = {}

-- 〔视觉 token〕#8B5E3C / #5D3A1A / #FDF6E9 / #3E2723 / #C9A227 / #4A7C59 / #E65100
local COLORS = {
    wood       = { 139,  94,  60 },
    woodDark   = {  93,  58,  26 },
    cream      = { 253, 246, 233 },
    brown      = {  62,  39,  35 },  -- 正文（与 cream 对比≈13:1）
    brownLight = { 109,  76,  65 },
    gold       = { 201, 162,  39 },
    green      = {  74, 124,  89 },  -- 已读
    warn       = { 230,  81,   0 },  -- 未解锁
    silhouette = { 201, 194, 184 },  -- 未解锁剪影
    overlay    = {   0,   0,   0, 150 },
}

-- 分类封面色 + 中文名
local CATEGORY_COLORS = {
    agriculture = COLORS.green,
    plot       = COLORS.gold,
    codex      = COLORS.brownLight,
    skill      = COLORS.wood,
    legend     = COLORS.gold,
}
local CATEGORY_NAMES = {
    agriculture = "农业", plot = "剧情", codex = "图鉴",
    skill = "技能", legend = "传说",
}

-- 解锁条件 → 是否满足 + 提示
-- 约定： "always" / "ruins_visited"(game.codex.ruins) / "bestiary_<key>"(game.codex.monsters[key])
local function bookUnlocked(bookDef, g)
    local unlock = bookDef.unlock
    if unlock == "always" or unlock == nil then return true, "" end
    g = g or {}
    local codex = g.codex or {}
    if unlock == "ruins_visited" then
        return codex.ruins == true, "需先探索遗迹"
    end
    local m = tostring(unlock):match("^bestiary_(.+)$")
    if m then
        return (codex.monsters and codex.monsters[m] == true), "需击败" .. m
    end
    return false, "解锁条件：" .. tostring(unlock)
end

-- 依赖（Init 注入）
local _ctx = nil
local _booksCache = nil

---@param ctx table  DI 依赖：UI / GetGameUIRoot / gameUIRoot / GetGame / GainExp /
--                     SaveCloudData / GetBooks / AddStamina / ShowFurnitureConfirm
function BookSystem.Init(ctx)
    _ctx = ctx
end

-- 取当前 ctx（优先传入，否则回退 _ctx）
local function resolveCtx(ctx)
    return ctx or _ctx
end

-- 取 game 表（优先 ctx.GetGame，回退全局 game）
local function getGame(ctx)
    ctx = resolveCtx(ctx)
    if ctx and ctx.GetGame then
        local ok, g = pcall(ctx.GetGame)
        if ok and g then return g end
    end
    if _ctx and _ctx.GetGame then
        local ok, g = pcall(_ctx.GetGame)
        if ok and g then return g end
    end
    return game  -- 全局 SSOT
end

-- 自加载 books.json（本项目 DataManager.LoadAll 未被调用，故自加载兜底）
local function loadBooksSelf()
    if _booksCache then return _booksCache end
    local ok, file = pcall(function() return File("data/books.json", FILE_READ) end)
    if ok and file and file:IsOpen() then
        local content = file:ReadString()
        file:Close()
        local decOk, data = pcall(cjson.decode, content)
        if decOk and data then
            _booksCache = data
            return _booksCache
        end
    end
    _booksCache = {}
    return _booksCache
end

-- 取书籍列表（DI GetBooks → DataManager.GetBooks → 自加载）
local function getBooks(ctx)
    ctx = resolveCtx(ctx)
    if ctx and ctx.GetBooks then
        local ok, b = pcall(ctx.GetBooks)
        if ok and b and #b > 0 then return b end
    end
    if _ctx and _ctx.GetBooks then
        local ok, b = pcall(_ctx.GetBooks)
        if ok and b and #b > 0 then return b end
    end
    return loadBooksSelf()
end

-- 懒初始化持久化结构（读档兜底）
local function ensureData(ctx)
    local g = getGame(ctx)
    if not g then return nil end
    g.library = g.library or {}
    g.codex = g.codex or { monsters = {}, crops = {}, ruins = false }
    g.codex.monsters = g.codex.monsters or {}
    g.codex.crops = g.codex.crops or {}
    g.unlockedRecipes = g.unlockedRecipes or {}
    return g
end

-- 懒初始化单本书条目
local function ensureLibEntry(g, bookId)
    g.library = g.library or {}
    g.library[bookId] = g.library[bookId] or { read = false, fav = false, pagesRead = 0 }
    return g.library[bookId]
end

-- 挂载到游戏 UI 根（活引用 getter，避免主菜单往返后死节点）
local function mountBookPanel(panel)
    local root
    if _ctx and _ctx.GetGameUIRoot then
        local ok, r = pcall(_ctx.GetGameUIRoot)
        if ok and r then root = r end
    end
    if not root and _ctx and _ctx.gameUIRoot then root = _ctx.gameUIRoot end
    if root then
        SafeAddChild(root, panel, "bookPanel")
        return true
    end
    print("[BookSystem] WARN: 无可用 UI 根，无法挂载面板")
    return false
end

local function closePanel(panel)
    if panel then pcall(function() panel:Remove() end) end
end

local function toast(msg)
    if _ctx and _ctx.ShowMessage then pcall(_ctx.ShowMessage, msg) end
end

-- 应用首次阅读奖励（守卫 if not read）
local function applyRewardIfFirstRead(ctx, bookDef)
    ctx = resolveCtx(ctx)
    local g = ensureData(ctx)
    if not g then return end
    local entry = ensureLibEntry(g, bookDef.id)
    if entry.read then return end  -- 重读不再发奖

    local reward = bookDef.reward
    if reward then
        if reward.exp and _ctx and _ctx.GainExp then
            pcall(_ctx.GainExp, reward.exp)
        end
        if reward.stamina then
            if _ctx and _ctx.AddStamina then
                pcall(_ctx.AddStamina, reward.stamina)
            else
                g.stamina = math.min(g.maxStamina or 100, (g.stamina or 0) + reward.stamina)
            end
        end
        if reward.unlockRecipe then
            BookSystem.UnlockRecipe(reward.unlockRecipe)
        end
    end
    entry.read = true
    if _ctx and _ctx.SaveCloudData then pcall(_ctx.SaveCloudData) end
    toast("📖 读完《" .. (bookDef.title or bookDef.id) .. "》！知识+")
end

-- 解锁配方（最小实现：仅置位标记；接入烹饪合成面板为已知限制，见交付说明）
function BookSystem.UnlockRecipe(recipeId)
    local g = ensureData(_ctx)
    if not g or not recipeId then return end
    g.unlockedRecipes[recipeId] = true
    if _ctx and _ctx.SaveCloudData then pcall(_ctx.SaveCloudData) end
end

-- 取 codex 书对应的怪物 key（unlock = "bestiary_<key>"）
local function codexMonsterKey(bookDef)
    return tostring(bookDef.unlock or ""):match("^bestiary_(.+)$")
end

-- ==================== 书架面板 ====================
local function makeBookCard(UI, g, b, openReader)
    local entry = ensureLibEntry(g, b.id)
    local unlocked, hint = bookUnlocked(b, g)
    local coverColor = CATEGORY_COLORS[b.category] or COLORS.wood

    return UI.Panel {
        flex = 1, minWidth = 0,
        backgroundColor = unlocked and COLORS.cream or COLORS.silhouette,
        borderRadius = 14, padding = 12,
        borderWidth = 2, borderColor = unlocked and coverColor or COLORS.warn,
        flexDirection = "column", gap = 6,
        children = {
            UI.Label {
                text = (unlocked and "📖 " or "🔒 ") .. (b.title or b.id),
                fontSize = 15, fontWeight = "bold",
                fontColor = unlocked and COLORS.brown or COLORS.warn,
            },
            UI.Label {
                text = unlocked
                    and (entry.read and "✓ 已读" or "未读")
                    or ("🔒 " .. (hint ~= "" and hint or "未解锁")),
                fontSize = 12, fontColor = unlocked and COLORS.green or COLORS.warn,
            },
            UI.Button {
                text = unlocked and "阅读" or "查看",
                fontSize = 13, width = "100%", height = 44,  -- ≥44px 触控
                backgroundColor = unlocked and COLORS.gold or COLORS.brownLight,
                textColor = COLORS.cream, borderRadius = 14,
                onClick = function()
                    if unlocked then
                        openReader(b.id)
                    else
                        toast("🔒 " .. (hint ~= "" and hint or "尚未解锁"))
                    end
                end,
            },
        },
    }
end

local function buildShelfGroups(UI, g, groups, openReader)
    local out = {}
    local order = { "agriculture", "plot", "skill", "legend", "codex" }
    for _, cat in ipairs(order) do
        local list = groups[cat]
        if list and #list > 0 then
            table.insert(out, UI.Label {
                text = (CATEGORY_NAMES[cat] or cat) .. "（" .. #list .. "）",
                fontSize = 16, fontWeight = "bold", fontColor = COLORS.gold,
                marginBottom = 8, marginTop = 4,
            })
            local row
            for i, b in ipairs(list) do
                if (i - 1) % 2 == 0 then
                    row = UI.Panel { flexDirection = "row", gap = 12, width = "100%", marginBottom = 12 }
                    table.insert(out, row)
                end
                row.children = row.children or {}
                table.insert(row.children, makeBookCard(UI, g, b, openReader))
            end
        end
    end
    if #out == 0 then
        table.insert(out, UI.Label { text = "（暂无书籍）", fontSize = 14, fontColor = COLORS.brownLight })
    end
    return out
end

function BookSystem.ShowBookShelfPanel(ctx)
    ctx = resolveCtx(ctx)
    local g = ensureData(ctx)
    if not g then return end
    local c = resolveCtx(ctx)
    local UI = (c and c.UI) or (_ctx and _ctx.UI)
    if not UI then print("[BookSystem] WARN: 无 UI 库"); return end

    local books = getBooks(ctx)
    local groups = {}
    for _, b in ipairs(books) do
        local cat = b.category or "plot"
        groups[cat] = groups[cat] or {}
        table.insert(groups[cat], b)
    end

    local shelfPanel
    local function closeShelf() closePanel(shelfPanel) end
    local function openReader(bookId)
        closeShelf()
        BookSystem.ShowBookReader(ctx, bookId)
    end

    shelfPanel = UI.Panel {
        width = "100%", height = "100%",
        position = "absolute", top = 0, left = 0,
        backgroundColor = COLORS.overlay,
        justifyContent = "center", alignItems = "center",
        children = {
            UI.Panel {
                width = "92%", maxWidth = 720, height = "86%",
                backgroundColor = COLORS.woodDark,
                borderRadius = 28, padding = 20,
                borderWidth = 3, borderColor = COLORS.wood,
                flexDirection = "column",
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center",
                        justifyContent = "space-between", marginBottom = 12,
                        children = {
                            UI.Label { text = "📚 书架", fontSize = 22, fontWeight = "bold",
                                fontColor = COLORS.cream },
                            UI.Button {
                                text = "📖 图鉴", fontSize = 14, width = 96, height = 44,
                                backgroundColor = COLORS.green, textColor = COLORS.cream,
                                borderRadius = 14,
                                onClick = function()
                                    closeShelf()
                                    BookSystem.ShowCodex(ctx)
                                end,
                            },
                            UI.Button {
                                text = "✕", fontSize = 18, width = 44, height = 44,
                                backgroundColor = COLORS.warn, textColor = COLORS.cream,
                                borderRadius = 14,
                                onClick = closeShelf,
                            },
                        },
                    },
                    UI.Panel {
                        flexDirection = "column", width = "100%",
                        overflow = "scroll", scrollDirection = "vertical",
                        flex = 1,
                        children = buildShelfGroups(UI, g, groups, openReader),
                    },
                },
            },
        },
    }
    mountBookPanel(shelfPanel)
end

-- ==================== 阅读面板 ====================
function BookSystem.ShowBookReader(ctx, bookId)
    ctx = resolveCtx(ctx)
    local g = ensureData(ctx)
    if not g then return end
    local c = resolveCtx(ctx)
    local UI = (c and c.UI) or (_ctx and _ctx.UI)
    if not UI then return end

    local books = getBooks(ctx)
    local bookDef
    for _, b in ipairs(books) do if b.id == bookId then bookDef = b; break end end
    if not bookDef then toast("书籍不存在：" .. tostring(bookId)); return end

    local pages = bookDef.pages or {}
    local total = #pages

    -- 向后兼容：无 pages / 空（旧贴士书）→ 降级为 ShowFurnitureConfirm 单页弹窗
    if total == 0 then
        applyRewardIfFirstRead(ctx, bookDef)
        if _ctx and _ctx.ShowFurnitureConfirm then
            _ctx.ShowFurnitureConfirm(bookDef.title or bookId, "（短内容）", nil)
        end
        return
    end

    local entry = ensureLibEntry(g, bookId)
    applyRewardIfFirstRead(ctx, bookDef)  -- 首次阅读发奖（守卫 if not read）

    local cur = 1
    local bodyLabel = UI.Label { text = "", fontSize = 14, fontColor = COLORS.brown, textAlign = "left" }
    local pageLabel = UI.Label { text = "", fontSize = 11, fontColor = COLORS.gold, marginBottom = 8 }
    local prevBtn, nextBtn, favBtn

    local function render()
        bodyLabel.text = pages[cur] or ""
        pageLabel.text = "第 " .. cur .. "/" .. total .. " 页"
        prevBtn.enabled = cur > 1
        nextBtn.enabled = cur < total
        favBtn.text = entry.fav and "★ 已收藏" or "☆ 收藏"
    end

    prevBtn = UI.Button {
        text = "‹ 上一页", fontSize = 14, width = "30%", height = 48,
        backgroundColor = COLORS.wood, textColor = COLORS.cream, borderRadius = 14,
        onClick = function()
            if cur > 1 then
                cur = cur - 1
                entry.pagesRead = math.max(entry.pagesRead or 0, cur)
                render()
            end
        end,
    }
    nextBtn = UI.Button {
        text = "下一页 ›", fontSize = 14, width = "30%", height = 48,
        backgroundColor = COLORS.wood, textColor = COLORS.cream, borderRadius = 14,
        onClick = function()
            if cur < total then
                cur = cur + 1
                entry.pagesRead = math.max(entry.pagesRead or 0, cur)
                render()
            else
                toast("已是最后一页")
            end
        end,
    }
    favBtn = UI.Button {
        text = "☆ 收藏", fontSize = 14, width = "30%", height = 48,
        backgroundColor = COLORS.brownLight, textColor = COLORS.cream, borderRadius = 14,
        onClick = function()
            entry.fav = not entry.fav
            if _ctx and _ctx.SaveCloudData then pcall(_ctx.SaveCloudData) end
            toast(entry.fav and "✅ 已收藏" or "已取消收藏")
            render()
        end,
    }

    local bottomChildren = { prevBtn, favBtn, nextBtn }
    if bookDef.category == "codex" then
        table.insert(bottomChildren, UI.Button {
            text = "📖 图鉴", fontSize = 14, width = "34%", height = 48,
            backgroundColor = COLORS.green, textColor = COLORS.cream, borderRadius = 14,
            onClick = function()
                closePanel(readerPanel)
                BookSystem.ShowCodex(ctx)
            end,
        })
    end

    local readerPanel
    readerPanel = UI.Panel {
        width = "100%", height = "100%",
        position = "absolute", top = 0, left = 0,
        backgroundColor = COLORS.overlay,
        justifyContent = "center", alignItems = "center",
        children = {
            UI.Panel {
                width = "92%", maxWidth = 720, height = "86%",
                backgroundColor = COLORS.woodDark, borderRadius = 28, padding = 20,
                borderWidth = 3, borderColor = COLORS.wood,
                flexDirection = "column",
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center",
                        justifyContent = "space-between", marginBottom = 12,
                        children = {
                            UI.Label { text = "📖 " .. (bookDef.title or bookId),
                                fontSize = 20, fontWeight = "bold", fontColor = COLORS.cream },
                            UI.Button { text = "✕", fontSize = 18, width = 44, height = 44,
                                backgroundColor = COLORS.warn, textColor = COLORS.cream, borderRadius = 14,
                                onClick = function() closePanel(readerPanel) end },
                        },
                    },
                    UI.Panel {
                        flex = 1, width = "100%",
                        backgroundColor = COLORS.cream, borderRadius = 20, padding = 20,
                        overflow = "scroll", scrollDirection = "vertical",
                        children = { bodyLabel },
                    },
                    pageLabel,
                    UI.Panel {
                        flexDirection = "row", gap = 10, width = "100%", marginTop = 10,
                        justifyContent = "center",
                        children = bottomChildren,
                    },
                },
            },
        },
    }
    render()
    mountBookPanel(readerPanel)
end

-- ==================== 图鉴面板 ====================
function BookSystem.ShowCodex(ctx)
    ctx = resolveCtx(ctx)
    local g = ensureData(ctx)
    if not g then return end
    local c = resolveCtx(ctx)
    local UI = (c and c.UI) or (_ctx and _ctx.UI)
    if not UI then return end

    local books = getBooks(ctx)
    local codex = g.codex or { monsters = {}, crops = {}, ruins = false }
    local entries = {}

    -- codex 类书籍
    for _, b in ipairs(books) do
        if b.category == "codex" then
            local key = codexMonsterKey(b)
            local found = key and codex.monsters and codex.monsters[key] == true
            table.insert(entries, {
                title = b.title or b.id,
                found = found,
                icon = "📖",
            })
        end
    end
    -- 遗迹
    table.insert(entries, { title = "古代遗迹", found = codex.ruins == true, icon = "🏛️" })
    -- 作物
    if codex.crops then
        for cid, v in pairs(codex.crops) do
            if v then
                table.insert(entries, { title = "作物·" .. tostring(cid), found = true, icon = "🌾" })
            end
        end
    end

    local grid = {}
    local row
    for i, e in ipairs(entries) do
        if (i - 1) % 2 == 0 then
            row = UI.Panel { flexDirection = "row", gap = 12, width = "100%", marginBottom = 12 }
            table.insert(grid, row)
        end
        row.children = row.children or {}
        table.insert(row.children, UI.Panel {
            flex = 1, minWidth = 0,
            backgroundColor = e.found and COLORS.cream or COLORS.silhouette,
            borderRadius = 14, padding = 12,
            borderWidth = 2, borderColor = e.found and COLORS.green or COLORS.warn,
            flexDirection = "column", gap = 4,
            children = {
                UI.Label {
                    text = (e.found and e.icon .. " " or "❓ ") .. (e.found and e.title or "???"),
                    fontSize = 14, fontWeight = "bold",
                    fontColor = e.found and COLORS.brown or COLORS.warn,
                },
                UI.Label {
                    text = e.found and "已发现" or "未发现",
                    fontSize = 12, fontColor = e.found and COLORS.green or COLORS.warn,
                },
            },
        })
    end
    if #grid == 0 then
        grid[1] = UI.Label { text = "（暂无图鉴条目）", fontSize = 14, fontColor = COLORS.brownLight }
    end

    local codexPanel
    codexPanel = UI.Panel {
        width = "100%", height = "100%",
        position = "absolute", top = 0, left = 0,
        backgroundColor = COLORS.overlay,
        justifyContent = "center", alignItems = "center",
        children = {
            UI.Panel {
                width = "92%", maxWidth = 720, height = "86%",
                backgroundColor = COLORS.woodDark, borderRadius = 28, padding = 20,
                borderWidth = 3, borderColor = COLORS.wood,
                flexDirection = "column",
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center",
                        justifyContent = "space-between", marginBottom = 12,
                        children = {
                            UI.Label { text = "📖 图鉴", fontSize = 22, fontWeight = "bold",
                                fontColor = COLORS.cream },
                            UI.Button { text = "✕", fontSize = 18, width = 44, height = 44,
                                backgroundColor = COLORS.warn, textColor = COLORS.cream, borderRadius = 14,
                                onClick = function() closePanel(codexPanel) end },
                        },
                    },
                    UI.Panel {
                        flexDirection = "column", width = "100%",
                        overflow = "scroll", scrollDirection = "vertical",
                        flex = 1,
                        children = grid,
                    },
                },
            },
        },
    }
    mountBookPanel(codexPanel)
end

return BookSystem
