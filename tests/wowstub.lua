-- Minimal WoW API stubs so the addon's non-UI modules can run under plain Lua 5.1+.
local S = {}

S.money = 0
S.gettime = 1000
S.walltime = 1762257600 -- fixed wall clock (2025-11-04 12:00 UTC-ish); tests advance it explicitly
S.frames = {}
S.inbox = {}       -- [index] = { header = {...}, invoice = {...}, link = "..." }
S.sendMoney, S.sendPostage = 0, 30

unpack = unpack or table.unpack

function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function strjoin(sep, ...) return table.concat({ ... }, sep) end
function tostringall(...)
    local out = {}
    for i = 1, select("#", ...) do out[i] = tostring((select(i, ...))) end
    return unpack(out, 1, select("#", ...))
end
function geterrorhandler() return function(err) error(err, 0) end end
function GetTime() return S.gettime end
function GetMoney() return S.money end
function UnitFullName() return "Testgoblin", "TestRealm" end
function UnitName() return "Partner" end
function UnitClass() return "Rogue", "ROGUE" end
function GetRealmName() return "TestRealm" end
function GetNormalizedRealmName() return "TestRealm" end
function InRepairMode() return S.repairMode end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) S.lastPrint = msg end }
C_Timer = { After = function(_, fn) fn() end, NewTicker = function() return {} end }
SlashCmdList = {}
function Mixin(obj, ...) for _, m in ipairs({ ... }) do for k, v in pairs(m) do obj[k] = v end end return obj end

-- Real wall-clock time() but controllable: the addon uses time() for timestamps.
local realTime = os.time
time = function(t) if t then return realTime(t) end return S.walltime end
date = os.date

function CreateFrame()
    local f = { events = {} }
    function f:RegisterEvent(e) self.events[e] = true end
    function f:SetScript(_, fn) self.onEvent = fn end
    S.frames[#S.frames + 1] = f
    return f
end

function S.Fire(event, ...)
    for _, f in ipairs(S.frames) do
        if f.events[event] and f.onEvent then f.onEvent(f, event, ...) end
    end
end

function hooksecurefunc(a, b, c)
    local tbl, name, hook
    if type(a) == "table" then tbl, name, hook = a, b, c else tbl, name, hook = _G, a, b end
    local orig = tbl[name]
    tbl[name] = function(...)
        local r = { orig(...) }
        hook(...)
        return unpack(r)
    end
end

-- APIs the addon hooks (originals are no-ops; tests drive money via S.SetMoney).
function GetQuestReward() end
function RepairAllItems() end
function BuyMerchantItem() end
function BuybackItem() end
function GetMerchantItemID(i) return S.merchantItems and S.merchantItems[i] end
function GetMerchantItemInfo(i) return "Item" .. i, nil, 100, 1 end
function TakeInboxMoney() end
function AutoLootMailItem() end
function TakeInboxItem() end
function SendMail() end
function GetSendMailMoney() return S.sendMoney end
function GetSendMailPrice() return S.sendPostage end
function GetInboxHeaderInfo(i)
    local m = S.inbox[i]
    if not m then return end
    local h = m.header
    return nil, nil, h.sender, h.subject or "", h.money or 0, h.cod or 0, h.daysLeft or 30, h.hasItem, false, false, false, h.canReply
end
function GetInboxInvoiceInfo(i)
    local m = S.inbox[i]
    local inv = m and m.invoice
    if not inv then return end
    return inv.type, inv.itemName, inv.playerName, inv.bid, inv.buyout, inv.deposit, inv.consignment, 0, 0, 0, inv.count
end
function GetInboxItemLink(i) return S.inbox[i] and S.inbox[i].link end
function TakeTaxiNode() end
function DepositGuildBankMoney() end
function WithdrawGuildBankMoney() end

C_AuctionHouse = {
    ConfirmCommoditiesPurchase = function() end,
    PlaceBid = function() end,
    PostItem = function() end,
    PostCommodity = function() end,
}
C_Item = {
    GetItemID = function(loc) return loc.itemID end,
    GetItemName = function(loc) return loc.name end,
    GetItemNameByID = function(id) return S.itemNames and S.itemNames[id] end,
    GetItemInfoInstant = function(x)
        if type(x) == "number" then return x end
        return S.nameToID and S.nameToID[x]
    end,
}
Enum = { PlayerInteractionType = { Merchant = 5, MailInfo = 17, Auctioneer = 21, TaxiNode = 2, Trainer = 7 } }

--- Change gold and fire PLAYER_MONEY.
function S.SetMoney(v)
    S.money = v
    S.Fire("PLAYER_MONEY")
end

function S.AddMoney(d) S.SetMoney(S.money + d) end

function S.Advance(sec)
    S.gettime = S.gettime + sec
    S.walltime = S.walltime + sec
end

--- Load the addon's non-UI files into a fresh namespace and log in.
function S.LoadAddon(root, startMoney)
    _G.GoblinBooksDB = nil
    S.frames = {}
    S.money = startMoney or 0
    local ns = {}
    local files = {
        "Core.lua", "Util.lua", "Categories.lua", "Ledger.lua", "CostBasis.lua", "Prices.lua", "Crafting.lua", "Money.lua",
        "Sources/Loot.lua", "Sources/Quest.lua", "Sources/Merchant.lua", "Sources/Mail.lua",
        "Sources/Trade.lua", "Sources/Misc.lua", "AuctionHouse.lua", "Inventory.lua", "Deals.lua",
    }
    -- Re-create hookable functions each load so hooks don't stack across tests.
    for _, name in ipairs({ "GetQuestReward", "RepairAllItems", "BuyMerchantItem", "BuybackItem", "TakeInboxMoney",
        "AutoLootMailItem", "TakeInboxItem", "SendMail", "TakeTaxiNode", "DepositGuildBankMoney", "WithdrawGuildBankMoney" }) do
        _G[name] = function() end
    end
    for k in pairs(C_AuctionHouse) do C_AuctionHouse[k] = function() end end
    ns.UI = { Toggle = function() end, ShowExport = function() end }
    for _, file in ipairs(files) do
        local chunk = assert(loadfile(root .. "/" .. file))
        chunk("GoblinBooks", ns)
    end
    S.Fire("ADDON_LOADED", "GoblinBooks")
    S.Fire("PLAYER_LOGIN")
    return ns
end

return S
