-- Quest rewards (and the occasional quest that costs gold).
local _, ns = ...
local M, U = ns.Money, ns.Util

local function QuestTitle(questID)
    if questID and C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, title = pcall(C_QuestLog.GetTitleForQuestID, questID)
        if ok and title then return title end
    end
    if GetTitleText then
        local ok, title = pcall(GetTitleText)
        if ok and title and title ~= "" then return title end
    end
end

-- Quest reward frame open.
M:RegisterContext("quest", function(_, data)
    return "quest", data and data.title
end)

ns:On("QUEST_COMPLETE", function() M:Enter("quest", { title = QuestTitle() }) end)
ns:On("QUEST_FINISHED", function() M:Leave("quest", 2) end)

U.HookGlobal("GetQuestReward", function()
    M:Expect({ cat = "quest", sign = 1, ttl = 3, s = QuestTitle() })
end)

-- Covers auto-complete / world quests where no reward frame is shown. Money may already have been recorded.
ns:On("QUEST_TURNED_IN", function(_, questID, _, money)
    if not money or money == 0 then return end
    local title = QuestTitle(questID)
    if not M:ClaimRecent("quest", money, 3, title) then
        M:Expect({ cat = "quest", amount = money, ttl = 3, s = title })
    end
end)
