-- Captures AH prices: passively from any browse/search (ours or Blizzard's), and via a full replicate scan.
-- Fires "AH_BROWSE_UPDATED", "PRICES_UPDATED", "AH_SEARCH_RESULTS"(itemID, listings, isCommodity) and "SCAN_PROGRESS"(state, done, total).
local _, ns = ...
local P = ns.Prices
local S = {}
ns.AHScan = S

local AH = C_AuctionHouse
local FULL_SCAN_COOLDOWN = 15 * 60

local function NotifyPrices()
    if S.notifyPending then return end
    S.notifyPending = true
    C_Timer.After(0.5, function()
        S.notifyPending = false
        ns:Fire("PRICES_UPDATED")
    end)
end

local function IsPet(itemKey)
    return itemKey and (itemKey.battlePetSpeciesID or 0) > 0
end

---------------------------------------------------------------------------
-- Browse results (category / text searches)
---------------------------------------------------------------------------
local function RecordBrowse(results)
    if not results then return end
    local now = time()
    for _, r in ipairs(results) do
        local key = r.itemKey
        if key and key.itemID and not IsPet(key) and r.minPrice then
            P.Record(key.itemID, r.minPrice, r.totalQuantity, nil, now, true)
            if S.OnCategoryItem then S.OnCategoryItem(key.itemID, r.totalQuantity) end
        end
    end
    NotifyPrices()
end

ns:On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
    if AH and AH.GetBrowseResults then RecordBrowse(AH.GetBrowseResults()) end
    ns:Fire("AH_BROWSE_UPDATED")
    if S.OnCategoryPage then S.OnCategoryPage() end
end)
ns:On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function(_, added)
    RecordBrowse(added)
    ns:Fire("AH_BROWSE_UPDATED")
    if S.OnCategoryPage then S.OnCategoryPage() end
end)

--- Text and/or category search (results arrive via "AH_BROWSE_UPDATED"; read them with
--- C_AuctionHouse.GetBrowseResults). classFilters = { { classID, subClassID?, inventoryType? } } or nil.
function S.Browse(text, classFilters)
    if not (AH and AH.SendBrowseQuery) then return false end
    local order = (Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price) or 0
    return pcall(AH.SendBrowseQuery, {
        searchString = text or "",
        sorts = { { sortOrder = order, reverseSort = false } },
        filters = {},
        itemClassFilters = classFilters or {},
    })
end

---------------------------------------------------------------------------
-- Single-item searches
---------------------------------------------------------------------------
--- Listings for a commodity: { { unit, qty, mine } } sorted by price (as the server returns them).
function S.CommodityListings(itemID)
    local out = {}
    local n = AH.GetNumCommoditySearchResults(itemID) or 0
    for i = 1, n do
        local r = AH.GetCommoditySearchResultInfo(itemID, i)
        if r and r.unitPrice then
            out[#out + 1] = { unit = r.unitPrice, qty = r.quantity or 0, mine = (r.numOwnerItems or 0) > 0 or r.containsOwnerItem }
        end
    end
    return out
end

--- Non-commodity listings. Returns buyout listings sorted by price ({ unit, qty, mine, link, id, bid fields }),
--- and bid-only listings (no buyout; unit = nil) sorted by next minimum bid.
--- Bid fields: minBid (minimum next bid), bid (current high bid or nil), winning (we are the high bidder), timeLeft band.
-- Last seen non-commodity listing per auction ID (bid vs buyout detection).
S.auctions = {}

function S.ItemListings(itemKey)
    local out, bidOnly = {}, {}
    local me = UnitGUID and UnitGUID("player")
    local n = AH.GetNumItemSearchResults(itemKey) or 0
    for i = 1, n do
        local r = AH.GetItemSearchResultInfo(itemKey, i)
        if r then
            local l = {
                unit = (r.buyoutAmount or 0) > 0 and r.buyoutAmount or nil,
                qty = r.quantity or 1, mine = r.containsOwnerItem, link = r.itemLink, id = r.auctionID,
                minBid = (r.minBid or 0) > 0 and r.minBid or nil,
                bid = (r.bidAmount or 0) > 0 and r.bidAmount or nil,
                winning = me ~= nil and r.bidder == me, timeLeft = r.timeLeft,
            }
            if l.id then S.auctions[l.id] = l end
            if l.unit then out[#out + 1] = l elseif l.minBid then bidOnly[#bidOnly + 1] = l end
        end
    end
    table.sort(out, function(a, b) return a.unit < b.unit end)
    table.sort(bidOnly, function(a, b) return a.minBid < b.minBid end)
    return out, bidOnly
end

-- Lowest price that isn't ours, per item, from searches this session: [itemID] = { p = unit or nil, t = time }
S.competitor = {}

local function RecordListings(itemID, listings, isCommodity, bidOnly, complete)
    local low, other, qty = nil, nil, 0
    for _, l in ipairs(listings) do
        if not low or l.unit < low then low = l.unit end
        if not l.mine and (not other or l.unit < other) then other = l.unit end
        qty = qty + l.qty
    end
    for _, l in ipairs(bidOnly or {}) do qty = qty + l.qty end
    S.competitor[itemID] = { p = other, t = time() }
    if low then P.Record(itemID, low, qty, ns.Util.ItemName(itemID), nil, complete) end
    ns:Fire("AH_SEARCH_RESULTS", itemID, listings, isCommodity, bidOnly or {})
    NotifyPrices()
end

local function OnCommodity(_, itemID)
    if not itemID then return end
    -- Only a fully loaded result set gives a true listed count (for the market estimate).
    local ok, full = pcall(AH.HasFullCommoditySearchResults, itemID)
    RecordListings(itemID, S.CommodityListings(itemID), true, nil, ok and full)
end
ns:On("COMMODITY_SEARCH_RESULTS_UPDATED", OnCommodity)
ns:On("COMMODITY_SEARCH_RESULTS_ADDED", OnCommodity)

local function OnItem(_, itemKey)
    if itemKey and itemKey.itemID and not IsPet(itemKey) then
        local listings, bidOnly = S.ItemListings(itemKey)
        local ok, full = pcall(AH.HasFullItemSearchResults, itemKey)
        RecordListings(itemKey.itemID, listings, false, bidOnly, ok and full)
    end
end
ns:On("ITEM_SEARCH_RESULTS_UPDATED", OnItem)
ns:On("ITEM_SEARCH_RESULTS_ADDED", OnItem)

local PRICE_SORT = { { sortOrder = 0, reverseSort = false } } -- Enum.AuctionHouseSortOrder.Price

--- Search one item (commodity or not). Results arrive via "AH_SEARCH_RESULTS".
function S.Search(itemKey)
    if not (AH and AH.SendSearchQuery and itemKey) then return false end
    local sorts = PRICE_SORT
    if Enum and Enum.AuctionHouseSortOrder then sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } } end
    return pcall(AH.SendSearchQuery, itemKey, sorts, true)
end

---------------------------------------------------------------------------
-- Scan log (saved, newest last): what was requested, what the game blocked, what arrived and when. Read
-- from the saved variables to see why a scan failed.
---------------------------------------------------------------------------
local LOG_MAX = 60
function S.Log(event, detail)
    if not ns.db then return end
    local log = ns.db.scanLog or {}
    ns.db.scanLog = log
    log[#log + 1] = { t = time(), e = event, d = detail ~= nil and tostring(detail) or nil }
    while #log > LOG_MAX do table.remove(log, 1) end
end

-- The game refusing one of our calls (e.g. one that must come straight from a click) shows up here.
local function OnBlocked(event, addon, func)
    if addon ~= ns.ADDON then return end
    S.Log(event == "ADDON_ACTION_FORBIDDEN" and "forbidden" or "blocked", func)
    if S.scanning and not S.processing and type(func) == "string" and func:find("Replicate") then
        S.scanning, S.requestedAt = false, nil
        ns:Fire("SCAN_PROGRESS", "failed", "the game blocked the request (" .. func .. ")")
    end
end
ns:On("ADDON_ACTION_BLOCKED", OnBlocked)
ns:On("ADDON_ACTION_FORBIDDEN", OnBlocked)

---------------------------------------------------------------------------
-- Full scan (C_AuctionHouse.ReplicateItems, server allows one every 15 minutes)
---------------------------------------------------------------------------
function S.FullScanReady(now)
    local last = ns.db.lastFullScan or 0
    local left = FULL_SCAN_COOLDOWN - ((now or time()) - last)
    return left <= 0, math.max(0, left)
end

function S.FullScan()
    if not (AH and AH.ReplicateItems) then return false, "full scan not supported by this client" end
    if S.scanning then return false, "scan already running" end
    local ready, left = S.FullScanReady()
    if not ready then return false, ("full scan available in %dm %ds"):format(math.floor(left / 60), left % 60) end
    S.scanning, S.processing = true, false
    local requested = GetTime()
    S.requestedAt = requested
    ns.db.lastFullScan = time()
    ns:Fire("SCAN_PROGRESS", "waiting", 0)
    -- Called directly (from the Scan button's click), not from a timer: some auction house requests are
    -- only allowed straight from a click. The client stays responsive here; the heavy part comes later.
    local ok, err = pcall(AH.ReplicateItems)
    S.Log("full: request", ok and "sent" or ("error: " .. tostring(err)))
    if not ok then
        S.scanning, S.requestedAt = false, nil
        ns.db.lastFullScan = nil
        ns:Fire("SCAN_PROGRESS", "failed", tostring(err))
        return true
    end
    -- A big auction house can take the server a minute or more to answer: show how long it's been, and
    -- only call it failed after WAIT_LIMIT. Even then, data that still arrives is used (see below).
    local function Tick()
        if S.requestedAt ~= requested or not S.scanning or S.processing then return end
        local waited = GetTime() - requested
        if waited >= S.WAIT_LIMIT then
            S.scanning = false
            S.Log("full: timeout", math.floor(waited) .. "s")
            ns:Fire("SCAN_PROGRESS", "failed", ("no answer from the server after %d seconds"):format(S.WAIT_LIMIT))
            return
        end
        ns:Fire("SCAN_PROGRESS", "waiting", math.floor(waited))
        C_Timer.After(5, Tick)
    end
    C_Timer.After(5, Tick)
    return true
end

S.WAIT_LIMIT = 180  -- seconds before a scan with no answer shows as failed
S.POST_HOLD = 2     -- seconds after a post that background searches wait (posts get the request budget)
S.postHoldUntil = 0

--- True while you're posting: background searches (Deals watcher, category scan) should wait.
function S.PostingHold()
    return GetTime() < (S.postHoldUntil or 0)
end
S.LATE_LIMIT = 600  -- seconds after asking that the server's data is still accepted

-- Closing the auction house drops the scan: say so instead of waiting for the timeout.
ns:On("AUCTION_HOUSE_CLOSED", function()
    if S.requestedAt and not S.processing then
        S.Log("full: auction house closed", S.scanning and "while waiting" or "after the timeout")
        local wasWaiting = S.scanning
        S.scanning, S.requestedAt = false, nil
        if wasWaiting then ns:Fire("SCAN_PROGRESS", "failed", "the auction house was closed before the data arrived") end
    end
end)

-- Work in small time slices (BUDGET_MS per frame) so the game keeps drawing and the status line updates.
-- A big auction house has tens of thousands of auctions; reading or saving them in one go froze the client.
local BUDGET_MS = 12
local clock = debugprofilestop or function() return GetTime() * 1000 end

ns:On("REPLICATE_ITEM_LIST_UPDATE", function()
    local count = AH.GetNumReplicateItems and AH.GetNumReplicateItems() or 0
    local since = S.requestedAt and math.floor(GetTime() - S.requestedAt)
    if S.processing then
        S.repeatEvents = (S.repeatEvents or 0) + 1 -- the client repeats this while it loads item details
        return
    end
    -- Data from our request, even if it arrived after we gave up waiting (the server was just slow).
    local late = not S.scanning and S.requestedAt and GetTime() - S.requestedAt <= S.LATE_LIMIT
    if not S.scanning and not late then
        S.Log("full: data event ignored", ("%d auctions, %s"):format(count, since and (since .. "s after request") or "no request"))
        return
    end
    S.Log("full: data arrived", ("%d auctions, %ss after request%s"):format(count, tostring(since), late and " (late)" or ""))
    S.repeatEvents = 0
    S.scanning, S.processing = true, true
    local n = count
    local lows, qtys, names = {}, {}, {}
    local i = 0
    local ids, j, now
    local lastReport = 0

    local function Report(state, done, total)
        local t = clock()
        if t - lastReport < 200 and done < total then return end -- 5 updates a second is plenty
        lastReport = t
        ns:Fire("SCAN_PROGRESS", state, done, total)
    end

    local function Save()
        local start = clock()
        while j < #ids do
            j = j + 1
            local itemID = ids[j]
            P.Record(itemID, lows[itemID], qtys[itemID], names[itemID], now, true)
            if j % 100 == 0 and clock() - start > BUDGET_MS then break end
        end
        Report("saving", j, #ids)
        if j < #ids then
            C_Timer.After(0, Save)
            return
        end
        S.scanning, S.processing, S.requestedAt = false, false, nil
        ns.db.lastScanResult = { t = time(), items = #ids, auctions = n, kind = "full" }
        S.Log("full: done", ("%d items from %d auctions (%d repeated data events while reading)"):format(
            #ids, n, S.repeatEvents or 0))
        S.repeatEvents = 0
        ns:Fire("SCAN_PROGRESS", "done", #ids, n)
        ns:Fire("PRICES_UPDATED")
    end

    local function Read()
        local start = clock()
        while i < n do
            local name, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = AH.GetReplicateItemInfo(i)
            if itemID and buyout and buyout > 0 and count and count > 0 then
                local unit = buyout / count
                if not lows[itemID] or unit < lows[itemID] then lows[itemID] = unit end
                qtys[itemID] = (qtys[itemID] or 0) + count
                if name and name ~= "" then names[itemID] = name end
            end
            i = i + 1
            if i % 100 == 0 and clock() - start > BUDGET_MS then break end
        end
        Report("reading", i, n)
        if i < n then
            C_Timer.After(0, Read)
            return
        end
        ids, j, now = {}, 0, time()
        for itemID in pairs(lows) do ids[#ids + 1] = itemID end
        C_Timer.After(0, Save)
    end
    Read()
end)

---------------------------------------------------------------------------
-- Category scan: the same searches as the Buy page, one category at a time (every page of each), instead
-- of the full snapshot. No 15-minute cooldown, prices are saved as each page arrives, and stopping keeps
-- what was found. Paced by the server's search throttle; the Deals watcher waits while it runs.
-- mode: "all" (every category) or "crafting" (trade goods, consumables, recipes, gems, reagents,
-- item enhancements).
---------------------------------------------------------------------------
S.CAT_INTERVAL = 0.6 -- seconds between requests (the server throttles faster ones)
S.CAT_TIMEOUT = 12   -- seconds to wait for a page before moving on
local CRAFTING_CLASSES = { [7] = true, [0] = true, [9] = true, [3] = true, [5] = true, [8] = true }

--- Top-level AH categories: { { label, filters } } (from the game's category list, or item classes).
function S.Categories()
    local cats = {}
    if type(AuctionCategories) == "table" then
        for _, c in ipairs(AuctionCategories) do
            if c.name and type(c.filters) == "table" and #c.filters > 0 then
                cats[#cats + 1] = { label = c.name, filters = c.filters }
            end
        end
    end
    if #cats == 0 and C_Item and C_Item.GetItemClassInfo then
        for _, id in ipairs({ 2, 4, 1, 3, 8, 0, 16, 7, 9, 17, 12, 15, 5 }) do
            local ok, name = pcall(C_Item.GetItemClassInfo, id)
            if ok and name then cats[#cats + 1] = { label = name, filters = { { classID = id } } } end
        end
    end
    return cats
end

--- { { label, filters, subs = { { label, filters } } } } for category dropdowns (Buy and Flips pages).
function S.CategoryTree()
    local cats = {}
    if type(AuctionCategories) == "table" then
        for _, c in ipairs(AuctionCategories) do
            if c.name and type(c.filters) == "table" and #c.filters > 0 then
                local subs = {}
                for _, sc in ipairs(c.subCategories or {}) do
                    if sc.name and type(sc.filters) == "table" and #sc.filters > 0 then
                        subs[#subs + 1] = { label = sc.name, filters = sc.filters }
                    end
                end
                cats[#cats + 1] = { label = c.name, filters = c.filters, subs = subs }
            end
        end
    end
    if #cats == 0 and C_Item and C_Item.GetItemClassInfo then
        for _, id in ipairs({ 2, 4, 1, 3, 8, 0, 16, 7, 9, 17, 12, 15 }) do
            local ok, name = pcall(C_Item.GetItemClassInfo, id)
            if ok and name then cats[#cats + 1] = { label = name, filters = { { classID = id } }, subs = {} } end
        end
    end
    return cats
end

local function Avg(itemID)
    return P.Average(P.Get(itemID), U.DayKeys(7))
end

--- Does an item fit any of these AH filters ({ classID, subClassID?, inventoryType? })? Local data only:
--- no server request. Nil or empty filters match everything; unknown items match nothing.
function S.ItemMatches(itemID, filters)
    if not filters or #filters == 0 then return true end
    if not (itemID and C_Item and C_Item.GetItemInfoInstant) then return false end
    local ok, _, _, _, _, _, classID, subClassID = pcall(C_Item.GetItemInfoInstant, itemID)
    if not ok or classID == nil then return false end
    local invType
    for _, f in ipairs(filters) do
        if (f.classID == nil or f.classID == classID) and (f.subClassID == nil or f.subClassID == subClassID) then
            if f.inventoryType == nil then return true end
            if invType == nil then
                local fn = C_Item.GetItemInventoryTypeByID
                local ok2, t = false, nil
                if fn then ok2, t = pcall(fn, itemID) end
                invType = ok2 and t or false
            end
            -- The client can't tell the slot: let it through rather than hide it.
            if invType == false or invType == f.inventoryType then return true end
        end
    end
    return false
end

local function CategoriesFor(mode)
    local out = {}
    for _, c in ipairs(S.Categories()) do
        local class = c.filters[1] and c.filters[1].classID
        if mode == "all" or (class ~= nil and CRAFTING_CLASSES[class]) then out[#out + 1] = c end
    end
    return out
end

local cat -- the running category scan: { list, i, items = { [itemID] = true }, count, auctions, token, waiting }
local lastCatSend = 0

local function Ready()
    if not (AH and AH.IsThrottledMessageSystemReady) then return true end
    local ok, ready = pcall(AH.IsThrottledMessageSystemReady)
    return not ok or ready
end

local NextCategory

--- Sends one request when the server is ready; moves on if no page comes back in time.
local function Send(fn)
    if not cat then return end
    if not Ready() or GetTime() - lastCatSend < S.CAT_INTERVAL or S.PostingHold() then
        C_Timer.After(0.2, function() Send(fn) end)
        return
    end
    lastCatSend = GetTime()
    cat.token = cat.token + 1
    local token = cat.token
    cat.waiting = true
    pcall(fn)
    C_Timer.After(S.CAT_TIMEOUT, function()
        if cat and cat.token == token and cat.waiting then
            cat.waiting = false
            NextCategory()
        end
    end)
end

local function Report()
    local c = cat.list[cat.i]
    ns:Fire("SCAN_PROGRESS", "categories", cat.i, #cat.list, c and c.label, cat.count)
end

local function Finish(state)
    local done = cat
    S.Log("categories: " .. state, ("%d items, %d of %d categories"):format(done.count, math.min(done.i, #done.list), #done.list))
    cat = nil
    S.catScanning = false
    ns.db.lastScanResult = { t = time(), items = done.count, auctions = done.auctions, kind = "categories" }
    ns:Fire("SCAN_PROGRESS", state, done.count, done.auctions)
    ns:Fire("PRICES_UPDATED")
end

function NextCategory()
    if not cat then return end
    cat.i = cat.i + 1
    if cat.i > #cat.list then
        Finish("done")
        return
    end
    Report()
    local filters = cat.list[cat.i].filters
    Send(function() S.Browse("", filters) end)
end

function S.OnCategoryItem(itemID, qty)
    if not cat or not cat.waiting then return end
    if not cat.items[itemID] then
        cat.items[itemID] = true
        cat.count = cat.count + 1
    end
    cat.auctions = cat.auctions + (qty or 0)
end

--- A page of browse results arrived: ask for the next page, or go to the next category.
function S.OnCategoryPage()
    if not cat or not cat.waiting then return end
    cat.waiting = false
    local full = true
    if AH.HasFullBrowseResults then
        local ok, v = pcall(AH.HasFullBrowseResults)
        full = not ok or v
    end
    if full then
        C_Timer.After(0, NextCategory)
    else
        Report()
        Send(function() AH.RequestMoreBrowseResults() end)
    end
end

-- A category scan of everything sends a lot of searches. Blizzard doesn't document how its servers treat
-- repeated ones, so we limit ourselves: at most one every CAT_ALL_COOLDOWN, counted from its start
-- (stopping early doesn't reset it). Crafting-market scans are much smaller and aren't limited.
S.CAT_ALL_COOLDOWN = 5 * 60

--- Whether a scan of this mode can start now, and the seconds left if not.
function S.CategoryScanReady(mode, now)
    if mode ~= "all" then return true, 0 end
    local last = ns.db.lastCategoryScanAll or 0
    local left = S.CAT_ALL_COOLDOWN - ((now or time()) - last)
    return left <= 0, math.max(0, left)
end

--- Starts a category scan. Returns true, or false and why not.
function S.CategoryScan(mode)
    mode = mode or "all"
    if not (AH and AH.SendBrowseQuery) then return false, "searching isn't supported by this client" end
    if S.scanning or cat then return false, "a scan is already running" end
    local ready, left = S.CategoryScanReady(mode)
    if not ready then
        return false, ("a scan of every category is limited to one every 5 minutes: available in %dm %ds"):format(
            math.floor(left / 60), left % 60)
    end
    local list = CategoriesFor(mode)
    if #list == 0 then return false, "no auction house categories found" end
    if mode == "all" then ns.db.lastCategoryScanAll = time() end
    S.Log("categories: start", mode .. ", " .. #list .. " categories")
    cat = { list = list, i = 0, items = {}, count = 0, auctions = 0, token = 0, waiting = false }
    S.catScanning = true
    NextCategory()
    return true
end

--- Stops a category scan; the prices found so far are kept.
function S.StopCategoryScan()
    if cat then Finish("stopped") end
end

ns:On("AUCTION_HOUSE_CLOSED", function()
    if cat then Finish("stopped") end
end)
