local ADDON_NAME = ...

local QUEST_ID = 97016
local QUEST_TITLE = "Mixing Mysteries"
local MIX_MASTER_ACHIEVEMENT_ID = 63432
local MIX_MASTER_ACHIEVEMENT_NAME = "Mysterious Mix Master"
local REQUIRED_INGREDIENTS = 3
local MAX_GOSSIP_PAGE_ATTEMPTS = 8
local LEGACY_ACTION_MACRO_NAME = "MixMystHelper"
local LEGACY_ACTION_MACRO_MARKER = "/mmh action"
local BINDING_ACTION = "MIXINGMYSTERIESHELPER_ADVANCE"
local PROXIMITY_UPDATE_INTERVAL = 0.5
local OFI_PROXIMITY_YARDS = 100

-- Ofi can appear at either location on the Coiled Isle. The Tokka's Landing
-- location is where the Mixing Mysteries ingredient dialogue is available.
local OFI_LOCATIONS = {
    { uiMapID = 2512, x = 0.574, y = 0.487 },
    { uiMapID = 2512, x = 0.610, y = 0.326 },
}

-- WoW groups bindings by the prefix before the underscore in the binding name.
-- Without this header, the helper's action is placed in the generic "Other"
-- section instead of a dedicated Mixing Mysteries Helper section.
BINDING_HEADER_MIXINGMYSTERIESHELPER = "Mixing Mysteries Helper"
BINDING_NAME_MIXINGMYSTERIESHELPER_ADVANCE = "Chain Actions"

-- The actual protected interaction is assigned through the secure button below.
-- This keeps the native key-binding definition valid when the Settings panel loads it.
function MixingMysteriesHelperBinding()
end
local INGREDIENTS = {
    { itemID = 276117, name = "Clouded Blood-Pearl", shortName = "Pearl" },
    { itemID = 276124, name = "Ancient Knucklebone", shortName = "Bone" },
    { itemID = 276126, name = "Serpent's Feather", shortName = "Feather" },
}
local INGREDIENT_ITEM_ID_SET = {}
for _, ingredient in ipairs(INGREDIENTS) do
    INGREDIENT_ITEM_ID_SET[ingredient.itemID] = true
end
local OFFERING_ITEM_IDS = {
    277937,
    277938,
    277939,
    277940,
    277941,
    277942,
    277943,
    277944,
    277945,
    277946,
}
local OFFERING_ITEM_ID_SET = {}
for _, itemID in ipairs(OFFERING_ITEM_IDS) do
    OFFERING_ITEM_ID_SET[itemID] = true
end
local OFFERING_RECIPES = {
    { itemID = 277937, name = "Balanced", ingredients = { 276117, 276124, 276126 } },
    { itemID = 277938, name = "Virulent", ingredients = { 276117, 276117, 276126 } },
    { itemID = 277939, name = "Volatile", ingredients = { 276117, 276117, 276124 } },
    { itemID = 277940, name = "Fragile", ingredients = { 276124, 276124, 276117 } },
    { itemID = 277941, name = "Eerie", ingredients = { 276124, 276124, 276126 } },
    { itemID = 277942, name = "Odious", ingredients = { 276126, 276126, 276117 } },
    { itemID = 277943, name = "Pestilent", ingredients = { 276126, 276126, 276124 } },
    { itemID = 277944, name = "Phlegmatic", ingredients = { 276126, 276126, 276126 } },
    { itemID = 277945, name = "Melancholic", ingredients = { 276124, 276124, 276124 } },
    { itemID = 277946, name = "Choleric", ingredients = { 276117, 276117, 276117 } },
}
local PREFIX = "|cff64d8ffMixing Mysteries Helper:|r "

local STATE = {
    TARGET_OFI = "TARGET_OFI",
    INTERACT_OFI = "INTERACT_OFI",
    TARGET_OFFERING = "TARGET_OFFERING",
    INTERACT_OFFERING = "INTERACT_OFFERING",
}

local DEFAULTS = {
    configVersion = 7,
    debug = false,
    enabled = true,
    mixPreference = "balanced",
    ofiName = "Ofi the Sly",
    offeringName = "Mysterious Offering",
    showStatus = true,
    showMinimapButton = true,
    anchor = "CENTER",
    relativeAnchor = "CENTER",
    x = 0,
    y = 180,
    minimapAngle = 220,
}

local STEP_TEXT = {
    [STATE.TARGET_OFI] = "Target Ofi the Sly",
    [STATE.INTERACT_OFI] = "Interact with Ofi",
    [STATE.TARGET_OFFERING] = "Target Mysterious Offering",
    [STATE.INTERACT_OFFERING] = "Interact with the offering",
}

local STEP_COLOR = {
    [STATE.TARGET_OFI] = { 0.35, 0.80, 1.00 },
    [STATE.INTERACT_OFI] = { 1.00, 0.82, 0.25 },
    [STATE.TARGET_OFFERING] = { 0.65, 0.90, 0.45 },
    [STATE.INTERACT_OFFERING] = { 1.00, 0.55, 0.25 },
}

local eventFrame = CreateFrame("Frame")
local bindingOwner = CreateFrame("Frame", ADDON_NAME .. "BindingOwner", UIParent)
local statusFrame
local minimapButton
local manualStatusVisible
local settingsCategoryID
local settingsManualVisibilityCheckbox
local settingsProximityCheckbox
local targetOfiButton
local targetOfferingButton
local noopButton
local rewardButton
local achievementButton
local db
local state = STATE.TARGET_OFI
local pendingBinding = false
local pendingRewardUpdate = false
local pendingLegacyMacroRemoval = false
local inputLocked = false
local questSelectionPending = false
local questAcceptPending = false
local ofiGossipSelections = 0
local selectedIngredientOptions = {}
local selectedIngredientIDs = {}
local pendingGossipSelection
local gossipTransitionToken = 0
local offeringTransitionToken = 0
local gossipAttemptPageSignature
local gossipPageAttempts = 0
local activeQuestID = QUEST_ID
local questRecoveryToken = 0
local pendingFullQuestRecovery = false
local questAcceptanceToken = 0
local rewardCaptureDeadline = 0
local rewardExpectedUntil = 0
local rewardItemID
local rewardItemCounts = {}
local rewardTotalCount = 0
local rewardVariantCount = 0
local lastFailureMessage
local lastFailureTime = 0
local lastTargetDebugSignature
local lastTargetDebugTime = 0
local lastReagentWarning
local playerNearOfi = false
local proximityElapsed = 0
local UpdateRewardButton
local UpdateAchievementStatus
local UpdateReagentStatus
local UpdateStatus
local ApplyBinding
local SetState
local HandleGossipShow
local ScheduleQuestStateRecovery
local SetHelperWindowVisible
local OpenAddonSettings
local UpdateStatusActionButton

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. message)
end

local function SafeString(value)
    local ok, text = pcall(tostring, value)
    return ok and text or "<unavailable>"
end

local function Debug(message)
    if db and db.debug then
        Print("|cffaaaaaaDEBUG|r " .. message)
    end
end

local function GetConfiguredKeys()
    if GetBindingKey then
        local primary, secondary = GetBindingKey(BINDING_ACTION)
        local keys = {}
        if primary then
            keys[#keys + 1] = primary
        end
        if secondary and secondary ~= primary then
            keys[#keys + 1] = secondary
        end
        return keys
    end
    return {}
end

local function GetConfiguredKeyLabel()
    local keys = GetConfiguredKeys()
    return #keys > 0 and table.concat(keys, " / ") or "?"
end

local function ExpandKeyBindingSection(sectionName)
    local settingsList = SettingsPanel and SettingsPanel.GetSettingsList and
        SettingsPanel:GetSettingsList()
    local scrollBox = settingsList and settingsList.ScrollBox
    if not scrollBox then
        return false
    end

    local function ExpandTargetSection(frame, elementData)
        local initializer = elementData or
            (frame.GetElementData and frame:GetElementData())
        local data = initializer and initializer.data
        if not data or data.name ~= sectionName then
            return false
        end

        -- The initializer owns the accordion's state; changing only the frame
        -- is undone when the scroll box next lays out its rows.
        data.expanded = true
        if initializer.SetExpanded then
            initializer:SetExpanded(true)
        end
        if frame.SetExpanded then
            frame:SetExpanded(true)
        elseif frame.EvaluateVisibility then
            frame:EvaluateVisibility(true)
            if initializer.GetExtent then
                frame:SetHeight(initializer:GetExtent())
            end
        end
        return true
    end

    if scrollBox.ForEachFrame then
        local expanded = false
        scrollBox:ForEachFrame(function(frame, elementData)
            expanded = ExpandTargetSection(frame, elementData) or expanded
        end)
        return expanded
    elseif scrollBox.FindFrameByPredicate then
        local section = scrollBox:FindFrameByPredicate(function(frame)
            local initializer = frame.GetElementData and frame:GetElementData()
            return initializer and initializer.data and
                initializer.data.name == sectionName
        end)
        return section and ExpandTargetSection(section) or false
    end

    return false
end

local function OpenKeyBindings()
    if InCombatLockdown() then
        Print("Key Bindings cannot be opened during combat.")
        return
    end
    if not Settings or not Settings.OpenToCategory then
        Print("Open Options > Key Bindings > Mixing Mysteries Helper to configure the helper.")
        return
    end

    local categoryID
    if SettingsPanel and SettingsPanel.GetAllCategories then
        for _, category in ipairs(SettingsPanel:GetAllCategories() or {}) do
            local name = category.GetName and category:GetName()
            if name == KEY_BINDINGS or name == "Keybindings" or name == "Key Bindings" then
                categoryID = category:GetID()
                break
            end
        end
    end

    -- Retail currently assigns this category ID to Key Bindings. The scan above
    -- keeps the button working if Blizzard changes its position in the list.
    local keyBindingsCategoryID = categoryID or 35
    local sectionName = BINDING_HEADER_MIXINGMYSTERIESHELPER

    -- The Keybindings provider resolves the XML category token to this display
    -- name before it creates the accordion row. Opening the panel can finish
    -- after the first call, so retry on the following frame once that row exists.
    Settings.OpenToCategory(keyBindingsCategoryID, sectionName)
    C_Timer.After(0, function()
        if SettingsPanel and SettingsPanel.OpenToCategory then
            SettingsPanel:OpenToCategory(keyBindingsCategoryID, sectionName)

            -- The section is not mounted until the scroll box reaches it. Keep
            -- trying briefly so we expand the actual row, not an absent frame.
            local remainingAttempts = 20
            local function ExpandWhenMounted()
                if ExpandKeyBindingSection(sectionName) or remainingAttempts <= 0 then
                    return
                end
                remainingAttempts = remainingAttempts - 1
                C_Timer.After(0, ExpandWhenMounted)
            end
            C_Timer.After(0, ExpandWhenMounted)
        end
    end)
end

local function RemoveLegacyActionMacro()
    if InCombatLockdown() then
        pendingLegacyMacroRemoval = true
        return
    end
    if not GetNumMacros or not GetMacroInfo or not DeleteMacro then
        return
    end

    pendingLegacyMacroRemoval = false
    local globalCount, characterCount = GetNumMacros()
    local accountLimit = MAX_ACCOUNT_MACROS or 120
    local ranges = {
        { 1, globalCount or 0 },
        { accountLimit + 1, accountLimit + (characterCount or 0) },
    }
    for _, range in ipairs(ranges) do
        for index = range[1], range[2] do
            local name, _, body = GetMacroInfo(index)
            if type(name) == "table" then
                body = name.body
                name = name.name
            end
            if name == LEGACY_ACTION_MACRO_NAME and type(body) == "string" and
                body:find(LEGACY_ACTION_MACRO_MARKER, 1, true) then
                local ok = pcall(DeleteMacro, index)
                if ok then
                    Print("Removed the obsolete Mixing Mysteries action-bar macro.")
                end
                return
            end
        end
    end
end

local function ResetMixProgress()
    ofiGossipSelections = 0
    selectedIngredientOptions = {}
    selectedIngredientIDs = {}
    pendingGossipSelection = nil
    gossipTransitionToken = gossipTransitionToken + 1
    offeringTransitionToken = offeringTransitionToken + 1
    gossipAttemptPageSignature = nil
    gossipPageAttempts = 0
end

local function CopyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            target[key] = value
        end
    end
end

local function CleanName(value)
    value = tostring(value or "")
    value = value:gsub("[\r\n]", " ")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    return value:sub(1, 80)
end

local function NamesMatch(actual, expected)
    -- Midnight can mark NPC names and gossip titles as secret values. Addon
    -- code is not allowed to compare those values, so use the map/gossip
    -- fallbacks below while the identity is restricted.
    if issecretvalue and (issecretvalue(actual) or issecretvalue(expected)) then
        return false
    end

    if not actual or not expected then
        return false
    end

    return actual == expected
end

local function UnitMatches(unit, expected)
    return UnitExists(unit) and NamesMatch(UnitName(unit), expected)
end

local function IsOfiContext()
    return UnitMatches("npc", db.ofiName) or UnitMatches("target", db.ofiName)
end

local function GetGossipTitle()
    if not GossipFrame then
        return nil
    end

    local titleRegion = GossipFrame.TitleText
    if GossipFrame.TitleContainer and GossipFrame.TitleContainer.TitleText then
        titleRegion = GossipFrame.TitleContainer.TitleText
    elseif GossipFrameTitleText then
        titleRegion = GossipFrameTitleText
    end

    return titleRegion and titleRegion.GetText and titleRegion:GetText()
end

-- Unlike HasOpenOfiGossip, this deliberately does not use the helper's current
-- state as a fallback. State recovery needs an answer based on the live game
-- UI, not the state it is trying to repair.
local function HasLiveOfiGossip()
    if not GossipFrame or not GossipFrame.IsShown or not GossipFrame:IsShown() then
        return false
    end

    return UnitMatches("npc", db.ofiName) or NamesMatch(GetGossipTitle(), db.ofiName)
end

local function HasOpenOfiGossip()
    if not GossipFrame or not GossipFrame.IsShown or not GossipFrame:IsShown() then
        return false
    end

    -- This state is reached only after our exact-target macro has selected
    -- Ofi. Keeping it as a fallback lets the interaction continue when the
    -- NPC name/title is intentionally hidden from addon code.
    return state == STATE.INTERACT_OFI or UnitMatches("npc", db.ofiName) or
        NamesMatch(GetGossipTitle(), db.ofiName)
end

local function GetPositionXY(position)
    if not position then
        return nil, nil
    end

    if position.GetXY then
        return position:GetXY()
    end

    return position.x, position.y
end

local function IsPlayerNearKnownOfiLocation()
    if not C_Map or not C_Map.GetPlayerMapPosition or not C_Map.GetWorldPosFromMapPos then
        return false
    end

    for _, location in ipairs(OFI_LOCATIONS) do
        local playerMapPosition = C_Map.GetPlayerMapPosition(location.uiMapID, "player")
        if playerMapPosition then
            local playerContinentID, playerWorldPosition = C_Map.GetWorldPosFromMapPos(
                location.uiMapID,
                playerMapPosition
            )
            local ofiContinentID, ofiWorldPosition = C_Map.GetWorldPosFromMapPos(
                location.uiMapID,
                { x = location.x, y = location.y }
            )

            if playerContinentID and playerContinentID == ofiContinentID and
                playerWorldPosition and ofiWorldPosition then
                local playerX, playerY = GetPositionXY(playerWorldPosition)
                local ofiX, ofiY = GetPositionXY(ofiWorldPosition)
                if playerX and playerY and ofiX and ofiY then
                    local deltaX = playerX - ofiX
                    local deltaY = playerY - ofiY
                    local distanceSquared = deltaX * deltaX + deltaY * deltaY
                    if distanceSquared <= OFI_PROXIMITY_YARDS * OFI_PROXIMITY_YARDS then
                        return true
                    end
                end
            end
        end
    end

    return false
end

local function IsVisibleOfiUnit(unit)
    if not UnitMatches(unit, db.ofiName) then
        return false
    end

    return not UnitIsVisible or UnitIsVisible(unit)
end

local function IsPlayerNearOfi()
    local directUnits = { "npc", "target", "mouseover", "softinteract", "anyinteract" }
    for _, unit in ipairs(directUnits) do
        if IsVisibleOfiUnit(unit) then
            return true
        end
    end

    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, nameplate in ipairs(C_NamePlate.GetNamePlates() or {}) do
            local unit = nameplate.namePlateUnitToken or nameplate.unitToken
            if not unit and nameplate.GetUnit then
                unit = nameplate:GetUnit()
            end
            if unit and IsVisibleOfiUnit(unit) then
                return true
            end
        end
    end

    return IsPlayerNearKnownOfiLocation()
end

local function GetMixingQuestOnLog()
    if not C_QuestLog or not C_QuestLog.IsOnQuest then
        return nil
    end

    if C_QuestLog.IsOnQuest(activeQuestID) then
        return activeQuestID
    end

    if activeQuestID ~= QUEST_ID and C_QuestLog.IsOnQuest(QUEST_ID) then
        return QUEST_ID
    end

    return nil
end

local function IsQuestOnLog()
    return GetMixingQuestOnLog() ~= nil
end

local function IsMixingQuestComplete()
    local questID = GetMixingQuestOnLog()
    return questID and C_QuestLog and C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID) or false
end

local function GetCurrentQuestID()
    if GetQuestID then
        return GetQuestID()
    end

    return 0
end

local function GetIngredientCount(itemID)
    if C_Item and C_Item.GetItemCount then
        local ok, count = pcall(C_Item.GetItemCount, itemID, false, false, false, false)
        if ok and type(count) == "number" then
            return count
        end
    end

    if not C_Container or not C_Container.GetContainerNumSlots or
        not C_Container.GetContainerItemInfo then
        return 0
    end

    local count = 0
    local lastBag = NUM_BAG_SLOTS or 4
    local reagentBag = REAGENTBAG_CONTAINER or
        (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag)
    for bag = 0, lastBag do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
            if itemInfo and itemInfo.itemID == itemID then
                count = count + (itemInfo.stackCount or 1)
            end
        end
    end

    if reagentBag and reagentBag > lastBag then
        local slots = C_Container.GetContainerNumSlots(reagentBag) or 0
        for slot = 1, slots do
            local itemInfo = C_Container.GetContainerItemInfo(reagentBag, slot)
            if itemInfo and itemInfo.itemID == itemID then
                count = count + (itemInfo.stackCount or 1)
            end
        end
    end

    return count
end

local function GetReagentSnapshot()
    local counts = {}
    local total = 0
    local distinct = 0

    for _, ingredient in ipairs(INGREDIENTS) do
        local count = GetIngredientCount(ingredient.itemID)
        counts[ingredient.itemID] = count
        total = total + count
        if count > 0 then
            distinct = distinct + 1
        end
    end

    return counts, total, distinct
end

local function GetRemainingIngredientNeed()
    if state == STATE.TARGET_OFFERING or state == STATE.INTERACT_OFFERING or
        IsMixingQuestComplete() then
        return 0
    end

    return math.max(0, REQUIRED_INGREDIENTS - ofiGossipSelections)
end

local function FormatReagentCounts(counts)
    local parts = {}
    for index, ingredient in ipairs(INGREDIENTS) do
        parts[index] = ingredient.shortName .. " " .. (counts[ingredient.itemID] or 0)
    end
    return table.concat(parts, "  |  ")
end

local function GetIngredientName(ingredient)
    if C_Item and C_Item.GetItemNameByID then
        local name = C_Item.GetItemNameByID(ingredient.itemID)
        if name then
            return name
        end
    end

    if C_Item and C_Item.GetItemInfo then
        local name = C_Item.GetItemInfo(ingredient.itemID)
        if name then
            return name
        end
    end

    return ingredient.name
end

local function GetAuctionatorShoppingListImport()
    local lines = { "**Mixing Mysteries" }
    for _, ingredient in ipairs(INGREDIENTS) do
        lines[#lines + 1] = GetIngredientName(ingredient)
    end
    return table.concat(lines, "\n")
end

local function GetReagentReadiness()
    local counts, total, distinct = GetReagentSnapshot()
    local needed = GetRemainingIngredientNeed()
    local sufficient = needed == 0 or total >= needed
    local balancedReady = needed == 0 or distinct >= needed
    return sufficient, balancedReady, counts, total, needed
end

UpdateReagentStatus = function(announce)
    if not db then
        return false
    end

    local sufficient, balancedReady, counts, total, needed = GetReagentReadiness()
    local countText = FormatReagentCounts(counts)

    if statusFrame and statusFrame.reagent then
        statusFrame.reagent:SetText("Available reagents:\n" .. countText)
    end

    if sufficient or needed == 0 then
        lastReagentWarning = nil
    elseif announce and db.enabled then
        local warningSignature = needed .. ":" .. countText
        if warningSignature ~= lastReagentWarning then
            local missing = needed - total
            Print(
                "|cffff6666Insufficient reagents:|r " .. total .. "/" .. needed ..
                " available (" .. countText .. "). Collect " .. missing .. " more before mixing."
            )
            lastReagentWarning = warningSignature
        end
    end

    return sufficient, balancedReady, counts, total, needed
end

UpdateStatus = function(note)
    if not statusFrame or not db then
        return
    end

    if not db.enabled or manualStatusVisible == false or
        (manualStatusVisible ~= true and (not db.showStatus or not playerNearOfi)) then
        statusFrame:Hide()
        return
    end

    statusFrame:Show()
    statusFrame.title:SetText("Mixing Mysteries Helper  |cffaaaaaa[" .. GetConfiguredKeyLabel() .. "]|r")
    if UpdateStatusActionButton then
        UpdateStatusActionButton()
    end

    local text = STEP_TEXT[state] or state
    if note then
        text = text .. "  |cffaaaaaa" .. note .. "|r"
    elseif pendingBinding then
        text = text .. "  |cffff6666(after combat)|r"
    end

    statusFrame.step:SetText(text)
    local color = STEP_COLOR[state] or { 1, 1, 1 }
    statusFrame.step:SetTextColor(color[1], color[2], color[3])

    UpdateReagentStatus(false)
end

local function RefreshOfiProximity(forceStatusUpdate)
    if not db then
        return
    end

    local wasNearOfi = playerNearOfi
    playerNearOfi = IsPlayerNearOfi()
    if forceStatusUpdate or playerNearOfi ~= wasNearOfi then
        UpdateStatus()
    end
end

local function GetOfferingItemName(itemID)
    if C_Item and C_Item.GetItemNameByID then
        return C_Item.GetItemNameByID(itemID)
    end

    if C_Item and C_Item.GetItemInfo then
        return C_Item.GetItemInfo(itemID)
    end

    return nil
end

local function ShowRewardTooltip(button)
    if rewardTotalCount <= 0 then
        return
    end

    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Mysterious Offerings")
    GameTooltip:AddLine(
        rewardTotalCount .. " container" .. (rewardTotalCount == 1 and "" or "s") ..
        " across " .. rewardVariantCount .. " variant" .. (rewardVariantCount == 1 and "" or "s") .. ".",
        0.75,
        0.95,
        1,
        true
    )
    for _, itemID in ipairs(OFFERING_ITEM_IDS) do
        local count = rewardItemCounts[itemID]
        if count and count > 0 then
            GameTooltip:AddLine((GetOfferingItemName(itemID) or ("Offering " .. itemID)) .. "  x" .. count)
        end
    end
    GameTooltip:AddLine("Click to open any available offering.", 0.45, 1, 0.45, true)
    GameTooltip:Show()
end

local function ShowAchievementTooltip(button)
    GameTooltip:SetOwner(button, "ANCHOR_BOTTOMLEFT", 0, -2)
    GameTooltip:SetAchievementByID(MIX_MASTER_ACHIEVEMENT_ID)
    GameTooltip:Show()
end

local function ShowReagentTooltip(button)
    local counts = GetReagentSnapshot()
    -- The panel is draggable. Anchoring at its right edge can put this tooltip
    -- completely off-screen after the player moves the panel to the right, as
    -- in the reported screenshots. Anchor beside the actual cursor instead.
    GameTooltip:SetOwner(button, "ANCHOR_CURSOR")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("Mixing reagents")
    for _, ingredient in ipairs(INGREDIENTS) do
        GameTooltip:AddLine(
            GetIngredientName(ingredient) .. "  x" .. (counts[ingredient.itemID] or 0),
            1,
            1,
            1
        )
    end
    GameTooltip:AddLine("Click to copy the Auctionator shopping list.", 0.45, 1, 0.45, true)
    GameTooltip:Show()
end

local auctionatorCopyFrame

local function ShowAuctionatorCopyDialog()
    if not auctionatorCopyFrame then
        auctionatorCopyFrame = CreateFrame(
            "Frame",
            ADDON_NAME .. "AuctionatorCopyFrame",
            UIParent,
            "BackdropTemplate"
        )
        auctionatorCopyFrame:SetSize(365, 158)
        auctionatorCopyFrame:SetPoint("CENTER")
        auctionatorCopyFrame:SetFrameStrata("DIALOG")
        auctionatorCopyFrame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        auctionatorCopyFrame:SetBackdropColor(0.025, 0.035, 0.055, 0.96)
        auctionatorCopyFrame:SetBackdropBorderColor(0.25, 0.65, 0.85, 0.9)
        auctionatorCopyFrame:EnableMouse(true)
        auctionatorCopyFrame:Hide()

        auctionatorCopyFrame.title = auctionatorCopyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        auctionatorCopyFrame.title:SetPoint("TOP", 0, -11)
        auctionatorCopyFrame.title:SetText("Copy Auctionator list")

        auctionatorCopyFrame.instructions = auctionatorCopyFrame:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )
        auctionatorCopyFrame.instructions:SetPoint("TOP", auctionatorCopyFrame.title, "BOTTOM", 0, -4)
        auctionatorCopyFrame.instructions:SetText("Press Ctrl+C, then paste it into Auctionator > Import.")

        auctionatorCopyFrame.textBox = CreateFrame("Frame", nil, auctionatorCopyFrame, "BackdropTemplate")
        auctionatorCopyFrame.textBox:SetPoint("TOPLEFT", 16, -52)
        auctionatorCopyFrame.textBox:SetPoint("TOPRIGHT", -16, -52)
        auctionatorCopyFrame.textBox:SetHeight(62)
        auctionatorCopyFrame.textBox:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        auctionatorCopyFrame.textBox:SetBackdropColor(0, 0, 0, 0.55)
        auctionatorCopyFrame.textBox:SetBackdropBorderColor(0.35, 0.55, 0.7, 0.85)

        auctionatorCopyFrame.editBox = CreateFrame("EditBox", nil, auctionatorCopyFrame.textBox)
        auctionatorCopyFrame.editBox:SetPoint("TOPLEFT", 8, -6)
        auctionatorCopyFrame.editBox:SetPoint("BOTTOMRIGHT", -8, 6)
        auctionatorCopyFrame.editBox:SetMultiLine(true)
        auctionatorCopyFrame.editBox:SetMaxLetters(1024)
        auctionatorCopyFrame.editBox:SetAutoFocus(false)
        auctionatorCopyFrame.editBox:SetFontObject(GameFontHighlightSmall)
        auctionatorCopyFrame.editBox:SetJustifyH("LEFT")
        auctionatorCopyFrame.editBox:SetJustifyV("TOP")
        auctionatorCopyFrame.editBox:SetScript("OnEscapePressed", function()
            auctionatorCopyFrame:Hide()
        end)
        auctionatorCopyFrame.editBox:SetScript("OnKeyDown", function(_, key)
            if key == "C" and IsControlKeyDown and IsControlKeyDown() then
                -- Let WoW finish its native copy shortcut before hiding the
                -- dialog on the following frame.
                C_Timer.After(0, function()
                    auctionatorCopyFrame:Hide()
                end)
            end
        end)

        auctionatorCopyFrame.closeButton = CreateFrame("Button", nil, auctionatorCopyFrame, "UIPanelButtonTemplate")
        auctionatorCopyFrame.closeButton:SetSize(130, 22)
        auctionatorCopyFrame.closeButton:SetPoint("BOTTOM", 0, 11)
        auctionatorCopyFrame.closeButton:SetText(CLOSE)
        auctionatorCopyFrame.closeButton:SetScript("OnClick", function()
            auctionatorCopyFrame:Hide()
        end)
    end

    auctionatorCopyFrame.editBox:SetText(GetAuctionatorShoppingListImport())
    auctionatorCopyFrame:Show()
    auctionatorCopyFrame.editBox:HighlightText()
    auctionatorCopyFrame.editBox:SetFocus()
end

local function OpenMixMasterAchievement()
    if OpenAchievementFrameToAchievement then
        OpenAchievementFrameToAchievement(MIX_MASTER_ACHIEVEMENT_ID)
        return
    end

    if AchievementFrame_LoadUI then
        AchievementFrame_LoadUI()
    end
    if AchievementFrame_ToggleAchievementFrame and
        (not AchievementFrame or not AchievementFrame:IsShown()) then
        AchievementFrame_ToggleAchievementFrame()
    end
    if AchievementFrame_SelectAchievement then
        AchievementFrame_SelectAchievement(MIX_MASTER_ACHIEVEMENT_ID)
    end
end

local function CreateStatusFrame()
    statusFrame = CreateFrame("Frame", ADDON_NAME .. "StatusFrame", UIParent, "BackdropTemplate")
    statusFrame:SetSize(310, 90)
    statusFrame:SetPoint(db.anchor, UIParent, db.relativeAnchor, db.x, db.y)
    statusFrame:SetClampedToScreen(true)
    statusFrame:SetMovable(true)
    statusFrame:EnableMouse(true)
    statusFrame:RegisterForDrag("LeftButton")
    statusFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    statusFrame:SetBackdropColor(0.025, 0.035, 0.055, 0.88)
    statusFrame:SetBackdropBorderColor(0.25, 0.65, 0.85, 0.75)
    statusFrame:Hide()

    statusFrame.title = statusFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusFrame.title:SetPoint("TOPLEFT", 12, -8)
    statusFrame.title:SetPoint("TOPRIGHT", -126, -8)
    statusFrame.title:SetJustifyH("LEFT")

    statusFrame.step = statusFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    statusFrame.step:SetPoint("TOPLEFT", 12, -27)
    statusFrame.step:SetPoint("TOPRIGHT", -60, -27)
    statusFrame.step:SetJustifyH("LEFT")

    statusFrame.reagentButton = CreateFrame("Button", nil, statusFrame)
    -- Use opposing vertical anchors. The old BOTTOMLEFT/BOTTOMRIGHT pair had
    -- different y offsets, which created an invalid hit rectangle.
    statusFrame.reagentButton:SetPoint("TOPLEFT", 7, -44)
    statusFrame.reagentButton:SetPoint("BOTTOMRIGHT", -56, 20)
    statusFrame.reagentButton:EnableMouse(true)
    statusFrame.reagentButton:RegisterForClicks("LeftButtonUp")
    statusFrame.reagentButton:SetFrameLevel(statusFrame:GetFrameLevel() + 2)
    statusFrame.reagentButton:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight", "ADD")

    statusFrame.reagent = statusFrame.reagentButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusFrame.reagent:SetPoint("TOPLEFT", 5, -1)
    statusFrame.reagent:SetPoint("TOPRIGHT", -4, -1)
    statusFrame.reagent:SetJustifyH("LEFT")

    statusFrame.reagentButton:SetScript("OnEnter", ShowReagentTooltip)
    statusFrame.reagentButton:SetScript("OnLeave", function()
        if GameTooltip.GetOwner and GameTooltip:GetOwner() == statusFrame.reagentButton then
            GameTooltip:Hide()
        end
    end)
    statusFrame.reagentButton:SetScript("OnClick", ShowAuctionatorCopyDialog)

    statusFrame.actionButton = CreateFrame("Button", nil, statusFrame, "UIPanelButtonTemplate")
    statusFrame.actionButton:SetSize(86, 19)
    statusFrame.actionButton:SetPoint("TOPRIGHT", -28, -3)

    statusFrame.closeButton = CreateFrame("Button", nil, statusFrame, "UIPanelCloseButton")
    statusFrame.closeButton:SetSize(22, 22)
    statusFrame.closeButton:SetPoint("TOPRIGHT", 2, 2)
    statusFrame.closeButton:SetScript("OnClick", function()
        SetHelperWindowVisible(false)
    end)

    rewardButton = CreateFrame(
        "Button",
        ADDON_NAME .. "RewardButton",
        statusFrame,
        "SecureActionButtonTemplate"
    )
    rewardButton:SetSize(38, 38)
    rewardButton:SetPoint("BOTTOMRIGHT", -12, 7)
    rewardButton:RegisterForClicks("AnyDown", "AnyUp")

    rewardButton.icon = rewardButton:CreateTexture(nil, "ARTWORK")
    rewardButton.icon:SetAllPoints()
    rewardButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    rewardButton.count = rewardButton:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    rewardButton.count:SetPoint("BOTTOMRIGHT", -4, 4)
    rewardButton:Hide()

    rewardButton:SetScript("OnEnter", ShowRewardTooltip)

    rewardButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    rewardButton:SetScript("PostClick", function()
        C_Timer.After(0.1, function()
            if UpdateRewardButton then
                UpdateRewardButton()
            end
        end)
        C_Timer.After(0.5, function()
            if UpdateRewardButton then
                UpdateRewardButton()
            end
        end)
    end)

    achievementButton = CreateFrame("Button", nil, statusFrame)
    achievementButton:SetPoint("BOTTOMLEFT", 10, 4)
    achievementButton:SetPoint("BOTTOMRIGHT", -60, 4)
    achievementButton:SetHeight(18)
    achievementButton:RegisterForClicks("LeftButtonUp")

    achievementButton.icon = achievementButton:CreateTexture(nil, "ARTWORK")
    achievementButton.icon:SetSize(15, 15)
    achievementButton.icon:SetPoint("LEFT", 0, 0)

    achievementButton.label = achievementButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    achievementButton.label:SetPoint("LEFT", achievementButton.icon, "RIGHT", 4, 0)
    achievementButton.label:SetPoint("RIGHT", 0, 0)
    achievementButton.label:SetJustifyH("LEFT")

    achievementButton:SetScript("OnEnter", ShowAchievementTooltip)
    achievementButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    achievementButton:SetScript("OnClick", OpenMixMasterAchievement)

    statusFrame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)

    statusFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local anchor, _, relativeAnchor, x, y = self:GetPoint(1)
        db.anchor = anchor
        db.relativeAnchor = relativeAnchor
        db.x = math.floor(x + 0.5)
        db.y = math.floor(y + 0.5)
    end)

end

local function UpdateMinimapButtonPosition()
    if not minimapButton then
        return
    end

    local angle = math.rad(db.minimapAngle or DEFAULTS.minimapAngle)
    local radius = (Minimap:GetWidth() / 2) + 10
    local x = radius * math.cos(angle)
    local y = radius * math.sin(angle)
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function UpdateMinimapButtonVisibility()
    if not minimapButton then
        return
    end

    minimapButton:SetShown(db.showMinimapButton)
end

local function IsHelperWindowEnabled()
    return manualStatusVisible == true or
        (manualStatusVisible ~= false and db.showStatus)
end

local function SyncWindowVisibilityCheckboxes()
    if settingsManualVisibilityCheckbox then
        settingsManualVisibilityCheckbox:SetChecked(IsHelperWindowEnabled())
    end
    if settingsProximityCheckbox then
        settingsProximityCheckbox:SetChecked(db.showStatus)
    end
end

SetHelperWindowVisible = function(visible)
    manualStatusVisible = visible
    if not visible then
        db.showStatus = false
    end
    UpdateStatus()
    SyncWindowVisibilityCheckboxes()
end

local function ToggleManualStatusVisibility()
    manualStatusVisible = not statusFrame:IsShown()
    if not manualStatusVisible then
        db.showStatus = false
    end
    UpdateStatus()
    SyncWindowVisibilityCheckboxes()
end

OpenAddonSettings = function()
    if Settings and Settings.OpenToCategory and settingsCategoryID then
        Settings.OpenToCategory(settingsCategoryID)
    end
end

UpdateStatusActionButton = function()
    if not statusFrame or not statusFrame.actionButton then
        return
    end

    if #GetConfiguredKeys() == 0 then
        statusFrame.actionButton:SetText("Set keybind")
        statusFrame.actionButton:SetScript("OnClick", OpenKeyBindings)
    else
        statusFrame.actionButton:SetText("Settings")
        statusFrame.actionButton:SetScript("OnClick", OpenAddonSettings)
    end
end

local function CreateMinimapButton()
    minimapButton = CreateFrame("Button", ADDON_NAME .. "MinimapButton", Minimap)
    minimapButton:SetSize(32, 32)
    minimapButton:SetFrameStrata("HIGH")
    minimapButton:SetFrameLevel(Minimap:GetFrameLevel() + 10)
    minimapButton:SetToplevel(true)
    minimapButton:SetMovable(true)
    minimapButton:SetClampedToScreen(true)

    local overlay = minimapButton:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")

    local background = minimapButton:CreateTexture(nil, "BACKGROUND")
    background:SetSize(24, 24)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("CENTER", 0, 1)

    local icon = minimapButton:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetTexture("Interface\\AddOns\\MixingMysteriesHelper\\art\\mixing-mysteries-helper-curseforge-logo-256.jpg")
    icon:SetPoint("CENTER", 0, 1)
    if icon.AddMaskTexture then
        local mask = minimapButton:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        mask:SetAllPoints(icon)
        icon:AddMaskTexture(mask)
    end

    minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    minimapButton:EnableMouse(true)
    minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    minimapButton:RegisterForDrag("LeftButton")
    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Mixing Mysteries Helper")
        GameTooltip:AddLine("Left-click to show or hide the helper window.", 0.75, 0.75, 0.75)
        GameTooltip:AddLine("Right-click to open settings.", 0.75, 0.75, 0.75)
        GameTooltip:AddLine("Drag to reposition the minimap button.", 0.75, 0.75, 0.75)
        GameTooltip:Show()
    end)
    minimapButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    minimapButton:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            OpenAddonSettings()
        else
            ToggleManualStatusVisibility()
        end
    end)
    minimapButton:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local minimapX, minimapY = Minimap:GetCenter()
            local cursorX, cursorY = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cursorX, cursorY = cursorX / scale, cursorY / scale
            db.minimapAngle = math.deg(math.atan2(cursorY - minimapY, cursorX - minimapX))
            UpdateMinimapButtonPosition()
        end)
    end)
    minimapButton:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    UpdateMinimapButtonPosition()
    UpdateMinimapButtonVisibility()
end

UpdateAchievementStatus = function()
    if not achievementButton then
        return
    end

    local _, name, _, completed = GetAchievementInfo(MIX_MASTER_ACHIEVEMENT_ID)
    name = name or MIX_MASTER_ACHIEVEMENT_NAME

    -- Warband achievements can report incomplete on an alt even when that alt
    -- has every offering criterion credited. Treat the criteria as the source
    -- of truth for this achievement in that case.
    if not completed and GetAchievementNumCriteria and GetAchievementCriteriaInfo then
        local criteriaCount = GetAchievementNumCriteria(MIX_MASTER_ACHIEVEMENT_ID) or 0
        local offeringCriteria = 0
        local allOfferingCriteriaComplete = criteriaCount > 0
        for index = 1, criteriaCount do
            local _, _, criteriaCompleted, _, _, _, _, assetID =
                GetAchievementCriteriaInfo(MIX_MASTER_ACHIEVEMENT_ID, index)
            if OFFERING_ITEM_ID_SET[assetID] then
                offeringCriteria = offeringCriteria + 1
                if not criteriaCompleted then
                    allOfferingCriteriaComplete = false
                    break
                end
            end
        end
        completed = allOfferingCriteriaComplete and offeringCriteria == #OFFERING_ITEM_IDS
    end

    if completed then
        achievementButton.icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        achievementButton.label:SetText("|cff55dd55" .. name .. "|r")
    else
        achievementButton.icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
        achievementButton.label:SetText("|cffff5555" .. name .. "|r")
    end
end

local function GetTargetMacroText(name, allowPartialMatch)
    -- Clear first so UnitExists("target") after the secure macro is a reliable
    -- success signal without reading the target's possibly-secret name.
    local lines = { "/cleartarget", "/targetexact " .. name }
    if allowPartialMatch then
        -- Some interactable objects do not resolve through /targetexact on
        -- every client build, while the normal target command still does.
        lines[#lines + 1] = "/target [noexists] " .. name
    end
    return table.concat(lines, "\n")
end

local function FindOfferingsInBags()
    local totalCount = 0
    local variantCount = 0
    local firstItemID
    local firstVariantIcon
    local counts = {}

    if not C_Container or not C_Container.GetContainerNumSlots or
        not C_Container.GetContainerItemInfo then
        return totalCount, nil, counts, variantCount, nil
    end

    local lastBag = NUM_BAG_SLOTS or 4
    for bag = 0, lastBag do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
            local itemID = itemInfo and itemInfo.itemID
            if itemID and OFFERING_ITEM_ID_SET[itemID] then
                local stackCount = itemInfo.stackCount or 1
                if not counts[itemID] then
                    counts[itemID] = 0
                    variantCount = variantCount + 1
                end
                counts[itemID] = counts[itemID] + stackCount
                totalCount = totalCount + stackCount
                firstItemID = firstItemID or itemID
                firstVariantIcon = firstVariantIcon or itemInfo.iconFileID
            end
        end
    end

    return totalCount, firstItemID, counts, variantCount, firstVariantIcon
end

UpdateRewardButton = function()
    if not rewardButton then
        return
    end

    local totalCount, firstItemID, counts, variantCount, firstVariantIcon = FindOfferingsInBags()
    local waitingForBag = totalCount == 0 and rewardItemID and GetTime() <= rewardExpectedUntil
    if waitingForBag then
        totalCount = 1
        firstItemID = rewardItemID
        counts = { [rewardItemID] = 1 }
        variantCount = 1
    end

    if InCombatLockdown() then
        pendingRewardUpdate = true
        return
    end

    pendingRewardUpdate = false
    if totalCount == 0 then
        local previousTotal = rewardTotalCount
        rewardButton:SetAttribute("type", nil)
        rewardButton:SetAttribute("item", nil)
        rewardButton:Hide()
        rewardItemID = nil
        rewardItemCounts = {}
        rewardTotalCount = 0
        rewardVariantCount = 0
        if GameTooltip.GetOwner and GameTooltip:GetOwner() == rewardButton then
            GameTooltip:Hide()
        end
        if previousTotal > 0 then
            Debug("No offering variants remain in the bags; hiding the pooled reward button.")
        end
        return
    end

    local previousItemID = rewardItemID
    rewardItemID = firstItemID
    rewardItemCounts = counts
    rewardTotalCount = totalCount
    rewardVariantCount = variantCount
    if not firstVariantIcon and C_Item and C_Item.GetItemIconByID then
        firstVariantIcon = C_Item.GetItemIconByID(firstItemID)
    end
    rewardButton.icon:SetTexture(firstVariantIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
    rewardButton.count:SetText(totalCount > 1 and totalCount or "")
    rewardButton:SetAttribute("type", "item")
    rewardButton:SetAttribute("item", "item:" .. firstItemID)
    rewardButton:Show()
    if GameTooltip.GetOwner and GameTooltip:GetOwner() == rewardButton then
        ShowRewardTooltip(rewardButton)
    end

    if previousItemID ~= firstItemID then
        Debug(
            "Pooled reward button bound to itemID=" .. firstItemID ..
            "; total=" .. totalCount .. ", variants=" .. variantCount .. "."
        )
    end
end

local function CaptureRewardFromLoot(message)
    local now = GetTime()
    if not db.enabled or (state ~= STATE.INTERACT_OFFERING and now > rewardCaptureDeadline) then
        return
    end

    local messageText = tostring(message or "")
    local itemID = tonumber(messageText:match("|Hitem:(%d+)"))
    if not itemID or not OFFERING_ITEM_ID_SET[itemID] then
        return
    end

    rewardCaptureDeadline = 0
    rewardExpectedUntil = now + 2
    rewardItemID = itemID
    Debug("Captured combination reward: itemID=" .. itemID .. ".")
    UpdateRewardButton()

    C_Timer.After(0.5, UpdateRewardButton)
    C_Timer.After(2.1, UpdateRewardButton)
end

local function ReportTargetFailure(expected)
    local now = GetTime()
    local message = "Could not target " .. expected .. ". Move closer and press " .. GetConfiguredKeyLabel() .. " again."

    if message ~= lastFailureMessage or now - lastFailureTime > 3 then
        Print(message)
        lastFailureMessage = message
        lastFailureTime = now
    end

    UpdateStatus("not found")
end

local function IsConfiguredActionPhase(down)
    local useKeyDown = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
    return (useKeyDown and down) or (not useKeyDown and not down)
end

local function TargetButtonClicked(expected, nextState)
    local isOpenOfiGossip = nextState == STATE.INTERACT_OFI and HasOpenOfiGossip()
    local actualTarget = SafeString(UnitName("target"))
    local debugSignature = expected .. ":" .. actualTarget .. ":" .. SafeString(isOpenOfiGossip)
    local now = GetTime()
    if debugSignature ~= lastTargetDebugSignature or now - lastTargetDebugTime > 0.75 then
        Debug(
            "Target action: expected=" .. expected ..
            ", actual=" .. actualTarget ..
            ", targetExists=" .. SafeString(UnitExists("target")) ..
            ", openOfiGossip=" .. SafeString(isOpenOfiGossip)
        )
        lastTargetDebugSignature = debugSignature
        lastTargetDebugTime = now
    end
    -- The macro clears any previous target before targeting this exact name.
    -- UnitExists is safe to query when names are secret, unlike UnitName.
    if UnitMatches("target", expected) or UnitExists("target") or isOpenOfiGossip then
        SetState(nextState)

        if nextState == STATE.INTERACT_OFFERING then
            rewardCaptureDeadline = GetTime() + 30
            Debug("Armed dynamic reward capture for the Mysterious Offering.")
        end

        if isOpenOfiGossip then
            C_Timer.After(0, function()
                if HandleGossipShow then
                    HandleGossipShow()
                end
            end)
        end
    else
        ReportTargetFailure(expected)
    end
end

local function CreateTargetButtons()
    noopButton = CreateFrame("Button", ADDON_NAME .. "NoopButton", nil, "SecureActionButtonTemplate")
    noopButton:RegisterForClicks("AnyDown", "AnyUp")

    targetOfiButton = CreateFrame("Button", ADDON_NAME .. "TargetOfiButton", nil, "SecureActionButtonTemplate")
    targetOfiButton:RegisterForClicks("AnyDown", "AnyUp")
    targetOfiButton:SetAttribute("type", "macro")
    targetOfiButton:SetScript("PostClick", function(_, _, down)
        if not IsConfiguredActionPhase(down) then
            return
        end
        TargetButtonClicked(db.ofiName, STATE.INTERACT_OFI)
    end)

    targetOfferingButton = CreateFrame(
        "Button",
        ADDON_NAME .. "TargetOfferingButton",
        nil,
        "SecureActionButtonTemplate"
    )
    targetOfferingButton:RegisterForClicks("AnyDown", "AnyUp")
    targetOfferingButton:SetAttribute("type", "macro")
    targetOfferingButton:SetScript("PostClick", function(_, _, down)
        if not IsConfiguredActionPhase(down) then
            return
        end
        TargetButtonClicked(db.offeringName, STATE.INTERACT_OFFERING)
    end)
end

local function UpdateTargetMacros()
    if InCombatLockdown() then
        pendingBinding = true
        UpdateStatus()
        return
    end

    targetOfiButton:SetAttribute("macrotext", GetTargetMacroText(db.ofiName, false))
    targetOfferingButton:SetAttribute("macrotext", GetTargetMacroText(db.offeringName, true))
end

ApplyBinding = function()
    if InCombatLockdown() then
        pendingBinding = true
        UpdateStatus()
        return
    end

    pendingBinding = false
    ClearOverrideBindings(bindingOwner)

    local keys = GetConfiguredKeys()
    if not db.enabled or #keys == 0 then
        UpdateStatus()
        return
    end

    for _, key in ipairs(keys) do
        if inputLocked then
            SetOverrideBindingClick(bindingOwner, true, key, noopButton:GetName(), "LeftButton")
        elseif state == STATE.TARGET_OFI or
            (state == STATE.INTERACT_OFI and not UnitExists("target") and not HasLiveOfiGossip()) then
            -- Quest acceptance can close Ofi's dialog and clear the target.
            -- Never leave the hotkey mapped to INTERACTTARGET in that case:
            -- use the target action until Ofi is found again.
            SetOverrideBindingClick(bindingOwner, true, key, targetOfiButton:GetName(), "LeftButton")
        elseif state == STATE.TARGET_OFFERING then
            SetOverrideBindingClick(bindingOwner, true, key, targetOfferingButton:GetName(), "LeftButton")
        else
            SetOverrideBinding(bindingOwner, true, key, "INTERACTTARGET")
        end
    end

    UpdateStatus()
end

local function ReleaseInputLockIfIdle(reason)
    if state ~= STATE.INTERACT_OFI or not inputLocked or HasOpenOfiGossip() or
        questSelectionPending or questAcceptPending then
        return false
    end

    inputLocked = false
    if not UnitExists("target") then
        SetState(STATE.TARGET_OFI)
        Debug("Ofi target was cleared; returning to the target step: " .. reason .. ".")
        return true
    end

    ApplyBinding()
    Debug("F12 interaction binding restored: " .. reason .. ".")
    return true
end

SetState = function(newState)
    if not STEP_TEXT[newState] then
        return
    end

    local previousState = state
    state = newState
    if newState == STATE.TARGET_OFI then
        ResetMixProgress()
        questSelectionPending = false
        questAcceptPending = false
        inputLocked = false
    elseif newState ~= STATE.INTERACT_OFI then
        inputLocked = false
    end
    if previousState ~= newState then
        Debug("State: " .. previousState .. " -> " .. newState)
    end
    ApplyBinding()
    UpdateReagentStatus(true)
end

local function IsMixingQuestID(questID)
    return questID == QUEST_ID or questID == activeQuestID
end

local function IsMixingQuestTitle(title)
    local ok, matches = pcall(function()
        return title == QUEST_TITLE
    end)
    return ok and matches
end

local function FindMixingQuest(quests)
    for _, quest in ipairs(quests or {}) do
        if IsMixingQuestID(quest.questID) or IsMixingQuestTitle(quest.title) then
            if quest.questID then
                activeQuestID = quest.questID
            end
            return quest
        end
    end
end

local function GetIngredientOptionInfo(options, index)
    local option = options and options[index]
    local optionCount = options and #options or 0
    local optionName = option and (option.name or option.title) or "<unknown>"
    local optionNameText = SafeString(optionName)
    local looksLikeIngredient = optionNameText:find("<Offer", 1, true) ~= nil
    local fallbackIngredient = optionCount >= 3 and index <= math.min(REQUIRED_INGREDIENTS, optionCount - 1)
    return option, optionNameText, looksLikeIngredient or fallbackIngredient
end

local function GetIngredientIdentity(optionNameText)
    local optionText = SafeString(optionNameText)
    local lowerOptionText = optionText:lower()

    for _, ingredient in ipairs(INGREDIENTS) do
        local localizedName
        if C_Item and C_Item.GetItemNameByID then
            localizedName = C_Item.GetItemNameByID(ingredient.itemID)
        end
        if (localizedName and optionText:find(localizedName, 1, true)) or
            lowerOptionText:find(ingredient.name:lower(), 1, true) then
            return ingredient.itemID
        end
    end

    local normalized = lowerOptionText
        :gsub("^%s*<%s*offer%s+", "")
        :gsub("[>%.%s]+$", "")
        :gsub("^an?%s+", "")
        :gsub("[^%w]+", "-")
        :gsub("^-+", "")
        :gsub("-+$", "")
    return normalized ~= "" and normalized or nil
end

local function GetIngredientOptionKey(option, optionNameText, index)
    local ingredientIdentity = GetIngredientIdentity(optionNameText)
    if ingredientIdentity then
        return "ingredient:" .. SafeString(ingredientIdentity)
    end

    if option and option.gossipOptionID then
        return "id:" .. SafeString(option.gossipOptionID)
    end

    return "name:" .. optionNameText .. ":" .. index
end

local function GetGossipPageSignature(options)
    local parts = {}
    for index, option in ipairs(options or {}) do
        local optionName = option and (option.name or option.title) or "<unknown>"
        parts[index] = SafeString(option and option.gossipOptionID) .. ":" .. SafeString(optionName)
    end

    return table.concat(parts, "|")
end

local function GetCurrentGossipOptions()
    if C_GossipInfo and C_GossipInfo.GetOptions then
        return C_GossipInfo.GetOptions() or {}
    end

    return {}
end

local function GetIngredientRequirements(ingredientIDs)
    local requirements = {}
    for _, itemID in ipairs(ingredientIDs) do
        requirements[itemID] = (requirements[itemID] or 0) + 1
    end
    return requirements
end

local function GetMissingMixMasterOfferings()
    local _, _, _, completed = GetAchievementInfo(MIX_MASTER_ACHIEVEMENT_ID)
    if completed or not GetAchievementNumCriteria or not GetAchievementCriteriaInfo then
        return nil
    end

    local missing = {}
    local criteriaCount = GetAchievementNumCriteria(MIX_MASTER_ACHIEVEMENT_ID) or 0
    for index = 1, criteriaCount do
        local _, _, criteriaCompleted, _, _, _, _, assetID =
            GetAchievementCriteriaInfo(MIX_MASTER_ACHIEVEMENT_ID, index)
        if OFFERING_ITEM_ID_SET[assetID] and not criteriaCompleted then
            missing[assetID] = true
        end
    end

    return next(missing) and missing or nil
end

local function GetIngredientCandidates(options)
    local candidates = {}
    for index = 1, #(options or {}) do
        local option, optionName, isIngredient = GetIngredientOptionInfo(options, index)
        if isIngredient then
            local itemID = GetIngredientIdentity(optionName)
            candidates[#candidates + 1] = {
                index = index,
                option = option,
                name = optionName,
                itemID = type(itemID) == "number" and itemID or nil,
            }
        end
    end
    return candidates
end

local function FindCandidateForIngredient(candidates, itemID)
    for _, candidate in ipairs(candidates) do
        if candidate.itemID == itemID then
            return candidate
        end
    end
end

local function ChooseAchievementRecipe(candidates)
    local missingOfferings = GetMissingMixMasterOfferings()
    if not missingOfferings then
        return nil
    end

    local availableCounts = GetReagentSnapshot()
    local alreadySelected = GetIngredientRequirements(selectedIngredientIDs)
    for _, recipe in ipairs(OFFERING_RECIPES) do
        if missingOfferings[recipe.itemID] then
            local requirements = GetIngredientRequirements(recipe.ingredients)
            local canMakeRecipe = true
            for itemID, requiredCount in pairs(requirements) do
                if (availableCounts[itemID] or 0) < requiredCount or
                    (alreadySelected[itemID] or 0) > requiredCount then
                    canMakeRecipe = false
                    break
                end
            end

            if canMakeRecipe then
                for _, itemID in ipairs(recipe.ingredients) do
                    if (alreadySelected[itemID] or 0) < (requirements[itemID] or 0) then
                        local candidate = FindCandidateForIngredient(candidates, itemID)
                        if candidate then
                            return candidate, recipe
                        end
                    end
                end
            end
        end
    end

    return nil
end

local function ChooseIngredientCandidate(candidates)
    local achievementCandidate, recipe = ChooseAchievementRecipe(candidates)
    if achievementCandidate then
        return achievementCandidate, recipe
    end

    local alreadySelected = GetIngredientRequirements(selectedIngredientIDs)
    for _, candidate in ipairs(candidates) do
        if candidate.itemID and not alreadySelected[candidate.itemID] then
            return candidate
        end
    end

    return candidates[1]
end

local function SelectNextOfiOption(options)
    if ofiGossipSelections >= REQUIRED_INGREDIENTS then
        return false
    end

    options = options or GetCurrentGossipOptions()
    local optionCount = options and #options or 0
    local optionIndex = 1
    local option, optionNameText, isIngredient = GetIngredientOptionInfo(options, optionIndex)
    local candidates = GetIngredientCandidates(options)
    local selectedCandidate, plannedRecipe = ChooseIngredientCandidate(candidates)
    if selectedCandidate then
        optionIndex = selectedCandidate.index
        option = selectedCandidate.option
        optionNameText = selectedCandidate.name
        isIngredient = true
    end

    local optionKey = GetIngredientOptionKey(option, optionNameText, optionIndex)
    local optionWasSelected = selectedIngredientOptions[optionKey]
    local ingredientID = isIngredient and GetIngredientIdentity(optionNameText)
    ingredientID = type(ingredientID) == "number" and ingredientID or nil

    Debug(
        "Gossip options=" .. optionCount ..
        ", chosenIndex=" .. optionIndex ..
        ", chosen=\"" .. optionNameText .. "\"" ..
        ", optionID=" .. SafeString(option and option.gossipOptionID) ..
        ", ingredient=" .. SafeString(isIngredient) ..
        ", recipe=" .. (plannedRecipe and plannedRecipe.name or "one-each/fallback") ..
        ", progress=" .. ofiGossipSelections .. "/" .. REQUIRED_INGREDIENTS
    )

    if option and option.gossipOptionID and C_GossipInfo.SelectOption then
        if isIngredient then
            ofiGossipSelections = ofiGossipSelections + 1
            selectedIngredientOptions[optionKey] = true
            if ingredientID then
                selectedIngredientIDs[#selectedIngredientIDs + 1] = ingredientID
            end
        end
        Debug("Selecting gossip option " .. optionIndex .. " via C_GossipInfo.SelectOption.")
        local ok, err = pcall(C_GossipInfo.SelectOption, option.gossipOptionID)
        if not ok then
            if isIngredient then
                ofiGossipSelections = ofiGossipSelections - 1
                if not optionWasSelected then
                    selectedIngredientOptions[optionKey] = nil
                end
                if ingredientID then
                    table.remove(selectedIngredientIDs)
                end
            end
            Print("Could not select Ofi's gossip option " .. optionIndex .. ": " .. tostring(err))
            return false
        end

        return true, isIngredient, optionNameText, optionIndex, optionKey, optionWasSelected, ingredientID
    end

    if GossipFrame and GossipFrame.SelectGossipOption then
        if isIngredient then
            ofiGossipSelections = ofiGossipSelections + 1
            selectedIngredientOptions[optionKey] = true
            if ingredientID then
                selectedIngredientIDs[#selectedIngredientIDs + 1] = ingredientID
            end
        end
        Debug("Selecting gossip option " .. optionIndex .. " via the legacy GossipFrame API.")
        local ok, err = pcall(GossipFrame.SelectGossipOption, GossipFrame, optionIndex)
        if not ok then
            if isIngredient then
                ofiGossipSelections = ofiGossipSelections - 1
                if not optionWasSelected then
                    selectedIngredientOptions[optionKey] = nil
                end
                if ingredientID then
                    table.remove(selectedIngredientIDs)
                end
            end
            Print("Could not select Ofi's gossip option " .. optionIndex .. ": " .. tostring(err))
            return false
        end

        return true, isIngredient, optionNameText, optionIndex, optionKey, optionWasSelected, ingredientID
    end

    return false
end

local function AdvanceAfterFinalIngredient(reason)
    offeringTransitionToken = offeringTransitionToken + 1
    local transitionToken = offeringTransitionToken
    Debug("Third ingredient confirmed by " .. reason .. ". Waiting for Mysterious Offering to spawn.")
    C_Timer.After(0.75, function()
        if transitionToken ~= offeringTransitionToken then
            return
        end
        if db.enabled and state == STATE.INTERACT_OFI and
            ofiGossipSelections >= REQUIRED_INGREDIENTS then
            SetState(STATE.TARGET_OFFERING)
        end
    end)
end

local function RollBackPendingIngredient(selection)
    if not selection or not selection.isIngredient then
        return
    end

    ofiGossipSelections = selection.progressBefore
    if not selection.optionWasSelected then
        selectedIngredientOptions[selection.optionKey] = nil
    end
    if selection.ingredientID then
        table.remove(selectedIngredientIDs)
    end
    Debug(
        "Ingredient selection was not confirmed; rolled progress back to " ..
        ofiGossipSelections .. "/" .. REQUIRED_INGREDIENTS .. "."
    )
end

local function ScheduleGossipContinuation(
    pageSignature,
    optionName,
    isIngredient,
    optionKey,
    optionWasSelected,
    ingredientID
)
    if gossipAttemptPageSignature == pageSignature then
        gossipPageAttempts = gossipPageAttempts + 1
    else
        gossipAttemptPageSignature = pageSignature
        gossipPageAttempts = 1
    end

    gossipTransitionToken = gossipTransitionToken + 1
    local transitionToken = gossipTransitionToken
    local selection = {
        pageSignature = pageSignature,
        optionName = optionName,
        isIngredient = isIngredient,
        optionKey = optionKey,
        optionWasSelected = optionWasSelected,
        ingredientID = ingredientID,
        progressBefore = isIngredient and (ofiGossipSelections - 1) or ofiGossipSelections,
    }
    pendingGossipSelection = selection

    C_Timer.After(0.35, function()
        if transitionToken ~= gossipTransitionToken or state ~= STATE.INTERACT_OFI then
            return
        end

        pendingGossipSelection = nil
        if not HasOpenOfiGossip() then
            return
        end

        local currentSignature = GetGossipPageSignature(GetCurrentGossipOptions())
        if currentSignature == pageSignature then
            RollBackPendingIngredient(selection)
            if gossipPageAttempts >= MAX_GOSSIP_PAGE_ATTEMPTS then
                local failedAttempts = gossipPageAttempts
                gossipAttemptPageSignature = nil
                gossipPageAttempts = 0
                inputLocked = false
                ApplyBinding()
                Print(
                    "Ofi's page did not advance after " .. failedAttempts ..
                    " attempts. Interact with Ofi or click the gossip option once, then press " .. GetConfiguredKeyLabel() .. "."
                )
                UpdateStatus("gossip retry needed")
                Debug("Stopped retrying unchanged gossip page after option \"" .. optionName .. "\".")
                return
            end

            Debug(
                "No GOSSIP_SHOW or page change after option \"" .. optionName ..
                "\"; retrying unchanged page (attempt " .. (gossipPageAttempts + 1) ..
                "/" .. MAX_GOSSIP_PAGE_ATTEMPTS .. ")."
            )
        else
            Debug("Gossip options changed without GOSSIP_SHOW; resuming automation.")
            if selection.isIngredient and ofiGossipSelections >= REQUIRED_INGREDIENTS then
                AdvanceAfterFinalIngredient("a gossip page change")
                return
            end
        end
        HandleGossipShow()
    end)
end

HandleGossipShow = function()
    Debug(
        "GOSSIP_SHOW: state=" .. state ..
        ", questOnLog=" .. SafeString(IsQuestOnLog()) ..
        ", ingredientProgress=" .. ofiGossipSelections .. "/" .. REQUIRED_INGREDIENTS
    )
    if not db.enabled or state ~= STATE.INTERACT_OFI then
        return
    end

    if not IsOfiContext() and not HasOpenOfiGossip() then
        return
    end

    if not inputLocked then
        inputLocked = true
        ApplyBinding()
        Debug("F12 locked to a no-op while Ofi's gossip is automated.")
    end

    local availableQuests
    if C_GossipInfo and C_GossipInfo.GetAvailableQuests then
        availableQuests = C_GossipInfo.GetAvailableQuests()
    end

    if availableQuests and C_GossipInfo.SelectAvailableQuest then
        local availableQuest = FindMixingQuest(availableQuests)
        if availableQuest then
            if questSelectionPending or questAcceptPending then
                UpdateStatus(questAcceptPending and "accepting Mixing Mysteries" or "opening Mixing Mysteries")
                Debug("Ignoring duplicate available-quest page while quest processing is pending.")
                return
            end

            questSelectionPending = true
            Debug(
                "Selecting available quest: title=\"" .. SafeString(availableQuest.title) ..
                "\", questID=" .. SafeString(availableQuest.questID)
            )
            C_GossipInfo.SelectAvailableQuest(availableQuest.questID)
            return
        end
    end

    if not IsQuestOnLog() then
        if questAcceptPending then
            UpdateStatus("accepting Mixing Mysteries")
            Debug("Quest acceptance is pending; waiting for QUEST_ACCEPTED.")
            return
        elseif questSelectionPending then
            UpdateStatus("opening Mixing Mysteries")
            Debug("Quest selection is pending; waiting for QUEST_DETAIL.")
            return
        end

        Print("Mixing Mysteries is not accepted yet. Select the quest in Ofi's window, then press " .. GetConfiguredKeyLabel() .. ".")
        UpdateStatus("accept Mixing Mysteries")
        return
    end

    local hasEnoughReagents = UpdateReagentStatus(true)
    if not hasEnoughReagents then
        UpdateStatus("not enough reagents")
        Debug(
            "Paused gossip automation because the bags do not contain enough reagents for the remaining mix."
        )
        return
    end

    local options = GetCurrentGossipOptions()
    local pageSignature = GetGossipPageSignature(options)
    if pendingGossipSelection then
        if pageSignature == pendingGossipSelection.pageSignature then
            Debug("Ignoring duplicate GOSSIP_SHOW while the selected gossip page is still pending.")
            return
        end

        local completedSelection = pendingGossipSelection
        pendingGossipSelection = nil
        gossipTransitionToken = gossipTransitionToken + 1
        Debug("Gossip page changed; continuing the serialized selection sequence.")
        if completedSelection.isIngredient and ofiGossipSelections >= REQUIRED_INGREDIENTS then
            AdvanceAfterFinalIngredient("GOSSIP_SHOW")
            return
        end
    end

    local selected, isIngredient, optionName, optionIndex, optionKey, optionWasSelected, ingredientID =
        SelectNextOfiOption(options)
    if selected then
        ScheduleGossipContinuation(
            pageSignature,
            optionName,
            isIngredient,
            optionKey,
            optionWasSelected,
            ingredientID
        )
        if not isIngredient then
            UpdateStatus("opening ingredient list")
            Debug(
                "Preparatory option " .. optionIndex .. " selected: \"" .. optionName ..
                "\". Waiting for the next GOSSIP_SHOW."
            )
        elseif ofiGossipSelections >= REQUIRED_INGREDIENTS then
            UpdateStatus("confirming 3/3")
            Debug("Third ingredient submitted. Waiting for the gossip page to confirm it.")
        else
            UpdateStatus("mixing " .. ofiGossipSelections .. "/" .. REQUIRED_INGREDIENTS)
            Debug("Ingredient selected. Waiting for the next GOSSIP_SHOW before continuing.")
        end
    else
        Print("Ofi has no selectable gossip option. Finish the dialog manually, or type /mmh reset.")
        UpdateStatus("gossip needs input")
    end
end

local function FinalizeQuestAcceptance(questID, source)
    if not questID or not IsMixingQuestID(questID) then
        return false
    end

    questAcceptanceToken = questAcceptanceToken + 1
    activeQuestID = questID
    questSelectionPending = false
    questAcceptPending = false
    ResetMixProgress()
    inputLocked = true
    Debug("Quest acceptance finalized via " .. source .. ": questID=" .. questID .. ".")
    SetState(STATE.INTERACT_OFI)
    C_Timer.After(0, function()
        if state ~= STATE.INTERACT_OFI then
            return
        end

        if HasOpenOfiGossip() then
            HandleGossipShow()
        else
            ReleaseInputLockIfIdle("quest accepted after Ofi's gossip closed")
        end
    end)
    C_Timer.After(0.5, function()
        ReleaseInputLockIfIdle("post-accept safety check")
    end)
    return true
end

local function ScheduleQuestAcceptanceWatchdog()
    questAcceptanceToken = questAcceptanceToken + 1
    local acceptanceToken = questAcceptanceToken

    C_Timer.After(0.35, function()
        if acceptanceToken ~= questAcceptanceToken or not questAcceptPending then
            return
        end

        local questID = GetMixingQuestOnLog()
        if questID then
            Debug("QUEST_ACCEPTED was missing, but the watchdog found the quest on the log.")
            FinalizeQuestAcceptance(questID, "quest-log watchdog")
        end
    end)

    C_Timer.After(1.25, function()
        if acceptanceToken ~= questAcceptanceToken or not questAcceptPending then
            return
        end

        local questID = GetMixingQuestOnLog()
        if questID then
            Debug("Late quest-log update recovered the missing QUEST_ACCEPTED event.")
            FinalizeQuestAcceptance(questID, "late quest-log watchdog")
            return
        end

        questAcceptanceToken = questAcceptanceToken + 1
        questSelectionPending = false
        questAcceptPending = false
        if state == STATE.INTERACT_OFI then
            inputLocked = false
            ApplyBinding()
            UpdateStatus("retry quest acceptance")
        end
        Print("Quest acceptance was interrupted. Press " .. GetConfiguredKeyLabel() .. " to interact with Ofi and retry.")
        Debug("Acceptance watchdog cleared the stale pending state and restored F12.")
    end)
end

local function HandleQuestDetail()
    local questID = GetCurrentQuestID()
    Debug("QUEST_DETAIL: questID=" .. SafeString(questID))
    if not db.enabled or not IsMixingQuestID(questID) then
        return
    end

    questSelectionPending = false
    if questAcceptPending then
        Debug("Ignoring duplicate QUEST_DETAIL while acceptance is already pending.")
        return
    end

    activeQuestID = questID
    if AcceptQuest then
        questAcceptPending = true
        ResetMixProgress()
        Debug("Accepting Mixing Mysteries and resetting ingredient progress to 0/3.")
        AcceptQuest()
        SetState(STATE.INTERACT_OFI)
        ScheduleQuestAcceptanceWatchdog()
    end
end

local function HandleQuestProgress()
    local questID = GetCurrentQuestID()
    Debug("QUEST_PROGRESS: questID=" .. SafeString(questID))
    if not db.enabled or not IsMixingQuestID(questID) then
        return
    end

    activeQuestID = questID
    if IsQuestCompletable and IsQuestCompletable() and CompleteQuest then
        CompleteQuest()
    end
end

local function HandleQuestComplete()
    local questID = GetCurrentQuestID()
    Debug("QUEST_COMPLETE: questID=" .. SafeString(questID))
    if not db.enabled or not IsMixingQuestID(questID) then
        return
    end

    activeQuestID = questID
    local choices = GetNumQuestChoices and GetNumQuestChoices() or 0
    if choices <= 1 and GetQuestReward then
        if choices == 1 then
            GetQuestReward(1)
        else
            GetQuestReward()
        end
    else
        UpdateStatus("choose a reward")
    end
end

local function HandleQuestFinished()
    if state == STATE.INTERACT_OFFERING and not IsQuestOnLog() then
        SetState(STATE.TARGET_OFI)
    end
end

local function HandleTargetChanged()
    if UnitMatches("target", db.offeringName) and IsQuestOnLog() then
        SetState(STATE.INTERACT_OFFERING)
        return
    end

    if UnitMatches("target", db.ofiName) and state == STATE.TARGET_OFI then
        SetState(STATE.INTERACT_OFI)
        return
    end

    -- The player may clear Ofi or select another unit between presses. The
    -- interaction binding would be a no-op (or affect that other unit), so
    -- immediately return to the safe target step unless Ofi's gossip is open.
    if state == STATE.INTERACT_OFI and not HasLiveOfiGossip() and
        not UnitMatches("target", db.ofiName) then
        SetState(STATE.TARGET_OFI)
        return
    end

    if state == STATE.INTERACT_OFFERING and not UnitMatches("target", db.offeringName) then
        if IsMixingQuestComplete() then
            SetState(STATE.TARGET_OFFERING)
        else
            SetState(STATE.TARGET_OFI)
        end
    end
end

local function RecoverSequenceFromQuestLog(reason, fullRecovery)
    if not db or not db.enabled then
        return
    end

    local questID = GetMixingQuestOnLog()
    local questComplete = IsMixingQuestComplete()
    Debug(
        "Quest-state recovery: reason=" .. reason ..
        ", questID=" .. SafeString(questID) ..
        ", complete=" .. SafeString(questComplete) ..
        ", full=" .. SafeString(fullRecovery) ..
        ", currentState=" .. state
    )

    if questComplete then
        if state == STATE.INTERACT_OFI and ofiGossipSelections >= REQUIRED_INGREDIENTS then
            -- The final gossip event and quest-log event can arrive in either
            -- order. Let the single final-transition timer own this handoff.
            return
        end
        local desiredState = (UnitMatches("target", db.offeringName) or
            (state == STATE.INTERACT_OFFERING and UnitExists("target"))) and
            STATE.INTERACT_OFFERING or STATE.TARGET_OFFERING
        if state ~= desiredState then
            ResetMixProgress()
            ofiGossipSelections = REQUIRED_INGREDIENTS
            questSelectionPending = false
            questAcceptPending = false
            inputLocked = false
            SetState(desiredState)
            Print(
                "Mixing Mysteries is ready for turn-in; resumed at " ..
                (desiredState == STATE.INTERACT_OFFERING and
                    "Interact with Mysterious Offering." or "Target Mysterious Offering.")
            )
        end
        return
    end

    if not fullRecovery then
        return
    end

    ResetMixProgress()
    questSelectionPending = false
    questAcceptPending = false
    inputLocked = false

    -- The quest log only distinguishes an incomplete mix from a completed
    -- one. The current target and gossip unit supply the missing part of the
    -- sequence when the addon begins after the player has already accepted
    -- the quest or advanced it manually.
    local desiredState = STATE.TARGET_OFI
    if UnitMatches("target", db.offeringName) then
        desiredState = STATE.INTERACT_OFFERING
    elseif UnitMatches("target", db.ofiName) or HasLiveOfiGossip() then
        desiredState = STATE.INTERACT_OFI
    end

    SetState(desiredState)

    -- GOSSIP_SHOW may have fired before an addon was enabled or reloaded. In
    -- that case, resume from the visible Ofi dialog without requiring the
    -- player to close and reopen it.
    if desiredState == STATE.INTERACT_OFI and HasLiveOfiGossip() then
        C_Timer.After(0, function()
            if state == STATE.INTERACT_OFI and HasLiveOfiGossip() then
                HandleGossipShow()
            end
        end)
    end
end

ScheduleQuestStateRecovery = function(reason, fullRecovery)
    pendingFullQuestRecovery = pendingFullQuestRecovery or fullRecovery
    questRecoveryToken = questRecoveryToken + 1
    local recoveryToken = questRecoveryToken

    C_Timer.After(0.15, function()
        if recoveryToken ~= questRecoveryToken then
            return
        end

        local runFullRecovery = pendingFullQuestRecovery
        pendingFullQuestRecovery = false
        RecoverSequenceFromQuestLog(reason, runFullRecovery)
    end)
end

local function SetEnabled(enabled)
    db.enabled = enabled
    if enabled then
        RefreshOfiProximity(false)
        SetState(STATE.TARGET_OFI)
        ScheduleQuestStateRecovery("addon enabled", true)
        Print("Enabled on " .. GetConfiguredKeyLabel() .. ".")
    else
        ApplyBinding()
        Print("Disabled; " .. GetConfiguredKeyLabel() .. " was restored to its normal binding.")
    end
    UpdateStatus()
end

local function CreateSettingsPanel()
    if not Settings or not Settings.RegisterCanvasLayoutCategory then
        return
    end

    local panel = CreateFrame("Frame")
    panel:SetSize(480, 245)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Mixing Mysteries Helper")

    local function AddCheckbox(y, label, getValue, setValue)
        local checkbox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        checkbox:SetPoint("TOPLEFT", 18, y)
        checkbox:SetSize(24, 24)

        local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        text:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
        text:SetText(label)

        checkbox:SetScript("OnClick", function(self)
            setValue(self:GetChecked() and true or false)
        end)

        return checkbox, getValue
    end

    local enabledCheckbox, getEnabled = AddCheckbox(
        -52,
        "Enable Mixing Mysteries Helper",
        function() return db.enabled end,
        SetEnabled
    )
    local manualVisibilityCheckbox, getManualVisibility = AddCheckbox(
        -82,
        "Show the helper window",
        IsHelperWindowEnabled,
        SetHelperWindowVisible
    )
    settingsManualVisibilityCheckbox = manualVisibilityCheckbox
    local proximityCheckbox, getProximityVisible = AddCheckbox(
        -112,
        "Show the helper window automatically when you are near Ofi the Sly.",
        function() return db.showStatus end,
        function(value)
            db.showStatus = value
            if value then
                manualStatusVisible = true
            end
            RefreshOfiProximity(true)
            SyncWindowVisibilityCheckboxes()
        end
    )
    settingsProximityCheckbox = proximityCheckbox

    local minimapCheckbox, getMinimapVisible = AddCheckbox(
        -142,
        "Show the minimap button",
        function() return db.showMinimapButton end,
        function(value)
            db.showMinimapButton = value
            UpdateMinimapButtonVisibility()
        end
    )

    local keyBindingsButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    keyBindingsButton:SetSize(110, 22)
    keyBindingsButton:SetPoint("TOPLEFT", 18, -178)
    keyBindingsButton:SetText("Key bindings")
    keyBindingsButton:SetScript("OnClick", OpenKeyBindings)

    panel:SetScript("OnShow", function()
        enabledCheckbox:SetChecked(getEnabled())
        minimapCheckbox:SetChecked(getMinimapVisible())
        proximityCheckbox:SetChecked(getProximityVisible())
        manualVisibilityCheckbox:SetChecked(getManualVisibility())
    end)

    local category = Settings.RegisterCanvasLayoutCategory(panel, "Mixing Mysteries Helper")
    Settings.RegisterAddOnCategory(category)
    settingsCategoryID = category:GetID()
end

local function SetConfiguredName(field, value, label)
    value = CleanName(value)
    if value == "" then
        Print(label .. " name cannot be empty.")
        return
    end

    db[field] = value
    UpdateTargetMacros()
    ApplyBinding()
    RefreshOfiProximity(true)
    Print(label .. " target set to " .. value .. ".")
end

local function PrintHelp()
    Print("Commands:")
    Print("  /mmh on | off - enable or disable the helper")
    Print("  /mmh reset - restart at Target Ofi")
    Print("  /mmh sync - rebuild the current step from the quest log")
    Print("  Configure the helper in Options > Key Bindings > AddOns")
    Print("  /mmh show | hide - enable or hide the proximity-based status panel")
    Print("  /mmh ofi <name> - change Ofi's localized name")
    Print("  /mmh offering <name> - change the offering's localized name")
    Print("  Ingredient choice prioritizes missing Mysterious Mix Master variants, then one of each reagent.")
    Print("  /mmh debug on | off - toggle detailed chat diagnostics")
end

local function HandleSlashCommand(message)
    local command, argument = tostring(message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()

    if command == "on" then
        SetEnabled(true)
    elseif command == "off" then
        SetEnabled(false)
    elseif command == "reset" then
        ResetMixProgress()
        questSelectionPending = false
        questAcceptPending = false
        inputLocked = false
        SetState(STATE.TARGET_OFI)
        Print("Sequence reset.")
    elseif command == "sync" then
        ScheduleQuestStateRecovery("manual /mmh sync", true)
        Print("Quest-state synchronization scheduled.")
    elseif command == "key" then
        Print("Configure the helper in Options > Key Bindings > AddOns.")
    elseif command == "show" then
        manualStatusVisible = nil
        db.showStatus = true
        RefreshOfiProximity(true)
        SyncWindowVisibilityCheckboxes()
    elseif command == "hide" then
        manualStatusVisible = false
        db.showStatus = false
        UpdateStatus()
        SyncWindowVisibilityCheckboxes()
    elseif command == "ofi" then
        SetConfiguredName("ofiName", argument, "Ofi")
    elseif command == "offering" then
        SetConfiguredName("offeringName", argument, "Offering")
    elseif command == "mix" then
        Print("Mixing is automatic: missing achievement variants, then one of each reagent, then any available reagent.")
    elseif command == "debug" then
        local debugValue = argument:lower()
        if debugValue == "on" then
            db.debug = true
            Print("Debug chat enabled.")
        elseif debugValue == "off" then
            db.debug = false
            Print("Debug chat disabled.")
        else
            Print("Debug chat is " .. (db.debug and "enabled" or "disabled") .. ". Use /mmh debug on or off.")
        end
    elseif command == "status" then
        local enabledText = db.enabled and "Enabled" or "Disabled"
        local _, _, _, reagentTotal, reagentNeeded = GetReagentReadiness()
        Print(
            enabledText .. " on " .. GetConfiguredKeyLabel() ..
            "; mixing=achievement priority" ..
            "; input=" .. (inputLocked and "locked" or "active") ..
            "; reagents=" .. reagentTotal .. "/" .. reagentNeeded ..
            "; rewards=" .. rewardTotalCount .. " in " .. rewardVariantCount .. " variants" ..
            "; next: " .. (STEP_TEXT[state] or state) .. "."
        )
    else
        PrintHelp()
    end
end

local function Initialize()
    ClearOverrideBindings(bindingOwner)
    MixingMysteriesHelperDB = MixingMysteriesHelperDB or {}
    db = MixingMysteriesHelperDB
    CopyDefaults(db, DEFAULTS)

    db.showControls = nil
    db.key = nil
    db.configVersion = DEFAULTS.configVersion
    manualStatusVisible = true

    db.ofiName = CleanName(db.ofiName)
    db.offeringName = CleanName(db.offeringName)
    if db.mixPreference ~= "balanced" and db.mixPreference ~= "first" then
        db.mixPreference = DEFAULTS.mixPreference
    end

    CreateStatusFrame()
    CreateMinimapButton()
    CreateSettingsPanel()
    UpdateAchievementStatus()
    RemoveLegacyActionMacro()
    db.rewardItemID = nil
    UpdateRewardButton()
    CreateTargetButtons()
    UpdateTargetMacros()

    SLASH_MIXINGMYSTERIESHELPER1 = "/mmh"
    SLASH_MIXINGMYSTERIESHELPER2 = "/mixingmysteries"
    SlashCmdList.MIXINGMYSTERIESHELPER = HandleSlashCommand

    ApplyBinding()
    UpdateReagentStatus(true)
    RefreshOfiProximity(true)
    ScheduleQuestStateRecovery("addon initialization", true)
    Print(
        "Loaded. Configure Mixing Mysteries Helper in Options > Key Bindings > AddOns."
    )
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == ADDON_NAME then
            Initialize()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateAchievementStatus()
        RefreshOfiProximity(true)
        ScheduleQuestStateRecovery("PLAYER_ENTERING_WORLD", true)
    elseif event == "UPDATE_BINDINGS" then
        ApplyBinding()
    elseif event == "ACHIEVEMENT_EARNED" then
        local achievementID = ...
        if achievementID == MIX_MASTER_ACHIEVEMENT_ID then
            UpdateAchievementStatus()
        end
    elseif event == "QUEST_LOG_UPDATE" then
        ScheduleQuestStateRecovery("QUEST_LOG_UPDATE", false)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingLegacyMacroRemoval then
            RemoveLegacyActionMacro()
        end
        if pendingBinding then
            UpdateTargetMacros()
            ApplyBinding()
        end
        if pendingRewardUpdate then
            UpdateRewardButton()
        end
    elseif event == "GOSSIP_SHOW" then
        RefreshOfiProximity(false)
        HandleGossipShow()
    elseif event == "GOSSIP_CLOSED" then
        RefreshOfiProximity(false)
        Debug("GOSSIP_CLOSED: state=" .. state .. ", ingredientProgress=" .. ofiGossipSelections .. "/3")
        local completedSelection = pendingGossipSelection
        pendingGossipSelection = nil
        gossipTransitionToken = gossipTransitionToken + 1
        if completedSelection and completedSelection.isIngredient and
            ofiGossipSelections >= REQUIRED_INGREDIENTS then
            AdvanceAfterFinalIngredient("GOSSIP_CLOSED")
        end
        ScheduleQuestStateRecovery("GOSSIP_CLOSED", false)
        C_Timer.After(0.4, function()
            ReleaseInputLockIfIdle("Ofi's gossip remained closed")
        end)
    elseif event == "QUEST_DETAIL" then
        HandleQuestDetail()
    elseif event == "QUEST_ACCEPTED" then
        local firstArgument, secondArgument = ...
        local questID = secondArgument or firstArgument
        Debug("QUEST_ACCEPTED: questID=" .. SafeString(questID))
        if db.enabled and IsMixingQuestID(questID) then
            FinalizeQuestAcceptance(questID, "QUEST_ACCEPTED")
        end
    elseif event == "QUEST_PROGRESS" then
        HandleQuestProgress()
    elseif event == "QUEST_COMPLETE" then
        HandleQuestComplete()
    elseif event == "QUEST_TURNED_IN" then
        local questID = ...
        Debug("QUEST_TURNED_IN: questID=" .. SafeString(questID))
        if db.enabled and IsMixingQuestID(questID) then
            activeQuestID = questID
            SetState(STATE.TARGET_OFI)
        end
    elseif event == "QUEST_FINISHED" then
        Debug("QUEST_FINISHED: state=" .. state)
        HandleQuestFinished()
    elseif event == "LOOT_READY" then
        Debug("LOOT_READY: state=" .. state)
        if state == STATE.INTERACT_OFFERING or GetTime() <= rewardCaptureDeadline then
            rewardCaptureDeadline = GetTime() + 8
        end
        if db.enabled and state == STATE.INTERACT_OFFERING then
            SetState(STATE.TARGET_OFI)
        end
    elseif event == "CHAT_MSG_LOOT" then
        CaptureRewardFromLoot(...)
    elseif event == "BAG_UPDATE_DELAYED" then
        UpdateRewardButton()
        local hasEnoughReagents = UpdateReagentStatus(true)
        if hasEnoughReagents and db.enabled and state == STATE.INTERACT_OFI and HasOpenOfiGossip() then
            C_Timer.After(0, HandleGossipShow)
        end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local itemID = ...
        if OFFERING_ITEM_ID_SET[itemID] then
            UpdateRewardButton()
        end
        if INGREDIENT_ITEM_ID_SET[itemID] then
            UpdateReagentStatus(false)
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        HandleTargetChanged()
        RefreshOfiProximity(false)
    elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" or
        event == "UPDATE_MOUSEOVER_UNIT" then
        RefreshOfiProximity(false)
    end
end)

eventFrame:SetScript("OnUpdate", function(_, elapsed)
    if not db or not db.enabled or not db.showStatus then
        return
    end

    proximityElapsed = proximityElapsed + elapsed
    if proximityElapsed < PROXIMITY_UPDATE_INTERVAL then
        return
    end

    proximityElapsed = 0
    RefreshOfiProximity(false)
end)

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UPDATE_BINDINGS")
eventFrame:RegisterEvent("ACHIEVEMENT_EARNED")
eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("GOSSIP_SHOW")
eventFrame:RegisterEvent("GOSSIP_CLOSED")
eventFrame:RegisterEvent("QUEST_DETAIL")
eventFrame:RegisterEvent("QUEST_ACCEPTED")
eventFrame:RegisterEvent("QUEST_PROGRESS")
eventFrame:RegisterEvent("QUEST_COMPLETE")
eventFrame:RegisterEvent("QUEST_TURNED_IN")
eventFrame:RegisterEvent("QUEST_FINISHED")
eventFrame:RegisterEvent("LOOT_READY")
eventFrame:RegisterEvent("CHAT_MSG_LOOT")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
eventFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
