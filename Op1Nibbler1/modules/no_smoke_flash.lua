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
    local flashGui = nil
    local flashOriginalEnabled = nil
    local flashBypassActive = false
    local flashHookTarget = nil
    local flashNewIndexHookInstalled = false
    local oldFlashNewIndex = nil

    local modifiedParts = {}
    local modifiedEmitters = {}
    local spoofedSmokeInstances = {}
    local dummySignalEvent = Instance_new("BindableEvent")

    local oldGetPropertyChangedSignal
    oldGetPropertyChangedSignal = hookfunction(game.GetPropertyChangedSignal, newcclosure(function(self, property)
        if spoofedSmokeInstances[self] and M.enabled and M.noSmoke then
            if property == "Size" or property == "Transparency" or property == "LocalTransparencyModifier" or property == "Color" or
                property == "Enabled" then
                return dummySignalEvent.Event
            end
        end
        return oldGetPropertyChangedSignal(self, property)
    end))

    local function getPlayerGui()
        if not LocalPlayer then
            return nil
        end
        return LocalPlayer:FindFirstChildOfClass("PlayerGui")
    end

    local function getFlashGui()
        local playerGui = getPlayerGui()
        if not playerGui then
            return nil
        end
        return playerGui:FindFirstChild("Flash")
    end

    local function ensureFlashNewIndexSpoof(target)
        local hookmetamethod = Runtime.hookmetamethod or hookmetamethod
        if not hookmetamethod or not target then
            return
        end

        flashHookTarget = target
        if flashNewIndexHookInstalled then
            return
        end

        oldFlashNewIndex = hookmetamethod(target, "__newindex", newcclosure(function(self, key, value)
            if self == flashHookTarget and M.enabled and M.noFlash and key == "Enabled" then
                return
            end
            return oldFlashNewIndex(self, key, value)
        end))
        flashNewIndexHookInstalled = true
    end

    local function clearFlashConnections()
        if flashEnabledConnection then
            flashEnabledConnection:Disconnect()
            flashEnabledConnection = nil
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

        ensureFlashNewIndexSpoof(flashGui)

        flashEnabledConnection = flashGui:GetPropertyChangedSignal("Enabled"):Connect(newcclosure(function()
            if M.enabled and M.noFlash and flashGui and flashGui.Parent and flashGui.Enabled then
                forceFlashDisabled()
            end
        end))

        return flashGui
    end

    local function setFlashBypass(active)
        bindFlashInstance()

        if active then
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
        modifiedParts[part] = nil
    end

    local function applyEmitter(emitter)
        if modifiedEmitters[emitter] ~= nil then
            return
        end
        modifiedEmitters[emitter] = emitter.Enabled
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
