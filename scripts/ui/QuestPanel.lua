local QuestPanel = {}

QuestPanel.panel = nil
QuestPanel.visible = false

function QuestPanel.Close(ctx)
    QuestPanel.visible = false
    if QuestPanel.panel then
        ctx.DismissOverlayPanel(QuestPanel.panel)
        QuestPanel.panel = nil
    end
end

function QuestPanel.Show(ctx)
    QuestPanel.Close(ctx)
    QuestPanel.visible = true

    local UI = ctx.UI
    local questChildren = {}
    local lastChapter = nil
    for i, quest in ipairs(ctx.storyQuests) do
        if quest.chapter ~= lastChapter then
            lastChapter = quest.chapter
            local chapter = ctx.storyChapters[lastChapter]
            questChildren[#questChildren + 1] = UI.Panel {
                width = "100%", paddingTop = 8, paddingBottom = 6, marginTop = #questChildren > 0 and 8 or 0,
                borderBottomWidth = 1, borderBottomColor = {120, 95, 50, 180},
                children = {
                    UI.Label {
                        text = chapter and (chapter.title .. "  " .. chapter.levelRange) or ("第" .. tostring(lastChapter) .. "章"),
                        fontSize = 13, fontWeight = "bold", color = {255, 210, 120},
                    },
                }
            }
        end

        local status = ""
        local textColor = {160, 155, 140}
        if i < ctx.storyProgress then
            status = "✅ "
            textColor = {100, 180, 80}
        elseif i == ctx.storyProgress then
            status = "➡️ "
            textColor = {255, 230, 100}
        else
            status = "🔒 "
            textColor = {100, 95, 85}
        end
        questChildren[#questChildren + 1] = UI.Panel {
            width = "100%", padding = 8, marginBottom = 4,
            backgroundColor = i == ctx.storyProgress and {50, 48, 35, 200} or {35, 33, 28, 150},
            borderRadius = 8,
            children = {
                UI.Label { text = status .. quest.title, fontSize = 14, fontWeight = "bold", color = textColor },
                UI.Label { text = quest.desc, fontSize = 11, color = {180, 175, 160}, marginTop = 2 },
                i == ctx.storyProgress and UI.Label { text = "💡 " .. quest.hint, fontSize = 10, color = {140, 180, 200}, marginTop = 2 } or nil,
            }
        }
    end

    QuestPanel.panel = UI.Panel {
        width = "100%", height = "100%",
        position = "absolute",
        backgroundColor = { 0, 0, 0, 150 },
        justifyContent = "center", alignItems = "center",
        onClick = function() QuestPanel.Close(ctx) end,
        children = {
            UI.Panel {
                width = 320, maxHeight = "80%",
                backgroundColor = { 40, 36, 28, 250 },
                borderRadius = 16, padding = 16,
                flexDirection = "column",
                onClick = function() end,
                children = {
                    UI.Label { text = "📜 主线任务", fontSize = 18, fontWeight = "bold", color = {255, 240, 180}, marginBottom = 12 },
                    UI.ScrollView {
                        width = "100%", flex = 1, maxHeight = 300,
                        children = questChildren,
                    },
                    UI.Button {
                        text = "关闭", width = "60%", height = 34, marginTop = 12,
                        variant = "default", fontSize = 13,
                        onClick = function() QuestPanel.Close(ctx) end,
                    },
                }
            }
        }
    }

    ctx.ShowOverlayPanel(QuestPanel.panel)
end

return QuestPanel
