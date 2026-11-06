-- AH panel "Flips" page: items whose current lowest price is well below their usual daily low, so buying
-- now and relisting near the usual price should clear a profit after the AH cut. Clicking one opens it on
-- the Buy tab with live listings. Everything here comes from saved price history: an estimate, not advice.
local _, ns = ...
local UI, W, U, P, CB = ns.UI, ns.Widgets, ns.Util, ns.Prices, ns.CostBasis
local T = W.Theme

local MARGINS = { { key = 0.1, label = "10%" }, { key = 0.2, label = "20%" }, { key = 0.35, label = "35%" }, { key = 0.5, label = "50%" } }
local MAX_AGE = 3 * 3600 -- only prices seen in the last 3 hours count as "current"
local MIN_PROFIT = 100   -- at least 1s per item after the cut
local GREEN = { 0.38, 1, 0.38 }

local function Name(r)
    if not r.name then r.name = r.e.n or U.ItemName(r.id) end
    return r.name or ("item:" .. r.id)
end

function UI.CreateAHFlips(parent, setStatus, openItem)
    local f = CreateFrame("Frame", nil, parent)
    f.minMargin = 0.2

    local label = W.Text(f, "label", "MIN MARGIN")
    label:SetPoint("TOPLEFT", 0, -7)
    f.marginSeg = W.Segmented(f, MARGINS, function(v)
        f.minMargin = v
        f:Refresh()
    end, 46)
    f.marginSeg:SetPoint("LEFT", label, "RIGHT", 8, 0)
    f.marginSeg:SetValue(f.minMargin)
    f.countFS = W.Text(f, "mutedSm")
    f.countFS:SetPoint("LEFT", f.marginSeg, "RIGHT", 12, 0)
    f.countFS:SetPoint("RIGHT")
    f.countFS:SetJustifyH("LEFT")
    f.countFS:SetWordWrap(false)

    local list = W.List(f, {
        { title = "Item", get = function(r)
            return (P.IsFavorite(r.id) and (P.FAV_ICON .. " ") or "") .. Name(r)
        end, sortValue = function(r) return Name(r):lower() end },
        { title = "Now", width = 60, align = "RIGHT", get = function(r) return U.FormatGoldShort(r.now) end,
          sortValue = function(r) return r.now end },
        { title = "Usual", width = 60, align = "RIGHT", get = function(r) return U.FormatGoldShort(r.usual) end,
          sortValue = function(r) return r.usual end },
        { title = "Profit/ea", width = 66, align = "RIGHT", get = function(r)
            return U.FormatGoldShort(r.profit), GREEN[1], GREEN[2], GREEN[3]
        end, sortValue = function(r) return r.profit end },
        { title = "Margin", width = 52, align = "RIGHT", get = function(r) return ("%.0f%%"):format(r.margin * 100) end,
          sortValue = function(r) return r.margin end },
        -- ESTIMATE of demand: units leaving the AH per day (includes expirations/cancellations).
        { title = "Est./day", width = 62, align = "RIGHT", get = function(r)
            local v = U.PerDay(r.est)
            return v or "-", T.muted[1], T.muted[2], T.muted[3]
        end, sortValue = function(r) return r.est or -1 end },
    }, 20)
    list:SetPoint("TOPLEFT", 0, -34)
    list:SetPoint("BOTTOMRIGHT", 0, 40)
    list.sortCol, list.sortDesc = 4, true
    list.empty:SetText("No flips right now. Prices need a few days of history and a recent Scan or search.")
    list.onClick = function(r) openItem(r.id) end
    list.onEnter = function(row, r)
        local cut = CB.CutRate(ns.db)
        GameTooltip:SetOwner(row, "ANCHOR_LEFT")
        if not pcall(GameTooltip.SetItemByID, GameTooltip, r.id) then GameTooltip:AddLine(Name(r)) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Lowest now", U.FormatMoney(r.now), 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddDoubleLine(("Usual low (median, %d days)"):format(r.days), U.FormatMoney(r.usual), 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddDoubleLine(("Relist at usual, after %s cut"):format(CB.CutLabel(cut)),
            U.FormatMoney(r.usual * (1 - cut)), 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddDoubleLine("Profit per item", U.FormatMoney(r.profit, true), 1, 0.82, 0, 1, 1, 1)
        if r.est then
            GameTooltip:AddDoubleLine("Market activity (estimate)", U.PerDay(r.est), 1, 0.82, 0, 1, 1, 1)
        end
        GameTooltip:AddDoubleLine("Price seen", U.Ago(r.e.t), 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to open on the Buy tab and check how many are actually this cheap.", 0.6, 0.63, 0.68, true)
        GameTooltip:Show()
    end
    f.list = list

    local note = W.Text(f, "mutedSm",
        "Estimates from your saved prices, so they're only as fresh as your last Scan or search. Deposits are refunded on a sale but lost if it doesn't sell.")
    note:SetPoint("BOTTOMLEFT", 2, 4)
    note:SetPoint("RIGHT", -2, 0)
    note:SetJustifyH("LEFT")

    function f:Refresh()
        self.marginSeg:SetValue(self.minMargin)
        local rows = P.FlipCandidates({
            cut = CB.CutRate(ns.db), minMargin = self.minMargin, minProfit = MIN_PROFIT, maxAge = MAX_AGE, minDays = 3,
        })
        list:SetData(rows)
        local last = ns.db.lastFullScan
        self.countFS:SetText(("%d candidates   |cff8c94a3prices from the last 3h; last full scan %s|r"):format(
            #rows, last and U.Ago(last) or "never"))
    end

    local pending = false
    ns:Register("PRICES_UPDATED", function()
        if pending or not f:IsVisible() then return end
        pending = true
        C_Timer.After(1, function()
            pending = false
            if f:IsVisible() then f:Refresh() end
        end)
    end)
    f:SetScript("OnShow", function() f:Refresh() end)
    return f
end
