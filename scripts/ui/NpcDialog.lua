-- ============================================================
-- NpcDialog - NPC 对话系统和 AI 聊天系统模块
-- 从 main.lua 提取，使用依赖注入模式
-- v2: 集成 AI 对话服务（AIDialogueService）
-- ============================================================

-- UI 构造器返回值与 and/or nil 模式的类型推断不匹配（false|nil 与 table 的联合）
---@diagnostic disable: assign-type-mismatch, return-type-mismatch

local NpcDialog = {}

-- 模块内部状态
local ctx_ = nil
local AIDialogueService = nil  -- 延迟加载

-- 内部状态变量（原 main.lua 的 local 变量）
local npcDialogOverlay_ = nil
local npcDialogVisible = false
local npcDialogIdx_ = nil
local chatOverlay_ = nil
local chatMessages_ = {}
local chatNpcIdx_ = nil

--- 初始化模块，接收依赖上下文
---@param ctx table 包含所有需要的依赖
function NpcDialog.Init(ctx)
    ctx_ = ctx
    -- 延迟加载 AI 模块
    local ok, mod = pcall(function() return require("ai.AIDialogueService") end)
    if ok and mod then
        AIDialogueService = mod
    end
end

--- 获取当前 NPC 对话是否可见（供外部 HasBlockingGameplayOverlay 等使用）
function NpcDialog.IsDialogVisible()
    return npcDialogVisible
end

--- 获取当前 AI 聊天面板（供外部 ESC 关闭逻辑使用）
function NpcDialog.GetChatOverlay()
    return chatOverlay_
end

--- 获取当前 NPC 对话覆盖层（供外部 settings 打开时关闭使用）
function NpcDialog.GetNpcDialogOverlay()
    return npcDialogOverlay_
end

--- 获取当前对话 NPC 索引
function NpcDialog.GetNpcDialogIdx()
    return npcDialogIdx_
end

--- 显示 NPC 对话面板
---@param npcIdx number NPC 索引
function NpcDialog.ShowNPCDialog(npcIdx)
    if ctx_.IsSettingsOpen and ctx_.IsSettingsOpen() then return end
    local npcs = ctx_.npcs
    local npc = npcs[npcIdx]
    if not npc or not npc.def then return end
    local def = npc.def
    local lvl = ctx_.GetFriendshipLevel(npc.friendship)
    ctx_.game._npcTalkCount = (ctx_.game._npcTalkCount or 0) + 1
    if def.name == "林爷爷" or def.name == "老陈" then
        ctx_.game._stoneDiscussed = (ctx_.game._stoneDiscussed or 0) + 1
    end

    -- 关闭已有
    if npcDialogOverlay_ then
        ctx_.DismissOverlayPanel(npcDialogOverlay_)
        npcDialogOverlay_ = nil
    end
    ctx_.VirtualControls.SetMobileMode(false)  -- 对话时隐藏摇杆
    npcDialogVisible = true
    npcDialogIdx_ = npcIdx

    -- 构建送礼按钮列表（背包中有的作物）
    ---@type table
    local giftChildren = {}
    for idx, ct in ipairs(ctx_.CROP_TYPES) do
        local count = ctx_.game.inventory[idx] or 0
        if count > 0 then
            local isLiked = false
            for _, like in ipairs(def.likes) do
                if like == ct.name then isLiked = true; break end
            end
            local label = ct.name .. " x" .. count
            if isLiked then label = "❤️" .. label end
            local capturedIdx = idx
            giftChildren[#giftChildren + 1] = ctx_.UI.Button { ---@diagnostic disable-line: assign-type-mismatch
                text = label, fontSize = 12,
                width = "45%", height = 34, margin = 3,
                variant = isLiked and "primary" or "default",
                onClick = function()
                    ctx_.GiftToNPC(npcIdx, capturedIdx)
                    NpcDialog.CloseNPCDialog()
                end,
            }
        end
    end

    if #giftChildren == 0 then
        giftChildren[1] = ctx_.UI.Label { text = "（背包中没有作物可送）", fontSize = 11, color = {160, 160, 160} }
    end

    local function npcReply(topic)
        local weather = ctx_.WEATHER_DISPLAY[ctx_.GetWeatherType()]
        local weatherName = weather and weather.name or ctx_.GetWeatherType()
        local reply = ""
        if topic == "weather" then
            if def.name == "林爷爷" then
                reply = "今天是" .. weatherName .. "。雨后蘑菇会多，干旱天记得提前浇水。"
            elseif def.name == "老陈" then
                reply = weatherName .. "会影响土壤水分。要是快下雨了，可以先省点体力。"
            else
                reply = "我觉得今天的" .. weatherName .. "挺适合出去走走，也别忘了照看田地。"
            end
        elseif topic == "farm" then
            if def.name == "老陈" then
                reply = "未成熟作物别急着动手，现在收获和铲除已经分开了，安全多了。"
            elseif def.name == "小花" then
                reply = "作物颜色最亮的时候通常快成熟啦，缺水的土地会发黄，看到就浇一下。"
            else
                reply = "看看土地颜色和作物提示，就能知道水分和成熟进度。"
            end
        else
            if lvl >= 2 then
                reply = def.name .. "笑了笑：最近农场热闹多了，有空常来聊聊。"
            else
                reply = def.name .. "说：慢慢来吧，熟悉起来以后我会告诉你更多村里的事。"
            end
        end
        npc.friendship = math.min(100, (npc.friendship or 0) + 1)
        ctx_.ShowMessage("💬 " .. reply .. "\n" .. def.name .. " 好感+1")
        ctx_.UpdateStatsUI()
    end

    local quickTalkChildren = {
        ctx_.UI.Button { text = "问天气", width = "30%", height = 30, fontSize = 11, onClick = function() npcReply("weather") end },
        ctx_.UI.Button { text = "问种植", width = "30%", height = 30, fontSize = 11, onClick = function() npcReply("farm") end },
        ctx_.UI.Button { text = "闲聊", width = "30%", height = 30, fontSize = 11, onClick = function() npcReply("chat") end },
    }

    -- 好感度进度条颜色
    local barColor = {100, 100, 100}
    if lvl == 1 then barColor = {180, 180, 80}
    elseif lvl == 2 then barColor = {240, 200, 60}
    elseif lvl == 3 then barColor = {240, 80, 100} end

    npcDialogOverlay_ = ctx_.UI.Panel {
        width = "100%", height = "100%",
        position = "absolute",
        backgroundColor = { 0, 0, 0, 150 },
        justifyContent = "center", alignItems = "center",
        onClick = function() NpcDialog.CloseNPCDialog() end,
        children = {
            ctx_.UI.Panel {
                width = 320, maxHeight = "80%",
                backgroundColor = { 40, 35, 28, 245 },
                borderRadius = 16, padding = 16,
                flexDirection = "column", alignItems = "center",
                onClick = function() end,  -- 阻止点击事件冒泡到外层关闭
                children = {
                    -- NPC 立绘
                    def.portrait and ctx_.UI.Panel {
                        width = 120, height = 160,
                        backgroundImage = def.portrait,
                        objectFit = "contain", marginBottom = 8,
                        borderRadius = 8,
                    } or nil,
                    -- NPC 名称和头衔
                    ctx_.UI.Label { text = def.name, fontSize = 20, fontWeight = "bold", color = {255, 240, 200} },
                    ctx_.UI.Label { text = def.title .. " · " .. def.personality, fontSize = 12, color = {180, 170, 140}, marginBottom = 8 },

                    -- 好感度条
                    ctx_.UI.Panel {
                        width = "90%", height = 16, marginBottom = 10,
                        backgroundColor = { 30, 28, 22 }, borderRadius = 8,
                        children = {
                            ctx_.UI.Panel {
                                width = tostring(math.max(5, npc.friendship)) .. "%", height = "100%",
                                backgroundColor = barColor, borderRadius = 8,
                            },
                        }
                    },
                    ctx_.UI.Label {
                        text = ctx_.FRIENDSHIP_ICONS[lvl] .. " " .. ctx_.FRIENDSHIP_NAMES[lvl] .. " (" .. npc.friendship .. "/100)",
                        fontSize = 12, color = {200, 190, 160}, marginBottom = 12,
                    },

                    -- 对话按钮 → 打开AI聊天面板
                    ctx_.UI.Button {
                        text = "💬 与" .. def.name .. "聊天",
                        width = "90%", height = 40, marginBottom = 8,
                        variant = "primary", fontSize = 14,
                        onClick = function()
                            NpcDialog.CloseNPCDialog()
                            NpcDialog.OpenAIChatPanel(npcIdx)
                        end,
                    },
                    ctx_.UI.Label { text = "快速互动", fontSize = 12, color = { 205, 190, 150 }, marginBottom = 5 },
                    ctx_.UI.Panel {
                        width = "92%", flexDirection = "row", justifyContent = "space-between",
                        marginBottom = 10,
                        children = quickTalkChildren,
                    },

                    -- 送礼区域
                    ctx_.UI.Label { text = "🎁 送礼 (喜欢: " .. table.concat(def.likes, "、") .. ")", fontSize = 12, color = {200, 180, 120}, marginBottom = 6 },
                    ctx_.UI.Panel {
                        width = "100%", flexDirection = "row", flexWrap = "wrap",
                        justifyContent = "center", alignItems = "center",
                        marginBottom = 12,
                        children = giftChildren,
                    },

                    -- 关闭按钮
                    ctx_.UI.Button {
                        text = "离开", width = "60%", height = 34,
                        variant = "default", fontSize = 13,
                        onClick = function() NpcDialog.CloseNPCDialog() end,
                    },
                }
            }
        }
    }

    ctx_.ShowOverlayPanel(npcDialogOverlay_)
end

--- 关闭 NPC 对话面板
function NpcDialog.CloseNPCDialog()
    -- 恢复NPC待机动画
    if npcDialogIdx_ and ctx_.npcs[npcDialogIdx_] and ctx_.npcs[npcDialogIdx_].animCtrl then
        ctx_.npcs[npcDialogIdx_].animCtrl:PlayExclusive(ctx_.ANIM_IDLE, 0, true, 0.3)
    end
    npcDialogIdx_ = nil
    npcDialogVisible = false
    if npcDialogOverlay_ then
        ctx_.DismissOverlayPanel(npcDialogOverlay_)
        npcDialogOverlay_ = nil
    end
    ctx_.VirtualControls.SetMobileMode(isMobile)  -- 恢复摇杆
end

--- NPC智能回复：根据性格、好感度、关键词生成回复
---@param npcIdx number
---@param playerMsg string
---@return string
function NpcDialog.GenerateNPCReply(npcIdx, playerMsg)
    local npcs = ctx_.npcs
    local npc = npcs[npcIdx]
    if not npc then return "......" end
    local def = npc.def
    local lvl = ctx_.GetFriendshipLevel(npc.friendship)
    local msg = playerMsg:lower()

    -- 通用话题关键词回复
    local replies = {}

    -- 打招呼
    if msg:find("你好") or msg:find("嗨") or msg:find("hi") or msg:find("早") then
        if lvl == 0 then
            replies = { "你好，你是新来的吧？", "嗯，你好。", "初次见面，你好。" }
        elseif lvl == 1 then
            replies = { "哟，又见面了！", "你好呀~今天过得怎么样？", "嘿！好久不见~" }
        elseif lvl == 2 then
            replies = { "好朋友来啦！", "嘿嘿，等你好久了~", "太好了，你来了！" }
        else
            replies = { "最好的朋友来了！快坐快坐！", "你来我就开心！", "想你了呀！" }
        end
    -- 天气
    elseif msg:find("天气") or msg:find("太阳") or msg:find("下雨") then
        local timeStr = ctx_.GetDayTime() < 12 and "上午" or "下午"
        replies = {
            "今天天气不错呢，适合" .. (ctx_.GetGameSeason() == 1 and "种花" or ctx_.GetGameSeason() == 2 and "浇水" or ctx_.GetGameSeason() == 3 and "收获" or "猫冬") .. "！",
            timeStr .. "了，你地里的庄稼还好吗？",
            "这个季节就是这样的天气啦~",
        }
    -- 种植/农场
    elseif msg:find("种") or msg:find("农") or msg:find("庄稼") or msg:find("作物") then
        if def.name == "小花" then
            replies = { "要种花的话，郁金香和向日葵都很美哦~", "春天种花最好！记得每天浇水！", "我最喜欢看满园花开的样子了~" }
        elseif def.name == "阿牛" then
            replies = { "玉米和南瓜产量高，适合大面积种！", "种地嘛，记得看季节，事半功倍！", "庄稼要勤浇水，别偷懒~" }
        else
            replies = { "种地是门学问呢，得看季节。", "多浇水，作物长得快！", "现在是" .. ctx_.SEASON_NAMES[ctx_.GetGameSeason()] .. "天，选对作物很重要。" }
        end
    -- 钓鱼
    elseif msg:find("鱼") or msg:find("钓") then
        if def.name == "林爷爷" then
            replies = { "钓鱼的秘诀就是...耐心！等鱼咬钩别急着拉！", "湖里有大家伙呢，得用好饵~", "年轻人，钓鱼能修身养性。" }
        else
            replies = { "想钓鱼的话去找林爷爷吧，他是这方面的专家！", "听说湖里有很大的鱼呢~", "钓鱼挺有趣的，放松心情。" }
        end
    -- 商店/买卖
    elseif msg:find("买") or msg:find("卖") or msg:find("商店") or msg:find("价") then
        if def.name == "小月" then
            replies = { "想买什么？种子、工具、饲料都有哦~", "今天有特价！来看看吧~", "我们这啥都有，物美价廉！" }
        else
            replies = { "想买东西的话去找小月吧，她那啥都有。", "卖作物可以赚金币哦~", "经营好农场，金币自然就有了。" }
        end
    -- 建筑
    elseif msg:find("建") or msg:find("房") or msg:find("装修") or msg:find("家具") then
        if def.name == "老陈" then
            replies = { "想建什么？围栏、仓库、还是新房子？", "好木材不好找，但我手艺没话说！", "有啥需要修的拿来，保证跟新的一样！" }
        else
            replies = { "建房子找老陈就对了，他可是大师傅！", "农场要有好围栏，不然动物跑出去~", "一个温馨的小屋，是农场主的梦想呢。" }
        end
    -- 好感/喜欢
    elseif msg:find("喜欢") or msg:find("最爱") or msg:find("礼物") then
        replies = {
            "我喜欢" .. table.concat(def.likes, "和") .. "呢~",
            "送我" .. def.likes[1] .. "的话我会很开心的！",
            "每个人喜欢的东西不一样嘛~",
        }
    -- 帮忙
    elseif msg:find("帮") or msg:find("怎么") or msg:find("教") or msg:find("攻略") then
        if def.personality == "温柔" then
            replies = { "需要帮忙吗？我很乐意哦~", "别着急，慢慢来，有什么不懂的问我~", "用心照料，作物自然会回报你的~" }
        elseif def.personality == "憨厚" then
            replies = { "有啥需要帮忙的直说！", "养殖方面我最在行了，问我就对了！", "勤劳才是致富之道！" }
        elseif def.personality == "睿智" then
            replies = { "年轻人，求知若渴是好事。", "经验需要时间积累，别急。", "多观察自然，答案就在其中。" }
        elseif def.personality == "活泼" then
            replies = { "我知道我知道！你听我说~", "这个简单啦，我教你！", "嘻嘻，跟着我准没错~" }
        else
            replies = { "嗯...这个嘛，你得自己琢磨。", "有些事情不是教就能会的。", "多练习，自然就懂了。" }
        end
    -- 默认回复
    else
        if lvl == 0 then
            replies = { "嗯...是吗。", "哦。", "我不太了解这个。", "你说的...我想想。" }
        elseif lvl == 1 then
            replies = { "有意思~", "说来听听？", "嗯嗯，然后呢？", "这样啊，挺好的。" }
        elseif lvl == 2 then
            replies = { "哈哈，你总是有有趣的想法！", "好呀！我也觉得不错~", "和你聊天真开心~", "你说的对！" }
        else
            replies = { "你说的我都支持！", "和你在一起总是很开心~", "好朋友嘛，什么都可以聊！", "嘿嘿，你最懂我了~" }
        end
    end

    return replies[math.random(1, #replies)]
end

--- 打开 AI 聊天面板
---@param npcIdx number NPC 索引
function NpcDialog.OpenAIChatPanel(npcIdx)
    local npcs = ctx_.npcs
    local npc = npcs[npcIdx]
    if not npc then return end
    local def = npc.def

    chatNpcIdx_ = npcIdx
    chatMessages_ = {}

    -- NPC主动打招呼
    local lvl = ctx_.GetFriendshipLevel(npc.friendship)
    local greetings = def.dialogues[lvl]
    local greeting = greetings and greetings[math.random(1, #greetings)] or "你好~"
    chatMessages_[#chatMessages_ + 1] = { role = "npc", text = greeting }

    -- 好感度提升
    if not npc.talked_today then
        npc.talked_today = true
        npc.friendship = math.min(100, npc.friendship + 5)
    end

    NpcDialog.RebuildChatUI()
end

--- 重建聊天界面
function NpcDialog.RebuildChatUI()
    if chatOverlay_ then
        ctx_.DismissOverlayPanel(chatOverlay_)
        chatOverlay_ = nil
    end

    local npcs = ctx_.npcs
    local npc = npcs[chatNpcIdx_]
    if not npc then return end
    local def = npc.def
    local lvl = ctx_.GetFriendshipLevel(npc.friendship)

    -- 构建消息列表
    local msgChildren = {}
    for _, msg in ipairs(chatMessages_) do
        local isNpc = msg.role == "npc"
        local isThinking = msg.isThinking == true
        local bgColor = isNpc and {60, 55, 45, 240} or {45, 90, 60, 240}

        -- 根据来源调整颜色
        if msg.source == "knowledge" then
            bgColor = isNpc and {65, 55, 75, 240} or bgColor
        elseif msg.source == "ai" then
            bgColor = isNpc and {55, 60, 80, 240} or bgColor
        end

        msgChildren[#msgChildren + 1] = ctx_.UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = isNpc and "flex-start" or "flex-end",
            marginBottom = 6,
            children = {
                ctx_.UI.Panel {
                    maxWidth = "75%",
                    backgroundColor = bgColor,
                    borderRadius = 12, padding = 10,
                    children = {
                        isNpc and not isThinking and ctx_.UI.Label { text = def.name, fontSize = 10, color = {180, 150, 100}, marginBottom = 2 } or nil,
                        ctx_.UI.Label {
                            text = isThinking and "思考中..." or msg.text,
                            fontSize = 13,
                            color = isThinking and {160, 150, 130} or {240, 235, 220},
                            fontStyle = isThinking and "italic" or "normal",
                        },
                    }
                }
            }
        }
    end

    -- 输入区域
    chatOverlay_ = ctx_.UI.Panel {
        width = "100%", height = "100%",
        position = "absolute",
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center", alignItems = "center",
        children = {
            ctx_.UI.Panel {
                width = 340, height = 420,
                backgroundColor = { 35, 32, 25, 250 },
                borderRadius = 16, padding = 12,
                flexDirection = "column",
                onClick = function() end,  -- 阻止冒泡
                children = {
                    -- 头部：NPC名称 + AI状态 + 关闭按钮
                    ctx_.UI.Panel {
                        width = "100%", flexDirection = "row",
                        justifyContent = "space-between", alignItems = "center",
                        marginBottom = 8,
                        children = {
                            ctx_.UI.Panel {
                                flexDirection = "row", alignItems = "center",
                                children = {
                                    ctx_.UI.Label {
                                        text = def.name .. " · " .. def.title,
                                        fontSize = 15, fontWeight = "bold", color = {255, 240, 200}
                                    },
                                    -- AI/知识库状态标识
                                    AIDialogueService and AIDialogueService.IsKnowledgeBaseEnabled() and ctx_.UI.Label {
                                        text = "📚",
                                        fontSize = 11,
                                        marginLeft = 6,
                                    } or nil,
                                }
                            },
                            ctx_.UI.Button {
                                text = "✕", width = 30, height = 30,
                                variant = "text", fontSize = 16,
                                onClick = function() NpcDialog.CloseAIChatPanel() end,
                            },
                        }
                    },
                    -- 好感度小条
                    ctx_.UI.Panel {
                        width = "100%", height = 6, marginBottom = 8,
                        backgroundColor = { 25, 22, 18 }, borderRadius = 3,
                        children = {
                            ctx_.UI.Panel {
                                width = tostring(math.max(5, npc.friendship)) .. "%", height = "100%",
                                backgroundColor = lvl >= 2 and {240, 180, 60} or {120, 120, 80}, borderRadius = 3,
                            },
                        }
                    },
                    -- 消息列表区域（可滚动）
                    ctx_.UI.ScrollView {
                        width = "100%", flex = 1,
                        marginBottom = 8,
                        children = msgChildren,
                    },
                    -- 输入区域
                    ctx_.UI.Panel {
                        width = "100%", flexDirection = "row",
                        alignItems = "center",
                        children = {
                            ctx_.UI.TextField {
                                id = "chat_input",
                                placeholder = "说点什么...",
                                width = "75%", height = 36, fontSize = 13,
                                onSubmit = function(self, text)
                                    if text and text ~= "" then
                                        NpcDialog.SendChatMessage(text)
                                        self:SetText("")
                                    end
                                end,
                            },
                            ctx_.UI.Button {
                                text = "发送", width = "23%", height = 36,
                                marginLeft = "2%",
                                variant = "primary", fontSize = 13,
                                onClick = function()
                                    if chatOverlay_ then
                                        local inputWidget = chatOverlay_:FindById("chat_input")
                                        if inputWidget then
                                            local text = inputWidget:GetText()
                                            if text and text ~= "" then
                                                NpcDialog.SendChatMessage(text)
                                                inputWidget:SetText("")
                                            end
                                        end
                                    end
                                end,
                            },
                        }
                    },
                }
            }
        }
    }

    ctx_.ShowOverlayPanel(chatOverlay_)
    npcDialogVisible = true
end

--- 发送聊天消息
---@param text string
function NpcDialog.SendChatMessage(text)
    if not chatNpcIdx_ then return end

    local npcs = ctx_.npcs
    local npc = npcs[chatNpcIdx_]
    if not npc then return end

    -- 添加玩家消息
    chatMessages_[#chatMessages_ + 1] = { role = "player", text = text }

    -- 尝试 AI 对话服务（知识库 fallback）
    if AIDialogueService then
        local gameState = {
            season = ctx_.GetGameSeason and ctx_.GetGameSeason() or 1,
            day = ctx_.GetGameDay and ctx_.GetGameDay() or 1,
            weather = ctx_.GetWeatherType and ctx_.GetWeatherType() or "晴天",
            hourFloat = ctx_.GetDayTime and ctx_.GetDayTime() or 12,
            friendshipLevel = ctx_.GetFriendshipLevel(npc.friendship),
            gold = ctx_.game and ctx_.game.gold or 0,
            level = ctx_.game and ctx_.game.level or 1,
        }

        -- 先显示"思考中"状态
        local thinkingMsg = { role = "npc", text = "...", isThinking = true }
        chatMessages_[#chatMessages_ + 1] = thinkingMsg
        NpcDialog.RebuildChatUI()

        -- 同步调用 fallback 链（当前不使用异步 AI API）
        local aiReply, source = AIDialogueService.SendMessageSync(
            npc.def.name, npc.def, gameState, text
        )

        -- 移除"思考中"
        for i = #chatMessages_, 1, -1 do
            if chatMessages_[i].isThinking then
                table.remove(chatMessages_, i)
                break
            end
        end

        if aiReply then
            -- AI/知识库 命中
            local label = ""
            if source == "knowledge" then
                label = "📚 "
            elseif source == "required" then
                label = "💡 "
            elseif source == "ai" then
                label = "🤖 "
            end
            chatMessages_[#chatMessages_ + 1] = { role = "npc", text = label .. aiReply, source = source }
        else
            -- Fallback 未命中，使用预设回复
            local reply = NpcDialog.GenerateNPCReply(chatNpcIdx_, text)
            chatMessages_[#chatMessages_ + 1] = { role = "npc", text = reply, source = "preset" }
        end
    else
        -- AI 模块不可用，使用预设回复
        local reply = NpcDialog.GenerateNPCReply(chatNpcIdx_, text)
        chatMessages_[#chatMessages_ + 1] = { role = "npc", text = reply, source = "preset" }
    end

    -- 每次对话小幅增加好感
    if npc and #chatMessages_ % 4 == 0 then
        npc.friendship = math.min(100, npc.friendship + 1)
    end

    -- 重建UI显示新消息
    NpcDialog.RebuildChatUI()
end

--- 关闭 AI 聊天面板
function NpcDialog.CloseAIChatPanel()
    chatNpcIdx_ = nil
    npcDialogVisible = false
    if chatOverlay_ then
        ctx_.DismissOverlayPanel(chatOverlay_)
        chatOverlay_ = nil
    end
    -- 恢复NPC动画
    if npcDialogIdx_ and ctx_.npcs[npcDialogIdx_] and ctx_.npcs[npcDialogIdx_].animCtrl then
        ctx_.npcs[npcDialogIdx_].animCtrl:PlayExclusive(ctx_.ANIM_IDLE, 0, true, 0.3)
    end
end

return NpcDialog
