local CustomGlow = LibStub("LibCustomGlow-1.0")
local DoTChecker = DeliDoTChecker

local TRACKED_DOTS = {
	[589] =    true, -- Shadow Word: Pain
	[204197] = true, -- Purge the Wicked
	[204213] = true, -- Purge the Wicked (from Penance)
};
local playerGUID = nil
local inCombat = false
local activeDoTs = {}
local numDoTs = 0;

local function subCommand(args)
	if #args < 1 then
		DeliDiscTools:PrintUsage("dot <subcommand> [args]...")
		return
	end

	local subCommand = table.remove(args, 1)
	if subCommand == "enable" then
		DeliDiscTools:SetVariable("dot", true)
		DoTChecker:Enable()
	elseif subCommand == "disable" then
		DeliDiscTools:SetVariable("dot", false)
		DoTChecker:Disable()
	else
		print(string.format("Unknown subcommand \"%s\"", subCommand))
		DeliDiscTools:PrintUsage("dot (enable | disable) [args]...")
	end
end

function DoTChecker:Initialize()
	CustomGlow.ButtonGlow_Start(self)
	self:RegisterForDrag("LeftButton")
	self:SetScript("OnEvent", self.OnEvent)
	self:RegisterEvent("PLAYER_ENTERING_WORLD")

	DeliDiscTools:AddSubCommand("dot", subCommand)
	DeliDiscTools:AddDefault("dot", true)

	DoTChecker:Disable()
end

function DoTChecker:Enable()
	playerGUID = UnitGUID("player")
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:RegisterEvent("UNIT_AURA")
	self:RegisterEvent("PLAYER_REGEN_DISABLED")
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end

function DoTChecker:Disable()
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	self:UnregisterEvent("UNIT_AURA")
	self:UnregisterEvent("PLAYER_REGEN_DISABLED")
	self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	self:Hide()
end

local function shouldEnable()
	local enabled = DeliDiscTools:GetVariable("dot")
	local _, class = UnitClass("player")

	return (enabled and (class == "PRIEST"))
end

function DoTChecker:Lock()
	self:SetScript("OnDragStart", nil);
	self:SetScript("OnDragStop", nil);
	self:Hide();

	local enabled = shouldEnable()
	if enabled then
		self:Enable()
	else
		self:Disable()
	end
end

function DoTChecker:Unlock()
	self:SetScript("OnDragStart", function(self, button) self:StartMoving(); end);
	self:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); end);
	self:Disable()
	
	self:Show();
end

function DoTChecker:StartTimer(guid, expires)
	local duration = expires - GetTime()
	assert(duration > 0)
	C_Timer.After(duration, function()
		local curExpires = activeDoTs[guid]
		if expires and curExpires == expires then
			self:RemoveDoTForGUID(guid)
		end
		local t = GetTime()
		for guid, expires in pairs(activeDoTs) do
			if expires <= t then
				self:RemoveDoTForGUID(guid)
			end
		end
		if numDoTs == 0 then
			if inCombat then
				self:Show()
			end
			return
		end

		local soonestGUID, soonestExpires = next(activeDoTs)
		for guid, expires in pairs(activeDoTs) do
			if expires < soonestExpires then
				soonestGUID = guid
				soonestExpires = expires
			end
		end
		assert(soonestExpires > t)	
		self:StartTimer(soonestGUID, soonestExpires)
	end)
end

function DoTChecker:AddDoT(guid, expires)
	local prevExpires = activeDoTs[guid]
	if prevExpires and prevExpires == expires then
		return
	end

	activeDoTs[guid] = expires
	if not prevExpires then
		numDoTs = numDoTs + 1
	end
	if numDoTs == 1 then
		if inCombat then
			self:Hide();
		end
		self:StartTimer(guid, expires)
	end
end

function DoTChecker:RemoveDoTForGUID(guid)
	if not activeDoTs[guid] then
		return
	end

	activeDoTs[guid] = nil
	numDoTs = numDoTs - 1
	if numDoTs == 0 and inCombat then
		self:Show();
	end
end

function DoTChecker:OnEvent(event, ...)
	local arg1 = ...
	if event == "PLAYER_ENTERING_WORLD" then
		if shouldEnable() then
			self:Enable()
		end
		self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	elseif event == "PLAYER_REGEN_DISABLED" then
		inCombat = true;
		if numDoTs == 0 then
			self:Show();
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		inCombat = false;
		self:Hide();
	elseif event == "UNIT_AURA" then
		local unit = ...;
		if unit == "player" then
			return
		end

		local i = 1
		local name, _, _, _, _, expires, _, _, _, spellID = UnitAura(unit, 1, "PLAYER|HARMFUL")
		while name do
			if TRACKED_DOTS[spellID] then
				local guid = UnitGUID(unit)
				self:AddDoT(guid, expires)
				break
			end

			i = i + 1
			name, _, _, _, _, expires, _, _, _, spellID = UnitAura(unit, i, "PLAYER|HARMFUL")
		end
	elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
		local ts, se, _, src, _, _, _, dest = CombatLogGetCurrentEventInfo();
		if se == "UNIT_DIED" then
			self:RemoveDoTForGUID(dest)
		end
	end
end

DoTChecker:Initialize();