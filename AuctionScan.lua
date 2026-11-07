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
        end
    end
    NotifyPrices()
end

ns:On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
    if AH and AH.GetBrowseResults then RecordBrowse(AH.GetBrowseResults()) end
    ns:Fire("AH_BROWSE_UPDATED")
end)
ns:On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function(_, added)
    RecordBrowse(added)
    ns:Fire("AH_BROWSE_UPDATED")
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
    -- Ask the server on the next frame, so the "waiting" status is drawn before the client gets busy.
    C_Timer.After(0, function()
        local ok, err = pcall(AH.ReplicateItems)
        if not ok then
            S.scanning, S.requestedAt = false, nil
            ns.db.lastFullScan = nil
            ns:Fire("SCAN_PROGRESS", "failed", tostring(err))
        end
    end)
    -- A big auction house can take the server a minute or more to answer: show how long it's been, and
    -- only call it failed after WAIT_LIMIT. Even then, data that still arrives is used (see below).
    local function Tick()
        if S.requestedAt ~= requested or not S.scanning or S.processing then return end
        local waited = GetTime() - requested
        if waited >= S.WAIT_LIMIT then
            S.scanning = false
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
S.LATE_LIMIT = 600  -- seconds after asking that the server's data is still accepted

-- Closing the auction house drops the scan: say so instead of waiting for the timeout.
ns:On("AUCTION_HOUSE_CLOSED", function()
    if S.requestedAt and not S.processing then
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
    if S.processing then return end
    -- Data from our request, even if it arrived after we gave up waiting (the server was just slow).
    local late = not S.scanning and S.requestedAt and GetTime() - S.requestedAt <= S.LATE_LIMIT
    if not S.scanning and not late then return end
    S.scanning, S.processing = true, true
    local n = AH.GetNumReplicateItems() or 0
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
