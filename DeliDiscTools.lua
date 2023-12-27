local addonName, L = ...;

DeliDiscTools = CreateFrame("Frame")

local DiscTools = DeliDiscTools

local function lock()
	DeliAtonementCount:Lock()
	DeliDoTChecker:Lock()
	DeliPowerInfusion:Lock()
end

local function unlock()
	DeliAtonementCount:Unlock()
	DeliDoTChecker:Unlock()
	DeliPowerInfusion:Unlock()
end

function DiscTools:Initialize()
    self.defaultVariables = {}
    self.subCommands = {
		["lock"] = lock,
		["unlock"] = unlock,
	}

    self:SetScript("OnEvent", self.OnEvent);
    self:RegisterEvent("ADDON_LOADED")
end

function DiscTools:OnEvent(event, ...)
    local arg1 = ...
    if event == "ADDON_LOADED" and arg1 == addonName then
        DeliDiscToolsSavedVariables = DeliDiscToolsSavedVariables or self.defaultVariables
    end
end

function DiscTools:PrintUsage(suffix)
    local msg = string.format("Usage: /ddt %s", suffix)
    print(msg)
end

function DiscTools:AddSubCommand(command, func)
    assert(not self.subCommands[command])
    assert(type(func) == "function")

        self.subCommands[command] = func
end 

SLASH_DDT1 = "/ddt"
SlashCmdList["DDT"] = function(msg)
    local args = {}
    for arg in string.gmatch(msg, "[^%s]+") do
        table.insert(args, arg)
    end
    if #args < 1 then
        PrintUsage("<command> <args>...")
        return
    end

    local command = DiscTools:RemoveNextCommand(args)
    local subCommand = DiscTools.subCommands[command]
    if not subCommand then
        print(string.format("Unknown command \"%s\"", command))

		local cmds = ""
		for cmd in pairs(DiscTools.subCommands) do
			cmds = cmds .. cmd .. " | "
		end
		cmds = cmds:sub(1, cmds:len()-3)
        DiscTools:PrintUsage(string.format("(%s) <args>...", cmds))
        return
    end

    subCommand(args)
end

-- Removes and returns the first element from `args` as a command, normalizing
-- it to  all lower case.
function DiscTools:RemoveNextCommand(args)
    local command = table.remove(args, 1)
    return string.lower(command)
end

function DiscTools:AddDefault(key, value)
    assert(not self.defaultVariables[key])
    self.defaultVariables[key] = value
end

function DiscTools:GetVariable(key)
    local value = DeliDiscToolsSavedVariables[key]
    if value == nil then
        value = self.defaultVariables[key]
    end

    return value
end

function DiscTools:SetVariable(key, value)
    DeliDiscToolsSavedVariables[key] = value
end

DiscTools:Initialize()