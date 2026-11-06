-- Crafting tab: profit per craft for your known recipes. Reagent cost = cheapest of AH market and vendor
-- price; value = the better of selling the result on the AH (after your measured cut) or to a vendor.
-- Click a reagent to open it on the AH Buy tab (while the auction house is open).
-- Shopping list view: reagents for the crafts you've queued, what you still need, and the cheapest source.
local _, ns = ...
local UI, W, U, P, CB, CR = ns.UI, ns.Widgets, ns.Util, ns.Prices, ns.CostBasis, ns.Crafting
local T = W.Theme

local GREEN, RED = { 0.38, 1, 0.38 }, { 1, 0.38, 0.38 }
local REAGENT_ROWS = 8

local function Money(v) return v and U.FormatGoldShort(v) or "?" end

local function ItemName(id, fallback)
    return (id and U.ItemName(id)) or fallback or (id and ("item:" .. id)) or "?"
end

function UI.CreateCraftingView(parent)
    local f = CreateFrame("Frame", nil, parent)

    f.profDrop = W.Dropdown(f, 170, function(key)
        f.profession = key
        f.selected = nil
        f:Refresh()
    end)
    f.profDrop.prefix = "|cff8c94a3Profession:|r  "
    f.profDrop:SetPoint("TOPLEFT")

    f.search = W.EditBox(f, 170, false, "Search recipes...")
    f.search:SetPoint("LEFT", f.profDrop, "RIGHT", 8, 0)
    f.search:HookScript("OnTextChanged", function(_, user) if user then f:Refresh() end end)

    f.profitable = W.Check(f, "Profitable only", function() f:Refresh() end)
    f.profitable:SetPoint("LEFT", f.search, "RIGHT", 14, 0)

    f.modeSeg = W.Segmented(f, {
        { key = "recipes", label = "Recipes" },
        { key = "shopping", label = "Shopping list" },
    }, function(key) f:SetMode(key) end, 92)
    f.modeSeg:SetPoint("TOPRIGHT")

    f.countFS = W.Text(f, "mutedSm")
    f.countFS:SetPoint("LEFT", f.profitable.label, "RIGHT", 14, 0)
    f.countFS:SetPoint("RIGHT", f.modeSeg, "LEFT", -10, 0)
    f.countFS:SetJustifyH("LEFT")
    f.countFS:SetWordWrap(false)

    local list = W.List(f, {
        { title = "Recipe", get = function(r)
            local icon = r.rec.icon and ("|T%s:16:16:0:0|t  "):format(r.rec.icon) or ""
            local made = r.res.made and r.res.made > 1 and ("  |cff8c94a3x%s|r"):format(r.res.made) or ""
            return icon .. (r.rec.n or "?") .. made
        end, sortValue = function(r) return (r.rec.n or ""):lower() end },
        { title = "Cost", width = 66, align = "RIGHT", get = function(r)
            if r.res.missing > 0 then return Money(r.res.cost) .. "+?", 1, 0.6, 0.2 end
            return Money(r.res.cost)
        end, sortValue = function(r) return r.res.cost end },
        { title = "Sells for", width = 70, align = "RIGHT", get = function(r)
            if not r.res.value then return "?", T.muted[1], T.muted[2], T.muted[3] end
            return Money(r.res.value) .. (r.res.valueSource == "Vendor" and " |cff8c94a3v|r" or "")
        end, sortValue = function(r) return r.res.value or -1 end },
        { title = "Profit", width = 70, align = "RIGHT", get = function(r)
            local p = r.res.profit
            if not p then return "?", T.muted[1], T.muted[2], T.muted[3] end
            local c = (p >= 0 and r.res.missing == 0) and GREEN or (p < 0 and RED or { 1, 0.6, 0.2 })
            return (p >= 0 and "+" or "") .. U.FormatGoldShort(p), c[1], c[2], c[3]
        end, sortValue = function(r) return r.res.profit or -math.huge end },
        { title = "Margin", width = 54, align = "RIGHT", get = function(r)
            if not r.res.margin then return "-", T.muted[1], T.muted[2], T.muted[3] end
            return ("%.0f%%"):format(r.res.margin * 100)
        end, sortValue = function(r) return r.res.margin or -math.huge end },
        -- ESTIMATE of demand for the crafted item (includes expirations/cancellations).
        { title = "Est./day", width = 62, align = "RIGHT", get = function(r)
            return U.PerDay(r.res.est) or "-", T.muted[1], T.muted[2], T.muted[3]
        end, sortValue = function(r) return r.res.est or -1 end },
    }, 20)
    list:SetPoint("TOPLEFT", 0, -36)
    list:SetPoint("BOTTOMRIGHT", 0, 206)
    list.sortCol, list.sortDesc = 4, true
    list.empty:SetText("Open a profession window in game to load your recipes.")
    list.onClick = function(r)
        f.selected = r.key
        f:ShowDetail(r)
    end
    list.isSelected = function(r) return r.key == f.selected end
    list.onEnter = function(row, r)
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        if r.rec.out then pcall(GameTooltip.SetItemByID, GameTooltip, r.rec.out) else GameTooltip:AddLine(r.rec.n or "?") end
        GameTooltip:Show()
    end
    f.list = list

    -- Detail panel: reagent breakdown + totals.
    local d = W.Panel(f)
    d:SetPoint("BOTTOMLEFT")
    d:SetPoint("BOTTOMRIGHT")
    d:SetHeight(196)
    f.detail = d
    d.title = W.Text(d, "heading", "Select a recipe")
    d.title:SetPoint("TOPLEFT", 14, -12)
    d.title:SetPoint("RIGHT", -14, 0)
    d.title:SetJustifyH("LEFT")
    d.title:SetWordWrap(false)
    local rh = W.Text(d, "label", "REAGENTS (CLICK ONE TO OPEN IT ON THE AH BUY TAB)")
    rh:SetPoint("TOPLEFT", 14, -36)
    d.rows = {}
    for i = 1, REAGENT_ROWS do
        local b = CreateFrame("Button", nil, d)
        b:SetHeight(17)
        b:SetPoint("TOPLEFT", 10, -50 - (i - 1) * 17)
        b:SetPoint("RIGHT", d, "CENTER", 60, 0)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        W.SetColor(hl, T.hover)
        b.name = W.Text(b, "body")
        b.name:SetPoint("LEFT", 4, 0)
        b.name:SetPoint("RIGHT", -150, 0)
        b.name:SetJustifyH("LEFT")
        b.name:SetWordWrap(false)
        b.price = W.Text(b, "body")
        b.price:SetPoint("RIGHT", -4, 0)
        b:SetScript("OnClick", function(s)
            if s.itemID and not UI:OpenInAH(s.itemID) then
                ns:Print("open the auction house first to buy reagents from here")
            end
        end)
        b:SetScript("OnEnter", function(s)
            if not s.itemID then return end
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            pcall(GameTooltip.SetItemByID, GameTooltip, s.itemID)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        d.rows[i] = b
    end
    d.addBtn = W.Button(d, "Add to shopping list", 150, function()
        if not f.selectedRec then return end
        local crafts = tonumber(d.crafts:GetText()) or 1
        CR.AddToShopping(f.selectedRec, crafts, CB.CutRate(ns.db))
        ns:Print(("added reagents for %d x %s to the shopping list"):format(crafts, f.selectedRec.n or "?"))
    end, true)
    d.addBtn:SetPoint("BOTTOMRIGHT", -12, 10)
    d.crafts = W.EditBox(d, 46, true)
    d.crafts:SetMaxLetters(4)
    d.crafts:SetText("1")
    d.crafts:SetPoint("RIGHT", d.addBtn, "LEFT", -8, 0)
    local craftsLabel = W.Text(d, "label", "CRAFTS")
    craftsLabel:SetPoint("RIGHT", d.crafts, "LEFT", -8, 0)
    d.addBtn:Disable()

    d.summary = W.Text(d, "body", "")
    d.summary:SetPoint("TOPLEFT", d, "TOP", 80, -50)
    d.summary:SetPoint("RIGHT", -14, 0)
    d.summary:SetJustifyH("LEFT")
    d.summary:SetSpacing(4)

    function f:ShowDetail(r)
        for _, b in ipairs(d.rows) do b:Hide() end
        f.selectedRec = r and r.rec
        d.addBtn:SetEnabled(r ~= nil and #(r.rec.r or {}) > 0)
        if not r then
            d.title:SetText("Select a recipe")
            d.summary:SetText("")
            return
        end
        local rec, res = r.rec, r.res
        local out = rec.out and ItemName(rec.out) or "no item (e.g. an enchant)"
        d.title:SetText(("%s  |cff8c94a3makes %s x%s|r"):format(rec.n or "?", out, res.made or 1))
        for i, part in ipairs(res.parts) do
            local b = d.rows[i]
            if not b then break end
            b.itemID = part.i
            b.name:SetText(("%s  |cff8c94a3x%d|r"):format(ItemName(part.i, part.n), part.q))
            if part.unit then
                b.price:SetText(("%s each |cff8c94a3(%s)|r  = %s"):format(U.FormatGoldShort(part.unit), part.source, U.FormatGoldShort(part.total)))
            else
                b.price:SetText("|cffff9933no price yet|r")
            end
            b:Show()
        end
        local cut = CB.CutRate(ns.db)
        local lines = {
            ("Reagents  %s%s"):format(U.FormatMoney(res.cost), res.missing > 0 and ("  |cffff9933+ %d unpriced|r"):format(res.missing) or ""),
            ("AH, after %s cut  %s"):format(CB.CutLabel(cut), res.ahNet and U.FormatMoney(res.ahNet) or "|cff8c94a3no AH price|r"),
            ("Vendor  %s"):format(res.vendorValue and U.FormatMoney(res.vendorValue) or "|cff8c94a3-|r"),
        }
        if res.profit then
            lines[#lines + 1] = ("Profit (%s)  %s"):format(res.valueSource == "Vendor" and "vendoring" or "on the AH",
                U.FormatMoney(res.profit, true))
        end
        if res.est then lines[#lines + 1] = ("|cff8c94a3Market est. %s (estimate)|r"):format(U.PerDay(res.est)) end
        if res.missing > 0 then
            lines[#lines + 1] = "|cff8c94a3Unpriced reagents: search them on the AH or visit a vendor that sells them.|r"
        end
        d.summary:SetText(table.concat(lines, "\n"))
    end

    function f:Refresh()
        local profs = CR.Professions()
        local opts = {}
        for _, name in ipairs(profs) do opts[#opts + 1] = { key = name, label = name } end
        self.profDrop:SetOptions(opts)
        if not self.profession or not (ns.db.recipes or {})[self.profession] then self.profession = profs[1] end
        self.profDrop:SetValue(self.profession)
        self.profDrop:SetEnabled(#profs > 0)
        if not self.profession then
            list:SetData({})
            self.countFS:SetText("")
            self:ShowDetail(nil)
            return
        end
        local cut = CB.CutRate(ns.db)
        local query = (self.search:GetText() or ""):lower()
        local rows, selectedRow, profitable = {}, nil, 0
        for key, rec in pairs(ns.db.recipes[self.profession]) do
            if query == "" or (rec.n or ""):lower():find(query, 1, true) then
                local res = CR.Evaluate(rec, cut)
                local good = res.profit and res.profit > 0 and res.missing == 0
                if good then profitable = profitable + 1 end
                if good or not self.profitable:GetChecked() then
                    local row = { key = key, rec = rec, res = res }
                    rows[#rows + 1] = row
                    if key == self.selected then selectedRow = row end
                end
            end
        end
        list:SetData(rows)
        self.countFS:SetText(("%d recipes, %d profitable   |cff8c94a3prices from your saved AH data and vendors|r"):format(#rows, profitable))
        self:ShowDetail(selectedRow)
    end

    -----------------------------------------------------------------------
    -- Shopping list view
    -----------------------------------------------------------------------
    local shop = CreateFrame("Frame", nil, f)
    shop:SetPoint("TOPLEFT", 0, -36)
    shop:SetPoint("BOTTOMRIGHT")
    shop:Hide()
    f.shop = shop

    local slist = W.List(shop, {
        { title = "Reagent", get = function(r)
            local done = r.remaining == 0 and "  |cff60ff60done|r" or ""
            return ItemName(r.id, r.n) .. done
        end, sortValue = function(r) return ItemName(r.id, r.n):lower() end },
        { title = "Need", width = 50, align = "RIGHT", get = function(r) return r.need end, sortValue = function(r) return r.need end },
        { title = "Have", width = 50, align = "RIGHT", get = function(r) return r.have end, sortValue = function(r) return r.have end },
        { title = "Alts", width = 44, align = "RIGHT", get = function(r)
            if (r.alts or 0) == 0 then return "-", T.muted[1], T.muted[2], T.muted[3] end
            return r.alts, 0.55, 0.8, 1
        end, sortValue = function(r) return r.alts or 0 end },
        { title = "Still need", width = 70, align = "RIGHT", get = function(r)
            if r.remaining == 0 then return "0", GREEN[1], GREEN[2], GREEN[3] end
            return r.remaining, 1, 0.78, 0.25
        end, sortValue = function(r) return r.remaining end },
        { title = "Best price", width = 110, align = "RIGHT", get = function(r)
            if not r.unit then return "|cffff9933no price yet|r" end
            return ("%s |cff8c94a3(%s)|r"):format(U.FormatGoldShort(r.unit), r.source)
        end, sortValue = function(r) return r.unit or math.huge end },
        { title = "Cost", width = 66, align = "RIGHT", get = function(r)
            if r.remaining == 0 then return "-", T.muted[1], T.muted[2], T.muted[3] end
            return r.cost and U.FormatGoldShort(r.cost) or "?"
        end, sortValue = function(r) return r.cost or -1 end },
    }, 20)
    slist:SetPoint("TOPLEFT")
    slist:SetPoint("BOTTOMRIGHT", 0, 40)
    slist.sortCol, slist.sortDesc = 4, true
    slist.empty:SetText("Your shopping list is empty. Pick a recipe and click Add to shopping list.")
    slist.onClick = function(r) f.shopSelected = r.id end
    slist.isSelected = function(r) return r.id == f.shopSelected end
    slist.onEnter = function(row, r)
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetItemByID, GameTooltip, r.id)
        GameTooltip:AddLine(" ")
        for name, crafts in pairs(r.recipes or {}) do
            GameTooltip:AddDoubleLine(name, "x" .. crafts, 0.8, 0.8, 0.8, 1, 1, 1)
        end
        if r.source == "Vendor" then GameTooltip:AddLine("Cheapest from a vendor.", 0.55, 0.8, 1) end
        if (r.alts or 0) > 0 and r.remaining > 0 then
            local _, o = ns.Inventory.AltCount(r.id)
            GameTooltip:AddLine(("Alts hold %d: mail them over."):format(r.alts), 0.55, 0.8, 1)
            for _, a in ipairs(o.alts) do GameTooltip:AddDoubleLine("  " .. a.name, a.bags + a.bank, 0.8, 0.8, 0.8, 1, 1, 1) end
            if o.warband > 0 then GameTooltip:AddDoubleLine("  Warband bank", o.warband, 0.8, 0.8, 0.8, 1, 1, 1) end
        end
        GameTooltip:AddLine("Select it, then Buy on AH (auction house must be open).", 0.6, 0.63, 0.68, true)
        GameTooltip:Show()
    end
    f.slist = slist

    shop.totalFS = W.Text(shop, "body")
    shop.totalFS:SetPoint("BOTTOMLEFT", 4, 12)
    shop.buyBtn = W.Button(shop, "Buy on AH", 96, function()
        local id = f.shopSelected
        if not id then return end
        local e = CR.Shopping()[id]
        local remaining = e and math.max(0, e.need - CR.ItemCount(id)) or nil
        if not UI:OpenInAH(id, remaining) then ns:Print("open the auction house first, then click Buy on AH") end
    end, true)
    shop.buyBtn:SetPoint("BOTTOMRIGHT", 0, 6)
    shop.removeBtn = W.Button(shop, "Remove", 76, function()
        if f.shopSelected then CR.RemoveShopping(f.shopSelected) f.shopSelected = nil end
    end)
    shop.removeBtn:SetPoint("RIGHT", shop.buyBtn, "LEFT", -6, 0)
    shop.clearDoneBtn = W.Button(shop, "Clear done", 86, function() CR.ClearShopping(true) end)
    shop.clearDoneBtn:SetPoint("RIGHT", shop.removeBtn, "LEFT", -6, 0)
    shop.clearAllBtn = W.Button(shop, "Clear all", 76, function() CR.ClearShopping(false) end)
    shop.clearAllBtn:SetPoint("RIGHT", shop.clearDoneBtn, "LEFT", -6, 0)

    function f:RefreshShopping()
        local rows, total, unpriced = CR.ShoppingRows()
        slist:SetData(rows)
        local left = 0
        for _, r in ipairs(rows) do if r.remaining > 0 then left = left + 1 end end
        shop.totalFS:SetText(("%d items still to get, about %s%s"):format(left, U.FormatMoney(total),
            unpriced > 0 and ("  |cffff9933+ %d unpriced|r"):format(unpriced) or ""))
        self.countFS:SetText(("%d on the list   |cff8c94a3have = this character's bags + bank; alts = other characters + warband bank|r"):format(#rows))
    end

    function f:SetMode(key)
        self.mode = key
        self.modeSeg:SetValue(key)
        local recipes = key == "recipes"
        for _, w in ipairs({ self.profDrop, self.search, self.profitable, list, d }) do w:SetShown(recipes) end
        shop:SetShown(not recipes)
        self.countFS:ClearAllPoints()
        if recipes then
            self.countFS:SetPoint("LEFT", self.profitable.label, "RIGHT", 14, 0)
        else
            self.countFS:SetPoint("LEFT", 0, 0)
            self.countFS:SetPoint("TOP", self.modeSeg, "TOP", 0, -6)
        end
        self.countFS:SetPoint("RIGHT", self.modeSeg, "LEFT", -10, 0)
        if recipes then self:Refresh() else self:RefreshShopping() end
    end

    ns:Register("SHOPPING_UPDATED", function() if shop:IsVisible() then f:RefreshShopping() end end)
    ns:On("BAG_UPDATE_DELAYED", function() if shop:IsVisible() then f:RefreshShopping() end end)

    ns:Register("RECIPES_UPDATED", function(profession)
        if f:IsVisible() and f.mode ~= "shopping" then
            f.profession = f.profession or profession
            f:Refresh()
        end
    end)
    f.mode = "recipes"
    f.modeSeg:SetValue("recipes")
    f.Refresh0 = f.Refresh
    -- The main window calls Refresh(): route it to whichever view is showing.
    function f:Refresh()
        if self.mode == "shopping" then return self:RefreshShopping() end
        return self:Refresh0()
    end
    return f
end
