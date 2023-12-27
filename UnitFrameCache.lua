local addonName, L = ...
local UnitFrameCache = CreateFrame("Frame", "DeliUnitFrameCache")

local cachedFrames = {}

function UnitFrameCache:Initialize()
	self:SetScript("OnEvent", self.OnEvent)
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:RegisterEvent("PLAYER_REGEN_DISABLED")

	UnitFrameCache:Disable()
end

function UnitFrameCache:Disable()
	self:UnregisterEvent("GROUP_ROSTER_UPDATE")
	self:UnregisterEvent("UNIT_NAME_UPDATE")
end

function UnitFrameCache:Enable()
	self:RegisterEvent("GROUP_ROSTER_UPDATE")
	self:RegisterEvent("UNIT_NAME_UPDATE")

	self:Reload()
end

function shouldEnable()
	local _, class = UnitClass("player")
	return (class == "PRIEST")
end

function UnitFrameCache:OnEvent(event, ...)
	if event == "PLAYER_ENTERING_WORLD" then
		if shouldEnable() then
			self:Enable()
		end

		self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	elseif event == "GROUP_ROSTER_UPDATE" or event == "UNIT_NAME_UPDATE" then
		self:Reload()
	elseif event == "PLAYER_REGEN_ENABLED" then
		self:Enable()
		self:Reload()
	elseif event == "PLAYER_REGEN_DISABLED" then
		self:Disable()
	end
end

function UnitFrameCache:FrameByUnit(unit)
	return cachedFrames[unit]
end

local function addUnitFrames(parent)
	local descendants = {parent:GetChildren()}
	while (#descendants > 0) do
		local frame = table.remove(descendants)
		if type(frame) == "table" and type(frame.IsForbidden) == "function" and not frame:IsForbidden() then
			local objType = frame:GetObjectType()
			if objType == "Button" then
				local unit = frame:GetAttribute("unit")
				if unit and frame:IsVisible() then
					cachedFrames[unit] = frame
				end
			end
		
			for _, child in ipairs({frame:GetChildren()}) do
				if type(child) == "table" and type(child.IsForbidden) == "function" and not child:IsForbidden() then
					local childType = child:GetObjectType()
					if childType == "Frame" or childType == "Button" then
						table.insert(descendants, child)
					end
				end
			end
		end
	end
end

local unitFrameContainers = {
	"Grid2LayoutFrame",
	"CompactRaidFrameContainer" -- Standard UI
};

function UnitFrameCache:Reload()
	table.wipe(cachedFrames)
	for prio, name in ipairs(unitFrameContainers) do
		local container = _G[name]
		-- We stop at the highest priority raid frames we find
		if container and not container:IsForbidden() then
			addUnitFrames(container)
			break
		end
	end
end

UnitFrameCache:Initialize()