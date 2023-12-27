local addonName, L = ...

local AtonementCount = DeliAtonementCount;
local UNIT_AURA_MAX = 40;
local ATONEMENT_SPELLID = 194384;
local AURA_FILTERS = "PLAYER";
local ONUPDATE_THROTTLE = 0.1;
local atonements = {};

local function unitAtonementStatus(unit)
	local _, name, duration, expires, spellID;
	for i = 1, UNIT_AURA_MAX, 1 do
		_, _, _, _, duration, expires, _, _, _, spellID = UnitBuff(unit, i, AURA_FILTERS);
		if spellID == nil then
			break;
		end
		if spellID == ATONEMENT_SPELLID then
			return true, duration, expires;
		end
	end
	return false, nil, nil;
end

local function expiresSooner(guida, guidb)
	return atonements[guida].expires < atonements[guidb].expires
end

local function subCommand(args)
	local subCommand = table.remove(args, 1)
	if subCommand == "enable" then
		DeliDiscTools:SetVariable("atonement", true)
		AtonementCount:Enable()
	elseif subCommand == "disable" then
		DeliDiscTools:SetVariable("atonement", false)
		AtonementCount:Disable()
	else
		print(string.format("Unknown subcommand \"%s\"", subCommand))
		DeliDiscTools:PrintUsage("atonement (enable | disable) [args]...")
	end
end

function AtonementCount:Initialize()
	self:ClearAllPoints();
	self:SetPoint("CENTER", UIParent, "CENTER", 0, -192);
	self:SetScale(0.5);

	self.durationInidcator:SetHideCountdownNumbers(true);
	self.durationInidcator:SetAlpha(0.75);
	self.expireHeap = BinHeap:New(expiresSooner);
	self:Reset();

	self:SetScript("OnEvent", self.OnEvent);
	self:RegisterEvent("PLAYER_ENTERING_WORLD");

	self:RegisterForDrag("LeftButton");

	DeliDiscTools:AddSubCommand("atonement", subCommand)
	DeliDiscTools:AddDefault("atonement", true)

	self:Disable()
end

function AtonementCount:Enable()
	self:SetScript("OnUpdate", self.OnUpdate);

	self:RegisterEvent("UNIT_AURA");
	self:RegisterEvent("UNIT_NAME_UPDATE");
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
end

function AtonementCount:Disable()
	self:SetScript("OnUpdate", nil);

	self:UnregisterEvent("UNIT_AURA");
	self:UnregisterEvent("UNIT_NAME_UPDATE");
	self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED");

	self:Reset()
end

function AtonementCount:Reset()
	self:Hide();
	self.elapsed = ONUPDATE_THROTTLE;
	self.duration = 0;
	self.numAtonments = 0;
	table.wipe(atonements);
	self.expireHeap:Wipe();
	
	self.durationInidcator:Hide();
	self.durationInidcator:SetCooldown(0, 0);
end

function AtonementCount:Lock()
	self:SetScript("OnDragStart", nil);
	self:SetScript("OnDragStop", nil);
	self:Reset();

	local enabled = DeliDiscTools:GetVariable("atonement")
	if enabled then
		AtonementCount:Enable()
	else
		AtonementCount:Disable()
	end
end

function AtonementCount:Unlock()
	self:SetScript("OnDragStart", function(self, button) self:StartMoving(); end);
	self:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); end);
	self:Disable()
	
	self.count:SetText("20")
	self.time:SetText("15.0")
	self.durationInidcator:SetCooldown(GetTime(), 999);
	self:Show();
end

function shouldEnable()
	local enabled = DeliDiscTools:GetVariable("atonement")
	local _, class = UnitClass("player")
	return (enabled and (class == "PRIEST"))
end

function AtonementCount:OnEvent(event, ...)
	local arg1 = ...;
	if event == "PLAYER_ENTERING_WORLD" then
		if shouldEnable() then
			AtonementCount:Enable()
		end
		self:UnregisterEvent("PLAYER_ENTERING_WORLD");
	elseif event == "UNIT_AURA" or event == "UNIT_NAME_UPDATE" then
		self:UpdateUnitAtonementStatus(arg1);
	end
end

function AtonementCount:OnUpdate(elapsed)
	self.elapsed = self.elapsed + elapsed;
	if self.elapsed >= ONUPDATE_THROTTLE then
		self.duration = self.duration - self.elapsed;
		self.elapsed = self.elapsed - ONUPDATE_THROTTLE;
		if self.duration <= 0 then
			local smallest = self.expireHeap:Pop();
			atonements[smallest] = nil;
			AtonementCount:SetAtonementCount(-1);
			AtonementCount:UpdateSmallestAtonementGUID();
		else
			self.time:SetText(math.floor(self.duration*10)/10);
		end
	end
end

function AtonementCount:UpdateUnitAtonementStatus(unit)
	local GUID = UnitGUID(unit);
	if (not GUID) then
		return;
	end
	
	local hasAtonement, duration, expires = unitAtonementStatus(unit);
	if hasAtonement then
		if not atonements[GUID] then
			AtonementCount:SetAtonementCount(1);
			atonements[GUID] = {};
		end
		if expires == atonements[GUID].expires then
			return;
		end
		self.expireHeap:Delete(GUID)
		atonements[GUID].duration = duration
		atonements[GUID].expires = expires
		self.expireHeap:Push(GUID)
	elseif atonements[GUID] then
		self.expireHeap:Delete(GUID);
		atonements[GUID] = nil;
		AtonementCount:SetAtonementCount(-1);
	end
	
	self:UpdateSmallestAtonementGUID();
end

function AtonementCount:SetAtonementCount(mod)
	self.numAtonments = self.numAtonments + mod;
	self.count:SetText(self.numAtonments);
end

function AtonementCount:UpdateSmallestAtonementGUID()
	local smallest = self.expireHeap:Peek();
	if smallest then
		local expires = atonements[smallest]["expires"];
		local duration = atonements[smallest]["duration"];
		local start = expires - duration;
		self.duration = expires - GetTime();
		self.durationInidcator:SetCooldown(start, duration);
		self:Show();
	else
		self:Reset();
	end
end

AtonementCount:Initialize();