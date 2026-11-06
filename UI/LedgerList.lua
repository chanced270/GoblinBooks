-- Ledger tab: every recorded gold change, newest first, filterable by source group.
local _, ns = ...
local UI, W, U, L, C = ns.UI, ns.Widgets, ns.Util, ns.Ledger, ns.Categories

local function CharName(key)
    return key and key:match("%-([^%-]+)$") or key
end

function UI.EntryDetail(e)
    local parts = {}
    local item = e.i and U.ItemName(e.i)
    if item then parts[#parts + 1] = item end
    if e.n and e.n ~= item then parts[#parts + 1] = e.n end
    if e.s then parts[#parts + 1] = e.s end
    if e.q and e.q > 1 then parts[#parts + 1] = "x" .. e.q end
    return table.concat(parts, " - ")
end

function UI.LedgerFilter()
    local group = UI.ledgerGroup
    if not group then return nil end
    return function(e) return C.Group(e.c) == group end
end

function UI.CreateLedgerList(parent)
    local f = CreateFrame("Frame", nil, parent)

    -- Filter dropdown: All + each source group.
    local options = { { key = "all", label = "All sources" } }
    for _, g in ipairs(C.groups) do options[#options + 1] = { key = g.key, label = g.label, color = g.color } end
    local filterBtn = W.Dropdown(f, 200, function(key)
        UI.ledgerGroup = key ~= "all" and key or nil
        f:Refresh()
    end)
    filterBtn.prefix = "|cff8c94a3Source:|r  "
    filterBtn:SetOptions(options)
    filterBtn:SetPoint("TOPLEFT")
    f.filterBtn = filterBtn

    f.countFS = W.Text(f, "GameFontHighlightSmall")
    f.countFS:SetPoint("LEFT", filterBtn, "RIGHT", 14, 0)

    local columns = {
        { title = "When", width = 80, get = function(r) return date("%m/%d %H:%M", r.e.t) end,
          sortValue = function(r) return r.e.t end },
        { title = "Character", width = 90, get = function(r) return CharName(r.who) end,
          sortValue = function(r) return r.who end },
        { title = "Category", width = 110, get = function(r)
            local g = C.GroupInfo(C.Group(r.e.c))
            return C.Label(r.e.c), g.color[1], g.color[2], g.color[3]
        end, sortValue = function(r) return r.e.c end },
        { title = "Detail", get = function(r) return UI.EntryDetail(r.e) end,
          sortValue = function(r) return UI.EntryDetail(r.e) end },
        { title = "Amount", width = 120, align = "RIGHT", get = function(r)
            local a = r.e.a
            if C.IsNeutral(r.e.c) then return U.FormatMoney(a), 0.6, 0.63, 0.68 end
            return U.FormatMoney(a), a >= 0 and 0.38 or 1, a >= 0 and 1 or 0.38, 0.38
        end, sortValue = function(r) return r.e.a end },
    }
    local list = W.List(f, columns, 20)
    list:SetPoint("TOPLEFT", 0, -36)
    list:SetPoint("BOTTOMRIGHT")
    list.onEnter = function(row, r)
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        if r.e.i then
            pcall(GameTooltip.SetItemByID, GameTooltip, r.e.i)
            GameTooltip:AddLine(" ")
        end
        GameTooltip:AddDoubleLine(C.Label(r.e.c), U.FormatMoney(r.e.a, true), 1, 0.82, 0)
        GameTooltip:AddLine(date("%Y-%m-%d %H:%M:%S", r.e.t), 0.7, 0.7, 0.7)
        local detail = UI.EntryDetail(r.e)
        if detail ~= "" then GameTooltip:AddLine(detail, 1, 1, 1, true) end
        GameTooltip:AddLine(r.who, 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end
    f.list = list

    function f:Refresh()
        filterBtn:SetValue(UI.ledgerGroup or "all")
        local rows = L.Entries(ns:ScopeChars(), UI.LedgerFilter())
        list:SetData(rows)
        local net = 0
        for _, r in ipairs(rows) do net = net + r.e.a end
        self.countFS:SetText(("%d entries, net %s  |cff999999(last %d days kept)|r"):format(
            #rows, U.FormatMoney(net, true), ns.db.settings.retentionDays))
    end

    return f
end
