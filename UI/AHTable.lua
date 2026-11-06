-- Auction P/L tab: per-item flip results with cost basis.
local _, ns = ...
local UI, W, U, CB = ns.UI, ns.Widgets, ns.Util, ns.CostBasis

local GREEN, RED = { 0.38, 1, 0.38 }, { 1, 0.38, 0.38 }

local function Colored(v)
    local c = v >= 0 and GREEN or RED
    return U.FormatGoldShort(v), c[1], c[2], c[3]
end

function UI.CreateAHTable(parent)
    local f = CreateFrame("Frame", nil, parent)

    local columns = {
        { title = "Item", get = function(r)
            return r.name .. (r.f.noCost > 0 and " |cffff9933*|r" or "")
        end, sortValue = function(r) return r.name end },
        { title = "Sold", width = 40, align = "RIGHT", get = function(r) return r.f.sold end,
          sortValue = function(r) return r.f.sold end },
        -- Exact, from your own auctions: sold / (sold + expired + cancelled).
        { title = "Sell-through", width = 74, align = "RIGHT", get = function(r)
            local rate = CB.SellThrough(r.f)
            if not rate then return "-", 0.55, 0.58, 0.64 end
            local c = rate >= 0.7 and GREEN or (rate >= 0.4 and { 1, 0.78, 0.25 } or RED)
            return ("%.0f%%"):format(rate * 100), c[1], c[2], c[3]
        end, sortValue = function(r) return CB.SellThrough(r.f) or -1 end },
        { title = "Sells in", width = 56, align = "RIGHT", get = function(r)
            local _, _, avg = CB.SellThrough(r.f)
            return U.Duration(avg)
        end, sortValue = function(r) local _, _, avg = CB.SellThrough(r.f) return avg or math.huge end },
        { title = "Revenue", width = 66, align = "RIGHT", get = function(r) return U.FormatGoldShort(r.f.revenue) end,
          sortValue = function(r) return r.f.revenue end },
        { title = "Cost", width = 66, align = "RIGHT", get = function(r) return U.FormatGoldShort(r.f.cost) end,
          sortValue = function(r) return r.f.cost end },
        { title = "Deposits", width = 62, align = "RIGHT", get = function(r) return U.FormatGoldShort(r.deposits) end,
          sortValue = function(r) return r.deposits end },
        { title = "Profit", width = 72, align = "RIGHT", get = function(r) return Colored(r.profit) end,
          sortValue = function(r) return r.profit end },
        { title = "Margin", width = 52, align = "RIGHT", get = function(r)
            if r.f.revenue <= 0 then return "-" end
            local m = r.profit / r.f.revenue * 100
            local c = m >= 0 and GREEN or RED
            return ("%.0f%%"):format(m), c[1], c[2], c[3]
        end, sortValue = function(r) return r.f.revenue > 0 and r.profit / r.f.revenue or -math.huge end },
    }

    local list = W.List(f, columns, 20)
    list:SetPoint("TOPLEFT")
    list:SetPoint("BOTTOMRIGHT", 0, 48)
    list.sortCol, list.sortDesc = 7, true
    list.onEnter = function(row, r)
        local fl = r.f
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        if fl.i then pcall(GameTooltip.SetItemByID, GameTooltip, fl.i) else GameTooltip:AddLine(r.name) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Sold", fl.sold, 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Revenue", U.FormatMoney(fl.revenue), 1, 1, 1)
        GameTooltip:AddDoubleLine("AH cut", U.FormatMoney(-fl.cut), 1, 1, 1)
        GameTooltip:AddDoubleLine("Cost of goods", U.FormatMoney(-fl.cost), 1, 1, 1)
        GameTooltip:AddDoubleLine("Deposits paid", U.FormatMoney(-fl.depPaid), 1, 1, 1)
        GameTooltip:AddDoubleLine("Deposits refunded", U.FormatMoney(fl.depRefund), 1, 1, 1)
        GameTooltip:AddDoubleLine("Profit", U.FormatMoney(r.profit, true), 1, 0.82, 0)
        local rate, resolved, avg = CB.SellThrough(fl)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Posted", fl.posted or 0, 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Sold / expired / cancelled", ("%d / %d / %d"):format(fl.sold or 0, fl.expired or 0, fl.cancelled or 0), 1, 1, 1, 1, 1, 1)
        if rate then
            GameTooltip:AddDoubleLine("Sell-through", ("%.0f%% of %d resolved"):format(rate * 100, resolved), 1, 1, 1, 1, 1, 1)
        end
        if avg then GameTooltip:AddDoubleLine("Average time to sell", U.Duration(avg), 1, 1, 1, 1, 1, 1) end
        if fl.noCost > 0 then
            GameTooltip:AddLine(("%d sold with no known cost (looted/crafted): counted as free."):format(fl.noCost), 1, 0.6, 0.2, true)
        end
        GameTooltip:Show()
    end
    f.list = list

    f.footer = W.Text(f, "GameFontHighlight")
    f.footer:SetPoint("BOTTOMLEFT", 4, 22)
    f.inventory = W.Text(f, "GameFontHighlightSmall")
    f.inventory:SetPoint("BOTTOMLEFT", 4, 4)
    local note = W.Text(f, "GameFontDisableSmall", "|cffff9933*|r = some units sold had no recorded cost")
    note:SetPoint("BOTTOMRIGHT", -4, 4)

    function f:Refresh()
        local chars = ns:ScopeCharTables()
        local rows = {}
        local tRev, tCut, tCost, tDep, tProfit = 0, 0, 0, 0, 0
        for key, fl in pairs(CB.MergeFlips(chars)) do
            local profit = CB.Profit(fl)
            local deposits = fl.depPaid - fl.depRefund
            rows[#rows + 1] = {
                key = key, f = fl, profit = profit, deposits = deposits,
                name = fl.n or U.ItemName(fl.i) or tostring(key),
            }
            tRev, tCut, tCost, tDep, tProfit = tRev + fl.revenue, tCut + fl.cut, tCost + fl.cost, tDep + deposits, tProfit + profit
        end
        list:SetData(rows)
        self.footer:SetText(("Total  revenue %s   cut %s   cost %s   deposits %s   profit %s"):format(
            U.FormatGoldShort(tRev), U.FormatGoldShort(tCut), U.FormatGoldShort(tCost), U.FormatGoldShort(tDep),
            U.FormatMoney(tProfit, true)))

        local qty, value = 0, 0
        for _, c in ipairs(chars) do
            for itemID in pairs(c.lots) do
                local q, v = CB.Holdings(c, itemID)
                qty, value = qty + q, value + v
            end
        end
        local rate, measured = CB.CutRate(ns.db)
        self.inventory:SetText(("Unsold stock at cost: %d items, %s     |cff8c94a3AH cut: %s%s|r"):format(qty, U.FormatMoney(value),
            CB.CutLabel(rate), measured and " (measured from your sales)" or " (assumed, no sales yet)"))
    end

    return f
end
