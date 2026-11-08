-- Formatting, date keys, and safe hooking helpers.
local _, ns = ...
local U = {}
ns.Util = U

local floor, abs = math.floor, math.abs

local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"

function U.Round(x)
    return floor((x or 0) + 0.5)
end

function U.CommaNumber(n)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    local s = tostring(n)
    local k
    repeat
        s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    until k == 0
    return s
end

--- Full money string with coin icons, e.g. "1,234g 5s 6c". colorize => green/red by sign.
function U.FormatMoney(copper, colorize)
    copper = U.Round(copper or 0)
    local neg = copper < 0
    local v = abs(copper)
    local g, s, c = floor(v / 10000), floor(v / 100) % 100, v % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = U.CommaNumber(g) .. GOLD end
    if s > 0 then parts[#parts + 1] = s .. SILVER end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. COPPER end
    local text = table.concat(parts, " ")
    if neg then text = "-" .. text end
    if colorize and copper ~= 0 then
        text = (neg and "|cffff6060" or "|cff60ff60") .. text .. "|r"
    end
    return text
end

--- Compact gold string for axes and tiles, e.g. "1.2k g", "350g", "45s".
function U.FormatGoldShort(copper)
    copper = copper or 0
    local sign = copper < 0 and "-" or ""
    local g = abs(copper) / 10000
    if g >= 1e6 then return ("%s%.1fM g"):format(sign, g / 1e6) end
    if g >= 1e4 then return ("%s%.0fk g"):format(sign, g / 1e3) end
    if g >= 1e3 then return ("%s%.1fk g"):format(sign, g / 1e3) end
    if g >= 1 then return ("%s%.0fg"):format(sign, g) end
    if abs(copper) >= 100 then return ("%s%ds"):format(sign, floor(abs(copper) / 100)) end
    return ("%s%dc"):format(sign, abs(copper))
end

--- Plain CSV-safe gold value ("123.4567").
function U.GoldDecimal(copper)
    return ("%.4f"):format((copper or 0) / 10000)
end

local lastDateT, lastDateKey
function U.DateKey(t)
    if t and t == lastDateT then return lastDateKey end -- full scans record thousands of prices at one time
    lastDateT, lastDateKey = t, date("%Y-%m-%d", t)
    return lastDateKey
end

--- Day keys for the last n days (oldest first), ending with today. Called per item in hot paths (prices,
--- net worth), so results are cached for the current second; callers get their own copy.
local dayKeyCache, dayKeyAt = {}, nil
function U.DayKeys(n, now)
    now = now or time()
    if now ~= dayKeyAt then dayKeyCache, dayKeyAt = {}, now end
    local cached = dayKeyCache[n]
    if not cached then
        local tbl = date("*t", now)
        tbl.hour, tbl.min, tbl.sec = 12, 0, 0 -- noon avoids DST edge cases
        local noon = time(tbl)
        cached = {}
        for i = n - 1, 0, -1 do
            cached[#cached + 1] = date("%Y-%m-%d", noon - i * 86400)
        end
        dayKeyCache[n] = cached
    end
    local keys = {}
    for i = 1, #cached do keys[i] = cached[i] end
    return keys
end

--- Relative age, e.g. "just now", "12m ago", "3h ago", "5d ago".
function U.Ago(t, now)
    if not t then return "never" end
    local s = (now or time()) - t
    if s < 60 then return "just now" end
    if s < 3600 then return ("%dm ago"):format(floor(s / 60)) end
    if s < 86400 then return ("%dh ago"):format(floor(s / 3600)) end
    return ("%dd ago"):format(floor(s / 86400))
end

--- Compact duration, e.g. "45m", "6h", "2.5d".
function U.Duration(sec)
    if not sec then return "-" end
    if sec < 3600 then return ("%dm"):format(math.max(1, floor(sec / 60))) end
    if sec < 86400 then return ("%dh"):format(floor(sec / 3600 + 0.5)) end
    return ("%.1fd"):format(sec / 86400)
end

--- Market-activity estimate label, e.g. "~120/day".
function U.PerDay(n)
    if not n then return nil end
    if n >= 10 then return ("~%d/day"):format(floor(n + 0.5)) end
    return ("~%.1f/day"):format(n)
end

function U.ShortDate(key)
    return key:sub(6, 7) .. "/" .. key:sub(9, 10)
end

--- hooksecurefunc on a global function if it exists.
function U.HookGlobal(name, fn)
    if type(_G[name]) == "function" then
        hooksecurefunc(name, fn)
        return true
    end
    return false
end

--- hooksecurefunc on a table method if it exists.
function U.HookMethod(tbl, method, fn)
    if type(tbl) == "table" and type(tbl[method]) == "function" then
        hooksecurefunc(tbl, method, fn)
        return true
    end
    return false
end

--- Best-effort item ID from a name or link.
function U.ItemIDFromName(nameOrLink)
    if not nameOrLink then return nil end
    local id = tonumber(tostring(nameOrLink):match("item:(%d+)"))
    if id then return id end
    local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if getInstant then
        local ok, result = pcall(getInstant, nameOrLink)
        if ok then return result end
    end
    return nil
end

--- Price to list at, `undercut` copper below a competitor's unit price (0 = match it). Gear and other
--- non-stacking items can only be listed in whole silver: their price is rounded down to whole silver,
--- staying below the competitor, and is at least 1 silver.
function U.UndercutPrice(unit, undercut, wholeSilver)
    local price = math.max(1, unit - (undercut or 0))
    if wholeSilver then
        price = math.floor(price / 100) * 100
        if price < 100 then price = 100 end
    end
    return price
end

function U.ItemName(itemID)
    if not itemID then return nil end
    local fn = (C_Item and C_Item.GetItemNameByID) or GetItemInfo
    if fn then
        local ok, name = pcall(fn, itemID)
        if ok then return name end
    end
    return nil
end
