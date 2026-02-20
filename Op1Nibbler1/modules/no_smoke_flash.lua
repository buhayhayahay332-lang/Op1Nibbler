return function(ctx)
    local Runtime = ctx and ctx.Runtime or {}
    local cloneref = Runtime.cloneref or cloneref or function(obj)
        return obj
    end
    local newcclosure = Runtime.newcclosure or newcclosure or function(fn)
        return fn
    end
    local hookfunction = Runtime.hookfunction or hookfunction or function(f)
        return f
    end
    local Instance_new = Runtime.InstanceNew or Instance.new

    local Services = ctx and ctx.Services or {}
    local Workspace = Services.Workspace or cloneref(game:GetService("Workspace"))
    local Players = Services.Players or cloneref(game:GetService("Players"))
    local LocalPlayer = Players.LocalPlayer

    local M = {
        enabled = false,
        noSmoke = true,
        noFlash = true
    }

    local initialized = false
    local smokeConnection = nil

    local flashEnabledConnection = nil
    local flashPollConnection = nil
    local flashGui = nil
    local flashOriginalEnabled = nil
    local flashBypassActive = false

    local modifiedParts = {}
    local modifiedEmitters = {}
    local spoofedSmokeInstances = {}
    local originalSmokeData = {}
    local dummySignalEvent = Instance_new("BindableEvent")

    local oldGetPropertyChangedSignal
    oldGetPropertyChangedSignal = hookfunction(game.GetPropertyChangedSignal, newcclosure(function(self, property)
        if spoofedSmokeInstances[self] and M.enabled and M.noSmoke then
            if property == "Size" or property == "Transparency" or property == "LocalTransparencyModifier" or property == "Color"  then
                return dummySignalEvent.Event
            end
        end
        return oldGetPropertyChangedSignal(self, property)
    end))

    -- property spoofing for smoke parts/emitters (similar to hitbox)
    do
        local hookmetamethod = Runtime.hookmetamethod or hookmetamethod
        local getrawmetatable = Runtime.getrawmetatable or getrawmetatable
        local setreadonly = Runtime.setreadonly or setreadonly
        if hookmetamethod and getrawmetatable and setreadonly then
            local mt = getrawmetatable(game)
            if mt and mt.__index then
                local old_index = mt.__index
                setreadonly(mt, false)
                mt.__index = newcclosure(function(self, key)
                    local data = originalSmokeData[self]
                    if data then
                        if key == "Size" then
                            return data.Size
                        elseif key == "Transparency" then
                            return data.Transparency
                        elseif key == "Color" then
                            return data.Color
                        elseif key == "LocalTransparencyModifier" then
                            return data.LocalTransparencyModifier
                        elseif key == "Enabled" and data.Enabled ~= nil then
                            return data.Enabled
                        end
                    end
                    return old_index(self, key)
                end)
                setreadonly(mt, true)
            end
        end
    end

    local function getPlayerGui()
        LocalPlayer = Players.LocalPlayer or LocalPlayer
        if not LocalPlayer then return nil end
        return LocalPlayer:FindFirstChildOfClass("PlayerGui")
    end

    local function getFlashGui()
        local playerGui = getPlayerGui()
        if not playerGui then
            return nil
        end
        return playerGui:FindFirstChild("Flash")
    end

    local function clearFlashConnections()
        if flashEnabledConnection then
            flashEnabledConnection:Disconnect()
            flashEnabledConnection = nil
        end
        if flashPollConnection then
            flashPollConnection:Disconnect()
            flashPollConnection = nil
        end
    end

    local function forceFlashDisabled()
        if flashGui and flashGui.Parent then
            flashGui.Enabled = false
        end
    end

    local function bindFlashInstance()
        if flashGui and flashGui.Parent then
            return flashGui
        end

        clearFlashConnections()
        flashGui = getFlashGui()

        if not flashGui then
            return nil
        end

        flashEnabledConnection = flashGui:GetPropertyChangedSignal("Enabled"):Connect(newcclosure(function()
            if M.enabled and M.noFlash and flashGui and flashGui.Parent and flashGui.Enabled then
                forceFlashDisabled()
            end
        end))

        if flashPollConnection then
            flashPollConnection:Disconnect()
            flashPollConnection = nil
        end

        return flashGui
    end

    local function setFlashBypass(active)
        bindFlashInstance()

        if active then
            if not flashGui then
                local RunService = Services.RunService or cloneref(game:GetService("RunService"))
                flashPollConnection = RunService.Heartbeat:Connect(newcclosure(function()
                    if not (M.enabled and M.noFlash) then
                        if flashPollConnection then
                            flashPollConnection:Disconnect()
                            flashPollConnection = nil
                        end
                        return
                    end
                    bindFlashInstance()
                    if flashGui then
                        forceFlashDisabled()
                        if flashPollConnection then
                            flashPollConnection:Disconnect()
                            flashPollConnection = nil
                        end
                    end
                end))
            end
            if not flashBypassActive and flashGui then
                flashOriginalEnabled = flashGui.Enabled
            end
            flashBypassActive = true
            forceFlashDisabled()
            return
        end

        flashBypassActive = false
        if flashGui and flashOriginalEnabled ~= nil then
            flashGui.Enabled = flashOriginalEnabled
        end
        flashOriginalEnabled = nil
    end

    local function applyPart(part)
        if modifiedParts[part] then
            return
        end
        modifiedParts[part] = {
            LocalTransparencyModifier = part.LocalTransparencyModifier,
            Size = part.Size
        }
        originalSmokeData[part] = {
            Size = part.Size,
            Transparency = part.Transparency,
            Color = part.Color,
            LocalTransparencyModifier = part.LocalTransparencyModifier
        }
        spoofedSmokeInstances[part] = true
        part.LocalTransparencyModifier = 1
        part.Size = Vector3.new(0.001, 0.001, 0.001)
    end

    local function restorePart(part)
        local original = modifiedParts[part]
        if not original then
            return
        end
        if part and part.Parent then
            part.LocalTransparencyModifier = original.LocalTransparencyModifier
            part.Size = original.Size
        end
        spoofedSmokeInstances[part] = nil
        originalSmokeData[part] = nil
        modifiedParts[part] = nil
    end

    local function applyEmitter(emitter)
        if modifiedEmitters[emitter] ~= nil then
            return
        end
        modifiedEmitters[emitter] = emitter.Enabled
        originalSmokeData[emitter] = {Enabled = emitter.Enabled}
        spoofedSmokeInstances[emitter] = true
        emitter.Enabled = false
    end

    local function restoreEmitter(emitter)
        local original = modifiedEmitters[emitter]
        if original == nil then
            return
        end
        if emitter and emitter.Parent then
            emitter.Enabled = original
        end
        spoofedSmokeInstances[emitter] = nil
        originalSmokeData[emitter] = nil
        modifiedEmitters[emitter] = nil
    end

    local function visitSmokeObject(obj, apply)
        pcall(function()
            if obj:IsA("BasePart") then
                if apply then
                    applyPart(obj)
                else
                    restorePart(obj)
                end
            end

            for _, part in ipairs(obj:GetDescendants()) do
                if part:IsA("BasePart") then
                    if apply then
                        applyPart(part)
                    else
                        restorePart(part)
                    end
                elseif part:IsA("ParticleEmitter") or part:IsA("Smoke") then
                    if apply then
                        applyEmitter(part)
                    else
                        restoreEmitter(part)
                    end
                end
            end
        end)
    end

    local function refreshSmoke()
        local shouldApply = M.enabled and M.noSmoke

        for _, obj in ipairs(Workspace:GetChildren()) do
            if obj.Name == "SmokePart" then
                visitSmokeObject(obj, shouldApply)
            end
        end

        if not shouldApply then
            for part in pairs(modifiedParts) do
                restorePart(part)
            end
            for emitter in pairs(modifiedEmitters) do
                restoreEmitter(emitter)
            end
        end
    end

    local function refreshFlash()
        setFlashBypass(M.enabled and M.noFlash)
    end

    function M:Init()
        if initialized then
            return
        end
        initialized = true

        smokeConnection = Workspace.ChildAdded:Connect(newcclosure(function(obj)
            if obj.Name == "SmokePart" and M.enabled and M.noSmoke then
                visitSmokeObject(obj, true)
            end
        end))

        bindFlashInstance()

        refreshSmoke()
        refreshFlash()
    end

    function M:SetEnabled(state)
        self.enabled = state and true or false
        if self.enabled and not initialized then
            self:Init()
        end
        refreshSmoke()
        refreshFlash()
    end

    function M:SetNoSmoke(state)
        self.noSmoke = state and true or false
        refreshSmoke()
    end

    function M:SetNoFlash(state)
        self.noFlash = state and true or false
        refreshFlash()
    end

    return M
end
