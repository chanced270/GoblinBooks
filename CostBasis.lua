-- FIFO cost-basis lots and per-item auction house profit/loss ("flips").
local _, ns = ...
local CB = {}
ns.CostBasis = CB

local function Round(x) return math.floor((x or 0) + 0.5) end

local function FlipKey(itemID, name)
    return itemID or ("n:" .. (name or "?"))
end
CB.FlipKey = FlipKey

---------------------------------------------------------------------------
-- Daily AH results, for the profit-over-time chart:
--   char.ahDaily[day] = { s = sales after the cut, c = cost of what sold, dp = deposits paid,
--                         dr = deposits refunded, n = units sold, nc = units sold with no known cost,
--                         est = true when rebuilt from old ledger entries (cost from the item's average),
--                         x = sale gold from old entries with no item (several mails at once): no cost is
--                             known, so it's left out of profit, like the Auction P/L tab leaves it out }
-- Profit for a day = s - c - dp + dr (the same sum as CB.Profit, per day).
---------------------------------------------------------------------------
local DAY_FIELDS = { "s", "c", "dp", "dr", "n", "nc" }

local function AHDay(char, t)
    char.ahDaily = char.ahDaily or {}
    local key = ns.Util.DateKey(t or time())
    local d = char.ahDaily[key]
    if not d then
        d = { s = 0, c = 0, dp = 0, dr = 0, n = 0, nc = 0 }
        char.ahDaily[key] = d
    end
    return d
end

function CB.DayProfit(d)
    return (d.s or 0) - (d.c or 0) - (d.dp or 0) + (d.dr or 0)
end

--- Merged daily AH results across chars: { [dayKey] = day } (days with nothing are absent).
function CB.AHDaily(chars, dayKeys)
    local out = {}
    for _, key in ipairs(dayKeys) do
        local m
        for _, c in ipairs(chars) do
            local d = c.ahDaily and c.ahDaily[key]
            if d then
                m = m or { s = 0, c = 0, dp = 0, dr = 0, n = 0, nc = 0 }
                for _, k in ipairs(DAY_FIELDS) do m[k] = m[k] + (d[k] or 0) end
                if d.est then m.est = true end
                if d.x then m.x = (m.x or 0) + d.x end
            end
        end
        out[key] = m
    end
    return out
end

--- One-time rebuild of ahDaily from the raw ledger entries (kept 90 days). The cost of each sale isn't
--- known per day, so each item's recorded cost (and its count of units with no known cost) is spread over
--- its units sold; the days then add up to the Auction P/L tab's totals. Marked `est`.
function CB.BackfillDaily(char)
    if char.ahDaily and next(char.ahDaily) then return end
    char.ahDaily = {}
    local perUnit = {} -- [itemID] = { cost per unit sold, share of units with no known cost }
    for key, f in pairs(char.flips or {}) do
        local sold = f.sold or 0
        if sold > 0 then perUnit[key] = { (f.cost or 0) / sold, (f.noCost or 0) / sold } end
    end
    for _, e in ipairs(char.entries or {}) do
        if e.c == "ah_sale" and not e.i then
            local d = AHDay(char, e.t)
            d.x, d.est = (d.x or 0) + e.a, true
        elseif e.c == "ah_sale" then
            local d = AHDay(char, e.t)
            local units = e.q or 1
            d.s, d.n, d.est = d.s + e.a, d.n + units, true
            local pu = perUnit[e.i]
            if pu then
                d.c, d.nc = d.c + Round(pu[1] * units), d.nc + Round(pu[2] * units)
            else
                d.nc = d.nc + units
            end
        elseif e.c == "ah_deposit" then
            local d = AHDay(char, e.t)
            d.est = true
            if e.a < 0 then d.dp = d.dp - e.a else d.dr = d.dr + e.a end
        end
    end
end

--- Record an acquired lot of `qty` items at `unitCost` copper each.
function CB.AddLot(char, itemID, qty, unitCost, src, t)
    if not itemID or not qty or qty <= 0 then return end
    local lots = char.lots[itemID]
    if not lots then
        lots = {}
        char.lots[itemID] = lots
    end
    lots[#lots + 1] = { q = qty, u = unitCost or 0, t = t, src = src }
end

--- Consume `qty` items FIFO. Returns total cost (copper) and how many were covered by lots.
function CB.Consume(char, itemID, qty)
    local lots = itemID and char.lots[itemID]
    local need, cost = qty, 0
    while need > 0 and lots and lots[1] do
        local lot = lots[1]
        local take = math.min(need, lot.q)
        cost = cost + take * lot.u
        lot.q = lot.q - take
        need = need - take
        if lot.q <= 0 then table.remove(lots, 1) end
    end
    if lots and #lots == 0 then char.lots[itemID] = nil end
    return Round(cost), qty - need
end

--- Quantity and total cost of items still held per lots.
function CB.Holdings(char, itemID)
    local qty, value = 0, 0
    for _, lot in ipairs(char.lots[itemID] or {}) do
        qty = qty + lot.q
        value = value + lot.q * lot.u
    end
    return qty, Round(value)
end

function CB.GetFlip(char, itemID, name)
    local key = FlipKey(itemID, name)
    local f = char.flips[key]
    if not f then
        f = { sold = 0, revenue = 0, cut = 0, cost = 0, depPaid = 0, depRefund = 0, noCost = 0, i = itemID, n = name,
              posted = 0, expired = 0, cancelled = 0, sellTime = 0, sellTimeN = 0 }
        char.flips[key] = f
    end
    if name and not f.n then f.n = name end
    return f
end

---------------------------------------------------------------------------
-- Sell-through (exact, from your own auctions): posts are queued FIFO per item; a sale, expiry or
-- cancellation resolves the oldest posted units. Sales also give the time it took to sell.
---------------------------------------------------------------------------
function CB.RecordPost(char, itemID, name, qty, t)
    if not itemID or not qty or qty <= 0 then return end
    local f = CB.GetFlip(char, itemID, name)
    f.posted = (f.posted or 0) + qty
    char.postQueue = char.postQueue or {}
    local q = char.postQueue[itemID] or {}
    char.postQueue[itemID] = q
    q[#q + 1] = { q = qty, t = t }
end

--- Resolve `qty` posted units (oldest first). Returns their summed age in seconds at `t`, and how many
--- units had a known post time.
local function ResolvePosted(char, itemID, qty, t)
    local q = char.postQueue and itemID and char.postQueue[itemID]
    local age, known = 0, 0
    while q and qty > 0 and #q > 0 do
        local p = q[1]
        local take = math.min(p.q, qty)
        if t then age = age + math.max(0, t - p.t) * take end
        known = known + take
        qty = qty - take
        p.q = p.q - take
        if p.q <= 0 then table.remove(q, 1) end
    end
    if q and #q == 0 then char.postQueue[itemID] = nil end
    return age, known
end

--- Units that came back unsold. kind = "expired" | "cancelled".
function CB.RecordUnsold(char, itemID, name, qty, kind)
    if not qty or qty <= 0 then return end
    local f = CB.GetFlip(char, itemID, name)
    f[kind] = (f[kind] or 0) + qty
    ResolvePosted(char, itemID, qty, nil)
end

--- Sold share of resolved auctions (sold / (sold + expired + cancelled)), resolved count, avg seconds to sell.
function CB.SellThrough(f)
    local resolved = (f.sold or 0) + (f.expired or 0) + (f.cancelled or 0)
    local rate = resolved > 0 and (f.sold or 0) / resolved or nil
    local avg = (f.sellTimeN or 0) > 0 and f.sellTime / f.sellTimeN or nil
    return rate, resolved, avg
end

--- An auction sold. bid = sale price, cut = AH consignment, refund = deposit returned with the sale.
--- soldAt = when it sold (from the mail), for time-to-sell.
function CB.RecordSale(char, itemID, name, count, bid, cut, refund, t, soldAt)
    count = count or 1
    local f = CB.GetFlip(char, itemID, name)
    local age, known = ResolvePosted(char, itemID, count, soldAt or t)
    if known > 0 then
        f.sellTime = (f.sellTime or 0) + age
        f.sellTimeN = (f.sellTimeN or 0) + known
    end
    local cost, covered = 0, 0
    if itemID then cost, covered = CB.Consume(char, itemID, count) end
    f.sold = f.sold + count
    f.revenue = f.revenue + (bid or 0)
    f.cut = f.cut + (cut or 0)
    f.cost = f.cost + cost
    f.depRefund = f.depRefund + (refund or 0)
    f.noCost = f.noCost + (count - covered)
    f.last = t
    local d = AHDay(char, t)
    d.s = d.s + (bid or 0) - (cut or 0)
    d.c, d.dr = d.c + cost, d.dr + (refund or 0)
    d.n, d.nc = d.n + count, d.nc + (count - covered)
    CB.cutCache = nil
    return f, cost
end

--- A posting deposit was paid.
function CB.RecordDeposit(char, itemID, name, amount, t)
    local f = CB.GetFlip(char, itemID, name)
    f.depPaid = f.depPaid + (amount or 0)
    f.last = t
    local d = AHDay(char, t)
    d.dp = d.dp + (amount or 0)
    return f
end

---------------------------------------------------------------------------
-- AH cut rate, measured from sale invoices (mail "consignment" vs sale price) across all characters.
---------------------------------------------------------------------------
CB.DEFAULT_CUT = 0.05
CB.MAX_SAMPLES = 200

--- Log one sale invoice (account-wide) so the cut can be checked per sale, not just on average.
function CB.RecordCutSample(db, bid, cut, t)
    if not bid or bid <= 0 then return end
    db.cutSamples = db.cutSamples or {}
    local list = db.cutSamples
    list[#list + 1] = { b = bid, c = cut or 0, t = t }
    while #list > CB.MAX_SAMPLES do table.remove(list, 1) end
    CB.cutCache = nil
end

--- { rate, revenue, cut, sold, samples, lo, hi } — rate is nil when nothing has sold yet.
function CB.CutStats(db)
    local rev, cut, sold = 0, 0, 0
    for _, c in pairs(db.chars or {}) do
        for _, f in pairs(c.flips or {}) do
            if (f.revenue or 0) > 0 then
                rev, cut, sold = rev + f.revenue, cut + (f.cut or 0), sold + (f.sold or 0)
            end
        end
    end
    local lo, hi
    local samples = db.cutSamples or {}
    for _, s in ipairs(samples) do
        local r = s.c / s.b
        if not lo or r < lo then lo = r end
        if not hi or r > hi then hi = r end
    end
    return { rate = rev > 0 and cut / rev or nil, revenue = rev, cut = cut, sold = sold, samples = #samples, lo = lo, hi = hi }
end

--- The cut rate to use for estimates: measured when any sale has been recorded, else the 5% default.
--- Returns rate, measured (bool). Cached until the next recorded sale.
function CB.CutRate(db)
    if not CB.cutCache then
        local s = CB.CutStats(db)
        CB.cutCache = s.rate and { s.rate, true } or { CB.DEFAULT_CUT, false }
    end
    return CB.cutCache[1], CB.cutCache[2]
end

--- "5%" / "4.9%" for labels.
function CB.CutLabel(rate)
    local pct = rate * 100
    if math.abs(pct - math.floor(pct + 0.5)) < 0.05 then return ("%d%%"):format(math.floor(pct + 0.5)) end
    return ("%.1f%%"):format(pct)
end

function CB.Profit(f)
    return f.revenue - f.cut - f.cost - f.depPaid + f.depRefund
end

--- Merge flips from several chars into one table keyed by flip key.
function CB.MergeFlips(chars)
    local out = {}
    for _, c in ipairs(chars) do
        for key, f in pairs(c.flips) do
            local m = out[key]
            if not m then
                m = { sold = 0, revenue = 0, cut = 0, cost = 0, depPaid = 0, depRefund = 0, noCost = 0, i = f.i, n = f.n, last = 0,
                      posted = 0, expired = 0, cancelled = 0, sellTime = 0, sellTimeN = 0 }
                out[key] = m
            end
            for _, field in ipairs({ "sold", "revenue", "cut", "cost", "depPaid", "depRefund", "noCost",
                                     "posted", "expired", "cancelled", "sellTime", "sellTimeN" }) do
                m[field] = m[field] + (f[field] or 0)
            end
            m.n = m.n or f.n
            if (f.last or 0) > m.last then m.last = f.last end
        end
    end
    return out
end
