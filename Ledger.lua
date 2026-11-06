-- Ledger storage: raw entries (pruned) + daily rollups (kept forever). Pure functions over char tables.
local _, ns = ...
local L = {}
ns.Ledger = L

local function U() return ns.Util end

--- Adjust the daily rollup for a category.
function L.AddDaily(char, t, cat, amount)
    local key = U().DateKey(t)
    local day = char.daily[key]
    if not day then
        day = {}
        char.daily[key] = day
    end
    local v = (day[cat] or 0) + amount
    if v == 0 then v = nil end
    day[cat] = v
end

--- Append an entry {t, a, c, s?, i?, q?, n?} and update rollups.
function L.Add(char, e)
    local list = char.entries
    list[#list + 1] = e
    L.AddDaily(char, e.t, e.c, e.a)
end

--- Move an existing entry to another category, keeping rollups consistent.
function L.Reclassify(char, e, newCat, sub, note)
    L.AddDaily(char, e.t, e.c, -e.a)
    e.c = newCat
    if sub then e.s = sub end
    if note then e.n = note end
    L.AddDaily(char, e.t, newCat, e.a)
end

--- Remove raw entries older than `days`. Entries are stored in time order. Returns the count removed.
function L.Prune(char, days, now)
    local cutoff = now - days * 86400
    local list = char.entries
    local first = 1
    while list[first] and list[first].t < cutoff do first = first + 1 end
    if first == 1 then return 0 end
    local kept = {}
    for i = first, #list do kept[#kept + 1] = list[i] end
    char.entries = kept
    return first - 1
end

--- Per-day totals: { [dayKey] = { [key] = amount } } where key = mapFn(cat) or cat.
--- filterFn(cat) may exclude categories.
function L.Daily(chars, dayKeys, mapFn, filterFn)
    local out = {}
    for _, dayKey in ipairs(dayKeys) do
        local agg = {}
        for _, c in ipairs(chars) do
            local d = c.daily[dayKey]
            if d then
                for cat, a in pairs(d) do
                    if not filterFn or filterFn(cat) then
                        local k = mapFn and mapFn(cat) or cat
                        agg[k] = (agg[k] or 0) + a
                    end
                end
            end
        end
        out[dayKey] = agg
    end
    return out
end

--- Totals across the given days: { [key] = amount }.
function L.Sum(chars, dayKeys, mapFn, filterFn)
    local total = {}
    for _, agg in pairs(L.Daily(chars, dayKeys, mapFn, filterFn)) do
        for k, a in pairs(agg) do total[k] = (total[k] or 0) + a end
    end
    return total
end

--- Net of a {key=amount} table.
function L.Net(tbl)
    local n = 0
    for _, a in pairs(tbl) do n = n + a end
    return n
end

--- Raw entries across scoped chars, newest first. scoped = { {key, char}, ... }.
function L.Entries(scoped, filterFn)
    local out = {}
    for _, sc in ipairs(scoped) do
        for _, e in ipairs(sc.char.entries) do
            if not filterFn or filterFn(e) then
                out[#out + 1] = { e = e, who = sc.key }
            end
        end
    end
    table.sort(out, function(a, b) return a.e.t > b.e.t end)
    return out
end
