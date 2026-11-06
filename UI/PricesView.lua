-- Prices tab: searchable AH price database with a price-over-time chart for the selected item.
local _, ns = ...
local UI, W, U, P = ns.UI, ns.Widgets, ns.Util, ns.Prices
local T = W.Theme

local GREEN, RED, GOLD = { 0.38, 1, 0.38 }, { 1, 0.38, 0.38 }, { 1, 0.78, 0.25 }
local function Cut() return ns.CostBasis.CutRate(ns.db) end

--- Vendor sell price (copper), cached on the row once the client has the item info. 0 = can't be vendored.
local function VendorPrice(row)
    if row.vendor == nil then
        local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        if fn then
            local ok, _, _, _, _, _, _, _, _, _, _, sellPrice = pcall(fn, row.id)
            if ok and sellPrice then row.vendor = sellPrice end
        end
    end
    return row.vendor
end

--- What selling one on the AH nets (after the cut) minus what a vendor pays; nil without a vendor price.
local function VendorDiff(row)
    local v = VendorPrice(row)
    if not v or v <= 0 then return nil end
    return math.floor(row.e.p * (1 - Cut()) + 0.5) - v
end

local function ItemLabel(row)
    if not row.name then row.name = row.e.n or U.ItemName(row.id) end
    return row.name or ("item:" .. row.id)
end

function UI.CreatePricesView(parent)
    local f = CreateFrame("Frame", nil, parent)

    f.search = W.EditBox(f, 240, false, "Search items...")
    f.search:SetPoint("TOPLEFT")
    f.search:HookScript("OnTextChanged", function(_, user)
        if user then
            f.dirty = true
            f:Refresh()
        end
    end)

    f.favOnly = W.Check(f, "Favorites only", function()
        f.dirty = true
        f:Refresh()
    end)
    f.favOnly:SetPoint("LEFT", f.search, "RIGHT", 14, 0)

    f.openBtn = W.Button(f, "Open in AH", 92, function()
        if not f.selected then return end
        if not UI:OpenInAH(f.selected) then ns:Print("open the auction house first, then click Open in AH") end
    end, true)
    f.openBtn:SetPoint("TOPRIGHT")
    f.starBtn = W.Button(f, P.FAV_ICON .. " Favorite", 92, function()
        if not f.selected then return end
        local row = f.selectedRow
        P.ToggleFavorite(f.selected, row and ItemLabel(row))
        f.dirty = true
        f:Refresh()
    end)
    f.starBtn:SetPoint("RIGHT", f.openBtn, "LEFT", -6, 0)

    f.countFS = W.Text(f, "body")
    f.countFS:SetPoint("LEFT", f.favOnly.label, "RIGHT", 14, 0)
    f.countFS:SetPoint("RIGHT", f.starBtn, "LEFT", -10, 0)
    f.countFS:SetJustifyH("LEFT")
    f.countFS:SetWordWrap(false)

    local columns = {
        { title = "Item", get = function(r)
            return (P.IsFavorite(r.id) and (P.FAV_ICON .. " ") or "") .. ItemLabel(r)
        end, sortValue = function(r) return ItemLabel(r):lower() end },
        { title = "Lowest", width = 92, align = "RIGHT", get = function(r) return U.FormatMoney(r.e.p) end,
          sortValue = function(r) return r.e.p end },
        { title = "7-day avg", width = 90, align = "RIGHT", get = function(r)
            return r.avg and U.FormatGoldShort(r.avg) or "-"
        end, sortValue = function(r) return r.avg or 0 end },
        { title = "vs avg", width = 60, align = "RIGHT", get = function(r)
            if not r.avg or r.avg == 0 then return "-" end
            local pct = (r.e.p - r.avg) / r.avg * 100
            local c = pct <= 0 and GREEN or RED
            return ("%+.0f%%"):format(pct), c[1], c[2], c[3]
        end, sortValue = function(r) return r.avg and r.avg > 0 and (r.e.p - r.avg) / r.avg or 0 end },
        { title = "vs vendor", width = 86, align = "RIGHT", get = function(r)
            if P.IsJunk(r.id) and VendorPrice(r) then return "Vendor (junk)", GOLD[1], GOLD[2], GOLD[3] end
            local diff = VendorDiff(r)
            if not diff then return "-", T.muted[1], T.muted[2], T.muted[3] end
            if diff == 0 then return "same", T.muted[1], T.muted[2], T.muted[3] end
            local c = diff > 0 and GREEN or GOLD
            return (diff > 0 and "AH +" or "Vendor +") .. U.FormatGoldShort(math.abs(diff)), c[1], c[2], c[3]
        end, sortValue = function(r) return VendorDiff(r) or -math.huge end },
        -- ESTIMATE: drops in listed quantity between complete counts (includes expirations/cancellations).
        { title = "Est./day", width = 62, align = "RIGHT", get = function(r)
            local v = U.PerDay(P.EstimatedDaily(r.e, 7))
            if not v then return "-", T.muted[1], T.muted[2], T.muted[3] end
            return v, T.muted[1], T.muted[2], T.muted[3]
        end, sortValue = function(r) return P.EstimatedDaily(r.e, 7) or -1 end },
        { title = "Listed", width = 50, align = "RIGHT", get = function(r) return r.e.q or "-" end,
          sortValue = function(r) return r.e.q or 0 end },
        { title = "Seen", width = 64, align = "RIGHT", get = function(r)
            return U.Ago(r.e.t), T.muted[1], T.muted[2], T.muted[3]
        end, sortValue = function(r) return r.e.t or 0 end },
    }
    local list = W.List(f, columns, 20)
    list:SetPoint("TOPLEFT", 0, -36)
    list:SetPoint("BOTTOMRIGHT", 0, 222)
    list.sortCol, list.sortDesc = 6, true
    list.empty:SetText("No prices yet. Open the auction house and browse, or run a full scan.")
    list.onEnter = function(row, r)
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        if not pcall(GameTooltip.SetItemByID, GameTooltip, r.id) then GameTooltip:AddLine(ItemLabel(r)) end
        local est = P.EstimatedDaily(r.e, 7)
        if est then
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("Market activity (estimate)", U.PerDay(est), 1, 0.82, 0, 1, 1, 1)
            GameTooltip:AddLine("Drop in listed quantity between looks. Includes expired and cancelled auctions, so it's not exact sales.", 0.6, 0.63, 0.68, true)
        end
        local diff = VendorDiff(r)
        if diff then
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("AH after " .. ns.CostBasis.CutLabel(Cut()) .. " cut",
                U.FormatMoney(math.floor(r.e.p * (1 - Cut()) + 0.5)), 1, 0.82, 0, 1, 1, 1)
            GameTooltip:AddDoubleLine("Vendor", U.FormatMoney(r.vendor), 1, 0.82, 0, 1, 1, 1)
        end
        GameTooltip:Show()
    end
    list.onClick = function(r)
        f.selectedRow = r
        f.selected = r.id
        f.history:SetItem(r.id)
    end
    list.isSelected = function(r) return r.id == f.selected end
    f.list = list

    f.history = UI.CreatePriceChart(f)
    f.history:SetPoint("BOTTOMLEFT")
    f.history:SetPoint("BOTTOMRIGHT")
    f.history:SetHeight(210)

    ns:Register("PRICES_UPDATED", function() f.dirty = true end)
    f.dirty = true

    function f:Refresh()
        if not self.dirty then
            list:Refresh()
            return
        end
        self.dirty = false
        local query = (self.search:GetText() or ""):lower()
        local week = U.DayKeys(7)
        local rows, total = {}, 0
        local selectedRow
        for id, e in pairs(P.Store()) do
            total = total + 1
            local r = { id = id, e = e }
            local favOk = not self.favOnly:GetChecked() or P.IsFavorite(id)
            if favOk and (query == "" or ItemLabel(r):lower():find(query, 1, true)) then
                r.avg = P.Average(e, week)
                rows[#rows + 1] = r
                if id == self.selected then selectedRow = r end
            end
        end
        list:SetData(rows)
        self.selectedRow = selectedRow
        self.history:SetItem(selectedRow and selectedRow.id)
        local ready, left = ns.AHScan.FullScanReady()
        local last = ns.db.lastFullScan
        self.countFS:SetText(("%d of %d items   |cff8c94a3last full scan: %s%s|r"):format(#rows, total,
            last and U.Ago(last) or "never", ready and "" or (" (next in %dm)"):format(math.ceil(left / 60))))
    end

    return f
end
