-- Auction house price database: latest observed lowest unit buyout per item, plus a daily low history.
-- Stored per realm in GoblinBooksDB.prices[realm][itemID] =
--   { n = name, p = unit, q = qty, t = time, d = { [day] = low },
--     qd = { [day] = listed qty }, out = { [day] = est. units that left the AH }, lqq/lqt = last complete count }
local _, ns = ...
local P = {}
ns.Prices = P

function P.Store()
    local db = ns.db
    db.prices = db.prices or {}
    local realm = ns.realm or "?"
    local store = db.prices[realm]
    if not store then
        store = {}
        db.prices[realm] = store
    end
    return store
end

function P.Get(itemID)
    return itemID and P.Store()[itemID]
end

--- Record an observed lowest unit buyout (copper) for an item. `complete` = qty counts every listing
--- (browse results, full scans, fully loaded searches), so it can feed the market-activity estimate.
function P.Record(itemID, unitPrice, qty, name, t, complete)
    if not itemID or not unitPrice or unitPrice <= 0 then return end
    unitPrice = math.floor(unitPrice + 0.5)
    t = t or time()
    local store = P.Store()
    local e = store[itemID]
    if not e then
        e = { d = {} }
        store[itemID] = e
    end
    e.p, e.t = unitPrice, t
    if qty then e.q = qty end
    if name and name ~= "" then e.n = name end
    local day = ns.Util.DateKey(t)
    local low = e.d[day]
    if not low or unitPrice < low then e.d[day] = unitPrice end
    if complete and qty then P.ObserveQty(e, qty, t) end
    P.version = (P.version or 0) + 1
end

---------------------------------------------------------------------------
-- Market activity: an ESTIMATE. The game never reports other players' sales; we only see how many are
-- listed. A drop between two complete counts (taken within OBS_GAP) is counted as units that left the
-- AH that day, which includes sales but also expirations and cancellations. New listings in between
-- hide sales, so this can undercount too.
---------------------------------------------------------------------------
P.OBS_GAP = 48 * 3600

function P.ObserveQty(e, qty, t)
    local day = ns.Util.DateKey(t)
    e.qd = e.qd or {}
    e.qd[day] = qty
    if e.lqt and t > e.lqt and t - e.lqt <= P.OBS_GAP then
        e.out = e.out or {}
        -- Recording 0 marks the day as measured even when nothing left.
        e.out[day] = (e.out[day] or 0) + math.max(0, (e.lqq or 0) - qty)
    end
    e.lqq, e.lqt = qty, t
end

--- Estimated units leaving the AH per day over the last `days` measured days; nil without data.
function P.EstimatedDaily(e, days, now)
    if not (e and e.out) then return nil end
    local sum, n = 0, 0
    for _, k in ipairs(ns.Util.DayKeys(days or 7, now)) do
        local v = e.out[k]
        if v then sum, n = sum + v, n + 1 end
    end
    return n > 0 and sum / n or nil
end

--- Median of the daily lows over the given day keys; returns median, days with data.
function P.Median(e, dayKeys)
    local vals = {}
    for _, k in ipairs(dayKeys) do
        local v = e and e.d[k]
        if v then vals[#vals + 1] = v end
    end
    if #vals == 0 then return nil, 0 end
    table.sort(vals)
    local mid = math.floor((#vals + 1) / 2)
    local m = (#vals % 2 == 1) and vals[mid] or (vals[mid] + vals[mid + 1]) / 2
    return m, #vals
end

---------------------------------------------------------------------------
-- Potential flips: the current lowest price is well below the item's usual daily low (median of the
-- previous 14 days, today excluded), so buying now and relisting near the usual price clears a profit
-- after the AH cut. opts: cut, minMargin, minProfit (copper), maxAge (sec), minDays, now.
---------------------------------------------------------------------------
--- Junk (gray, Poor quality) items: these rarely sell on the AH, so the vendor is the better choice
--- even when an AH listing looks higher. nil if the item isn't loaded yet.
local junkCache = {}
function P.IsJunk(itemID)
    if not itemID then return nil end
    local v = junkCache[itemID]
    if v ~= nil then return v end
    local q
    if C_Item and C_Item.GetItemQualityByID then
        local ok, quality = pcall(C_Item.GetItemQualityByID, itemID)
        if ok then q = quality end
    end
    if q == nil and GetItemInfo then q = select(3, GetItemInfo(itemID)) end
    if q == nil then return nil end
    v = q == 0
    junkCache[itemID] = v
    return v
end

function P.FlipCandidates(opts)
    local now = opts.now or time()
    local past = ns.Util.DayKeys(15, now)
    past[#past] = nil -- drop today
    local out = {}
    for itemID, e in pairs(P.Store()) do
        if e.p and e.t and now - e.t <= (opts.maxAge or 3 * 3600) and not P.IsJunk(itemID) then
            local usual, n = P.Median(e, past)
            if usual and n >= (opts.minDays or 3) then
                local profit = usual * (1 - opts.cut) - e.p
                local margin = profit / e.p
                if profit >= (opts.minProfit or 1) and margin >= (opts.minMargin or 0.2) then
                    out[#out + 1] = {
                        id = itemID, e = e, now = e.p, usual = usual, profit = profit, margin = margin,
                        est = P.EstimatedDaily(e, 7, now), days = n,
                    }
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.profit > b.profit end)
    return out
end

--- Average of daily lows over the given day keys (nil if none recorded).
function P.Average(e, dayKeys)
    if not e then return nil end
    local sum, n = 0, 0
    for _, k in ipairs(dayKeys) do
        local v = e.d[k]
        if v then sum, n = sum + v, n + 1 end
    end
    return n > 0 and math.floor(sum / n + 0.5) or nil
end

--- Best guess at current market value: the latest price if fresh (< 24h), else the 7-day average.
--- Cached (it's asked for every item in your bags on each refresh) until prices change or a minute passes.
local marketCache, marketVersion, marketMinute = {}, nil, nil
local NONE = false
local function MarketUncached(itemID, now)
    local e = P.Get(itemID)
    if not e then return nil end
    if e.t and now - e.t < 86400 then return e.p end
    return P.Average(e, ns.Util.DayKeys(7, now)) or e.p
end
function P.Market(itemID, now)
    if not itemID then return nil end
    if now then return MarketUncached(itemID, now) end
    now = time()
    local minute = math.floor(now / 60)
    if marketVersion ~= P.version or marketMinute ~= minute then
        marketCache, marketVersion, marketMinute = {}, P.version, minute
    end
    local v = marketCache[itemID]
    if v == nil then
        v = MarketUncached(itemID, now)
        marketCache[itemID] = v == nil and NONE or v
        return v
    end
    if v == NONE then return nil end
    return v
end

---------------------------------------------------------------------------
-- Favorites: account-wide { [itemID] = { n = name, t = added } }
---------------------------------------------------------------------------
P.FAV_ICON = "|TInterface\\Common\\FavoritesIcon:14:14:0:0|t"

function P.Favorites()
    ns.db.favorites = ns.db.favorites or {}
    return ns.db.favorites
end

function P.IsFavorite(itemID)
    return itemID ~= nil and P.Favorites()[itemID] ~= nil
end

--- Toggle; returns the new state.
function P.ToggleFavorite(itemID, name)
    if not itemID then return false end
    local favs = P.Favorites()
    if favs[itemID] then
        favs[itemID] = nil
    else
        favs[itemID] = { n = name or ns.Util.ItemName(itemID), t = time() }
    end
    ns:Fire("FAVORITES_UPDATED", itemID)
    return favs[itemID] ~= nil
end

--- Drop daily history older than `days`, and items not seen within that window.
function P.Prune(days, now)
    now = now or time()
    local cutoff = ns.Util.DateKey(now - days * 86400)
    local removed = 0
    for _, store in pairs(ns.db.prices or {}) do
        for itemID, e in pairs(store) do
            for _, field in ipairs({ "d", "qd", "out" }) do
                for k in pairs(e[field] or {}) do
                    if k < cutoff then e[field][k] = nil end
                end
            end
            if (e.t or 0) < now - days * 86400 and not (ns.db.favorites and ns.db.favorites[itemID]) then
                store[itemID] = nil
                removed = removed + 1
            end
        end
    end
    return removed
end

ns:Register("READY", function()
    P.Prune(ns.db.settings.priceHistoryDays, time())
end)
