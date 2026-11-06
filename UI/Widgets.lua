-- UI building blocks come from the shared GoblinTheme library (Libs/GoblinTheme.lua), so GoblinBooks
-- and GoblinUI look the same. If GoblinUI is installed it loads first and both use one copy.
local _, ns = ...
ns.Widgets = GoblinTheme
ns.UI = ns.UI or {}
