-- Bagshui Bags Inventory Class Instance
-- Exposes: Bagshui.components.Bags [via Inventory:New()]

Bagshui:AddComponent(function()


-- Create class instance.
local Bags = Bagshui.prototypes.Inventory:New(BS_INVENTORY_TYPE.BAGS)


-- Hook handling.
--
-- These replace the global WoW API functions directly (like Bagnon/AdiBags),
-- so the original never runs and native ContainerFrames never open.
-- This avoids taint: our uiFrame:Show()/Hide() calls are never preceded by
-- any protected-frame method call, so they work in combat lockdown too.
-- CloseBackpack/CloseBag are intentionally not hooked (ElvUI calls them as
-- side effects, which would immediately close Bagshui).

--- Open bag hooks (OpenAllBags, OpenBackpack, OpenBag(bagNum)).
---@param hookFunctionName string Name of the original WoW API function.
---@param bagNumParam number Container ID.
function Bags:OpenBag(hookFunctionName, bagNumParam)
	self:OpenCloseToggle(BS_INVENTORY_UI_VISIBILITY_ACTION.OPEN, hookFunctionName, bagNumParam)
end

--- Close bag hooks (CloseBackpack, CloseBag(bagNum)).
---@param hookFunctionName string Name of the original WoW API function.
---@param bagNumParam number Container ID.
function Bags:CloseBag(hookFunctionName, bagNumParam)
	self:OpenCloseToggle(BS_INVENTORY_UI_VISIBILITY_ACTION.CLOSE, hookFunctionName, bagNumParam, self:OriginalContainerFrameVisible(bagNumParam))
end

--- Toggle bag hooks (ToggleBackpack, ToggleBag(bagNum)).
---@param hookFunctionName string Name of the original WoW API function.
---@param bagNumParam number Container ID.
function Bags:ToggleBag(hookFunctionName, bagNumParam)
	self:OpenCloseToggle(BS_INVENTORY_UI_VISIBILITY_ACTION.TOGGLE, hookFunctionName, bagNumParam, self:OriginalContainerFrameVisible(bagNumParam))
end




--- Register additional events and properties to make bag slot buttons "just work" with Blizzard code.
---@param bagSlotButton table Bag slot button instance.
function Bags:BagSlotButton_Init(bagSlotButton)

	bagSlotButton:RegisterEvent("BAG_UPDATE")
	bagSlotButton.isBag = 1  -- We're not relying too much on PaperDollItemSlotButton, but let's set this just to be safe.

	local oldOnClick = bagSlotButton:GetScript("OnClick")
	--- If there was an item in the cursor when the slot was clicked, catch it and prevent the original
	--- from being called, since since PaperDollItemSlotButton will interpret that as trying to *equip*
	--- the item in that slot, instead of trying to put it in the bag. Note that bags in the cursor are
	--- passed through so native bag swapping can be invoked.
	bagSlotButton:SetScript("OnClick", function(self)
		if
			-- Pass through to the default Bagshui OnClick for bags
			-- so native bag swapping can be invoked.
			(
				_G.CursorHasItem()
				and BsItemInfo:IsContainer(Bagshui.cursorItem)
			)
		then
			oldOnClick(self)
		elseif _G.CursorHasItem() and not BsItemInfo:IsContainer(Bagshui.cursorItem) then
			-- Place cursor item into the bag slot (WotLK: PutItemInBag removed, use PickupInventoryItem).
			_G.PickupInventoryItem(self.bagshuiData.inventorySlotId)
		else
			oldOnClick(self)
		end
--- Suppress ElvUI bag module interference.
--- When ElvUI bags are enabled, ElvUI installs SecureHook post-hooks on the bag
--- toggle globals (OpenAllBags, ToggleBag, ToggleBackpack, etc.) that Bagshui has
--- replaced. Those post-hooks call B:ToggleBackpack() / B:ToggleBags() / B:OpenBags()
--- which show/update ElvUI's BagFrame redundantly, causing performance issues
--- (especially when combined with Auctionator's tooltip hooks).
--- We neutralize ElvUI's bag toggle handlers and hide its bag frame so only
--- Bagshui manages bag visibility.
function Bags:SuppressElvUIBags()
	local E = _G.ElvUI and _G.ElvUI[1]
	if not E then return end
	local B = E:GetModule("Bags", true)
	if not B or not B.Initialized then return end

	-- Replace ElvUI's toggle/open/close bag functions with no-ops so its
	-- SecureHook post-hooks do nothing.
	local noop = function() end
	B.ToggleBackpack = noop
	B.ToggleBags = noop
	B.OpenBags = noop
	B.CloseBags = noop

	-- Hide ElvUI's bag frame if it exists.
	if B.BagFrame and B.BagFrame:IsShown() then
		B.BagFrame:Hide()
	end

	Bagshui:PrintDebug("ElvUI bag module suppressed")
end

end)
end



--- Override Inventory:UpdateBagBar() and Inventory:UiFrame_OnHide() so we can correctly set the
--- highlight state of the Blizzard action bar bag slot buttons when our window opens/closes/updates.
function Bags:UpdateBagBar()
	self._super.UpdateBagBar(self)
	-- Don't update action bar bag slot buttons until the next update tick.
	-- This avoids having the Blizzard UI code immediately turn off the checked state.
	Bagshui:QueueClassCallback(self, self.UpdateActionBarBagSlotButtonState)
end


--- Ensure the Blizzard action bar bag buttons are un-highlighted when the Bags window is closed.
function Bags:UiFrame_OnHide()
	self._super.UiFrame_OnHide(self)
	-- It's safe to instantly un-highlight the action bar bag buttons when the window is closed.
	self:UpdateActionBarBagSlotButtonState()
end



Bags._actionBarButtonWasChecked = {}
--- Set Blizzard action bar bag slot buttons to "checked" (highlighted) when our
--- window is open and unchecked when it's closed.
function Bags:UpdateActionBarBagSlotButtonState()

	local shouldBeChecked = self:Visible()
	local actionBarButtonName, actionBarButton

	for _, bagNum in pairs(self.containerIds) do
		local hookEnabled = self:GetHookEnabled("Bag", bagNum)
		-- Only highlight bags in the action bar that we're hooking.
		if
			(hookEnabled or self._actionBarButtonWasChecked[bagNum])
			and type(self.currentCharacterInventory[bagNum]) == "table"
		then
			if bagNum == 0 then
				actionBarButtonName = "MainMenuBarBackpackButton"
			else
				actionBarButtonName = string.format("CharacterBag%dSlot", bagNum + self.bagSlotNameNumberOffset)
			end
			actionBarButton = _G[actionBarButtonName]
			-- Avoid messing with the highlight state when the original container frame is open.
			if actionBarButton and not self:OriginalContainerFrameVisible(bagNum) then
				actionBarButton:SetChecked(
					shouldBeChecked
					and hookEnabled
					-- Only highlight buttons where there are bags.
					and (table.getn(self.currentCharacterInventory[bagNum]) > 0)
				)
				self._actionBarButtonWasChecked[bagNum] = hookEnabled
			end
		end
	end
end



--- Helper to determine when when one of the Blizzard bag frames is open.
---@param bagNum any
---@return boolean frameVisible
function Bags:OriginalContainerFrameVisible(bagNum)
	if not bagNum then
		return false
	end
	return self.ui:IsFrameVisible("ContainerFrame" .. tostring(bagNum))
end



--- Execute `self:Open()/Close()` and the superclass version only if there isn't a reason to block it.
---@param action "Open"|"Close"
---@return boolean? # false if event was blocked.
function Bags:SmartOpenClose(action)

	-- Block based on settings.
	if
		type(_G.event) == "string"
		and (
			(string.find(_G.event, "^AUCTION_HOUSE_") and self.settings.toggleBagsWithAuctionHouse == false)
			or
			(string.find(_G.event, "^BANKFRAME_") and self.settings.toggleBagsWithBankFrame == false)
			or
			(string.find(_G.event, "^MAIL_") and self.settings.toggleBagsWithMailFrame == false)
			or
			(string.find(_G.event, "^TRADE_") and self.settings.toggleBagsWithTradeFrame == false)
		)
	then
		return
	end

	-- Proceed with action.
	self._super[action](self)
end

--- Add intelligence to Open().
function Bags:Open()
	self:SmartOpenClose("Open")
end

--- Add intelligence to Close().
function Bags:Close()
	self:SmartOpenClose("Close")
	self.lastOpenEventTrigger = nil
end


--- Override Init to suppress ElvUI bags after Bagshui hooks are installed.
function Bags:Init()
	self._super.Init(self)
	-- Defer by one frame so ElvUI's module has finished initializing.
	local suppressFrame = _G.CreateFrame("Frame")
	suppressFrame:SetScript("OnUpdate", function()
		suppressFrame:SetScript("OnUpdate", nil)
		self:SuppressElvUIBags()
	end)
end


--- Suppress ElvUI bag module interference.
--- When ElvUI bags are enabled, ElvUI installs SecureHook post-hooks on the bag
--- toggle globals (OpenAllBags, ToggleBag, ToggleBackpack, etc.) that Bagshui has
--- replaced. Those post-hooks call B:ToggleBackpack() / B:ToggleBags() / B:OpenBags()
--- which show/update ElvUI's BagFrame redundantly, causing performance issues
--- (especially when combined with Auctionator's tooltip hooks).
--- We neutralize ElvUI's bag toggle handlers and hide its bag frame so only
--- Bagshui manages bag visibility.
function Bags:SuppressElvUIBags()
	local E = _G.ElvUI and _G.ElvUI[1]
	if not E then return end
	local B = E:GetModule("Bags", true)
	if not B or not B.Initialized then return end

	-- Replace ElvUI's toggle/open/close bag functions with no-ops so its
	-- SecureHook post-hooks do nothing.
	local noop = function() end
	B.ToggleBackpack = noop
	B.ToggleBags = noop
	B.OpenBags = noop
	B.CloseBags = noop

	-- Hide ElvUI's bag frame if it exists.
	if B.BagFrame and B.BagFrame:IsShown() then
		B.BagFrame:Hide()
	end

	Bagshui:PrintDebug("ElvUI bag module suppressed")
end

end)