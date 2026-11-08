-- Settings panel (Options > AddOns > GoblinBooks).
local _, ns = ...

local function Register()
    if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
    local category = Settings.RegisterVerticalLayoutCategory("GoblinBooks")
    local s = ns.db.settings

    local function Checkbox(key, name, tooltip, default)
        -- No value-changed callback: the addon reads ns.db.settings live, and running addon code inside
        -- Blizzard's settings processing taints it (which can block action bar setup at login).
        local setting = Settings.RegisterAddOnSetting(category, "GoblinBooks_" .. key, key, s, Settings.VarType.Boolean, name, default)
        Settings.CreateCheckbox(category, setting, tooltip)
    end

    Checkbox("accountView", "Account-wide view", "Show all characters in the GoblinBooks window.", false)
    Checkbox("includeTransfers", "Include bank transfers", "Count guild/warband bank deposits and withdrawals as income/spending in charts.", false)
    Checkbox("minimapButton", "Show minimap button", "A GoblinBooks button on the minimap: left-click to open, right-click for settings, drag to move.", true)
    Checkbox("tooltipPrices", "Show prices in item tooltips", "Adds vendor price, and AH lowest / 7-day average for tradeable items, to item tooltips.", true)
    Checkbox("merchantStackBuy", "Shift-click vendor items to buy a full stack", "Shift-left-click an item at a vendor to open a confirmation for a full stack (capped by your gold and the vendor's stock), with the total price. You can change the amount before buying. Off: the standard Blizzard quantity box.", true)
    Checkbox("ahPanel", "Show panel at the auction house", "Opens the GoblinBooks sell panel next to the auction house window.", true)
    Checkbox("ahReplace", "Replace the Blizzard auction house window", "Shows GoblinBooks as a large, resizable window in place of the standard auction house window (which stays open but hidden).", true)
    Checkbox("debug", "Debug: print every gold change", "Prints each recorded gold change and its category to chat.", false)

    local retention = Settings.RegisterAddOnSetting(category, "GoblinBooks_retentionDays", "retentionDays", s,
        Settings.VarType.Number, "Keep detailed entries (days)", 90)
    local opts = Settings.CreateSliderOptions(7, 365, 1)
    opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
    Settings.CreateSlider(category, retention, opts, "Raw ledger entries older than this are pruned at login. Daily totals for charts are kept forever.")

    local history = Settings.RegisterAddOnSetting(category, "GoblinBooks_priceHistoryDays", "priceHistoryDays", s,
        Settings.VarType.Number, "Keep AH price history (days)", 60)
    local hopts = Settings.CreateSliderOptions(7, 365, 1)
    hopts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
    Settings.CreateSlider(category, history, hopts, "Daily lowest prices older than this, and items not seen in that time, are pruned at login.")

    local undercut = Settings.RegisterAddOnSetting(category, "GoblinBooks_undercut", "undercut", s,
        Settings.VarType.Number, "Undercut (copper)", 1)
    local uopts = Settings.CreateSliderOptions(0, 100, 1)
    uopts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
    Settings.CreateSlider(category, undercut, uopts, "How far below the cheapest competing auction the sell panel suggests (0 = match it).")

    Checkbox("ahFlips", "Show the Flips page at the auction house", "Adds a Flips page to the auction house window: items listed well below their usual price that you could buy and relist for a profit. Takes effect the next time the auction house window opens.", false)
    local dpct = Settings.RegisterAddOnSetting(category, "GoblinBooks_dealsPct", "dealsPct", s,
        Settings.VarType.Number, "Watchlist: default limit (share of usual price)", 0.7)
    local dopts = Settings.CreateSliderOptions(0.3, 0.95, 0.05)
    dopts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end)
    Settings.CreateSlider(category, dpct, dopts, "A watched item's price limit, as a share of its usual price, unless you set a max price for that item. The Watchlist shows its lowest price in green at or under the limit.")

    Settings.RegisterAddOnCategory(category)
    ns.settingsCategory = category
end

-- Register during ADDON_LOADED (after Core's InitDB, which is registered first), before Blizzard applies
-- its own settings at login, so nothing of ours runs in the middle of that.
ns:On("ADDON_LOADED", function(_, name)
    if name ~= ns.ADDON or ns.settingsCategory then return end
    local ok, err = pcall(Register)
    if not ok and ns.db.settings.debug then ns:Print("settings panel unavailable: " .. tostring(err)) end
end)

function ns:OpenOptions()
    if ns.settingsCategory and Settings.OpenToCategory then
        Settings.OpenToCategory(ns.settingsCategory:GetID())
    else
        ns:Print("settings panel unavailable; use /gb commands")
    end
end
