local addonName, L = ...

local CustomGlow = LibStub("LibCustomGlow-1.0")
local PowerInfusion = DeliPowerInfusion
local UnitFrameCache = DeliUnitFrameCache

-- Holds all valid offensives that should be paired with power infusion.
-- The key's value is the duration of the offensive CD.
local OFFENSIVE_CDS = {
	-- CDs that are always PI-worthy (raid and M+)

	-- Death Knight
	[49206] = 30,   -- Summon Gargoyle
	[51271] = 12,   -- Pillar of Frost

	-- Demon Hunter
	[200166] = 30,  -- Metamorphosis: Havoc Demon Hunter
	[370966] = 30,  -- The Hunt

	-- Druid
	[102560] = 30,  -- Incarnation: Chosen of Elune
	[194223] = 30,  -- Celestial Alignment
	[106951] = 20,  -- Berserk: Feral Druid
	[102543] = 30,  -- Incarnation: King of the Jungle: Feral Druid 

	-- Evoker
	[375087] = 18,  -- Dragonrage

	-- Hunter
	[288613] = 15,  -- Trueshot: Marksman Hunter
	[266779] = 20,  -- Coordinated Assault: Survival Hunter
	[359844] = 20,  -- Call of the Wild

	-- Mage
	[365350] = 12,  -- Arcane Surge
	[12472]  = 20,  -- Icy Veins: Frost Mage
	[190319] = 10,  -- Combustion: Fire Mage

	-- Monk
	[123904] = 24,  -- Invoke Xuen, the White Tiger: Windwalker Monk

	-- Paladin
	[31884] =  20,  -- Avenging Wrath: Retribution Paladin

	-- Priest
	[228260] = 20, -- Void Erruption: Shadow Priest
	[391109] = 20, -- Dark Ascension: Shadow Priest

	-- Rogue
	[360194] = 16,  -- Deathmark: Assassination Rogue
	[13750] = 20,   -- Adrenaline Rush: Outlaw Rogue
	[121471] = 20,  -- Shadow Blades: Subtlety Rogue

	-- Shaman
	[51533] = 15,   -- Feral Spirit: Enhancement Shaman
	[198067] = 30,  -- Fire Elemental: Elemental Shaman
	[192249] = 30,  -- Storm Elemental: Elemental Shaman

	-- Warlock
	[111898] = 17,  -- Grimoire: Felguard: Demonology Warlock
	[1122] = 30,    -- Summon Infernal: Destruction Warlock
	[205180] = 20,  -- Summon Darkglare: Affliction Warlock

	-- Warrior
	[107574] = 20,  -- Avatar: Arms Warrior
	[1719] = 10,    -- Recklessness: Furry Warrior

	-- CDs that are useful only in M+ or Raid, respectively
	["party"] = {
		-- Death Knight
		[383269] = 12,  -- Abomination Limb: Unholy Death Knight
   		[42650] =  15,  -- Army of the Dead: Unholy Death Knight
	},
	["raid"] = {
	},
}

-- Mapping from offensive CDs to delays in seconds. The delay is used to show  the Power Infusion icon
-- n seconds after the target has cast its offensive CD to optimize PI usage. 
local OFFENSIVE_CD_DELAYS_SEC = {
	[111898] = 3,  -- Grimoire: Felguard
	[49206] =  4 -- Summon Gargoyle
}

-- TODO: Make these spec prios
local CLASS_PRIORITIES = {
	["DRUID"] = {
		["boss"] = 13,
		["trash"] = 18,
	},
	["DEATHKNIGHT"] = {
		["boss"] = 19,
		["trash"] = 15,
	},
	["DEMONHUNTER"] = {
		["boss"] = 10,
		["trash"] = 13,
	},
	["EVOKER"] = {
		["boss"] = 18,
		["trash"] = 20,
	},
	["HUNTER"]  = {
		["boss"] = 17,
		["trash"] = 15,
	},
	["MAGE"] = {
		["boss"] = 15,
		["trash"] = 16,
	},
	["MONK"] = {
		["boss"] = 11,
		["trash"] = 12,
	},
	["PALADIN"] = {
		["boss"] = 12,
		["trash"] = 10,
	},
	["ROGUE"] = {
		["boss"] = 9,
		["trash"] = 9,
	},
	["SHAMAN"] = {
		["boss"] = 16,
		["trash"] = 17,
	},
	["WARLOCK"] = {
		["boss"] = 20,
		["trash"] = 19,
	},
	["WARRIOR"] = {
		["boss"] = 14,
		["trash"] = 14,
	},
}

local NUM_PARTY_MEMBERS = 4
local NUM_RAID_MEMBERS = 40

local kissPrio = nil

local flirtPrio = nil

local inEncounter = false
local numPIsInEncounter = 0

local mrtPrios = {}

local playernameToUnit = {}

-- Return whether `unit` is the current PI target from the MRT Note, if one exists. The functions
-- returns true if an encounter is in progress, there is a name remaining from the MRT note that
-- is part of the raid and this player is still alive. Otherwise, false is returned.
local function isMRTNoteUnit(unit)
	if not inEncounter then
		return false
	end

	local playername = mrtPrios[(numPIsInEncounter % #mrtPrios) + 1]
	if not playername then
		return false
	end

	-- If the player is not in our current group the note is probably outdated.
	local mrtUnit = playernameToUnit[playername]
	return (unit == mrtUnit and UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit))
end

local function unitPrio(unit)
	assert(unit ~= nil)

	local role = UnitGroupRolesAssigned(unit)
	if role == "HEALER" or role == "TANK" then
		return 0
	end
	local unitType = string.gsub(unit, "%d+", "")
	if unitType ~= "raid" and unitType ~= "party" then
		return 0
	end

	local _, class = UnitClass(unit)
	if not CLASS_PRIORITIES[class] then
		return 0
	end

	local prioType = "trash"
	if inEncounter then
		prioType = "boss"
	end
	local prio = CLASS_PRIORITIES[class][prioType]
	-- The order of people receiving PI from the MRT note should take precedence over
	-- all other priorities.
	if isMRTNoteUnit(unit) then
		prio = prio * 9001
	end
	local name = GetUnitName(unit, true)
	if inEncounter and name == kissPrio then
		prio = prio * 100
	end
	if not inEncounter and name == flirtPrio then
		prio = prio * 100
	end
	
	return prio
end

local function sortUnitByPrios(a, b)
	local prioA = unitPrio(a)
	local prioB = unitPrio(b)
	return prioA > prioB
end

local unitPrios = {}

local function updateGroupRoster()
	table.wipe(playernameToUnit)
	table.wipe(unitPrios)

	if not IsInRaid() and not IsInGroup() then
		return
	end
	
	local unitPrefix = "raid"
	local maxUnit = NUM_RAID_MEMBERS		
	if not IsInRaid() then
		unitPrefix = "party"
		maxUnit = NUM_PARTY_MEMBERS
	end
	for i = 1, maxUnit do
		local unit = string.format("%s%d", unitPrefix, i)
		if not UnitExists(unit) then
			break
		end
		table.insert(unitPrios, unit)
		
		local name = GetUnitName(unit, true)
		playernameToUnit[name] = unit
	end
	table.sort(unitPrios, sortUnitByPrios)
end

local DISC_SPEC_ID = 256
local HOLY_SPEC_ID = 257
local POWER_INFUSION_ID = 10060

local function shouldEnable()
	if not DeliDiscTools:GetVariable("pi") or (not IsInRaid() and not IsInGroup()) then
		return false
	end

	local currentSpec = GetSpecialization()
	local specID = GetSpecializationInfo(currentSpec)
	if specID ~= DISC_SPEC_ID and specID ~= HOLY_SPEC_ID then
		return false
	end

	return true
end

local function resetPriorities()
	kissPrio = nil
	flirtPrio = nil
	
	updateGroupRoster()
end

local function processKiss(target)
	local unit = playernameToUnit[target]
	if not unit then
		print(string.format("Unknown player %s, ignoring emote.", target))
		return
	end

	local locClass, class = UnitClass(unit)
	if not CLASS_PRIORITIES[class] then
		print(string.format("%s is not playing a valid class (%s)", target, locClass));
		return;
	end
	kissPrio = target
	print("Boss PI is now assigned to:", target)
	updateGroupRoster()
end

local function processFlirt(target)
	local unit = playernameToUnit[target]
	if not unit then
		print(string.format("Unknown player %s, ignoring emote.", target))
		return
	end

	local locClass, class = UnitClass(unit)
	if not CLASS_PRIORITIES[class] then
		print(string.format("%s is not playing a valid class (%s)", target, locClass));
		return;
	end
	flirtPrio = target
	print("Trash PI is now assigned to:", target)
	updateGroupRoster()
end

local function subCommand(args)
	if #args < 1 then
		DeliDiscTools:PrintUsage("pi <subcommand> [args]...")
		return
	end

	local subCommand = DeliDiscTools:RemoveNextCommand(args)
	if subCommand == "enable" then
		DeliDiscTools:SetVariable("pi", true)
		if shouldEnable() then
			PowerInfusion:Enable()
		end
	elseif subCommand == "disable" then
		DeliDiscTools:SetVariable("pi", false)
		PowerInfusion:Disable()
	elseif subCommand == "set" then
		if #args < 1 then
			DeliDiscTools:PrintUsage("pi set [boss|trash] <player_name>")
		end

		local player
		local piType = "both"
		if #args == 1 then
			player = args[1]
		elseif #args == 2 then
			piType = args[1]
			player = args[2]
		else
			DeliDiscTools:PrintUsage("pi set [both|boss|trash] <player_name>")
		end

		local unit = playernameToUnit[player]
		if not unit then
			print(string.format("Unknown playername '%s'.", player))
			return
		end

		if piType == "boss" then
			processKiss(player)
		elseif piType == "trash" then
			processFlirt(player)
		elseif piType == "both" then
			processKiss(player)
			processFlirt(player)
		else
			DeliDiscTools:PrintUsage("pi set [boss|trash] <player_name>")
		end
	elseif subCommand == "reset" then
		resetPriorities()
	else
		print(string.format("Unknown subcommand \"%s\"", subCommand))
		DeliDiscTools:PrintUsage("pi (enable | disable | set | reset) [args]...")
	end
end

function PowerInfusion:Initialize()
	self:Hide()
	self.enabled = false

	CustomGlow.ButtonGlow_Start(self)
	
	self:RegisterForDrag("LeftButton")

	self:SetScript("OnEvent", self.OnEvent)
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

	DeliDiscTools:AddSubCommand("pi", subCommand)
	DeliDiscTools:AddDefault("pi", true)
end

function PowerInfusion:Enable()	
	if self.enabled then
		return
	end

	print("DeliPowerInfusion Activated")
	self:RegisterEvent("GROUP_ROSTER_UPDATE")
	self:RegisterEvent("UNIT_NAME_UPDATE")
	self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	self:RegisterEvent("ENCOUNTER_START")
	self:RegisterEvent("ENCOUNTER_END")
	self:RegisterEvent("CHAT_MSG_EMOTE")
	self:RegisterEvent("CHAT_MSG_TEXT_EMOTE")
	updateGroupRoster()
	self.enabled = true
end

function PowerInfusion:Disable()
	if not self.enabled then
		return
	end

	print("DeliPowerInfusion Deactivated")
	self:UnregisterEvent("GROUP_ROSTER_UPDATE")
	self:UnregisterEvent("UNIT_NAME_UPDATE")
	self:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	self:UnregisterEvent("ENCOUNTER_START")
	self:UnregisterEvent("ENCOUNTER_END")
	self:UnregisterEvent("CHAT_MSG_EMOTE")
	self:UnregisterEvent("CHAT_MSG_TEXT_EMOTE")
	table.wipe(unitPrios)
	self.enabled = false
	
	inEncounter = false
end

function PowerInfusion:Lock()
	self:SetScript("OnDragStart", nil);
	self:SetScript("OnDragStop", nil);
	self:Hide()
	
	if shouldEnable() then
		PowerInfusion:Enable()
	else
		PowerInfusion:Disable()
	end
end

function PowerInfusion:Unlock()
	self:SetScript("OnDragStart", function(self, button) self:StartMoving(); end);
	self:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); end);
	self:Disable();
	
	self.target:SetText("Playername")
	self:Show();
end

local UNIT_FRAME_GLOW_COLOR = {0.95, 0.95, 0.32, 1}
local UNIT_FRAME_GLOW_PARTICLES = 8
local UNIT_FRAME_GLOW_FREQUENCY = 0.25
local UNIT_FRAME_GLOW_SCALE = 1.2

function PowerInfusion:Activate(unit, hideAfterSecs)
	-- Do not overwrite if another person of same priority used their CD earlier.
	if self:IsShown() then
		return
	end
	local _, class = UnitClass(unit)
	local color = RAID_CLASS_COLORS[class]
	local name = UnitName(unit)
	self.target:SetText(name)
	self.target:SetTextColor(color.r, color.g, color.b, 1.0);
	self:Show();
	
	local unitFrame = UnitFrameCache:FrameByUnit(unit)
	if unitFrame then
		CustomGlow.AutoCastGlow_Start(unitFrame, UNIT_FRAME_GLOW_COLOR, UNIT_FRAME_GLOW_PARTICLES, UNIT_FRAME_GLOW_FREQUENCY, UNIT_FRAME_GLOW_SCALE)
		self.glowUnitFrame = unitFrame
	end
	
	C_Timer.After(hideAfterSecs, function() self:Reset() end)
end

function PowerInfusion:Reset()
	self:Hide()
	if self.glowUnitFrame then
		CustomGlow.AutoCastGlow_Stop(self.glowUnitFrame)
	end
	self.glowUnitFrame = nil
end

local function unitIsValidTarget(unit)
	local unitType = string.gsub(unit, "%d+", "")
	if unitType ~= "party" and unitType ~= "raid" then
		return false
	end
	
	for _, highestPrioUnit in pairs(unitPrios) do
		if unit == highestPrioUnit or unitPrio(unit) == unitPrio(highestPrioUnit) then
			return true
		end
		
		-- A unit with higher priority is still alive
		-- so we hold PI for that unit.
		if UnitIsConnected(highestPrioUnit) and not UnitIsDeadOrGhost(highestPrioUnit) then
			return false
		end
	end
	return true
end

function PowerInfusion:OnSpellcast(unit, spellID)
	if unit == "player" and spellID == POWER_INFUSION_ID then
		if inEncounter then
			numPIsInEncounter = numPIsInEncounter + 1
			updateGroupRoster()
		end
		if self:IsShown() then
			self:Reset()
		end
		return;
	end

	local instanceType = "party"
	if IsInRaid() then
		instanceType = "raid"
	end
	if not OFFENSIVE_CDS[spellID] and not OFFENSIVE_CDS[instanceType][spellID] then
		return
	end
	if not unitIsValidTarget(unit) then
		return
	end

	local cdDuration = OFFENSIVE_CDS[spellID] or OFFENSIVE_CDS[instanceType][spellID]
	local start, duration = GetSpellCooldown(POWER_INFUSION_ID)
	local now = GetTime()
	local secsPIReady = 0
	local delay = OFFENSIVE_CD_DELAYS_SEC[spellID] or 0

	if start ~= 0 then
		secsPIReady = duration - (now - start)
	end
	if cdDuration <= secsPIReady then
		return
	end
	if delay < secsPIReady then
		delay = secsPIReady
	end

	if delay == 0 then
		self:Activate(unit, cdDuration)
	else
		C_Timer.After(delay, function()
			-- Do not show the icon if PI was used during the delay
			local start = GetSpellCooldown(POWER_INFUSION_ID)
			if start > 0 then
				return
			end
			self:Activate(unit, cdDuration - secsPIReady)
		end)
	end
end

local kissPattern = "You blow a kiss to (.+)."
local flirtPattern = "You flirt with (.+)."

function PowerInfusion:OnEmoteReceived(msg)
	local target = string.gmatch(msg, kissPattern)()
	if target then
		processKiss(target)
	end

	target = string.gmatch(msg, flirtPattern)()
	if target then
		processFlirt(target);
	end
end

local function readPITargetsFromMRT()
	table.wipe(mrtPrios)
	if not IsAddOnLoaded("MRT") or not not IsInRaid() then
		return
	end
	
	local text = VMRT.Note.Text1
	local _, playerListStart = text:find("PI[\r\n]+")
	if not playerListStart then
		return
	end

	text = text:sub(playerListStart)
	for  line in text:gmatch("[^\r\n]+") do
		if line == "end" then
			break
		end
		
		local name = line:gmatch("|c%x%x%x%x%x%x%x%x([^|]+)|", "%1")()
		if name then
			table.insert(mrtPrios, name)
			print(name)
		end
	end
end

function PowerInfusion:OnEncounterStart()
	inEncounter = true
	numPIsInEncounter = 0
	readPITargetsFromMRT()
	updateGroupRoster()
end

function PowerInfusion:OnEncounterEnd()
	table.wipe(mrtPrios)
	inEncounter = false
	numPIsInEncounter = 0
	updateGroupRoster()
end

function PowerInfusion:OnEvent(event, ...)
	if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_SPECIALIZATION_CHANGED" then
		inEncounter = IsEncounterInProgress()
		if shouldEnable() then
			PowerInfusion:Enable()
		else
			PowerInfusion:Disable()
		end
	elseif event == "UNIT_NAME_UPDATE" then
		local unit = ...
		local unitType = string.match(unit, "^([a-z]+)[0-9]*$")
		if unitType ~= "party" and unitType ~= "raid" then
			return
		end
		for name, nameUnit in pairs(playernameToUnit) do
			if unit == nameUnit then
				playernameToUnit[name] = nil
			end
		end
		local name = GetUnitName(unit, true)
		playernameToUnit[name] = unit
	elseif event == "GROUP_ROSTER_UPDATE" then
		if shouldEnable() then
			PowerInfusion:Enable()
			-- PowerInfusion:Enable() returns early if it is already enabled.
			-- Therefore, we have to update the group roster here so everything
			-- works correctly.
			updateGroupRoster()
		else
			PowerInfusion:Disable()
		end
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		local unit, _, spellID = ...;
		self:OnSpellcast(unit, spellID)
	elseif event == "CHAT_MSG_EMOTE" or event == "CHAT_MSG_TEXT_EMOTE" then
		local playerName = UnitName("player")
		local msg, senderName = ...
		if (senderName ~= playerName) then
			return
		end
		
		self:OnEmoteReceived(msg)
	elseif event == "ENCOUNTER_START" then
		self:OnEncounterStart()
	elseif event == "ENCOUNTER_END" then
		self:OnEncounterEnd()
	end
end

PowerInfusion:Initialize();