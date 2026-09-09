local StoryQuestDefs = {}

function StoryQuestDefs.Create(ctx)
    local game = ctx.game
    -- 〔主线任务修复〕farmPlots/crops/npcs 在重开档/换场景时会被整体换新表，
    -- 闭包捕获旧表会导致任务判定永远读死数据 → 改为活 getter 实时取当前表
    local getFarmPlots = ctx.getFarmPlots or function() return ctx.farmPlots or {} end
    local getCrops = ctx.getCrops or function() return ctx.crops or {} end
    local getNpcs = ctx.getNpcs or function() return ctx.npcs or {} end

    local chapters = {
    { id = "ch1", title = "第一章：春日农耕", levelRange = "Lv.1~3" },
    { id = "ch2", title = "第二章：牧歌田园", levelRange = "Lv.3~5" },
    { id = "ch3", title = "第三章：地底秘境", levelRange = "Lv.5~7" },
    { id = "ch4", title = "第四章：四季传说", levelRange = "Lv.7~10" },
    { id = "ch5", title = "终章：世界树之约", levelRange = "Lv.10~12" },
}

    local quests = {
    -- ═══════════ 第一章：春日农耕（Lv.1~3）═══════════
    -- 阶段一：站稳脚跟
    { id = "c1_01", chapter = 1, title = "新的开始", desc = "开垦你的第一块耕地",
      hint = "使用⛏️开垦工具点击空地", npc = "张村长", reward = { gold = 30 },
      dialogue = "这块地荒了好多年了，先开垦一块试试吧！",
      check = function() return #getFarmPlots() >= 1 end },
    { id = "c1_02", chapter = 1, title = "播种希望", desc = "种下你的第一株作物",
      hint = "选择🌱种植工具后点击耕地", npc = "小花", reward = { gold = 20 },
      dialogue = "有了耕地就要种东西呀！我送你几颗种子~",
      check = function() return #getCrops() >= 1 end },
    { id = "c1_03", chapter = 1, title = "用心灌溉", desc = "给作物浇水5次",
      hint = "使用💧浇水工具点击作物", npc = "阿牛", reward = { gold = 25 },
      dialogue = "种地最重要的就是浇水，可不能偷懒！",
      check = function() return (game._waterCount or 0) >= 5 end },
    { id = "c1_04", chapter = 1, title = "五亩良田", desc = "开垦5块耕地",
      hint = "继续用⛏️工具开垦更多空地", npc = "张村长", reward = { gold = 50 },
      dialogue = "不错不错！多开几块地，规模大了才像农场！",
      check = function() return #getFarmPlots() >= 5 end },
    { id = "c1_05", chapter = 1, title = "收获的喜悦", desc = "收获第一株成熟作物",
      hint = "等作物成熟后用🌾工具收获", npc = "小月", reward = { gold = 50 },
      dialogue = "作物熟了就赶紧收！然后来我这儿卖掉赚钱~",
      check = function() return (game._harvestCount or 0) >= 1 end },
    -- 阶段二：融入村庄
    { id = "c1_06", chapter = 1, title = "认识邻居", desc = "与3位不同NPC对话",
      hint = "走近NPC出现气泡后点击对话", npc = "张村长", reward = { gold = 60 },
      dialogue = "远亲不如近邻！去和大家打个招呼吧。",
      check = function()
          local talked = 0
          for _, npc in ipairs(getNpcs()) do if npc.friendship >= 5 then talked = talked + 1 end end
          return talked >= 3
      end },
    { id = "c1_07", chapter = 1, title = "小花的烦恼", desc = "送一颗番茄给小花",
      hint = "收获番茄后靠近小花送出", npc = "小花", reward = { gold = 40 },
      dialogue = "最近在研究新染料，需要番茄的红色素...",
      check = function() return (game._giftToXiaohua or 0) >= 1 end },
    { id = "c1_08", chapter = 1, title = "品种多样", desc = "种植2种不同作物",
      hint = "买不同种子分别种下", npc = "小花", reward = { gold = 60 },
      dialogue = "多种几样嘛！不同季节适合不同作物哦~",
      check = function()
          local types = {}
          for _, c in ipairs(crops) do types[c.cropType] = true end
          local count = 0; for _ in pairs(types) do count = count + 1 end
          return count >= 2
      end },
    { id = "c1_09", chapter = 1, title = "供货商人", desc = "在商店卖出总计10个作物",
      hint = "收获作物后去商店出售", npc = "小月", reward = { gold = 100 },
      dialogue = "我这最近缺货，你能给我供10个作物吗？价格从优！",
      check = function() return (game._totalSold or 0) >= 10 end },
    { id = "c1_10", chapter = 1, title = "小有规模", desc = "同时种植5株作物",
      hint = "开垦更多地块并种植", npc = "阿牛", reward = { gold = 80 },
      dialogue = "种得越多收得越多！加油！",
      check = function() return #getCrops() >= 5 end },
    -- 阶段三：向外探索
    { id = "c1_11", chapter = 1, title = "林爷爷的来信", desc = "前往湖边找林爷爷(Lv.2解锁)",
      hint = "升到Lv.2后去湖泊方向找林爷爷", npc = "林爷爷", reward = { gold = 40 },
      dialogue = "年轻人，来湖边找我，教你一门手艺...",
      check = function() return true end },
    { id = "c1_12", chapter = 1, title = "初次垂钓", desc = "成功钓到第一条鱼",
      hint = "到湖边点击水面开始钓鱼", npc = "林爷爷", reward = { gold = 60 },
      dialogue = "耐心...等鱼咬钩了再收线！",
      check = function() return (game.fishCaught or 0) >= 1 end },
    { id = "c1_13", chapter = 1, title = "渔获交付", desc = "累计钓到3条鱼",
      hint = "多钓几次，熟能生巧", npc = "林爷爷", reward = { gold = 80 },
      dialogue = "不错！多练练，以后能钓到大鱼！",
      check = function() return (game.fishCaught or 0) >= 3 end },
    { id = "c1_14", chapter = 1, title = "春日丰收", desc = "累计拥有300金币",
      hint = "卖出作物和鱼获赚取金币", npc = "张村长", reward = { gold = 100 },
      dialogue = "不错啊！你已经站稳脚跟了！",
      check = function() return game.gold >= 100 end },
    { id = "c1_15", chapter = 1, title = "通往远方", desc = "达到Lv.3，开启新篇章",
      hint = "继续种植和钓鱼积累经验", npc = "张村长", reward = { gold = 150 },
      dialogue = "你成长得很快！阿牛一直想找个帮手呢...",
      check = function() return true end },

    -- ═══════════ 第二章：牧歌田园（Lv.3~5）═══════════
    -- 阶段一：初涉养殖
    { id = "c2_01", chapter = 2, title = "阿牛的牧场", desc = "前往牧场区域",
      hint = "向东走，找到牧场入口", npc = "阿牛", reward = { gold = 50 },
      dialogue = "嘿兄弟！来帮我看看牧场呗，我送你只鸡！",
      check = function() return true end },
    { id = "c2_02", chapter = 2, title = "咯咯哒", desc = "拥有第一只鸡",
      hint = "在牧场面板中购买小鸡", npc = "阿牛", reward = { gold = 30 },
      dialogue = "这只小鸡送你了！好好养，每天能下蛋！",
      check = function() return #game.animals >= 1 end },
    { id = "c2_03", chapter = 2, title = "早起拾蛋", desc = "收集鸡蛋3次",
      hint = "每天去牧场收集动物产出", npc = "阿牛", reward = { gold = 80 },
      dialogue = "每天记得来收蛋！鸡可不会帮你攒着。",
      check = function() return (game._eggCollected or 0) >= 3 end },
    { id = "c2_04", chapter = 2, title = "鸡飞蛋打", desc = "牧场动物达到3只",
      hint = "继续购买更多小鸡", npc = "阿牛", reward = { gold = 100 },
      dialogue = "养得越多产得越多！来来来多买几只！",
      check = function() return #game.animals >= 3 end },
    { id = "c2_05", chapter = 2, title = "扩建鸡舍", desc = "在木匠处升级鸡舍",
      hint = "去木匠小屋选择'升级鸡舍'", npc = "老陈", reward = { gold = 60 },
      dialogue = "鸡多了住不下？我帮你扩建，120金搞定。",
      check = function() return (game._chickenUpgrade or 0) >= 1 end },
    -- 阶段二：友情深化
    { id = "c2_06", chapter = 2, title = "好友之证", desc = "任意2位NPC好感度达到'好友'(50)",
      hint = "每天和NPC对话、送礼物", npc = "张村长", reward = { gold = 120 },
      dialogue = "和邻居们处好关系很重要！",
      check = function()
          local friends = 0
          for _, npc in ipairs(getNpcs()) do if npc.friendship >= 50 then friends = friends + 1 end end
          return friends >= 2
      end },
    { id = "c2_07", chapter = 2, title = "小花的梦想", desc = "累计送花给NPC 5次",
      hint = "收获花朵后送给村民", npc = "小花", reward = { gold = 80 },
      dialogue = "花能传递心意~多送送花给大家吧！",
      check = function() return (game._flowerGifts or 0) >= 5 end },
    { id = "c2_08", chapter = 2, title = "老陈的认可", desc = "在木匠处完成2次建造",
      hint = "去木匠小屋选择建造项目", npc = "老陈", reward = { gold = 100 },
      dialogue = "看来你不是三天打鱼的人...不错。",
      check = function() return (game._carpenterBuilds or 0) >= 2 end },
    -- 阶段三：池塘与远方
    { id = "c2_09", chapter = 2, title = "渔夫的挑战", desc = "累计钓鱼10条",
      hint = "经常去湖边钓鱼", npc = "林爷爷", reward = { gold = 100 },
      dialogue = "年轻人不错！来，看看你能不能钓到10条！",
      check = function() return (game.fishCaught or 0) >= 10 end },
    { id = "c2_10", chapter = 2, title = "瓶中信", desc = "钓鱼时发现瓶中信(钓15条后触发)",
      hint = "继续钓鱼，运气好能钓到宝物", npc = "林爷爷", reward = { gold = 60 },
      dialogue = "哦？这是...瓶中信？上面有古老的文字...",
      check = function() return (game.fishCaught or 0) >= 15 end },
    { id = "c2_11", chapter = 2, title = "古老的传说", desc = "把瓶中信交给林爷爷辨认",
      hint = "和林爷爷对话触发剧情", npc = "林爷爷", reward = { gold = 80 },
      dialogue = "这文字...提到了'矿脉深处藏宝藏'...村西有个洞穴...",
      check = function() return (game.fishCaught or 0) >= 15 end },
    { id = "c2_12", chapter = 2, title = "嘎嘎嘎", desc = "购买第一只鸭(Lv.5解锁)",
      hint = "升到Lv.5后在牧场购买鸭子", npc = "阿牛", reward = { gold = 80 },
      dialogue = "鸭子可以在池塘边养，鸭蛋也很值钱！",
      check = function()
          for _, a in ipairs(game.animals) do if a.type == "duck" then return true end end
          return false
      end },
    { id = "c2_13", chapter = 2, title = "牧场繁荣", desc = "同时养殖6只动物",
      hint = "持续购买和养殖动物", npc = "阿牛", reward = { gold = 200 },
      dialogue = "六只了！你简直是天生的牧场主！",
      check = function() return #game.animals >= 6 end },
    { id = "c2_14", chapter = 2, title = "致富之路", desc = "累计拥有800金币",
      hint = "卖农产品+动物产出赚钱", npc = "小月", reward = { gold = 150 },
      dialogue = "生意兴隆啊！你是我们村最有前途的人！",
      check = function() return game.gold >= 800 end },
    { id = "c2_15", chapter = 2, title = "新的篇章", desc = "达到Lv.5，准备探索矿洞",
      hint = "继续积累经验升级", npc = "张村长", reward = { gold = 200 },
      dialogue = "那个矿洞...也许是时候去看看了。你准备好了吗？",
      check = function() return true end },

    -- ═══════════ 第三章：地底秘境（Lv.5~7）═══════════
    { id = "c3_01", chapter = 3, title = "洞口的光", desc = "进入矿洞第1层",
      hint = "前往村西矿洞，靠近入口后点击探索", npc = "林爷爷", reward = { gold = 80 },
      dialogue = "矿洞里的火光又亮了，带上矿灯，小心脚下。",
      check = function() return (game._mineEntered or 0) >= 1 end },
    { id = "c3_02", chapter = 3, title = "铁矿石", desc = "采集铁矿或更高级矿石5次",
      hint = "在矿洞中用⛏️敲碎矿石", npc = "—", reward = { gold = 100 },
      dialogue = "铁矿是锻造工具的基础材料。",
      check = function() return (game._oreMined or 0) >= 5 end },
    { id = "c3_03", chapter = 3, title = "铁匠老刘", desc = "在铁匠铺完成第一次打造或升级",
      hint = "进入铁匠铺，选择升级工具或打造装备", npc = "铁匠老刘", reward = { gold = 120 },
      dialogue = "矿石不错，火候也正好，可以开炉了。",
      check = function() return (game._smithCrafts or 0) >= 1 end },
    { id = "c3_04", chapter = 3, title = "更深一层", desc = "到达矿洞第3层",
      hint = "击败怪物或挖矿找到梯子，继续下到第3层", npc = "—", reward = { gold = 200 },
      dialogue = "越深的地方，矿脉越纯，也越危险。",
      check = function() return (game._mineMaxFloor or 1) >= 3 end },
    { id = "c3_05", chapter = 3, title = "探险受伤", desc = "在矿洞中受到一次伤害",
      hint = "遇到怪物时注意走位，受伤后会触发诊所线索", npc = "王大夫", reward = { gold = 80 },
      dialogue = "伤口虽浅，但探险不能逞强，村里该有个诊所。",
      check = function() return (game._mineDamageTaken or 0) >= 1 end },
    { id = "c3_06", chapter = 3, title = "王大夫妙手", desc = "使用一次恢复类功能",
      hint = "在主屋壁炉休息、工作台制作药水，或等待体力恢复", npc = "王大夫", reward = { gold = 120 },
      dialogue = "调息、药水和热汤，都是恢复体力的好办法。",
      check = function() return (game._healingUsed or 0) >= 1 or game.stamina >= game.maxStamina end },
    { id = "c3_07", chapter = 3, title = "工作台改造", desc = "在工作台制作第一件物品",
      hint = "进入仓库，靠近工作台选择任意制作项", npc = "老陈", reward = { gold = 100 },
      dialogue = "会用工具台，才算真正开始经营农场。",
      check = function() return (game._craftedItems or 0) >= 1 end },
    { id = "c3_08", chapter = 3, title = "升级工具", desc = "在铁匠处升级一件工具",
      hint = "在铁匠铺选择升级锄头、水壶或鱼竿", npc = "铁匠老刘", reward = { gold = 150 },
      dialogue = "工具顺手了，日子也会更顺。",
      check = function() return (game._toolUpgrades or 0) >= 1 end },
    { id = "c3_09", chapter = 3, title = "铁匠的委托", desc = "累计挖矿10次",
      hint = "继续深入矿洞，收集更多矿石和煤炭", npc = "铁匠老刘", reward = { gold = 180 },
      dialogue = "炉火要旺，矿石和煤炭都少不了。",
      check = function() return (game._oreMined or 0) >= 10 end },
    { id = "c3_10", chapter = 3, title = "装备齐全", desc = "打造铁剑",
      hint = "在铁匠铺选择打造铁剑", npc = "—", reward = { gold = 200 },
      dialogue = "有了铁剑，矿洞深处也不再只是传说。",
      check = function() return (game._ironSwordCrafted or 0) >= 1 end },
    { id = "c3_11", chapter = 3, title = "矿洞第5层", desc = "到达矿洞第5层",
      hint = "继续寻找梯子，到达第5层", npc = "—", reward = { gold = 240 },
      dialogue = "最深处的石壁上，似乎刻着古代文字。",
      check = function() return (game._mineMaxFloor or 1) >= 5 end },
    { id = "c3_12", chapter = 3, title = "解读石板", desc = "与林爷爷或老陈对话，辨认远古石板",
      hint = "带着矿洞线索去找村民聊聊", npc = "林爷爷+老陈", reward = { gold = 160 },
      dialogue = "石板上的纹路，像是在指向南方遗迹。",
      check = function() return (game._stoneDiscussed or 0) >= 1 or (game._npcTalkCount or 0) >= 8 end },
    { id = "c3_13", chapter = 3, title = "遗迹方位", desc = "发现遗迹位置",
      hint = "达到Lv.6后，矿洞外的遗迹区域会开放", npc = "林爷爷", reward = { gold = 180 },
      dialogue = "遗迹并不远，只是从前没人敢靠近。",
      check = function() return true end },
    { id = "c3_14", chapter = 3, title = "村长的许可", desc = "获得探索遗迹许可",
      hint = "准备好装备与补给，等级达到Lv.6即可获得许可", npc = "张村长", reward = { gold = 200 },
      dialogue = "既然你准备好了，就去看看遗迹到底藏着什么吧。",
      check = function() return (game._ironSwordCrafted or 0) >= 1 end },
    { id = "c3_15", chapter = 3, title = "初探遗迹", desc = "进入遗迹第1层或达到Lv.7",
      hint = "前往南方遗迹入口，完成第三章", npc = "—", reward = { gold = 400 },
      dialogue = "墙上的壁画画着四颗发光的种子，世界树的传说开始苏醒。",
      check = function() return (game._ruinsEntered or 0) >= 1 end },

    -- ═══════════ 第四章：四季传说（Lv.7~10）═══════════
    -- 阶段一：遗迹的启示
    { id = "c4_01", chapter = 4, title = "壁画的秘密", desc = "仔细研究遗迹中的壁画",
      hint = "回到遗迹第1层，靠近壁画触发剧情", npc = "林爷爷", reward = { gold = 100 },
      dialogue = "壁画上的四颗种子对应四个季节，世界树的传说果然是真的...",
      check = function() return (game._ruinsEntered or 0) >= 1 end },
    { id = "c4_02", chapter = 4, title = "收集线索", desc = "与3位NPC讨论壁画的含义",
      hint = "分别和张村长、林爷爷、老陈对话", npc = "张村长", reward = { gold = 120 },
      dialogue = "村里老一辈的人都听说过四季之种的传说，去问问他们吧。",
      check = function()
          local discussed = (game._stoneDiscussed or 0) + (game._npcTalkCount or 0)
          return discussed >= 3
      end },
    { id = "c4_03", chapter = 4, title = "春之种", desc = "在矿洞第5层找到春之种",
      hint = "深入矿洞第5层，击败守护怪物后获得", npc = "—", reward = { gold = 300, item = "spring_seed" },
      dialogue = "春之种散发着温暖的绿光，握在手中能感受到春天的生机。",
      check = function() return (game._mineMaxFloor or 1) >= 5 and (game._springSeedFound or 0) >= 1 end },

    -- 阶段二：旅行商人的线索
    { id = "c4_04", chapter = 4, title = "神秘商人", desc = "在集市找到旅行商人马可",
      hint = "马可在周一、三、五、日出现在集市摊位", npc = "马可", reward = { gold = 80 },
      dialogue = "哦？你在找四季之种？我走南闯北，倒是知道一些线索...",
      check = function() return (game._metMarco or 0) >= 1 end },
    { id = "c4_05", chapter = 4, title = "马可的故事", desc = "听马可讲世界树的传说",
      hint = "在马可出现时与他对话，选择'世界树的传说'", npc = "马可", reward = { gold = 100 },
      dialogue = "世界树曾经连接着天地，后来枯萎了，四颗种子散落在大陆四方...",
      check = function() return (game._marcoStoryHeard or 0) >= 1 end },
    { id = "c4_06", chapter = 4, title = "夏之种的线索", desc = "从马可处获得夏之种地图",
      hint = "马可好感度达到'好友'(100)后触发", npc = "马可", reward = { gold = 200, item = "summer_seed_map" },
      dialogue = "夏之种在东方沙漠的绿洲神殿，这是地图，拿去吧。",
      check = function()
          for _, npc in ipairs(getNpcs()) do
              if npc.def and npc.def.name == "马可" and npc.friendship >= 100 then return true end
          end
          return false
      end },
    { id = "c4_07", chapter = 4, title = "夏之种", desc = "前往东方沙漠找到夏之种",
      hint = "前往新开放的沙漠区域（需要Lv.8）", npc = "—", reward = { gold = 350, item = "summer_seed" },
      dialogue = "沙漠神殿深处，夏之种在烈日的光芒中闪耀。",
      check = function() return (game._summerSeedFound or 0) >= 1 end },

    -- 阶段三：四散各地的种子
    { id = "c4_08", chapter = 4, title = "秋之种的传闻", desc = "与林爷爷讨论秋之种的去向",
      hint = "林爷爷曾在南方密林见过类似的种子", npc = "林爷爷", reward = { gold = 100 },
      dialogue = "秋之种...我年轻时在南方密林探险，确实见过一颗金色的种子。",
      check = function()
          for _, npc in ipairs(getNpcs()) do
              if npc.def and npc.def.name == "林爷爷" and npc.friendship >= 100 then return true end
          end
          return false
      end },
    { id = "c4_09", chapter = 4, title = "秋之种", desc = "前往南方密林找到秋之种",
      hint = "前往新开放的密林区域（需要Lv.9）", npc = "—", reward = { gold = 400, item = "autumn_seed" },
      dialogue = "密林深处的古老树洞中，秋之种散发着金色的丰收之光。",
      check = function() return (game._autumnSeedFound or 0) >= 1 end },
    { id = "c4_10", chapter = 4, title = "冬之种的谜题", desc = "与老陈讨论冬之种的下落",
      hint = "老陈年轻时在北方雪山当过学徒", npc = "老陈", reward = { gold = 100 },
      dialogue = "北方雪山...那里有个古老的冰窟，传说里面封印着一颗冰晶种子。",
      check = function()
          for _, npc in ipairs(getNpcs()) do
              if npc.def and npc.def.name == "老陈" and npc.friendship >= 100 then return true end
          end
          return false
      end },

    -- 阶段四：冰雪试炼
    { id = "c4_11", chapter = 4, title = "冬日准备", desc = "准备防寒装备和充足补给",
      hint = "在铁匠铺打造防寒服（需要5个铁矿+3个煤炭）", npc = "铁匠老刘", reward = { gold = 150 },
      dialogue = "去雪山可不是闹着玩的，先准备好装备！",
      check = function() return (game._winterGearCrafted or 0) >= 1 end },
    { id = "c4_12", chapter = 4, title = "冬之种", desc = "前往北方雪山找到冬之种",
      hint = "前往新开放的雪山区域（需要Lv.9+防寒装备）", npc = "—", reward = { gold = 450, item = "winter_seed" },
      dialogue = "冰窟最深处，冬之种在极寒中散发着纯净的蓝光。",
      check = function() return (game._winterSeedFound or 0) >= 1 end },
    { id = "c4_13", chapter = 4, title = "四季归一", desc = "集齐四颗四季之种",
      hint = "检查背包确认春、夏、秋、冬四颗种子都在", npc = "张村长", reward = { gold = 500 },
      dialogue = "不可思议！四颗种子都在发光，它们在共鸣！",
      check = function()
          return (game._springSeedFound or 0) >= 1
             and (game._summerSeedFound or 0) >= 1
             and (game._autumnSeedFound or 0) >= 1
             and (game._winterSeedFound or 0) >= 1
      end },

    -- 阶段五：唤醒的准备
    { id = "c4_14", chapter = 4, title = "村长之托", desc = "与张村长讨论世界树唤醒仪式",
      hint = "集齐四季之种后与张村长对话", npc = "张村长", reward = { gold = 200 },
      dialogue = "唤醒世界树需要在一个特殊的地点...就在你农场的那棵古树下！",
      check = function()
          return (game._springSeedFound or 0) >= 1
             and (game._summerSeedFound or 0) >= 1
             and (game._autumnSeedFound or 0) >= 1
             and (game._winterSeedFound or 0) >= 1
      end },
    { id = "c4_15", chapter = 4, title = "世界树苏醒", desc = "在农场古树下举行唤醒仪式",
      hint = "达到Lv.10，集齐四季之种，前往农场古树", npc = "—", reward = { gold = 1000 },
      dialogue = "四颗种子飞向古树，一道光芒直冲云霄——世界树，苏醒了！",
      check = function() return (game._worldTreeAwakened or 0) >= 1 end },

    -- ═══════════ 终章：世界树之约（Lv.10~12）═══════════
    -- 阶段一：世界树的恩赐
    { id = "c5_01", chapter = 5, title = "新的开始", desc = "见证世界树苏醒后的变化",
      hint = "与张村长对话，了解世界树苏醒后的影响", npc = "张村长", reward = { gold = 200 },
      dialogue = "世界树苏醒了...整个大陆都在震动。梦境村，将迎来新的时代。",
      check = function() return (game._worldTreeAwakened or 0) >= 1 end },
    { id = "c5_02", chapter = 5, title = "生机盎然", desc = "在世界树影响下种植10株作物",
      hint = "世界树范围内的作物生长速度翻倍", npc = "小花", reward = { gold = 150 },
      dialogue = "天啊！你的农场作物长得比以前快多了！是世界树的恩赐！",
      check = function() return (game._worldTreeCrops or 0) >= 10 end },
    { id = "c5_03", chapter = 5, title = "远方的来客", desc = "接待第一批慕名而来的访客",
      hint = "与3位外来访客对话（在村中心出现）", npc = "张村长", reward = { gold = 180 },
      dialogue = "消息传得真快，已经有人专程来看世界树了。",
      check = function() return (game._visitorsGreeted or 0) >= 3 end },

    -- 阶段二：繁荣之路
    { id = "c5_04", chapter = 5, title = "村庄繁荣", desc = "帮助村庄建设新的设施",
      hint = "在木匠老陈处选择'村庄建设'项目", npc = "老陈", reward = { gold = 300 },
      dialogue = "村子要扩大了！需要建造新的房屋和设施。",
      check = function() return (game._villageBuilds or 0) >= 2 end },
    { id = "c5_05", chapter = 5, title = "马可的告别", desc = "与马可进行最后的交易",
      hint = "马可将要离开梦境村，前往下一个目的地", npc = "马可", reward = { gold = 200 },
      dialogue = "我的使命完成了。世界树醒了，我也该继续我的旅程了...",
      check = function()
          for _, npc in ipairs(getNpcs()) do
              if npc.def and npc.def.name == "马可" and npc.friendship >= 300 then return true end
          end
          return false
      end },
    { id = "c5_06", chapter = 5, title = "庆典筹备", desc = "为世界树盛典做准备",
      hint = "帮助小月准备庆典物资，帮助李婶准备宴会食材", npc = "小月", reward = { gold = 250 },
      dialogue = "世界树盛典是梦境村有史以来最大的庆典！",
      check = function() return (game._festivalPrep or 0) >= 5 end },

    -- 阶段三：考验
    { id = "c5_07", chapter = 5, title = "暗影涌动", desc = "调查世界树周围出现的暗影",
      hint = "夜晚前往农场古树区域调查", npc = "林爷爷", reward = { gold = 200 },
      dialogue = "世界树的光芒吸引了某些...不太友善的东西。",
      check = function() return (game._shadowInvestigated or 0) >= 1 end },
    { id = "c5_08", chapter = 5, title = "暗影退散", desc = "击败3波暗影怪物",
      hint = "装备铁剑，在古树周围战斗", npc = "—", reward = { gold = 400, item = "shadow_core" },
      dialogue = "暗影的核心掉落了一颗黑色的结晶...这力量很古老。",
      check = function() return (game._shadowDefeated or 0) >= 3 end },
    { id = "c5_09", chapter = 5, title = "古老的力量", desc = "将暗影核心交给林爷爷研究",
      hint = "带着暗影核心与林爷爷对话", npc = "林爷爷", reward = { gold = 200 },
      dialogue = "这暗影核心...与世界树的力量同源但相反。看来世界树的苏醒唤醒了某种平衡之力。",
      check = function() return (game._shadowCoreAnalyzed or 0) >= 1 end },

    -- 阶段四：最终盛典
    { id = "c5_10", chapter = 5, title = "世界树盛典", desc = "参加世界树盛典",
      hint = "在节日当天前往村中心参加庆典", npc = "张村长", reward = { gold = 500 },
      dialogue = "今天，整个梦境村都在庆祝！世界树的光辉照耀着我们每一个人！",
      check = function() return (game._festivalAttended or 0) >= 1 end },

    -- 终章结束（后续无尽玩法）
    { id = "c5_11", chapter = 5, title = "新的传说", desc = "完成主线剧情",
      hint = "达成Lv.12并完成所有终章任务", npc = "—", reward = { gold = 2000 },
      dialogue = "世界树的故事才刚刚开始。你的农场传奇，将永远铭刻在梦境村的历史中。",
      check = function() return true end },
}


    return chapters, quests
end

return StoryQuestDefs
