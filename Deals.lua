-- Deals watcher: keeps searching a watch list (your watched items, plus favorites and shopping-list
-- reagents if enabled) within the server's search limit, and flags listings at or under a threshold:
-- your max price for the item, or a % of its usual price (median daily low of the previous 14 days).
-- Buying stays a click per purchase (UI/AHDeals.lua); this file only finds the deals.
--
-- db.watch[itemID] = { n = name, max = copper?, pct = 0..1? }
-- Fires "DEALS_UPDATED" and "DEALS_PROGRESS".
local _, ns = ...
local D = {}
ns.Deals = D

local AH = C_AuctionHouse
local MIN_INTERVAL = 1.2 -- seconds between searches
local TIMEOUT = 5        -- give up waiting for one item's results

D.found = {}  -- [itemID] = deal
D.running = false

local function P() return ns.Prices end
local function U() return ns.Util end

---------------------------------------------------------------------------
-- Watch list and thresholds
---------------------------------------------------------------------------
function D.Watch() ns.db.watch = ns.db.watch or {} return ns.db.watch end

function D.AddWatch(itemID, name)
    if not itemID then return end
    local w = D.Watch()
    w[itemID] = w[itemID] or { n = name or U().ItemName(itemID) }
    ns:Fire("DEALS_UPDATED")
end

function D.RemoveWatch(itemID)
    D.Watch()[itemID] = nil
    D.found[itemID] = nil
    ns:Fire("DEALS_UPDATED")
end

function D.IsWatched(itemID) return itemID and D.Watch()[itemID] ~= nil end

--- Usual price: median daily low of the previous 14 days (not today), else the 7-day average.
function D.Usual(itemID, now)
    local e = P().Get(itemID)
    if not e then return nil end
    now = now or time()
    local past = U().DayKeys(15, now)
    past[#past] = nil
    local median = P().Median(e, past)
    if median then return median end
    return P().Average(e, U().DayKeys(7, now))
end

--- Max price per unit for a deal, and how it was set ("max" | "pct").
function D.Threshold(itemID)
    local w = D.Watch()[itemID]
    if w and w.max and w.max > 0 then return w.max, "max" end
    local usual = D.Usual(itemID)
    if not usual then return nil end
    local pct = (w and w.pct) or ns.db.settings.dealsPct or 0.7
    return math.floor(usual * pct), "pct", pct
end

--- Items to check: watched, + favorites and still-needed shopping reagents when enabled. Sorted IDs.
function D.Targets()
    local set, out = {}, {}
    local function add(id) if id and not set[id] then set[id] = true out[#out + 1] = id end end
    for id in pairs(D.Watch()) do add(id) end
    local s = ns.db.settings
    if s.dealsFavorites then for id in pairs(P().Favorites()) do add(id) end end
    if s.dealsShopping and ns.Crafting then
        for _, r in ipairs((ns.Crafting.ShoppingRows())) do if r.remaining > 0 then add(r.id) end end
    end
    table.sort(out)
    return out, set
end

--- Listings at or under the threshold that aren't yours. listings = { { unit, qty, mine, id? } } as
--- AuctionScan returns them; for non-commodities `unit` is the auction's buyout (per stack).
--- Returns a deal or nil.
function D.Evaluate(itemID, listings, isCommodity, threshold)
    threshold = threshold or D.Threshold(itemID)
    if not threshold then return nil end
    local best, qty, cost, pick
    for _, l in ipairs(listings or {}) do
        if l.unit and not l.mine then
            local each = isCommodity and l.unit or l.unit / math.max(1, l.qty or 1)
            if each <= threshold then
                qty = (qty or 0) + (l.qty or 1)
                cost = (cost or 0) + each * (l.qty or 1)
                if not best or each < best then best, pick = each, l end
            end
        end
    end
    if not best then return nil end
    local usual = D.Usual(itemID)
    local cut = ns.CostBasis.CutRate(ns.db)
    return {
        id = itemID, unit = best, qty = qty, cost = cost, usual = usual, threshold = threshold,
        commodity = isCommodity and true or false,
        off = usual and usual > 0 and (1 - best / usual) or nil,
        profit = usual and (usual * (1 - cut) - best) or nil,
        auctionID = pick and pick.id, auctionPrice = pick and pick.unit, t = time(),
    }
end

---------------------------------------------------------------------------
-- Scanner
---------------------------------------------------------------------------
local queue, idx, waiting, lastSend, cycleStart = {}, 0, nil, 0, 0
D.progress = { i = 0, n = 0, cycle = nil }

local function Alert()
    if not ns.db.settings.dealsSound then return end
    pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959)
    if FlashClientIcon then pcall(FlashClientIcon) end
end

local function Ready()
    if not (AH and AH.IsThrottledMessageSystemReady) then return true end
    local ok, ready = pcall(AH.IsThrottledMessageSystemReady)
    return not ok or ready
end

function D.Next()
    if not D.running then return end
    -- A category scan uses the same search budget: wait for it to finish.
    local busy = (D.paused and D.paused()) or (ns.AHScan and ns.AHScan.catScanning)
    if busy or GetTime() - lastSend < MIN_INTERVAL or not Ready() then
        C_Timer.After(0.3, D.Next)
        return
    end
    if idx == 0 or idx >= #queue then
        if idx ~= 0 then D.progress.cycle = GetTime() - cycleStart end
        queue = D.Targets()
        idx = 0
        cycleStart = GetTime()
        if #queue == 0 then
            D.Stop("Nothing to watch. Add items with Watch on the Buy tab, or turn on favorites / shopping list.")
            return
        end
    end
    idx = idx + 1
    local id = queue[idx]
    D.progress.i, D.progress.n = idx, #queue
    local ok, key = pcall(AH.MakeItemKey, id)
    waiting, lastSend = id, GetTime()
    local token = lastSend
    if ok and key then ns.AHScan.Search(key) end
    ns:Fire("DEALS_PROGRESS")
    C_Timer.After(TIMEOUT, function()
        if D.running and waiting == id and lastSend == token then
            waiting = nil
            D.Next()
        end
    end)
end

function D.Start()
    if D.running then return end
    D.running = true
    idx, waiting = 0, nil
    D.progress = { i = 0, n = 0, cycle = D.progress.cycle }
    ns:Fire("DEALS_PROGRESS")
    D.Next()
end

function D.Stop(msg)
    D.running = false
    waiting = nil
    D.stopMsg = msg
    ns:Fire("DEALS_PROGRESS")
end

-- Every search result for a target item (ours or one you ran) refreshes its deal.
ns:Register("AH_SEARCH_RESULTS", function(itemID, listings, isCommodity)
    local _, set = D.Targets()
    if set[itemID] then
        local deal = D.Evaluate(itemID, listings, isCommodity)
        local had = D.found[itemID]
        D.found[itemID] = deal
        if deal and not had then Alert() end
        ns:Fire("DEALS_UPDATED")
    end
    if D.running and waiting == itemID then
        waiting = nil
        C_Timer.After(0.1, D.Next)
    end
end)

ns:On("AUCTION_HOUSE_CLOSED", function()
    if D.running then D.Stop() end
end)

--- Deals sorted by how far under usual they are (or by price when there's no usual).
function D.List()
    local out = {}
    for _, d in pairs(D.found) do out[#out + 1] = d end
    table.sort(out, function(a, b) return (a.off or 0) > (b.off or 0) end)
    return out
end
