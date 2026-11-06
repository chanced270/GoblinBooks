-- Public, read-only API for companion addons (e.g. GoblinTrades).
--
--   GoblinBooksAPI.version                      -> 1
--   GoblinBooksAPI.IsReady()                    -> true once saved variables are loaded
--   GoblinBooksAPI.GetMarketPrice(itemID)       -> copper per unit (recent AH lowest or 7-day avg) or nil
--   GoblinBooksAPI.GetVendorSellPrice(itemID)   -> copper per unit a vendor pays, or nil
--   GoblinBooksAPI.GetVendorBuyPrice(itemID)    -> cheapest merchant price seen, or nil
--   GoblinBooksAPI.GetReagentPrice(itemID)      -> copper, "AH" | "Vendor"  (cheapest way to buy it)
--   GoblinBooksAPI.GetCutRate()                 -> AH cut (0..1), measured (bool)
--   GoblinBooksAPI.GetRecipe(recipeID)          -> saved recipe { n, out, qmin, qmax, r = { { i, q, alt? } } } or nil
--   GoblinBooksAPI.RegisterCallback(event, fn)  -> listen to an event (see below)
--
-- Events:
--   ITEM_SOLD(itemID, count, netCopper, channel, time, charKey)
--     channel "ah": an auction sale's money was collected; net = sale price - AH cut (deposit refund excluded)
--     channel "vendor": items sold to a merchant; net = gold received
local _, ns = ...

local API = { version = 1 }
local listeners = {}

function API.IsReady()
    return ns.db ~= nil
end

function API.GetMarketPrice(itemID)
    if not ns.db or not itemID then return nil end
    return ns.Prices.Market(itemID)
end

function API.GetVendorSellPrice(itemID)
    if not itemID then return nil end
    local sell
    if C_Item and C_Item.GetItemInfo then
        local ok, _, _, _, _, _, _, _, _, _, _, price = pcall(C_Item.GetItemInfo, itemID)
        if ok then sell = price end
    end
    if sell == nil and GetItemInfo then
        sell = select(11, GetItemInfo(itemID))
    end
    if sell and sell > 0 then return sell end
    return nil
end

function API.GetVendorBuyPrice(itemID)
    return ns.db and ns.db.vendorBuy and itemID and ns.db.vendorBuy[itemID] or nil
end

function API.GetReagentPrice(itemID)
    if not ns.db then return nil end
    return ns.Crafting.ReagentPrice(itemID)
end

function API.GetCutRate()
    if not ns.db then return ns.CostBasis.DEFAULT_CUT, false end
    return ns.CostBasis.CutRate(ns.db)
end

function API.GetRecipe(recipeID)
    if not ns.db or not ns.db.recipes or not recipeID then return nil end
    for _, store in pairs(ns.db.recipes) do
        if store[recipeID] then return store[recipeID] end
    end
    return nil
end

function API.RegisterCallback(event, fn)
    if type(event) ~= "string" or type(fn) ~= "function" then return false end
    listeners[event] = listeners[event] or {}
    table.insert(listeners[event], fn)
    return true
end

-- Forward internal events to outside listeners. Their errors must never break GoblinBooks.
local function Forward(event)
    ns:Register(event, function(...)
        for _, fn in ipairs(listeners[event] or {}) do
            local ok, err = pcall(fn, ...)
            if not ok and ns.db and ns.db.settings.debug then ns:Print("API listener error: " .. tostring(err)) end
        end
    end)
end
Forward("ITEM_SOLD")

GoblinBooksAPI = API
