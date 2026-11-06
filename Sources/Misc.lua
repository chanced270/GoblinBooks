-- Services and banks: flights, trainers, transmog, barber, guild bank, warband bank.
local _, ns = ...
local M, U = ns.Money, ns.Util

local function Fixed(cat)
    return function() return cat end
end

local function BankClassifier(cat)
    return function(delta) return cat, delta < 0 and "Deposit" or "Withdraw" end
end

M:RegisterContext("flight", Fixed("flight"))
M:RegisterContext("training", Fixed("training"))
M:RegisterContext("transmog", Fixed("transmog"))
M:RegisterContext("barber", Fixed("barber"))
M:RegisterContext("guildbank", BankClassifier("guildbank"))
M:RegisterContext("warbank", BankClassifier("warbank"))

-- Modern clients route most NPC windows through the interaction manager.
local interaction = {}
local function Map(enumName, ctx)
    local v = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType[enumName]
    if v then interaction[v] = ctx end
end
Map("TaxiNode", "flight")
Map("Trainer", "training")
Map("Transmogrifier", "transmog")
Map("GuildBanker", "guildbank")
Map("Banker", "warbank")
Map("AccountBanker", "warbank")
Map("Merchant", "merchant")
Map("MailInfo", "mail")
Map("Auctioneer", "auction")

ns:On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, kind)
    local ctx = interaction[kind]
    if ctx and not M:IsActive(ctx) then M:Enter(ctx) end
end)

ns:On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, kind)
    local ctx = interaction[kind]
    if ctx then M:Leave(ctx, 3) end
end)

-- Legacy / extra events (harmless if missing).
ns:On("TAXIMAP_OPENED", function() M:Enter("flight") end)
ns:On("TAXIMAP_CLOSED", function() M:Leave("flight", 3) end)
ns:On("TRAINER_SHOW", function() M:Enter("training") end)
ns:On("TRAINER_CLOSED", function() M:Leave("training", 2) end)
ns:On("TRANSMOGRIFY_OPEN", function() M:Enter("transmog") end)
ns:On("TRANSMOGRIFY_CLOSE", function() M:Leave("transmog", 2) end)
ns:On("BARBER_SHOP_OPEN", function() M:Enter("barber") end)
ns:On("BARBER_SHOP_CLOSE", function() M:Leave("barber", 2) end)

-- Explicit actions.
U.HookGlobal("TakeTaxiNode", function()
    M:Expect({ cat = "flight", sign = -1, ttl = 3 })
end)
U.HookGlobal("DepositGuildBankMoney", function(amount)
    M:Expect({ cat = "guildbank", s = "Deposit", amount = amount and -amount or nil, sign = -1, ttl = 5 })
end)
U.HookGlobal("WithdrawGuildBankMoney", function(amount)
    M:Expect({ cat = "guildbank", s = "Withdraw", amount = amount, sign = 1, ttl = 5 })
end)
if C_Bank then
    U.HookMethod(C_Bank, "DepositMoney", function(_, amount)
        M:Expect({ cat = "warbank", s = "Deposit", amount = amount and -amount or nil, sign = -1, ttl = 5 })
    end)
    U.HookMethod(C_Bank, "WithdrawMoney", function(_, amount)
        M:Expect({ cat = "warbank", s = "Withdraw", amount = amount, sign = 1, ttl = 5 })
    end)
end
