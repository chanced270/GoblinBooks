-- Account inventory and net worth.
--
-- Item counts per character (bags incl. reagent bag; bank incl. bank bags, reagent bank and character bank
-- tabs, read while the bank is open) and for the warband bank (account-wide), so tooltips and the shopping
-- list can show what your alts hold. Net worth = gold of every character on the realm + everything they
-- own at its value (AH market after the cut, or vendor price when that's better; junk and soulbound items
-- at vendor price). A daily snapshot feeds the Net worth chart.
--
-- char.inv = { bags = { [id] = n }, bank = { [id] = n }, boundBags = { [id] = n }, boundBank = { [id] = n },
--              bagsT, bankT }
-- db.warband = { items = { [id] = n }, t }
-- db.netWorth[realm][dayKey] = { gold, items }
local _, ns = ...
local I = {}
ns.Inventory = I

local function U() return ns.Util end
local function P() return ns.Prices end

---------------------------------------------------------------------------
-- Container IDs
---------------------------------------------------------------------------
local function BagIDs()
    local ids = {}
    for i = 0, (NUM_BAG_SLOTS or 4) do ids[#ids + 1] = i end
    local reagent = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
    if reagent then ids[#ids + 1] = reagent end
    return ids
end

--- Bank containers (character) and warband bank tabs, from Enum.BagIndex when the client has it.
local function BankIDs()
    local bank, warband = {}, {}
    local E = Enum and Enum.BagIndex
    if E then
        for name, id in pairs(E) do
            if type(id) == "number" then
                if name:find("^AccountBankTab") then
                    warband[#warband + 1] = id
                elseif name:find("Bank") then
                    bank[#bank + 1] = id
                end
            end
        end
    end
    if #bank == 0 then
        bank[1] = -1 -- main bank
        local first = (NUM_BAG_SLOTS or 4) + 1
        for i = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do bank[#bank + 1] = i end
        bank[#bank + 1] = -3 -- reagent bank
    end
    return bank, warband
end

local function ReadContainers(ids)
    local items, bound = {}, {}
    if not (C_Container and C_Container.GetContainerNumSlots) then return items, bound end
    for _, bag in ipairs(ids) do
        local ok, slots = pcall(C_Container.GetContainerNumSlots, bag)
        for slot = 1, (ok and slots) or 0 do
            local okI, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
            if okI and type(info) == "table" and info.itemID then
                local n = info.stackCount or 1
                items[info.itemID] = (items[info.itemID] or 0) + n
                if info.isBound then bound[info.itemID] = (bound[info.itemID] or 0) + n end
            end
        end
    end
    return items, bound
end

---------------------------------------------------------------------------
-- Scanning
---------------------------------------------------------------------------
local bankOpen = false

local function Inv(c)
    c.inv = c.inv or { bags = {}, bank = {}, boundBags = {}, boundBank = {} }
    return c.inv
end

I.version = 0 -- bumped whenever an inventory changes (net worth cache key)

function I.ScanBags()
    if not ns.char then return end
    local inv = Inv(ns.char)
    inv.bags, inv.boundBags = ReadContainers(BagIDs())
    inv.bagsT = time()
    I.version = I.version + 1
end

function I.ScanBank()
    if not ns.char or not bankOpen then return end
    local inv = Inv(ns.char)
    local bankIDs, warbandIDs = BankIDs()
    inv.bank, inv.boundBank = ReadContainers(bankIDs)
    inv.bankT = time()
    I.version = I.version + 1
    if #warbandIDs > 0 then
        local items = ReadContainers(warbandIDs)
        if next(items) ~= nil or not ns.db.warband then
            ns.db.warband = { items = items, t = time() }
        end
    end
end

local queued = false
local function QueueScan()
    if queued then return end
    queued = true
    C_Timer.After(1, function()
        queued = false
        pcall(I.ScanBags)
        if bankOpen then pcall(I.ScanBank) end
        ns:Fire("INVENTORY_UPDATED")
    end)
end

ns:On("BAG_UPDATE_DELAYED", QueueScan)
ns:On("BANKFRAME_OPENED", function()
    bankOpen = true
    QueueScan()
end)
ns:On("BANKFRAME_CLOSED", function()
    pcall(I.ScanBank)
    bankOpen = false
    I.Snapshot()
end)
ns:On("PLAYERBANKSLOTS_CHANGED", QueueScan)

---------------------------------------------------------------------------
-- Queries
---------------------------------------------------------------------------
--- Characters on the current realm: list of { key, name, char }.
local function RealmChars()
    local out = {}
    local prefix = (ns.realm or "") .. "-"
    for key, c in pairs(ns.db.chars or {}) do
        if key:sub(1, #prefix) == prefix then
            out[#out + 1] = { key = key, name = key:sub(#prefix + 1), char = c }
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end
I.RealmChars = RealmChars

--- { mine = { bags, bank }, alts = { { name, bags, bank } }, warband, total, altTotal }
function I.Owned(itemID)
    local out = { mine = { bags = 0, bank = 0 }, alts = {}, warband = 0, total = 0, altTotal = 0 }
    if not itemID or not ns.db then return out end
    for _, rc in ipairs(RealmChars()) do
        local inv = rc.char.inv
        local bags = inv and inv.bags[itemID] or 0
        local bank = inv and inv.bank[itemID] or 0
        if rc.key == ns.charKey then
            out.mine.bags, out.mine.bank = bags, bank
        elseif bags + bank > 0 then
            out.alts[#out.alts + 1] = { name = rc.name, bags = bags, bank = bank }
            out.altTotal = out.altTotal + bags + bank
        end
        out.total = out.total + bags + bank
    end
    out.warband = ns.db.warband and ns.db.warband.items[itemID] or 0
    out.total = out.total + out.warband
    return out
end

--- What other characters and the warband bank hold (for the shopping list).
function I.AltCount(itemID)
    local o = I.Owned(itemID)
    return o.altTotal + o.warband, o
end

---------------------------------------------------------------------------
-- Net worth
---------------------------------------------------------------------------
local function VendorPrice(itemID)
    local price
    if C_Item and C_Item.GetItemInfo then
        local ok, _, _, _, _, _, _, _, _, _, _, sell = pcall(C_Item.GetItemInfo, itemID)
        if ok then price = sell end
    end
    if price == nil and GetItemInfo then price = select(11, GetItemInfo(itemID)) end
    return price or 0
end
I.VendorPrice = VendorPrice

--- Value of one unit: the better of AH market (after the cut) and vendor; junk at vendor price.
--- bound = true: can't be auctioned, so vendor price only.
function I.UnitValue(itemID, bound, vendorFn)
    local vendor = (vendorFn or VendorPrice)(itemID) or 0
    if bound or P().IsJunk(itemID) then return vendor end
    local m = P().Market(itemID)
    if m then
        local net = m * (1 - ns.CostBasis.CutRate(ns.db))
        if net > vendor then return net end
    end
    return vendor
end

local function AddItems(acc, items, bound, vendorFn, where)
    for id, n in pairs(items or {}) do
        local b = bound and bound[id] or 0
        local free = n - b
        local v = (free > 0 and free * I.UnitValue(id, false, vendorFn) or 0) + (b > 0 and b * I.UnitValue(id, true, vendorFn) or 0)
        if v > 0 then
            acc.items = acc.items + v
            acc.byItem[id] = (acc.byItem[id] or 0) + v
            acc.where[where] = (acc.where[where] or 0) + v
        end
    end
end

--- { gold, items, total, where = { bags, bank, alts, warband }, top = { { id, value } } } for the realm.
--- The default valuation is cached until prices, inventories, gold or the minute change.
local nwCache, nwKey
local NetWorthUncached
function I.NetWorth(vendorFn)
    if vendorFn then return NetWorthUncached(vendorFn) end
    local key = ("%s:%d:%d:%d"):format(tostring(P().version), I.version, GetMoney() or 0, math.floor(time() / 60))
    if nwKey ~= key then nwCache, nwKey = NetWorthUncached(), key end
    return nwCache
end

function NetWorthUncached(vendorFn)
    local acc = { gold = 0, items = 0, byItem = {}, where = {} }
    for _, rc in ipairs(RealmChars()) do
        local c = rc.char
        local mine = rc.key == ns.charKey
        local gold = mine and GetMoney() or c.lastMoney or 0
        acc.gold = acc.gold + gold
        local inv = c.inv
        if inv then
            AddItems(acc, inv.bags, inv.boundBags, vendorFn, mine and "bags" or "alts")
            AddItems(acc, inv.bank, inv.boundBank, vendorFn, mine and "bank" or "alts")
        end
    end
    if ns.db.warband then AddItems(acc, ns.db.warband.items, nil, vendorFn, "warband") end
    local top = {}
    for id, v in pairs(acc.byItem) do top[#top + 1] = { id = id, value = v } end
    table.sort(top, function(a, b) return a.value > b.value end)
    acc.top = top
    acc.total = acc.gold + acc.items
    return acc
end

--- Today's snapshot for the realm (kept per day; older ones pruned).
function I.Snapshot()
    if not ns.db or not ns.realm then return end
    local nw = I.NetWorth()
    ns.db.netWorth = ns.db.netWorth or {}
    local realm = ns.db.netWorth[ns.realm] or {}
    ns.db.netWorth[ns.realm] = realm
    realm[U().DateKey(time())] = { gold = math.floor(nw.gold), items = math.floor(nw.items) }
    local keep = {}
    for _, k in ipairs(U().DayKeys((ns.db.settings.retentionDays or 90) * 4)) do keep[k] = true end
    for k in pairs(realm) do if not keep[k] then realm[k] = nil end end
    ns:Fire("NETWORTH_UPDATED")
end

--- Daily history for the chart: list of { key, gold, items } over the last `days` (gaps carry the
--- previous day forward; nothing before the first snapshot).
function I.History(days)
    local realm = ns.db.netWorth and ns.db.netWorth[ns.realm] or {}
    local out, last = {}, nil
    for _, key in ipairs(U().DayKeys(days)) do
        local s = realm[key] or last
        if s then last = s end
        out[#out + 1] = { key = key, gold = s and s.gold or 0, items = s and s.items or 0 }
    end
    return out
end

ns:Register("READY", function()
    pcall(I.ScanBags)
    -- Item prices/info load over the first seconds; snapshot then and every 10 minutes.
    C_Timer.After(10, function() pcall(I.Snapshot) end)
    C_Timer.NewTicker(600, function() pcall(I.Snapshot) end)
end)
