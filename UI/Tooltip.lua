-- Item tooltips: vendor sell price for every item, plus AH price data for tradeable items.
local _, ns = ...
local P, U = ns.Prices, ns.Util

local BIND_ON_PICKUP, BIND_QUEST = 1, 4
local GREY = "|cff8c94a3"

local function ItemInfo(itemID)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getInfo then return nil end
    local ok, _, _, _, _, _, _, _, _, _, _, sellPrice, _, _, bindType = pcall(getInfo, itemID)
    if not ok then return nil end
    return sellPrice, bindType
end

-- Stack size of the hovered item instance (bags), when the tooltip carries its GUID.
local function StackCount(data)
    if not (data and data.guid and C_Item and C_Item.GetItemLocation and C_Item.GetStackCount) then return 1 end
    local ok, loc = pcall(C_Item.GetItemLocation, data.guid)
    if not ok or not loc then return 1 end
    local ok2, count = pcall(C_Item.GetStackCount, loc)
    return ok2 and count or 1
end

local function IsBoundInstance(data)
    if not (data and data.guid and C_Item and C_Item.GetItemLocation and C_Item.IsBound) then return false end
    local ok, loc = pcall(C_Item.GetItemLocation, data.guid)
    if not ok or not loc then return false end
    local ok2, bound = pcall(C_Item.IsBound, loc)
    return ok2 and bound or false
end

-- All units of the item in your bags (incl. reagent bag), not counting the bank.
local function BagCount(itemID)
    if C_Item and C_Item.GetItemCount then
        local ok, n = pcall(C_Item.GetItemCount, itemID, false, false, true)
        if ok and n then return n end
    end
    if GetItemCount then
        local ok, n = pcall(GetItemCount, itemID)
        if ok and n then return n end
    end
    return 0
end

local function MoneyWithStack(unit, count)
    if count > 1 then
        return ("%s  %s(x%d: %s)|r"):format(U.FormatMoney(unit), GREY, count, U.FormatMoney(unit * count))
    end
    return U.FormatMoney(unit)
end

local function AddLines(tt, data)
    if not ns.db or not ns.db.settings.tooltipPrices then return end
    local itemID = data and data.id
    if not itemID then return end
    local sellPrice, bindType = ItemInfo(itemID)
    local count = StackCount(data)
    -- Shift: price every stack of this item in your bags, not just the hovered one.
    local bagTotal = BagCount(itemID)
    local allStacks = IsShiftKeyDown() and bagTotal > count
    if allStacks then count = bagTotal end
    local e = P.Get(itemID)
    local tradeable = e ~= nil or (bindType ~= BIND_ON_PICKUP and bindType ~= BIND_QUEST and not IsBoundInstance(data))
    if not sellPrice and not tradeable then return end

    tt:AddLine(" ")
    if allStacks then
        tt:AddLine(("All %d in your bags"):format(count), 1, 0.78, 0.25)
    elseif bagTotal > count and data.guid then
        tt:AddLine(("Hold Shift for all %d in your bags"):format(bagTotal), 0.55, 0.58, 0.64)
    end
    -- What you and your alts own (bank counts are from the last bank visit).
    local owned = ns.Inventory and ns.Inventory.Owned(itemID)
    if owned and owned.total > 0 and (owned.mine.bank > 0 or owned.altTotal > 0 or owned.warband > 0) then
        tt:AddDoubleLine("Owned", ("%d  %s(bags %d, bank %d%s)|r"):format(owned.total, GREY, owned.mine.bags, owned.mine.bank,
            owned.warband > 0 and (", warband " .. owned.warband) or ""), 0.55, 0.58, 0.64, 1, 1, 1)
        if #owned.alts > 0 then
            local parts = {}
            for i, a in ipairs(owned.alts) do
                if i > 4 then parts[#parts + 1] = "..." break end
                parts[#parts + 1] = ("%s %d"):format(a.name, a.bags + a.bank)
            end
            tt:AddDoubleLine("Alts", table.concat(parts, ", "), 0.55, 0.58, 0.64, 1, 1, 1)
        end
    end
    if sellPrice and sellPrice > 0 then
        tt:AddDoubleLine("Vendor", MoneyWithStack(sellPrice, count), 0.55, 0.58, 0.64, 1, 1, 1)
    elseif sellPrice == 0 then
        tt:AddDoubleLine("Vendor", GREY .. "cannot be sold|r", 0.55, 0.58, 0.64, 1, 1, 1)
    end
    if not tradeable then return end
    if P.IsJunk(itemID) and sellPrice and sellPrice > 0 then
        tt:AddDoubleLine("Junk", "|cffffc640sell to a vendor|r " .. GREY .. "(rarely sells on the AH)|r",
            0.55, 0.58, 0.64, 1, 1, 1)
        return
    end
    if e then
        local now = time()
        tt:AddDoubleLine("AH lowest", MoneyWithStack(e.p, count), 1, 0.78, 0.25, 1, 1, 1)
        local avg = P.Average(e, U.DayKeys(7, now))
        if avg and avg ~= e.p then
            tt:AddDoubleLine("AH 7-day avg", U.FormatMoney(avg), 0.55, 0.58, 0.64, 1, 1, 1)
        end
        tt:AddDoubleLine(" ", ("%sseen %s%s|r"):format(GREY, U.Ago(e.t, now), e.q and (", " .. e.q .. " listed") or ""))
        -- AH vs vendor, using what you'd actually receive from the AH (after its measured cut).
        if sellPrice and sellPrice > 0 then
            local ahNet = math.floor(e.p * (1 - ns.CostBasis.CutRate(ns.db)) + 0.5)
            local diff = (ahNet - sellPrice) * count
            local each = count > 1 and (" %s(%s each)|r"):format(GREY, U.FormatMoney(math.abs(ahNet - sellPrice))) or ""
            if diff > 0 then
                tt:AddDoubleLine("AH vs vendor", ("|cff60ff60AH +%s|r%s"):format(U.FormatMoney(diff), each), 0.55, 0.58, 0.64, 1, 1, 1)
            elseif diff < 0 then
                tt:AddDoubleLine("AH vs vendor", ("|cffffc640Vendor +%s|r%s"):format(U.FormatMoney(-diff), each), 0.55, 0.58, 0.64, 1, 1, 1)
            else
                tt:AddDoubleLine("AH vs vendor", GREY .. "same|r", 0.55, 0.58, 0.64, 1, 1, 1)
            end
        end
    else
        tt:AddDoubleLine("AH lowest", GREY .. "no data yet|r", 1, 0.78, 0.25, 1, 1, 1)
    end
end

--- Is the tooltip showing an item? Only those get our lines, so only those need a redraw.
local function ShowsItem(tt)
    if not tt.GetItem then return false end
    local ok, _, link = pcall(tt.GetItem, tt)
    return ok and link ~= nil
end

-- Redraw the hovered item tooltip when Shift is pressed or released (out of combat only). Never a unit
-- tooltip: rebuilding one from addon code hits the client's restricted unit data ("secret values") and
-- Blizzard's tooltip code errors.
ns:On("MODIFIER_STATE_CHANGED", function(_, key)
    if InCombatLockdown() or not (key == "LSHIFT" or key == "RSHIFT") then return end
    if GameTooltip:IsShown() and GameTooltip.RefreshData and ShowsItem(GameTooltip) then
        pcall(GameTooltip.RefreshData, GameTooltip)
    end
end)

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
        -- Stay out of combat entirely: action button tooltips run through here, and addon code in that
        -- path during combat can taint Blizzard's action bar handling.
        if InCombatLockdown() then return end
        if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
        local ok, err = pcall(AddLines, tt, data)
        if not ok and ns.db and ns.db.settings.debug then ns:Print("tooltip error: " .. tostring(err)) end
    end)
end
