-- Watch list: items you're keeping an eye on, each with a price limit: your max price for it, or a share of
-- its usual price (median daily low of the previous 14 days). The Watchlist page shows the lowest price
-- seen next to it. Nothing searches in the background: prices come from your scans and searches.
--
-- db.watch[itemID] = { n = name, max = copper?, pct = 0..1? }
-- Fires "WATCHLIST_UPDATED".
local _, ns = ...
local WL = {}
ns.Watchlist = WL

local function P() return ns.Prices end
local function U() return ns.Util end

function WL.Watch() ns.db.watch = ns.db.watch or {} return ns.db.watch end

function WL.AddWatch(itemID, name)
    if not itemID then return end
    local w = WL.Watch()
    w[itemID] = w[itemID] or { n = name or U().ItemName(itemID) }
    ns:Fire("WATCHLIST_UPDATED")
end

function WL.RemoveWatch(itemID)
    WL.Watch()[itemID] = nil
    ns:Fire("WATCHLIST_UPDATED")
end

function WL.IsWatched(itemID) return itemID and WL.Watch()[itemID] ~= nil end

--- Usual price: median daily low of the previous 14 days (not today), else the 7-day average.
function WL.Usual(itemID, now)
    local e = P().Get(itemID)
    if not e then return nil end
    now = now or time()
    local past = U().DayKeys(15, now)
    past[#past] = nil
    local median = P().Median(e, past)
    if median then return median end
    return P().Average(e, U().DayKeys(7, now))
end

--- Your price limit per unit, and how it was set ("max" | "pct", with the share).
function WL.Threshold(itemID)
    local w = WL.Watch()[itemID]
    if w and w.max and w.max > 0 then return w.max, "max" end
    local usual = WL.Usual(itemID)
    if not usual then return nil end
    local pct = (w and w.pct) or ns.db.settings.dealsPct or 0.7
    return math.floor(usual * pct), "pct", pct
end

--- Watched item IDs, sorted.
function WL.Items()
    local out = {}
    for id in pairs(WL.Watch()) do out[#out + 1] = id end
    table.sort(out)
    return out
end
