-- Looted gold: money gained while a loot window is open (or just closed).
-- Group-loot shares arrive without our own loot window, so CHAT_MSG_MONEY acts as a hint (its text is never parsed).
local _, ns = ...
local M = ns.Money

M:RegisterContext("loot", function(delta)
    if delta > 0 then return "loot" end
end)

ns:On("LOOT_READY", function() M:Enter("loot") end)
ns:On("LOOT_OPENED", function() M:Enter("loot") end)
ns:On("LOOT_CLOSED", function() M:Leave("loot", 1.5) end)

ns:On("CHAT_MSG_MONEY", function()
    if M:IsActive("loot") then return end
    if not M:ClaimRecent("loot", nil, 2, "share") then
        M:Expect({ cat = "loot", s = "share", sign = 1, ttl = 2 })
    end
end)
