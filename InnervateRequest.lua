local addonName, L = ...

local InnervateRequest = CreateFrame("Frame")

local NUM_MAX_RAID_MEMBERS = 40
local INNERVATE = 29166
local INNERVATE_COOLDOWN = 180
local RAVENOUS_FRENZY = {
    [323546] = true,
}
local MOONKIN_FORM = {
    [24858] = true,
    [197625] = true,
}
local DEFAULT_INNERVATE_MESSAGE = "innervate"

local moonkinNames = {}
local numMoonkinNames = 0
local moonkins = {}
local innervateCDExpires = {}

local function isInnervateReady(guid)
    local innervateCDExpires = innervateCDExpires[guid] or 0
    return (GetTime() >= innervateCDExpires)
end

local function subCommand(args)
	if #args == 0 then
		DeliDiscTools:PrintUsage("innervate (request | moonkin | message) [args]...")
		return
	end

    local subCommand = DeliDiscTools:RemoveNextCommand(args)
    if subCommand == "request" then
        InnervateRequest:SendInnervateRequest()
    elseif subCommand == "moonkin" then
        if #args < 1 then
            DeliDiscTools:PrintUsage("innervate moonkin <player name>...")
            return
        end
        if #args == 1 and args[1] == "reset" then
            table.wipe(moonkinNames)
            numMoonkinNames = 0
            DeliDiscTools:SetVariable("innervateMoonkins", {})
            print("Moonkin list has been reset")
            return
        end

        local savedNames = {}
        for _, name in pairs(args) do
            moonkinNames[name] = true
            table.insert(savedNames, name)
            print(string.format("Added %s to list of moonkins", name))
        end
        numMoonkinNames = #savedNames

        DeliDiscTools:SetVariable("innervateMoonkins", savedNames)
    elseif subCommand == "message" then
        local message = table.concat(args, " ")
        DeliDiscTools:SetVariable("innervateMessage", message)
    end
end

function InnervateRequest:Initialize()
    self:SetScript("OnEvent", self.OnEvent)
    self:RegisterEvent("ADDON_LOADED")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")

	DeliDiscTools:AddSubCommand("innervate", subCommand)
    DeliDiscTools:AddDefault("innervateMessage", DEFAULT_INNERVATE_MESSAGE)
    DeliDiscTools:AddDefault("innervateMoonkins", {})

    self:Disable()
end

function InnervateRequest:Enable()
    self:RegisterEvent("GROUP_ROSTER_UPDATE")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    self:UpdateMoonkins()
end

function InnervateRequest:Disable()
    self:UnregisterEvent("GROUP_ROSTER_UPDATE")
    self:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
end

local NUM_MAX_BUFFS = 40

local function unitBuffBySpellID(unit, spellIDs, filter)
    for i = 1, NUM_MAX_BUFFS, 1 do
        local name, _, _, _, _, _, expirationTime, _, _, buffSpellID = UnitBuff(unit, i, filter)
        if name == nil then
            break
        end
        if spellIDs[buffSpellID] then
            return name, expirationTime, spellIDs[buffSpellID]
        end
    end

    return nil
end

local function isMoonkin(unit)
    if not unit then
        return false
    end

    local _, class = UnitClass(unit)
    if class ~= "DRUID" then
        return false
    end
    local unitName = GetUnitName(unit, true)
    if numMoonkinNames > 0 then
        return (moonkinNames[unitName] ~= nil)
    end
	
    local role = UnitGroupRolesAssigned(unit)
    if role == "HEALER" or role == "TANK"  then
        return false
    end
    local name = unitBuffBySpellID(unit, MOONKIN_FORM, nil)
    if not name then
        return false
    end

    return true
end

function shouldEnable()
	local enabled = DeliDiscTools:GetVariable("atonement")
	local _, class = UnitClass("player")

	return (enabled and (class == "PRIEST"))
end

function shouldEnable()
	local _, class = UnitClass("player")
	return (class == "PRIEST")
end

function InnervateRequest:OnEvent(event, ...)
    local arg1 = ...
    if event == "ADDON_LOADED" and arg1 == addonName then
        local savedMoonkinNames = DeliDiscTools:GetVariable("innervateMoonkins", savedNames)
        for _, name in pairs(savedMoonkinNames) do
            moonkinNames[name] = true
        end
        numMoonkinNames = #savedMoonkinNames
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_ENTERING_WORLD" then
        if shouldEnable() then
            self:Enable()
        end

        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    elseif event == "GROUP_ROSTER_UPDATE" then
        self:UpdateMoonkins()

		if IsInRaid() or IsInGroup() then
			self:RegisterEvent("UNIT_AURA")
		else
			self:UnregisterEvent("UNIT_AURA")
		end
    elseif event == "UNIT_AURA" then
        local unit = ...
        local guid = UnitGUID(unit)
		local moonkin = moonkins[guid]
        if not isMoonkin(unit) then
			return
		end
		
		self:AddMoonkin(unit)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if spellID ~= INNERVATE then
            return
        end

        local guid = UnitGUID(unit)
        local moonkin = moonkins[guid]
        if not moonkin then
            return
        end
        innervateCDExpires[guid] = GetTime() + INNERVATE_COOLDOWN
    end
end

function InnervateRequest:AddMoonkin(unit)
	local guid = UnitGUID(unit)
	if moonkins[guid] then
		return
	end

	local moonkin = {}
	moonkin.unit = unit
	moonkin.guid = guid
	moonkins[guid] = moonkin
end

function InnervateRequest:UpdateMoonkins()
    table.wipe(moonkins)
    if not IsInRaid() and not IsInGroup() then
        return
    end
    
    for i = 1, NUM_MAX_RAID_MEMBERS do
        local unit = string.format("raid%d", i)
        if not UnitExists(unit) then
            break
        end
        if isMoonkin(unit) then
			self:AddMoonkin(unit)
        end
    end

    for guid in pairs(innervateCDExpires) do
        if not moonkins[guid] then
            innervateCDExpires[guid] = nil
        end
    end
end

local function sortByInnervatePriority(unit1, unit2)
    local guid1 = UnitGUID(unit1)
    local guid2 = UnitGUID(unit2)

    local moonkin1 = moonkins[guid1]
    local moonkin2 = moonkins[guid2]
    local _, _, frenzy1Expires = unitBuffBySpellID(unit1, RAVENOUS_FRENZY, nil)
    local _, _, frenzy2Expires = unitBuffBySpellID(unit2, RAVENOUS_FRENZY, nil)
    if not frenzy1Expires then
        return true
    end
    if not frenzy2Expires then
        return false
    end

    return (frenzy1Expires < frenzy2Expires)
end

local function sendInnervateWhisper(unit)
    local msg = DeliDiscTools:GetVariable("innervateMessage")
    local name = GetUnitName(unit, true)
    SendChatMessage(msg, "WHISPER", nil, name)
end

local whisperBackoff = 0

function InnervateRequest:SendInnervateRequest()
    if GetTime() < whisperBackoff then
        return
    end

    local availableInnervates = {}
    for guid, moonkin in pairs(moonkins) do
        if isInnervateReady(guid) and not UnitIsDeadOrGhost(moonkin.unit) then
            table.insert(availableInnervates, moonkin.unit)
        end
    end

    if #availableInnervates == 0 then
        print("All moonkins have innervate on cooldown")
        return
    end
    table.sort(availableInnervates, sortByInnervatePriority)

    local unit = availableInnervates[1]
    sendInnervateWhisper(unit)
    whisperBackoff = GetTime() + 1
end

InnervateRequest:Initialize()