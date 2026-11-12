-- Crafting profit calculator data: recipes captured from the profession window (account-wide), vendor buy
-- prices captured at merchants, and a per-recipe profit evaluation using AH prices and your measured AH cut.
--
-- db.recipes[profession][key] = { n = name, out = itemID?, qmin, qmax, icon, r = { { i = itemID, q = qty, n = name } },
--                                 chars = { [charKey] = true } }
-- db.vendorBuySeen[itemID] = { [vendorKey] = { p = per-unit price, t = when seen } } (latest price per vendor)
-- db.vendorBuy[itemID] = cheapest current per-unit price across those vendors (gold only; currency costs skipped)
local _, ns = ...
local CR = {}
ns.Crafting = CR

local function U() return ns.Util end
local function P() return ns.Prices end

---------------------------------------------------------------------------
-- Vendor buy prices (reagents like thread, flux and vials)
---------------------------------------------------------------------------
-- Each vendor's latest price replaces what that vendor charged before, so a price increase is picked up.
-- vendorBuy[itemID] is the cheapest of those current prices (what reagent costing and the API read).
-- A price saved before per-vendor tracking has no vendor; it stays until the item is seen at any vendor.
local function Cheapest(seen)
    local best
    for _, v in pairs(seen) do
        if not best or v.p < best then best = v.p end
    end
    return best
end

function CR.RecordVendorPrice(itemID, unitPrice, vendor, t)
    if not itemID or not unitPrice or unitPrice <= 0 then return end
    local db = ns.db
    db.vendorBuy = db.vendorBuy or {}
    db.vendorBuySeen = db.vendorBuySeen or {}
    local seen = db.vendorBuySeen[itemID]
    if not seen then
        seen = {}
        db.vendorBuySeen[itemID] = seen
    end
    seen[vendor or "?"] = { p = math.floor(unitPrice + 0.5), t = t or time() }
    db.vendorBuy[itemID] = Cheapest(seen) -- replaces an old vendor-less price
end

--- Prices this item has at each vendor it was seen at: { [vendorKey] = { p = copper, t = time } } or nil.
function CR.VendorPrices(itemID)
    return ns.db.vendorBuySeen and itemID and ns.db.vendorBuySeen[itemID] or nil
end

--- Key for the open merchant: its NPC ID from the GUID, or nil.
local function MerchantKey()
    local guid = UnitGUID and UnitGUID("npc")
    -- "Creature-0-<server>-<instance>-<zone>-<npcID>-<spawn>"
    local npcID = type(guid) == "string" and guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    return npcID and ("npc:" .. npcID) or nil
end

local function ScanMerchant()
    local vendor, now = MerchantKey(), time()
    local n = (GetMerchantNumItems and GetMerchantNumItems()) or 0
    for i = 1, n do
        local itemID = GetMerchantItemID and GetMerchantItemID(i)
        local price, stack, extended
        if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
            local ok, info = pcall(C_MerchantFrame.GetItemInfo, i)
            if ok and type(info) == "table" then price, stack, extended = info.price, info.stackCount, info.hasExtendedCost end
        end
        if not price and GetMerchantItemInfo then
            local ok, _, _, p, q, _, _, _, ext = pcall(GetMerchantItemInfo, i)
            if ok then price, stack, extended = p, q, ext end
        end
        if itemID and price and price > 0 and not extended then
            CR.RecordVendorPrice(itemID, price / math.max(1, stack or 1), vendor, now)
        end
    end
end

ns:On("MERCHANT_SHOW", function()
    if ns.db then pcall(ScanMerchant) end
end)
ns:On("MERCHANT_UPDATE", function()
    if ns.db then pcall(ScanMerchant) end
end)

---------------------------------------------------------------------------
-- Recipe capture
---------------------------------------------------------------------------
local function ProfessionName()
    if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
        local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        if ok and type(info) == "table" and info.professionName and info.professionName ~= "" then
            return info.professionName
        end
    end
    if GetTradeSkillLine then
        local ok, name = pcall(GetTradeSkillLine)
        if ok and name and name ~= "" and name ~= "UNKNOWN" then return name end
    end
end

local function Store(profession)
    ns.db.recipes = ns.db.recipes or {}
    ns.db.recipes[profession] = ns.db.recipes[profession] or {}
    return ns.db.recipes[profession]
end

local function SaveRecipe(profession, key, rec)
    local store = Store(profession)
    local old = store[key]
    rec.chars = (old and old.chars) or {}
    rec.chars[ns.charKey] = true
    store[key] = rec
end

-- Modern Professions API (C_TradeSkillUI recipe schematics).
local function ScanModern(profession)
    local ok, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
    if not ok or type(ids) ~= "table" then return 0 end
    local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
    local count = 0
    for _, recipeID in ipairs(ids) do
        local okI, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if okI and type(info) == "table" and info.learned and not info.isRecraft then
            local okS, sch = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
            if okS and type(sch) == "table" then
                local reagents = {}
                for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
                    -- Required basic reagents only (optional/finishing reagents vary per craft).
                    local isBasic = (basic == nil or slot.reagentType == basic) and slot.required ~= false
                    if isBasic and slot.reagents and slot.reagents[1] then
                        -- Several qualities of one reagent: keep all, the cheapest is used.
                        local alts = {}
                        for _, r in ipairs(slot.reagents) do
                            if r.itemID then alts[#alts + 1] = r.itemID end
                        end
                        if #alts > 0 then
                            reagents[#reagents + 1] = { i = alts[1], alt = #alts > 1 and alts or nil, q = slot.quantityRequired or 1 }
                        end
                    end
                end
                SaveRecipe(profession, recipeID, {
                    n = info.name, icon = info.icon, out = sch.outputItemID,
                    qmin = sch.quantityMin or 1, qmax = sch.quantityMax or sch.quantityMin or 1, r = reagents,
                })
                count = count + 1
            end
        end
    end
    return count
end

-- Older trade skill API (GetTradeSkillInfo / GetTradeSkillReagentInfo).
local function ScanLegacy(profession)
    local n = GetNumTradeSkills() or 0
    local count = 0
    for i = 1, n do
        local name, kind = GetTradeSkillInfo(i)
        if name and kind ~= "header" and kind ~= "subheader" then
            local link = GetTradeSkillItemLink and GetTradeSkillItemLink(i)
            local qmin, qmax = 1, 1
            if GetTradeSkillNumMade then qmin, qmax = GetTradeSkillNumMade(i) end
            local reagents = {}
            for j = 1, (GetTradeSkillNumReagents(i) or 0) do
                local rname, _, rcount = GetTradeSkillReagentInfo(i, j)
                local rlink = GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(i, j)
                local rid = U().ItemIDFromName(rlink) or U().ItemIDFromName(rname)
                reagents[#reagents + 1] = { i = rid, q = rcount or 1, n = rname }
            end
            SaveRecipe(profession, "n:" .. name, {
                n = name, out = U().ItemIDFromName(link), qmin = qmin or 1, qmax = qmax or qmin or 1, r = reagents,
            })
            count = count + 1
        end
    end
    return count
end

function CR.ScanOpenProfession()
    if not ns.db or not ns.charKey then return end
    local profession = ProfessionName()
    if not profession then return end
    local count = 0
    if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeSchematic then
        count = ScanModern(profession)
    elseif GetNumTradeSkills and GetTradeSkillInfo then
        count = ScanLegacy(profession)
    end
    if count > 0 then
        CR.lastScan = { profession = profession, count = count }
        ns:Fire("RECIPES_UPDATED", profession)
    end
end

-- The recipe list fills in over several events; debounce.
local pending = false
local function QueueScan()
    if pending then return end
    pending = true
    C_Timer.After(1, function()
        pending = false
        pcall(CR.ScanOpenProfession)
    end)
end
for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "TRADE_SKILL_UPDATE" }) do
    ns:On(event, QueueScan)
end

---------------------------------------------------------------------------
-- Crafted cost basis: when you craft, the reagents' recorded costs (FIFO lots) move into what you made,
-- so selling the crafted item shows the real profit. Which reagents were used comes from bag counts
-- before and after each craft (handles reagent qualities and optional reagents too).
---------------------------------------------------------------------------
local craft -- { outID, counts = { [itemID] = n }, outBefore, left, results = {} }

--- used = { [itemID] = n }, outputs = { { id, qty } }. Takes the reagents' cost lots and gives the outputs
--- lots carrying that cost. Reagents with no recorded cost add nothing; if none of them had a cost, the
--- outputs get no lot either (they stay "no recorded cost"). Returns total cost, units without a cost.
function CR.TransferCost(char, used, outputs, t)
    local CB = ns.CostBasis
    local cost, free = 0, 0
    for id, n in pairs(used) do
        local c, covered = CB.Consume(char, id, n)
        cost = cost + c
        free = free + (n - covered)
    end
    local total = 0
    for _, o in ipairs(outputs) do total = total + o.qty end
    if total <= 0 or (cost == 0 and free > 0) then return cost, free end
    for _, o in ipairs(outputs) do
        CB.AddLot(char, o.id, o.qty, cost / total, "craft", t)
    end
    return cost, free
end

local function BeginCraft(reagentIDs, outID, casts)
    local counts = {}
    for _, id in ipairs(reagentIDs) do counts[id] = CR.ItemCount(id) end
    if outID then counts[outID] = CR.ItemCount(outID) end
    craft = { outID = outID, counts = counts, outBefore = outID and counts[outID], left = casts or 1, results = {} }
end

local function SettleCraft()
    local c = craft
    if not c or #c.results == 0 or not ns.char then return end
    local used = {}
    for id, before in pairs(c.counts) do
        local now = CR.ItemCount(id)
        if id ~= c.outID and now < before then used[id] = before - now end
        c.counts[id] = now
    end
    local outputs = {}
    for _, r in ipairs(c.results) do
        if r.id and r.qty and r.qty > 0 then outputs[#outputs + 1] = { id = r.id, qty = r.qty } end
    end
    if #outputs == 0 and c.outID and c.outBefore then
        local gained = c.counts[c.outID] - c.outBefore
        if gained > 0 then outputs[1] = { id = c.outID, qty = gained } end
    end
    CR.TransferCost(ns.char, used, outputs, time())
    c.left = c.left - #c.results
    wipe(c.results)
    c.outBefore = c.outID and c.counts[c.outID] or nil
    if c.left <= 0 then craft = nil end
    ns:Fire("LEDGER_UPDATED")
end

local settleQueued = false
local function QueueSettle()
    if settleQueued then return end
    settleQueued = true
    C_Timer.After(1.5, function()
        settleQueued = false
        pcall(SettleCraft)
    end)
end

local function ModernSchematic(recipeID)
    if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic) then return nil end
    local ok, sch = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    if not ok or type(sch) ~= "table" then return nil end
    local ids = {}
    for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
        for _, r in ipairs(slot.reagents or {}) do
            if r.itemID then ids[#ids + 1] = r.itemID end
        end
    end
    return ids, sch.outputItemID
end

local function LinkID(link)
    return link and tonumber(link:match("item:(%d+)")) or nil
end

local function LegacySchematic(index)
    if not GetTradeSkillNumReagents then return nil end
    local ids = {}
    for j = 1, GetTradeSkillNumReagents(index) or 0 do
        local id = GetTradeSkillReagentItemLink and LinkID(GetTradeSkillReagentItemLink(index, j))
        if id then ids[#ids + 1] = id end
    end
    return ids, GetTradeSkillItemLink and LinkID(GetTradeSkillItemLink(index))
end

local resultEvent = false
local craftSpell -- spell/recipe ID to match when there's no result event

if C_TradeSkillUI and C_TradeSkillUI.CraftRecipe then
    hooksecurefunc(C_TradeSkillUI, "CraftRecipe", function(recipeID, casts)
        if InCombatLockdown() then return end
        local ids, outID = ModernSchematic(recipeID)
        if ids then
            BeginCraft(ids, outID, casts)
            craftSpell = recipeID
        end
    end)
end
U().HookGlobal("DoTradeSkill", function(index, casts)
    if InCombatLockdown() then return end
    local ids, outID = LegacySchematic(index)
    if ids then
        BeginCraft(ids, outID, casts)
        craftSpell = nil -- legacy: any successful cast of yours while crafting counts
    end
end)

resultEvent = ns:On("TRADE_SKILL_ITEM_CRAFTED_RESULT", function(_, result)
    if not craft or type(result) ~= "table" then return end
    craft.results[#craft.results + 1] = { id = result.itemID, qty = result.quantity }
    QueueSettle()
end)
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
    if resultEvent or unit ~= "player" or not craft or InCombatLockdown() then return end
    if craftSpell and spellID ~= craftSpell then return end
    craft.results[#craft.results + 1] = { id = craft.outID }
    QueueSettle()
end)

---------------------------------------------------------------------------
-- Evaluation
---------------------------------------------------------------------------
--- Cheapest known way to get one unit of a reagent: AH market or vendor. Returns unit, source ("AH"/"Vendor").
function CR.ReagentPrice(itemID)
    if not itemID then return nil end
    local ah = P().Market(itemID)
    local vendor = ns.db.vendorBuy and ns.db.vendorBuy[itemID]
    if ah and vendor then
        if vendor <= ah then return vendor, "Vendor" end
        return ah, "AH"
    end
    if vendor then return vendor, "Vendor" end
    if ah then return ah, "AH" end
    return nil
end

local function SellPrice(itemID)
    local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not (fn and itemID) then return nil end
    local ok, _, _, _, _, _, _, _, _, _, _, sellPrice = pcall(fn, itemID)
    return ok and sellPrice or nil
end

--- { cost, missing, made, value, valueSource, ahNet, vendorValue, profit, margin, est, parts = { ... } }
--- value = the better of selling the output on the AH (after the cut) or to a vendor.
function CR.Evaluate(rec, cut)
    local res = { cost = 0, missing = 0, parts = {} }
    for _, r in ipairs(rec.r or {}) do
        local id, unit, src = r.i, nil, nil
        for _, alt in ipairs(r.alt or { r.i }) do
            local u, s = CR.ReagentPrice(alt)
            if u and (not unit or u < unit) then id, unit, src = alt, u, s end
        end
        local part = { i = id, q = r.q, n = r.n, unit = unit, source = src, total = unit and unit * r.q or nil }
        res.parts[#res.parts + 1] = part
        if unit then res.cost = res.cost + part.total else res.missing = res.missing + 1 end
    end
    res.made = ((rec.qmin or 1) + (rec.qmax or rec.qmin or 1)) / 2
    if rec.out then
        local market = P().Market(rec.out)
        res.ahNet = market and market * (1 - cut) * res.made or nil
        local sp = SellPrice(rec.out)
        res.vendorValue = sp and sp > 0 and sp * res.made or nil
        if res.ahNet and (not res.vendorValue or res.ahNet >= res.vendorValue) then
            res.value, res.valueSource = res.ahNet, "AH"
        elseif res.vendorValue then
            res.value, res.valueSource = res.vendorValue, "Vendor"
        end
        res.est = P().EstimatedDaily(P().Get(rec.out), 7)
    end
    if res.value then
        res.profit = res.value - res.cost
        res.margin = res.cost > 0 and res.profit / res.cost or nil
    end
    return res
end

---------------------------------------------------------------------------
-- Shopping list (account-wide): db.shopping[itemID] = { need = total units, n = name, for = { [recipe] = crafts } }
-- "Have" is read live from bags + bank, so buying (or crafting) updates the list on its own.
---------------------------------------------------------------------------
function CR.Shopping()
    ns.db.shopping = ns.db.shopping or {}
    return ns.db.shopping
end

function CR.ItemCount(itemID)
    if C_Item and C_Item.GetItemCount then
        local ok, n = pcall(C_Item.GetItemCount, itemID, true, false, true)
        if ok and n then return n end
    end
    if GetItemCount then
        local ok, n = pcall(GetItemCount, itemID, true)
        if ok and n then return n end
    end
    return 0
end

--- Add the reagents for `crafts` crafts of a recipe (cheapest quality where there's a choice).
function CR.AddToShopping(rec, crafts, cut)
    crafts = math.max(1, math.floor(crafts or 1))
    local res = CR.Evaluate(rec, cut or 0.05)
    local list = CR.Shopping()
    for _, part in ipairs(res.parts) do
        if part.i then
            local e = list[part.i] or { need = 0, recipes = {} }
            e.need = e.need + part.q * crafts
            e.n = e.n or part.n or U().ItemName(part.i)
            e.recipes = e.recipes or {}
            e.recipes[rec.n or "?"] = (e.recipes[rec.n or "?"] or 0) + crafts
            list[part.i] = e
        end
    end
    ns:Fire("SHOPPING_UPDATED")
    return #res.parts
end

function CR.RemoveShopping(itemID)
    CR.Shopping()[itemID] = nil
    ns:Fire("SHOPPING_UPDATED")
end

--- Clear everything, or only items you already have enough of.
function CR.ClearShopping(doneOnly)
    local list = CR.Shopping()
    for itemID, e in pairs(list) do
        if not doneOnly or CR.ItemCount(itemID) >= e.need then list[itemID] = nil end
    end
    ns:Fire("SHOPPING_UPDATED")
end

--- Rows { id, n, need, have, remaining, unit, source, cost, recipes } plus the total cost still to buy.
function CR.ShoppingRows()
    local rows, total, unpriced = {}, 0, 0
    for itemID, e in pairs(CR.Shopping()) do
        local have = CR.ItemCount(itemID)
        local remaining = math.max(0, e.need - have)
        local unit, source = CR.ReagentPrice(itemID)
        local cost = unit and unit * remaining or nil
        if cost then total = total + cost elseif remaining > 0 then unpriced = unpriced + 1 end
        local alts = ns.Inventory and ns.Inventory.AltCount(itemID) or 0
        rows[#rows + 1] = {
            id = itemID, n = e.n or U().ItemName(itemID), need = e.need, have = have, remaining = remaining,
            unit = unit, source = source, cost = cost, recipes = e.recipes, alts = alts,
        }
    end
    return rows, total, unpriced
end

--- Professions with stored recipes, sorted.
function CR.Professions()
    local out = {}
    for name in pairs(ns.db.recipes or {}) do out[#out + 1] = name end
    table.sort(out)
    return out
end
