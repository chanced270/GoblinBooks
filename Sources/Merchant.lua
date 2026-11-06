-- Vendors: sales, purchases (which also create cost-basis lots), buybacks and repairs.
local _, ns = ...
local M, U, CB = ns.Money, ns.Util, ns.CostBasis

M:RegisterContext("merchant", function(delta)
    if delta < 0 and InRepairMode and InRepairMode() then return "repair" end
    return delta > 0 and "vendor_sell" or "vendor_buy"
end)

ns:On("MERCHANT_SHOW", function() M:Enter("merchant") end)
ns:On("MERCHANT_CLOSED", function() M:Leave("merchant", 1.5) end)

U.HookGlobal("RepairAllItems", function(useGuildBank)
    if not useGuildBank then
        M:Expect({ cat = "repair", s = "Repair all", sign = -1, ttl = 3 })
    end
end)

local function MerchantStackSize(index)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local ok, info = pcall(C_MerchantFrame.GetItemInfo, index)
        if ok and type(info) == "table" then return info.stackCount or 1, info.name end
    end
    if GetMerchantItemInfo then
        local ok, name, _, _, stack = pcall(GetMerchantItemInfo, index)
        if ok then return stack or 1, name end
    end
    return 1
end

U.HookGlobal("BuyMerchantItem", function(index, quantity)
    local itemID = GetMerchantItemID and GetMerchantItemID(index)
    local stack, name = MerchantStackSize(index)
    local qty = quantity or stack or 1
    M:Expect({
        cat = "vendor_buy", sign = -1, ttl = 3, i = itemID, q = qty, n = name,
        onRecord = function(_, delta)
            if itemID and qty > 0 then
                CB.AddLot(ns.char, itemID, qty, -delta / qty, "vendor", time())
            end
        end,
    })
end)

-- Selling to a merchant: right-clicking a bag item while the merchant is open. We note which item it
-- was so the gold can be tied to it (ITEM_SOLD for companion addons). The hook runs for every bag item
-- use, so it returns immediately in combat or away from a merchant.
local merchantOpen = false
ns:On("MERCHANT_SHOW", function() merchantOpen = true end)
ns:On("MERCHANT_CLOSED", function() merchantOpen = false end)

local function BagItem(bag, slot)
    if not (C_Container and C_Container.GetContainerItemInfo) then return nil end
    local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
    if not ok or type(info) ~= "table" or not info.itemID then return nil end
    return info.itemID, info.stackCount or 1, info.itemName
end

local function SellPrice(itemID)
    local api = GoblinBooksAPI
    return api and api.GetVendorSellPrice(itemID)
end

U.HookMethod(C_Container, "UseContainerItem", function(bag, slot)
    if not merchantOpen or InCombatLockdown() then return end
    if MerchantFrame and MerchantFrame.IsShown and not MerchantFrame:IsShown() then return end
    local itemID, count, name = BagItem(bag, slot)
    if not itemID then return end
    local unit = SellPrice(itemID)
    if not unit then return end -- no vendor value: not a sale
    M:Expect({
        cat = "vendor_sell", sign = 1, amount = unit * count, ttl = 3, i = itemID, q = count, n = name,
        onRecord = function(_, delta)
            ns:Fire("ITEM_SOLD", itemID, count, delta, "vendor", time(), ns.charKey)
        end,
    })
end)

U.HookGlobal("BuybackItem", function()
    M:Expect({ cat = "vendor_buy", s = "Buyback", sign = -1, ttl = 3 })
end)
