-- ============================================================
-- config/NPCConfig.lua - NPC 静态配置与好感度纯函数
-- ============================================================

local NPCConfig = {}

NPCConfig.NPC_DEFS = {
    { name = "小花", title = "花店老板娘", color = Color(0.95, 0.55, 0.7, 1.0),
      pos = Vector3(45, 0, 30.0), wanderRadius = 1.6, homeBuilding = "flower_shop",
      personality = "温柔", likes = { "郁金香", "向日葵" },
      portrait = "image/npc_xiaohua_20260616062912.png",
      dialogues = {
          [0] = { "你好呀，新来的农场主~", "需要花种子吗？我这里品种很多哦！" },
          [1] = { "今天天气真好，适合种花呢~", "有空来我这坐坐吧！" },
          [2] = { "嘿嘿，又来找我啦？", "给你看看我新培育的品种！" },
          [3] = { "你是我最好的朋友了！", "这些花种送你，别客气~" },
      }
    },
    { name = "阿牛", title = "养殖能手", color = Color(0.6, 0.45, 0.3, 1.0),
      pos = Vector3(57.8, 0, 21.4), wanderRadius = 4.0, homeBuilding = "ranch",
      personality = "憨厚", likes = { "玉米", "南瓜" },
      portrait = "image/npc_aniu_20260616062911.png",
      dialogues = {
          [0] = { "哟，新邻居！", "我是养鸡场的阿牛，有啥不懂的问我！" },
          [1] = { "最近鸡蛋产量不错~", "你那庄稼长得咋样了？" },
          [2] = { "兄弟，来喝碗汤！", "有好东西给你分享~" },
          [3] = { "你可是我最铁的哥们儿！", "以后我的饲料半价给你！" },
      }
    },
    { name = "林爷爷", title = "退休渔夫", color = Color(0.5, 0.6, 0.7, 1.0),
      pos = Vector3(46, 0, -11.0), wanderRadius = 1.0, homeBuilding = "lake",
      personality = "睿智", likes = { "萝卜", "草莓" },
      portrait = "image/npc_lingrandpa_20260616062908.png",
      dialogues = {
          [0] = { "年轻人，来钓鱼吗？", "这湖里的鱼可肥了！" },
          [1] = { "耐心是钓鱼的关键...", "急性子可钓不到大鱼啊。" },
          [2] = { "不错不错，有悟性！", "送你个秘诀：阴天鱼更活跃。" },
          [3] = { "你让我想起年轻时的自己...", "这根鱼竿送给你，好好用！" },
      }
    },
    { name = "小月", title = "杂货店员", color = Color(0.85, 0.75, 0.4, 1.0),
      pos = Vector3(39.5, 0, 30.0), wanderRadius = 1.6, homeBuilding = "shop",
      personality = "活泼", likes = { "番茄", "草莓" },
      portrait = "image/npc_xiaoyue_20260616062914.png",
      dialogues = {
          [0] = { "欢迎光临~", "今天有什么想买的？" },
          [1] = { "哎呀，常客来了！", "给你推荐个好东西~" },
          [2] = { "嘻嘻，每次看到你心情都好好~", "下次一起去探险吧！" },
          [3] = { "你是我最好的朋友啦！", "VIP 专属折扣给你！" },
      }
    },
    { name = "老陈", title = "木匠师傅", color = Color(0.55, 0.4, 0.25, 1.0),
      pos = Vector3(21.9, 0, 40.4), wanderRadius = 2.4, homeBuilding = "carpenter",
      personality = "严肃", likes = { "南瓜", "玉米" },
      portrait = "image/npc_laochen_20260616063024.png",
      dialogues = {
          [0] = { "嗯？有事吗？", "我正忙着做家具呢。" },
          [1] = { "做事情要专注...", "你农场的围栏我可以帮你修。" },
          [2] = { "看来你不是那种三天打鱼的人。", "不错，有什么需要帮忙的说一声。" },
          [3] = { "你小子行啊！", "有个大活儿，想不想一起干？" },
      }
    },
    { name = "张村长", title = "村庄管理者", color = Color(0.5, 0.55, 0.65, 1.0),
      pos = Vector3(10, 0, 36), wanderRadius = 3.0, homeBuilding = nil,  -- 临时兜底：村公所无 3D 模型，按 §0 方案 A 挪至公告栏旁；待补模型后恢复 "town_hall" 且 pos=Vector3(2,0,-10)
      personality = "慈祥", likes = { "南瓜", "萝卜" },
      portrait = "image/npc_zhang_villagechief_20260623035924.png",
      dialogues = {
          [0] = { "欢迎来到梦境村！", "有什么不懂的尽管问我。" },
          [1] = { "村子虽小，五脏俱全！", "多去和邻居们走动走动。" },
          [2] = { "你让这村子有了活力！", "继续加油，我看好你！" },
          [3] = { "你就是这村的骄傲！", "以后有什么决定我都支持你！" },
      }
    },
    { name = "李婶", title = "酒馆厨娘", color = Color(0.8, 0.5, 0.3, 1.0),
      pos = Vector3(50.5, 0, 30.0), wanderRadius = 1.8, homeBuilding = "tavern",
      personality = "热情", likes = { "番茄", "玉米" },
      portrait = "image/npc_lishen_cook_20260623035925.png",
      dialogues = {
          [0] = { "来来来，尝尝我做的汤！", "新来的孩子都瘦，多吃点！" },
          [1] = { "又来啦？今天给你加个菜！", "多吃点才有力气干活！" },
          [2] = { "你这孩子讨人喜欢！", "想学做菜吗？我教你几手！" },
          [3] = { "你就是我半个孩子了！", "以后来吃饭不要钱！" },
      }
    },
    { name = "王大夫", title = "村医", color = Color(0.55, 0.65, 0.75, 1.0),
      pos = Vector3(50.8, 0, 30.5), wanderRadius = 2.0, homeBuilding = "clinic",
      personality = "文雅", likes = { "草莓", "草药" },
      portrait = "image/npc_wang_doctor_20260716.png",
      dialogues = {
          [0] = { "身体不舒服吗？让我看看。", "依我看，你需要好好休息一下。" },
          [1] = { "最近天气变化大，注意保暖。", "我这里有些草药，对你有好处。" },
          [2] = { "你气色好多了！", "这个药方送给你，有备无患。" },
          [3] = { "你就是我的好朋友了！", "以后看病不收钱！" },
      }
    },
    { name = "老刘", title = "铁匠师傅", color = Color(0.4, 0.35, 0.3, 1.0),
      pos = Vector3(15, 0, 38.8), wanderRadius = 2.5, homeBuilding = "smithy",  -- 修正：原 "blacksmith" 与注册表 id "smithy" 不一致
      personality = "豪爽", likes = { "铁矿", "煤炭" },
      portrait = "image/npc_laoliu_smith_20260716.png",
      dialogues = {
          [0] = { "叮叮当当！来得正好！", "需要打铁还是修理工具？" },
          [1] = { "好铁要千锤百炼！", "你这工具该升升级了。" },
          [2] = { "你这小子有点意思！", "来，我教你一招独门锻造术。" },
          [3] = { "你是我见过最有天赋的农场主！", "这把剑是我专门为你打造的！" },
      }
    },
    { name = "马可", title = "旅行商人", color = Color(0.7, 0.5, 0.3, 1.0),
      pos = Vector3(12, 0, 42), wanderRadius = 5.0, homeBuilding = nil,  -- 开放世界例外：无固定建筑，按 pos 在广场/市集漫游；显隐见 §4
      personality = "神秘", likes = { "稀有物品", "旅行故事" },
      portrait = "image/npc_marco_merchant_20260716.png",
      dialogues = {
          [0] = { "哟！新面孔！我是马可，走南闯北的商人。", "我这里有些稀罕玩意儿，看看？" },
          [1] = { "老顾客来了！今天又进了新货！", "农场最近怎么样？我这有批新种子..." },
          [2] = { "老朋友！专门绕路过来看你！", "我打听到一个关于遗迹的消息..." },
          [3] = { "你是我在所有村子里最好的朋友！", "我走遍大陆收集的信息，都为了帮你。" },
      }
    },
    -- 〔市集独立 v1〕独立市集区的固定商贩 NPC
    { name = "阿果", title = "水果摊主", color = Color(0.85, 0.45, 0.35, 1.0),
      pos = Vector3(4, 0, 39), wanderRadius = 1.0, homeBuilding = "market_stall",
      personality = "热情", likes = { "草莓", "苹果" },
      portrait = "image/npc_male_00_tripo_material_79813308-367e-4ec9-9946-4d37e3a1d17f.png",
      dialogues = {
          [0] = { "新鲜的水果！快来尝尝！", "刚从果园摘下来的，甜得很！" },
          [1] = { "今天苹果卖得不错~", "你要不要也来一篮？" },
          [2] = { "老顾客来啦！", "这批草莓专门给你留的。" },
          [3] = { "你可是我最好的朋友！", "以后来我摊位随便吃！" },
      }
    },
    { name = "阿菜", title = "蔬菜摊主", color = Color(0.45, 0.65, 0.35, 1.0),
      pos = Vector3(10, 0, 39), wanderRadius = 1.0, homeBuilding = "market_stall",
      personality = "爽朗", likes = { "番茄", "萝卜" },
      portrait = "image/npc_female_00_tripo_material_6b7768ca-6466-4a04-8701-ce0f55ba07ed.png",
      dialogues = {
          [0] = { "自家种的蔬菜，绿色健康！", "看看这萝卜，多水灵！" },
          [1] = { "种菜可是门学问。", "你农场里的菜长得咋样？" },
          [2] = { "你这人挺实在。", "下回我给你留点好种子。" },
          [3] = { "咱就是一家人！", "这些菜你拿去，别给钱！" },
      }
    },
    { name = "阿面", title = "面包摊主", color = Color(0.75, 0.60, 0.40, 1.0),
      pos = Vector3(10, 0, 47), wanderRadius = 1.0, homeBuilding = "market_stall",
      personality = "温和", likes = { "小麦", "玉米" },
      portrait = "image/npc_male_00_tripo_material_79813308-367e-4ec9-9946-4d37e3a1d17f.png",
      dialogues = {
          [0] = { "刚出炉的面包，香喷喷！", "来一块尝尝？" },
          [1] = { "这面包用村里最好的小麦做的。", "吃了干活有劲儿！" },
          [2] = { "你尝尝这个新品。", "特意给你留了一个。" },
          [3] = { "你是我最尊贵的客人！", "以后我的面包你随便拿！" },
      }
    },
    -- 〔集市扩展 2026-09-01〕新增摊主：驻入口通道，刻意不占 L0 交互锚点
    --（NPC 对话 F 键优先级高于交互锚点，重叠会吞掉摊位交互）
    { name = "老周", title = "鱼贩", color = Color(0.30, 0.50, 0.65, 1.0),
      pos = Vector3(14, 0, 33.5), wanderRadius = 1.2, homeBuilding = "market_stall",
      personality = "爽快", likes = { "鲤鱼", "鲫鱼" },
      portrait = "image/npc_male_00_tripo_material_79813308-367e-4ec9-9946-4d37e3a1d17f.png",
      dialogues = {
          [0] = { "刚靠岸的鲜鱼，活蹦乱跳！", "清晨的湖鱼，熬汤最鲜！" },
          [1] = { "你钓的鱼要是吃不完，拿我这来。", "今天湖上风平浪静，好钓鱼。" },
          [2] = { "老主顾！这条大的给你便宜点。", "我给你留了最肥的一尾。" },
          [3] = { "咱俩谁跟谁，鱼随便挑！", "以后你的鱼我包销了！" },
      }
    },
    { name = "小葵", title = "种子商", color = Color(0.55, 0.70, 0.40, 1.0),
      pos = Vector3(6, 0, 33.5), wanderRadius = 1.2, homeBuilding = "market_stall",
      personality = "细心", likes = { "向日葵", "番红花" },
      portrait = "image/npc_female_00_tripo_material_6b7768ca-6466-4a04-8701-ce0f55ba07ed.png",
      dialogues = {
          [0] = { "种子要挑饱满的，产量才高。", "应季的种子刚到货，看看？" },
          [1] = { "你这农场打理得真不错。", "种地先选种，这是根本。" },
          [2] = { "这包种子是特意给你留的。", "信我，这批发芽率特别高。" },
          [3] = { "你是我最信赖的客人！", "新种子到了先给你留着！" },
      }
    },
    -- 〔DLC 场景 NPC v2〕只在其 dlcScene 场景创建（NpcSystem.ShouldCreateNpc 守卫）
    { name = "钱掌柜", title = "城镇银行家", color = Color(0.35, 0.45, 0.62, 1.0),
      pos = Vector3(0, 0, 44), wanderRadius = 1.2, homeBuilding = "town_bank", dlcScene = "town",
      personality = "精明", likes = { "南瓜", "向日葵" },
      portrait = "image/npc_male_00_tripo_material_79813308-367e-4ec9-9946-4d37e3a1d17f.png",
      dialogues = {
          [0] = { "欢迎光临城镇银行！", "存款有利息，童叟无欺。" },
          [1] = { "又来存钱啦？好眼光！", "利滚利，日子越过越红火。" },
          [2] = { "老主顾了，柜台随便用！", "最近金库又扩容了。" },
          [3] = { "你是本行最尊贵的客户！", "利息再给你上浮一成！" },
      }
    },
    { name = "海妹", title = "海岛向导", color = Color(0.30, 0.65, 0.70, 1.0),
      pos = Vector3(4, 0, -41), wanderRadius = 2.5, homeBuilding = nil, dlcScene = "island",
      personality = "爽快", likes = { "草莓", "萝卜" },
      portrait = "image/npc_female_00_tripo_material_6b7768ca-6466-4a04-8701-ce0f55ba07ed.png",
      dialogues = {
          [0] = { "欢迎来到神秘海岛！", "沙滩上有贝壳，篝火能烤东西。" },
          [1] = { "今天潮水不错，去捡贝吧！", "退潮后的沙滩最热闹。" },
          [2] = { "你来得真勤！", "带你看个隐藏礁石区。" },
          [3] = { "你已经是自己人了！", "岛上的秘密都告诉你。" },
      }
    },
    { name = "草叔", title = "全牧场主", color = Color(0.55, 0.50, 0.30, 1.0),
      pos = Vector3(-12, 0, 26), wanderRadius = 3.5, homeBuilding = nil, dlcScene = "big_ranch",
      personality = "豪迈", likes = { "玉米", "南瓜" },
      portrait = "image/npc_male_00_tripo_material_79813308-367e-4ec9-9946-4d37e3a1d17f.png",
      dialogues = {
          [0] = { "好大的牧场，随便逛！", "放牧演习随时可以参加。" },
          [1] = { "你的动物看着挺精神！", "多遛遛，产得更多。" },
          [2] = { "有点放牧的天赋啊！", "教你一手赶羊的口诀。" },
          [3] = { "兄弟，这牧场有你一半！", "以后饲料管够！" },
      }
    },
}

NPCConfig.FRIENDSHIP_NAMES = { [0] = "陌生", [1] = "认识", [2] = "朋友", [3] = "挚友" }
NPCConfig.FRIENDSHIP_ICONS = { [0] = "💤", [1] = "🤝", [2] = "💛", [3] = "❤️" }

function NPCConfig.GetFriendshipLevel(pts)
    if pts >= 75 then return 3 end
    if pts >= 50 then return 2 end
    if pts >= 25 then return 1 end
    return 0
end

return NPCConfig
