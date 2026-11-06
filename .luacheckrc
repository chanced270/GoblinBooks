std = "lua51"
max_line_length = false
exclude_files = { "tests/wowstub.lua" }
ignore = { "212" } -- unused arguments (event handler signatures)

globals = {
    "GoblinTheme", "GoblinUIDB", "SLASH_GOBLINUI1", "SLASH_GOBLINUI2", "GoblinUI_OnAddonCompartmentClick",
    "GoblinBooksAPI", "GoblinTradesAPI", "GoblinTradesDB", "SLASH_GOBLINTRADES1", "SLASH_GOBLINTRADES2", "GoblinTrades_OnAddonCompartmentClick",
    "GoblinClassDB", "SLASH_GOBLINCLASS1", "SLASH_GOBLINCLASS2", "GoblinClass_OnAddonCompartmentClick",
    "GoblinBooksDB", "SlashCmdList", "SLASH_GOBLINBOOKS1", "SLASH_GOBLINBOOKS2",
    "GoblinBooks_OnAddonCompartmentClick", "GoblinBooks_OnAddonCompartmentEnter", "GoblinBooks_OnAddonCompartmentLeave",
}

read_globals = {
    -- Lua / WoW utility
    "wipe", "strjoin", "tostringall", "geterrorhandler", "hooksecurefunc", "date", "time", "Mixin", "tinsert",
    "BreakUpLargeNumbers",
    -- Frames & UI
    "CreateFrame", "UIParent", "GameTooltip", "DEFAULT_CHAT_FRAME", "UISpecialFrames", "MinimapCluster",
    "ChatFontNormal", "Settings", "MinimalSliderWithSteppersMixin", "C_Timer", "CreateFont",
    -- Unit / money
    "GetMoney", "GetTime", "UnitName", "UnitFullName", "UnitClass", "GetRealmName", "GetNormalizedRealmName",
    -- Sources
    "Enum", "C_Item", "C_AuctionHouse", "C_Bank", "C_QuestLog", "C_MerchantFrame",
    "GetTitleText", "GetQuestReward", "InRepairMode", "RepairAllItems", "BuyMerchantItem", "BuybackItem",
    "GetMerchantItemID", "GetMerchantItemInfo", "GetItemInfo", "GetItemInfoInstant",
    "C_Container", "ItemLocation", "IsShiftKeyDown", "GetItemCount", "C_TradeSkillUI", "GetTradeSkillLine", "GetNumTradeSkills",
    "GetTradeSkillInfo", "GetTradeSkillItemLink", "GetTradeSkillNumMade", "GetTradeSkillNumReagents",
    "GetTradeSkillReagentInfo", "GetTradeSkillReagentItemLink", "GetMerchantNumItems", "DoTradeSkill", "GetInboxItem", "AUCTION_EXPIRED_MAIL_SUBJECT", "AUCTION_REMOVED_MAIL_SUBJECT", "Minimap", "GetCursorPosition", "SettingsPanel", "AuctionCategories", "UnitGUID", "AUCTION_OUTBID_MAIL_SUBJECT", "InCombatLockdown", "AuctionHouseFrame", "TooltipDataProcessor", "ItemRefTooltip",
    "GetInboxHeaderInfo", "GetInboxInvoiceInfo", "GetInboxItemLink", "TakeInboxMoney", "AutoLootMailItem",
    "TakeInboxItem", "SendMail", "GetSendMailMoney", "GetSendMailPrice",
    "C_AddOns", "IsAddOnLoaded", "MerchantFrame", "issecretvalue", "C_Map", "UiMapPoint", "C_SuperTrack", "C_Spell",
    "GetSpellInfo", "GetZoneText", "GetNumLootItems", "GetLootSlotLink", "GetLootSlotInfo", "GetLootSourceInfo",
    "strsplit", "GetItemInfoInstant", "PlaySound", "SOUNDKIT", "FlashClientIcon", "NUM_BANKBAGSLOTS", "NUM_BAG_SLOTS", "WorldMapFrame", "GetItemIcon", "GetMinimapShape", "IsIndoors", "GetPlayerFacing", "GetCVar",
    "TakeTaxiNode", "DepositGuildBankMoney", "WithdrawGuildBankMoney",
    -- GoblinClass
    "UnitPower", "UnitPowerMax", "UnitHealth", "UnitHealthMax", "UnitExists", "UnitIsDead", "UnitCanAttack",
    "C_UnitAuras", "tContains", "debugprofilestop",
    "MerchantItemButton_OnModifiedClick", "StackSplitFrame", "ChatEdit_GetActiveWindow", "GetMerchantItemMaxStack", "C_ClassTalents", "C_Traits", "UnitLevel",
}

files["tests/run.lua"] = { std = "+busted", globals = { "GoblinBooksDB" }, allow_defined_top = true }
