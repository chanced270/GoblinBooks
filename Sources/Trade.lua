-- Player-to-player trades.
local _, ns = ...
local M = ns.Money

M:RegisterContext("trade", function(delta, data)
    return delta > 0 and "trade_in" or "trade_out", data and data.partner
end)

ns:On("TRADE_SHOW", function()
    M:Enter("trade", { partner = UnitName("NPC") })
end)

ns:On("TRADE_CLOSED", function() M:Leave("trade", 3) end)
