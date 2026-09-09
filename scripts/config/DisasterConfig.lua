-- ============================================================
-- config/DisasterConfig.lua - 地区灾害事件配置（聚合器 + 抽样逻辑）
-- 〔按地区拆分 2026-09-01〕各地区灾害数据已拆分到 config/regions/<id>.lua
-- 的 disasters 段（真实资料锚定，每条 ref 注明出处要点），本文件只保留：
--   · 强度档位 INTENSITY（设置面板"灾害"行的数据源）
--   · 灾害数据聚合（REGIONS）+ 运行时扩展接口 RegisterRegion
--   · 归一化 Normalize / 加权抽样 Roll（与 WeatherConfig.Roll 同范式）
--
-- 可迁移性设计：
--   · 数据与逻辑分离 —— 各地区数据在 regions/<id>.lua；本文件只放逻辑
--   · 文案即翻译键 —— name/tip/ref 均为中文原文，i18n 提取后可整体翻译
--   · 权重语义：seasons[season] = 每日触发权重（总和≈该季节每日触发概率%）
--   · days = { [season]={min,max} } 可选，限定季节内天数窗口
--   · effects 简写键经 Normalize() 展开为完整结构，缺省值安全
--
-- effects 字段说明（mul = 设置强度倍率，见 INTENSITY）：
--   grow   {min,max} 单株生长进度回退比例（延迟生长）
--   q      {min,max} 单株品质损失（收获产量自动吃 quality 乘区 → 减产）
--   wither number    单株枯死概率（0-1，损毁）
--   frac   {min,max} 每株受影响判定概率（灾害波及面）
--   water  {min,max} 作物 waterLevel 增量（负=失水；正值=涝渍饱和）
--   moist  {min,max} 土壤 moisture 增量（负=旱）
--   fert   {min,max} 土壤 fertility 增量（负=养分流失/退化）
--   ph     {min,max} 土壤 ph 增量（正=盐碱化/扬尘，负=酸化）
--   weed   {min,max} 土壤 weeds 增量
--   mature {min,max} 成熟株(stage>=6)额外品质损失（干热风/冰雹等）
--   young  boolean   仅影响幼苗(stage<=3)（倒春寒等）
--   gh     boolean   温室作物可豁免该灾害
--   warn   0/1       是否提前一天预警（0=突发，冰雹/火灾等）
-- ============================================================

local DisasterConfig = {}

DisasterConfig.VERSION = 2

--- 强度档位（设置面板"灾害"行）：weight 乘触发概率、damage 乘伤害量
DisasterConfig.INTENSITY = {
    off  = { weightMul = 0.0, damageMul = 0.0 },
    easy = { weightMul = 0.5, damageMul = 0.5 },
    real = { weightMul = 1.0, damageMul = 1.0 },
    hard = { weightMul = 1.4, damageMul = 1.6 },
}
DisasterConfig.MODE_ORDER = { "off", "easy", "real", "hard" }
DisasterConfig.DEFAULT_MODE = "real"

-- ==================== 灾害数据聚合（静态 require，保证构建可达） ====================
-- 每个地区分区文件的 disasters 段：{ {id,name,icon,warn,gh,seasons,...}, ... }
local REGION_PACKAGES = {
    northeast     = require("config.regions.northeast"),
    north_china   = require("config.regions.north_china"),
    jiangnan      = require("config.regions.jiangnan"),
    australia     = require("config.regions.australia"),
    mediterranean = require("config.regions.mediterranean"),
}

DisasterConfig.REGIONS = {}
for _, id in ipairs({ "northeast", "north_china", "jiangnan", "australia", "mediterranean" }) do
    local pkg = REGION_PACKAGES[id]
    assert(pkg and pkg.disasters, "[DisasterConfig] region package missing disasters: " .. tostring(id))
    DisasterConfig.REGIONS[id] = pkg.disasters
end

--- 运行时扩展接口：为地区注入/追加灾害（自定义地区或 MOD 用）
function DisasterConfig.RegisterRegion(regionId, disasterList)
    DisasterConfig.REGIONS[regionId] = disasterList
end

-- ==================== 归一化与查询 ====================

--- 展开简写字段为完整 effects 结构（缺省安全）
function DisasterConfig.Normalize(def)
    if def._normalized then return def end
    def.frac = def.frac or { 1.0, 1.0 }
    def.grow = def.grow or { 0, 0 }
    def.q = def.q or { 0, 0 }
    def.mature = def.mature or { 0, 0 }
    def.water = def.water or { 0, 0 }
    def.moist = def.moist or { 0, 0 }
    def.fert = def.fert or { 0, 0 }
    def.ph = def.ph or { 0, 0 }
    def.weed = def.weed or { 0, 0 }
    def.wither = def.wither or 0
    def.young = def.young == true
    def.gh = def.gh == true
    def.warn = (def.warn == 0) and 0 or 1
    def.seasons = def.seasons or {}
    def.days = def.days or {}
    def._normalized = true
    return def
end

--- 取某地区全部灾害定义（已归一化）
function DisasterConfig.GetAll(regionId)
    local list = DisasterConfig.REGIONS[regionId]
    if not list then return {} end
    for _, def in ipairs(list) do DisasterConfig.Normalize(def) end
    return list
end

--- 按 id 取定义（限定地区，找不到返回 nil）
function DisasterConfig.Get(regionId, id)
    for _, def in ipairs(DisasterConfig.GetAll(regionId)) do
        if def.id == id then return def end
    end
    return nil
end

--- 区间随机 [min, max]
function DisasterConfig.RandRange(range)
    if not range then return 0 end
    local lo = math.min(range[1], range[2])
    local hi = math.max(range[1], range[2])
    if hi == lo then return lo end
    return lo + math.random() * (hi - lo)
end

--- 判定某地区某季节某天是否命中灾害（加权随机）
-- 权重语义：候选权重总和 ≈ 当日触发概率(%)，再乘 weightMul（设置强度）
---@param regionId string
---@param season number 1春2夏3秋4冬
---@param day number 季节内天数 1-28
---@param weightMul number 设置强度倍率（0=关闭）
---@return table|nil def 命中的灾害定义
function DisasterConfig.Roll(regionId, season, day, weightMul)
    if not weightMul or weightMul <= 0 then return nil end
    local candidates, total = {}, 0
    for _, def in ipairs(DisasterConfig.GetAll(regionId)) do
        local w = def.seasons[season]
        if w and w > 0 then
            local dr = def.days[season]
            if not dr or (day >= dr[1] and day <= dr[2]) then
                candidates[#candidates + 1] = { def = def, w = w }
                total = total + w
            end
        end
    end
    if total <= 0 then return nil end
    -- 先判"今日是否有灾"（概率 = 权重和% × 强度），再加权挑一种
    if math.random() * 100.0 > total * weightMul then return nil end
    local pick = math.random() * total
    for _, c in ipairs(candidates) do
        pick = pick - c.w
        if pick <= 0 then return c.def end
    end
    return candidates[#candidates].def
end

return DisasterConfig
