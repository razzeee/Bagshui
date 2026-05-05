-- Bagshui Core: Blizzard FrameXML code fixes
-- Patches to work around issues in game code that don't fit anywhere else go here.

Bagshui:LoadComponent(function()

--- Stupid monkeypatch for a difficult-to-reproduce bug in Blizzard's FrameXML code
--- that intermittently leads to this error when calling `CreateFrame()` with
--- `GameTooltipTemplate` as the frame template:
--- ```text
--- Message: Interface\FrameXML\MoneyFrame.lua:185: attempt to perform arithmetic on local `money' (a nil value)
--- Stack: Interface\FrameXML\MoneyFrame.lua:185: in function `MoneyFrame_Update'
--- Interface\FrameXML\MoneyFrame.lua:168: in function `MoneyFrame_UpdateMoney'
--- Interface\FrameXML\MoneyFrame.lua:161: in function `MoneyFrame_SetType'
--- [string "<TooltipName>MoneyFrame:OnLoad"]:3: in main chunk
--- [C]: in function `CreateFrame'
--- ```
---@param wowApiFunctionName string Hooked WoW API function that triggered this call. 
function Bagshui:MoneyFrame_UpdateMoney(wowApiFunctionName)
	-- Guard against _G.this being nil (can happen in non-1.12-style OnLoad/OnShow
	-- contexts such as ElvUI's static popup construction).
	if not _G.this then
		return
	end
	-- There doesn't seem to be anything that initializes the `staticMoney` property
	-- of money frames, but this is only a problem sometimes? It's confusing.
	-- Regardless, this prevents the error from happening.
	if _G.this.moneyType == "STATIC" and _G.this.staticMoney == nil then
		_G.this.staticMoney = 0
	end
	-- The original function asserts that a named child frame exists. This can fail
	-- intermittently during frame construction (e.g. OnShow firing before children
	-- are ready). Swallow the error silently -- the frame will update correctly
	-- once it is fully initialized.
	pcall(self.hooks.OriginalHook, self.hooks, wowApiFunctionName)
end



--- Guard against `MoneyFrame_SetType` being called without a valid moneyType string.
--- ElvUI constructs SmallMoneyFrames using the WotLK calling convention
--- MoneyFrame_SetType(frame, moneyType), passing the frame as arg1 and moneyType as arg2.
--- When moneyType is nil (SmallMoneyFrame_OnLoad passes none), skip the call entirely.
---@param wowApiFunctionName string Hooked WoW API function that triggered this call.
---@param arg1 any Frame (WotLK style) or moneyType string (1.12 style).
---@param arg2 any moneyType string (WotLK style) or nil (1.12 style).
function Bagshui:MoneyFrame_SetType(wowApiFunctionName, arg1, arg2)
	-- WotLK style: arg1=frame, arg2=moneyType. 1.12 style: arg1=moneyType.
	local moneyType = arg2 ~= nil and arg2 or arg1
	-- Pass through if arg1 is a frame (WotLK SmallMoneyFrame_OnLoad calls MoneyFrame_SetType(frame)
	-- with no moneyType; WotLK's original defaults to "PLAYER" and we must not block that).
	-- Only block calls where moneyType is nil AND arg1 is not a frame object.
	if (moneyType == nil or type(moneyType) ~= "string") and type(arg1) ~= "table" then
		return
	end
	self.hooks:OriginalHook(wowApiFunctionName, arg1, arg2)
end



--- Ensure the stack split frame stays onscreen.
---@param wowApiFunctionName string Hooked WoW API function that triggered this call. 
---@param maxStack any `OpenStackSplitFrame()` parameter.
---@param parent any `OpenStackSplitFrame()` parameter.
---@param anchor any `OpenStackSplitFrame()` parameter.
---@param anchorTo any `OpenStackSplitFrame()` parameter.
function Bagshui:OpenStackSplitFrame(wowApiFunctionName, maxStack, parent, anchor, anchorTo)
	-- Pass along to the normal `OpenStackSplitFrame()` to handle everything.
	self.hooks:OriginalHook(wowApiFunctionName, maxStack, parent, anchor, anchorTo)
	-- Reposition if needed.
	if BsUtil.GetFrameOffscreenAmount(_G.StackSplitFrame, "y") < 0 then
		self:PrintDebug(anchor)
		self:PrintDebug(BsUtil.FlipAnchorPointComponent(anchor, 1))
		_G.StackSplitFrame:ClearAllPoints()
		_G.StackSplitFrame:SetPoint(
			BsUtil.FlipAnchorPointComponent(anchor, 1),
			parent,
			BsUtil.FlipAnchorPointComponent(anchorTo, 1),
			0, 0
		)
	end
end



-- UIDropDownMenu_Refresh compatibility shim.
-- On WotLK this server's UIDropDownMenu_Refresh expects (dropdown, useValue, dropDownLevel).
-- But Blizzard's internal DropDownList button OnClick calls UIDropDownMenu_Refresh(level)
-- with just a number (1.12 calling convention). Wrap to handle both.
-- Only applies the number->frame fixup when the currently open menu belongs to Bagshui,
-- to avoid interfering with other addons' dropdowns.
if _G.UIDropDownMenu_Refresh then
	local _orig_UIDropDownMenu_Refresh = _G.UIDropDownMenu_Refresh
	_G.UIDropDownMenu_Refresh = function(dropdownOrLevel, useValue, dropDownLevel)
		if type(dropdownOrLevel) == "number"
			and Bagshui
			and Bagshui.menuFrame
			and Bagshui.menuFrame.bagshuiData
			and _G.UIDROPDOWNMENU_OPEN_MENU == Bagshui.menuFrame.bagshuiData.name
		then
			-- Old 1.12 call from within a Bagshui menu: UIDropDownMenu_Refresh(level)
			-- Use the currently open menu frame and treat arg as level.
			_orig_UIDropDownMenu_Refresh(
				_G.UIDROPDOWNMENU_OPEN_MENU,
				useValue,
				dropdownOrLevel
			)
		else
			_orig_UIDropDownMenu_Refresh(dropdownOrLevel, useValue, dropDownLevel)
		end
	end
end

end)