# 《梦境农场》游戏架构设计文档

> 版本: v1.1 | 更新日期: 2026-07-06

---

## 一、项目概述

《梦境农场》是一款 3D 童话梦幻风格的农场模拟经营游戏，玩家继承一座荒废农场，通过种植作物、养殖动物、探索秘境、结交村民，最终唤醒传说中的世界树。

### 技术栈
- **引擎**: Urho3D Lua (TapTap Maker)
- **渲染**: PBR 材质 + 金色小时光照系统
- **架构**: 数据驱动 + 事件总线 + 模块化设计

### 核心目标
1. 提供完整的农场模拟经营玩法
2. 支持丰富的 NPC 社交和剧情系统
3. 实现四季轮回和天气系统
4. 支持跨引擎迁移（Unity/UE）

---

## 二、系统架构

### 2.1 整体架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                      游戏入口 (main.lua)                        │
├─────────────────────────────────────────────────────────────────┤
│                    核心系统层 (core/)                            │
│  ┌─────────┐ ┌─────────┐ ┌──────────┐ ┌──────────┐ ┌─────────┐ │
│  │EventBus │ │DataMgr  │ │TimeSys   │ │SaveSys   │ │QuestSys │ │
│  └────┬────┘ └────┬────┘ └────┬─────┘ └────┬─────┘ └────┬────┘ │
│       │           │           │            │            │       │
├───────┼───────────┼───────────┼────────────┼────────────┼───────┤
│                    业务系统层 (gameplay/core/)                   │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐           │
│  │CropSystem    │ │WeatherSystem │ │RegionSystem  │           │
│  │PestDisease   │ │FestivalSystem│ │DialogueSystem│           │
│  │WorldTreeSys  │ │AnimalSystem  │ │NpcSystem     │           │
│  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘           │
│         │                │                │                    │
├─────────┼────────────────┼────────────────┼─────────────────────┤
│                    数据配置层 (data/)                            │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌───────┐ ┌───────┐ ┌─────────┐   │
│  │crops │ │items │ │npc   │ │quests │ │recipes│ │dialogue │   │
│  └──────┘ └──────┘ └──────┘ └───────┘ └───────┘ └─────────┘   │
│  ┌─────────┐ ┌──────────┐                                     │
│  │weather  │ │festivals │                                     │
│  └─────────┘ └──────────┘                                     │
├─────────────────────────────────────────────────────────────────┤
│                    场景渲染层 (scene/)                           │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────────────┐    │
│  │FarmScene     │ │ExploreScene  │ │RealisticBuildings    │    │
│  │LakeScene     │ │InteriorScene │ │RealisticMaterials    │    │
│  └──────────────┘ └──────────────┘ └──────────────────────┘    │
├─────────────────────────────────────────────────────────────────┤
│                    UI交互层 (ui/)                                │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────────────┐   │
│  │HUD       │ │QuestPanel│ │LoginMenu │ │SettingsPanel   │   │
│  │Guide     │ │Account   │ │Minimap   │ │LifeTransition  │   │
│  └──────────┘ └──────────┘ └──────────┘ └────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 核心系统职责

| 系统 | 职责 | 关键特性 |
|------|------|---------|
| **EventBus** | 事件总线 | 解耦模块通信，支持订阅/发布 |
| **DataManager** | 数据管理 | JSON 配置加载，缓存查询 |
| **TimeSystem** | 时间系统 | 日夜循环、季节切换、时间加速 |
| **SaveSystem** | 存档系统 | 多槽存档、自动保存、版本兼容 |
| **QuestSystem** | 任务系统 | 任务追踪、条件判断、奖励发放 |
| **WeatherSystem** | 天气系统 | 随机天气、灾害事件、作物影响 |
| **RegionSystem** | 地区系统 | 气候带、专属作物、地区变体 |
| **DialogueSystem** | 对话系统 | 好感度、多分支对话、礼物反应 |
| **FestivalSystem** | 节日系统 | 季节节日、活动参与、奖励发放 |
| **WorldTreeSystem** | 世界树系统 | 四季之种收集、祭坛仪式、7日养成 |
| **PestDiseaseSystem** | 病虫害系统 | 病害触发、害虫驱除、作物影响 |

---

## 三、核心系统设计

### 3.1 EventBus 事件总线

**设计模式**: 观察者模式

```lua
-- 核心接口
EventBus.Subscribe(eventName, callback)  -- 订阅事件
EventBus.Emit(eventName, ...)           -- 发布事件
EventBus.Unsubscribe(eventName, callback) -- 取消订阅
```

**标准事件列表**:

| 事件名 | 参数 | 触发时机 |
|--------|------|---------|
| OnTimeChange | day, hour, minute | 时间变化 |
| OnDayChange | day | 新的一天 |
| OnSeasonChange | season | 季节切换 |
| OnWeatherChange | weather | 天气变化 |
| OnQuestAccepted | questId, questDef | 接受任务 |
| OnQuestCompleted | questId | 完成任务 |
| OnItemAdded | itemId, count | 添加物品 |
| OnMoneyChanged | amount | 金钱变化 |
| OnWorldTreeUnlocked | - | 世界树解锁 |
| OnWorldTreePlanted | - | 世界树种植 |
| OnWorldTreeBloomed | - | 世界树开花 |
| OnAllSeasonSeedsCollected | - | 集齐四季之种 |
| OnFestivalAttended | festivalId, festival | 参加节日 |

### 3.2 DataManager 数据管理

**设计模式**: 单例 + 数据仓库

```lua
-- 核心接口
DataManager.LoadAll()              -- 加载所有配置
DataManager.GetCrop(cropId)        -- 获取作物配置
DataManager.GetNPC(npcId)          -- 获取NPC配置
DataManager.GetQuest(questId)      -- 获取任务配置
DataManager.GetWeather(weatherId)  -- 获取天气配置
DataManager.GetDialogue(npcId)     -- 获取对话配置
DataManager.GetFestival(festivalId)-- 获取节日配置
```

**数据文件索引**:

| 文件 | 用途 | 格式 |
|------|------|------|
| crops.json | 作物定义 | 生长周期、季节、价格 |
| items.json | 物品定义 | 类型、价格、效果 |
| npc.json | NPC定义 | 属性、喜好、日程 |
| quests.json | 任务定义 | 目标、奖励、条件 |
| recipes.json | 配方定义 | 原料、产物、分类 |
| dialogue.json | 对话定义 | 问候、对话、故事 |
| weather.json | 天气定义 | 温度、湿度、效果 |
| festivals.json | 节日定义 | 时间、奖励、类型 |

### 3.3 TimeSystem 时间系统

**设计模式**: 状态机

```lua
-- 核心接口
TimeSystem.GetTime()           -- 获取当前时间
TimeSystem.Update(dt)         -- 更新时间
TimeSystem.SetSpeed(speed)     -- 设置时间速度
TimeSystem.GetSeasonName()    -- 获取季节名称
TimeSystem.IsNight()          -- 是否夜晚
```

**时间单位**:
- 游戏内一天 = 20 分钟现实时间
- 一季 = 28 天
- 一年 = 4 季 = 112 天

### 3.4 SaveSystem 存档系统

**设计模式**: 持久化管理器

```lua
-- 核心接口
SaveSystem.Save(slot)           -- 保存到指定槽位
SaveSystem.Load(slot)           -- 从指定槽位加载
SaveSystem.Reset()             -- 重置存档
SaveSystem.CheckAutoSave(time)  -- 检查自动保存
```

**存档结构**:

```json
{
  "version": "1.1",
  "player": { "money": 100, "stamina": 100, "level": 1, ... },
  "inventory": [{ "id": "carrot_seed", "count": 10 }],
  "farm": { "tiles": {}, "buildings": {} },
  "relationships": {},
  "quests": {},
  "worldTree": {
    "unlocked": false, "planted": false, "growthDay": 0, ...
  },
  "festivals": {
    "attendedFestivals": {}, "festivalHistory": [], ...
  }
}
```

### 3.5 WorldTreeSystem 世界树系统

**设计模式**: 状态机 + 进度追踪

```lua
-- 核心接口
WorldTreeSystem.CanUnlock(game)           -- 是否可解锁
WorldTreeSystem.CollectSeasonSeed(game, seasonId)  -- 收集季节种子
WorldTreeSystem.ActivateAltar(game)       -- 激活祭坛
WorldTreeSystem.Plant(game)               -- 种植世界树
WorldTreeSystem.Care(game, day)           -- 照料世界树
WorldTreeSystem.GetStatus(game)           -- 获取状态
```

**成长阶段**:

| 阶段 | 名称 | 图标 | 条件 |
|------|------|------|------|
| 0 | 沉睡 | 💤 | 未解锁 |
| 1 | 萌芽 | 🌱 | 种植后第1天 |
| 2 | 幼苗 | 🌿 | 种植后第2-3天 |
| 3 | 小树 | 🌳 | 种植后第4-5天 |
| 4 | 大树 | 🌲 | 种植后第6天 |
| 5 | 开花 | 🌺 | 种植后第7天 |
| 6 | 盛开 | ✨ | 完全开花 |

**四季之种**:

| 季节 | 种子ID | 名称 | 图标 |
|------|--------|------|------|
| spring | seed_spring | 春之种 | 🌸 |
| summer | seed_summer | 夏之种 | ☀️ |
| autumn | seed_autumn | 秋之种 | 🍂 |
| winter | seed_winter | 冬之种 | ❄️ |

---

## 四、游戏数据设计

### 4.1 数据驱动原则

1. **配置与逻辑分离**: 所有游戏数据存储在 JSON 配置文件中
2. **类型安全**: 通过 DataManager 提供强类型访问接口
3. **热更新**: 支持运行时重新加载配置
4. **版本兼容**: 存档格式支持版本迁移

### 4.2 数据模型

#### 作物模型 (crops.json)

```json
{
  "id": "carrot",
  "name": "胡萝卜",
  "description": "常见的根茎蔬菜",
  "buyPrice": 10,
  "sellPrice": 30,
  "growthDays": 4,
  "seasons": [1, 2, 3],
  "regrowth": 0,
  "waterNeeded": true,
  "seedId": "carrot_seed"
}
```

#### NPC 模型 (npc.json)

```json
{
  "id": "zhang_cunzhang",
  "name": "张村长",
  "age": 65,
  "gender": "male",
  "likes": ["gold", "tea", "rice"],
  "dislikes": ["garbage", "rocks"],
  "position": {"x": 0, "z": 0},
  "homeBuilding": "town_hall",
  "schedule": []
}
```

#### 对话模型 (dialogue.json)

```json
{
  "id": "zhang_cunzhang",
  "greetings": {
    "stranger": ["欢迎来到梦境村"],
    "friend": ["老朋友，今天也辛苦了"]
  },
  "dialogues": {
    "stranger": ["这片土地荒废很久了"],
    "friend": ["世界树的传说代代相传"]
  },
  "personalStory": [],
  "villageComments": [],
  "taskOffers": []
}
```

#### 天气模型 (weather.json)

```json
{
  "id": "sunny",
  "name": "晴天",
  "icon": "☀️",
  "temperature": 22,
  "moistureGain": 0,
  "moistureEvaporation": 1.2,
  "growthModifier": 1.0,
  "isDisaster": false,
  "visualEffect": "bright_sun"
}
```

#### 节日模型 (festivals.json)

```json
{
  "id": "spring_seed",
  "name": "春耕播种节",
  "icon": "🌱",
  "season": 1,
  "day": 5,
  "host": "zhang_cunzhang",
  "rewardGold": 30,
  "staminaCost": 10,
  "friendshipGain": 2,
  "type": "seasonal"
}
```

---

## 五、场景设计

### 5.1 场景层级

| 层级 | 场景 | 功能 |
|------|------|------|
| 主场景 | FarmScene | 农场核心区域，种植、养殖 |
| 探索场景 | ExploreScene | 矿洞、遗迹探索 |
| 湖泊场景 | LakeScene | 钓鱼、采集 |
| 室内场景 | InteriorScene | 商店、诊所、酒馆 |

### 5.2 场景资源管理

```lua
-- SceneResources.lua - 场景资源统一管理
local SceneResources = {
    materials = {},
    models = {},
    textures = {},
}

function SceneResources.Load()
    -- 加载所有场景资源
end
```

### 5.3 建筑系统

```lua
-- buildings.lua - 建筑定义
local BUILDINGS = {
    house = { id = "house", name = "主屋", cost = 500 },
    barn = { id = "barn", name = "谷仓", cost = 800 },
    chicken_coop = { id = "chicken_coop", name = "鸡舍", cost = 300 },
    greenhouse = { id = "greenhouse", name = "温室", cost = 1500 },
}
```

---

## 六、UI 系统设计

### 6.1 UI 组件架构

```
UI.Panel
  ├── UI.Label          # 文本显示
  ├── UI.Button         # 按钮交互
  ├── UI.Slider         # 滑块控件
  ├── UI.Image          # 图片显示
  ├── UI.ScrollView     # 滚动视图
  └── UI.Container      # 容器布局
```

### 6.2 UI 面板列表

| 面板 | 功能 | 文件 |
|------|------|------|
| HUD | 游戏主界面 | ui/hud/FarmHudTheme.lua |
| QuestPanel | 任务面板 | ui/QuestPanel.lua |
| Minimap | 小地图 | ui/Minimap.lua |
| SettingsPanel | 设置面板 | ui/SettingsPanel.lua |
| LoginMenu | 登录菜单 | ui/LoginMenu.lua |
| GuidePanel | 新手引导 | ui/GuidePanel.lua |

---

## 七、跨引擎迁移策略

### 7.1 设计原则

1. **数据与逻辑分离**: 所有游戏数据存储在 JSON/配置文件中
2. **接口抽象**: 核心系统通过统一接口访问
3. **平台无关**: 避免使用引擎特定的硬编码功能
4. **模块化**: 每个系统独立，便于迁移

### 7.2 引擎映射表

#### Lua → C# (Unity) 映射

| Urho3D Lua | Unity C# | 说明 |
|------------|----------|------|
| File(path, FILE_READ) | File.ReadAllText(path) | 文件读取 |
| cjson.encode/decode | JsonUtility.ToJson/FromJson | JSON 序列化 |
| Vector3(x, y, z) | Vector3(x, y, z) | 向量 |
| Quaternion(r, axis) | Quaternion.AngleAxis(r, axis) | 四元数 |
| Node:CreateChild(name) | new GameObject(name) | 创建节点 |
| SubscribeToEvent(event, handler) | EventBus.Subscribe(event, handler) | 事件订阅 |
| cache:GetResource(type, path) | Resources.Load(path) | 资源加载 |
| renderer:SetViewport(...) | Camera.targetTexture | 渲染视图 |

#### 核心系统迁移路径

| 系统 | Lua 文件 | C# 文件路径 | 迁移优先级 |
|------|----------|-------------|-----------|
| EventBus | core/EventBus.lua | Core/EventBus.cs | P0 |
| DataManager | core/DataManager.lua | Core/DataManager.cs | P0 |
| TimeSystem | core/TimeSystem.lua | Core/TimeSystem.cs | P0 |
| SaveSystem | core/SaveSystem.lua | Core/SaveSystem.cs | P0 |
| QuestSystem | core/QuestSystem.lua | Core/QuestSystem.cs | P1 |
| WeatherSystem | core/WeatherSystem.lua | Core/WeatherSystem.cs | P1 |
| DialogueSystem | core/DialogueSystem.lua | Core/DialogueSystem.cs | P1 |
| WorldTreeSystem | gameplay/WorldTreeSystem.lua | Gameplay/WorldTreeSystem.cs | P1 |
| CropSystem | gameplay/CropSystem.lua | Gameplay/CropSystem.cs | P2 |
| NpcSystem | gameplay/NpcSystem.lua | Gameplay/NpcSystem.cs | P2 |
| FestivalSystem | core/FestivalSystem.lua | Core/FestivalSystem.cs | P2 |

### 7.3 数据迁移

**JSON 配置文件无需修改，直接复用**：
- crops.json → Assets/Data/crops.json
- items.json → Assets/Data/items.json
- npc.json → Assets/Data/npc.json
- quests.json → Assets/Data/quests.json
- recipes.json → Assets/Data/recipes.json
- dialogue.json → Assets/Data/dialogue.json
- weather.json → Assets/Data/weather.json
- festivals.json → Assets/Data/festivals.json

### 7.4 场景迁移

**3D 模型迁移**：
1. Urho3D 模型 (.mdl) → FBX/GLB 格式
2. PBR 材质 → Unity Standard Shader 或 HDRP 材质
3. 光照系统 → Unity Light 组件
4. 粒子系统 → Unity Particle System

**场景重建建议**：
1. 使用 Unity 场景管理器重建场景层次
2. 使用预制件 (Prefab) 替换 Urho3D 节点模板
3. 使用 NavMesh 替换 Urho3D 导航系统

### 7.5 代码迁移步骤

```
Step 1: 创建 Unity 项目结构
        ├── Assets/
        │   ├── Core/           # 核心系统
        │   ├── Gameplay/       # 业务系统
        │   ├── Data/           # JSON配置
        │   ├── UI/             # UI组件
        │   └── Scenes/         # 场景

Step 2: 迁移核心系统 (EventBus, DataManager, TimeSystem, SaveSystem)

Step 3: 迁移业务系统 (QuestSystem, WeatherSystem, DialogueSystem)

Step 4: 迁移游戏玩法 (CropSystem, NpcSystem, WorldTreeSystem)

Step 5: 重建场景和UI

Step 6: 测试和优化
```

---

## 八、开发路线图

### Phase 1: 基础框架 (完成)
- ✅ 核心系统架构
- ✅ 数据配置系统
- ✅ 时间系统
- ✅ 存档系统

### Phase 2: 游戏玩法 (完成)
- ✅ 作物系统
- ✅ 任务系统
- ✅ NPC系统
- ✅ 天气系统
- ✅ 地区系统

### Phase 3: 终章内容 (进行中)
- ✅ 世界树系统
- ✅ 节日系统
- ✅ 对话系统
- ✅ 病虫害系统

### Phase 4: 跨引擎迁移
- 📋 Unity C# 核心系统迁移
- 📋 场景重建
- 📋 UI 重构
- 📋 性能优化

---

## 九、代码规范

### 9.1 命名规范

| 类型 | 规范 | 示例 |
|------|------|------|
| 文件 | 驼峰式 | CropSystem.lua |
| 类/模块 | PascalCase | WorldTreeSystem |
| 函数 | 驼峰式 | GetSeasonSeed() |
| 变量 | 蛇形命名 | growth_day |
| 常量 | 全大写 | MAX_PLAYERS |
| 事件名 | 帕斯卡式 | OnWorldTreeBloomed |

### 9.2 代码结构

```lua
-- 文件头部注释
-- ============================================================
-- module/FileName.lua - 功能描述
-- ============================================================

local ModuleName = {}

-- 私有变量/常量
local PRIVATE_CONST = 100

-- 公共接口
function ModuleName.PublicFunction()
    -- 实现
end

return ModuleName
```

### 9.3 事件命名规范

```lua
-- 格式: On + 系统名 + 动作
OnWorldTreeUnlocked      -- 世界树解锁
OnSeasonSeedCollected   -- 季节种子收集
OnFestivalAttended      -- 参加节日
OnQuestAccepted         -- 接受任务
```

---

## 十、性能优化策略

### 10.1 数据层优化

1. **配置缓存**: DataManager 加载后缓存到内存
2. **批量加载**: 启动时一次性加载所有配置
3. **对象池**: 重复使用的对象（如粒子、UI元素）使用对象池

### 10.2 渲染层优化

1. **LOD 系统**: 远景使用低精度模型
2. **遮挡剔除**: 隐藏被遮挡的物体
3. **批处理**: 合并相同材质的渲染

### 10.3 逻辑层优化

1. **事件节流**: 避免频繁触发事件
2. **延迟更新**: 非关键逻辑延迟到下一帧
3. **空间分区**: 使用网格或四叉树优化碰撞检测

---

## 附录：版本历史

| 版本 | 日期 | 变更内容 |
|------|------|---------|
| v1.0 | 2026-06 | 基础框架完成 |
| v1.1 | 2026-07 | 添加世界树、节日、对话系统，跨引擎迁移文档 |

---

*文档结束*