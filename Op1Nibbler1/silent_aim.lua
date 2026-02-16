local cloneref = cloneref or function(obj) return obj end
local clonefunction = clonefunction or function(fn) return fn end
local newcclosure = newcclosure or function(fn) return fn end

local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local Workspace = cloneref(game:GetService("Workspace"))

local Module = {
    _initialized = false,
    _hooked = false,
    _enabled = false,
    _gunModule = nil,
    _originalGetShootLook = nil,
    _fovRadius = 60,
    _targetPlayers = true,
    _targetGadgets = true,
    _targetCameras = true,
    _smoothness = 1,
    _debug = false,
}

local TARGET_PARTS = {
    "head", "torso", "shoulder1", "shoulder2",
    "arm1", "arm2", "hip1", "hip2",
    "leg1", "leg2", "Sleeve", "Glove", "Boot",
}

local function isCallable(value)
    if type(value) == "function" then
        return true
    end

    if type(value) == "table" then
        local mt = getmetatable(value)
        return mt ~= nil and type(mt.__call) == "function"
    end

    return false
end

local function checkPart(camera, part, mousePos, closestPart, closestDistSq, fovRadiusSq)
    if not part or not part:IsA("BasePart") then
        return closestPart, closestDistSq
    end

    local screenPos, onScreen = camera:WorldToViewportPoint(part.Position)
    if not onScreen then
        return closestPart, closestDistSq
    end

    local dx = screenPos.X - mousePos.X
    local dy = screenPos.Y - mousePos.Y
    local distSq = dx * dx + dy * dy

    if distSq <= fovRadiusSq and distSq < closestDistSq then
        return part, distSq
    end

    return closestPart, closestDistSq
end

function Module:_getClosestTarget()
    local camera = Workspace.CurrentCamera
    if not camera then
        return nil
    end

    local closestPart, closestDistSq = nil, math.huge
    local fovRadiusSq = self._fovRadius * self._fovRadius
    local mousePos = UserInputService:GetMouseLocation()

    local viewmodelsFolder = Workspace:FindFirstChild("Viewmodels")
    if self._targetPlayers and viewmodelsFolder then
        for _, vm in ipairs(viewmodelsFolder:GetChildren()) do
            if vm:IsA("Model") and vm.Name ~= "LocalViewmodel" then
                local torso = vm:FindFirstChild("torso")
                if not torso or torso.Transparency ~= 1 then
                    for _, partName in ipairs(TARGET_PARTS) do
                        local part = vm:FindFirstChild(partName)
                        closestPart, closestDistSq = checkPart(camera, part, mousePos, closestPart, closestDistSq, fovRadiusSq)
                    end
                end
            end
        end
    end

    if self._targetGadgets then
        for _, model in ipairs(Workspace:GetChildren()) do
            if model:IsA("Model") then
                local targetChild = nil
                if model.Name == "Drone" then
                    targetChild = model:FindFirstChild("HumanoidRootPart")
                elseif model.Name == "Claymore" then
                    targetChild = model:FindFirstChild("Laser")
                elseif model.Name == "ProximityAlarm" then
                    targetChild = model:FindFirstChild("RedDot")
                elseif model.Name == "StickyCamera" then
                    targetChild = model:FindFirstChild("Cam")
                elseif model.Name == "SignalDisruptor" then
                    targetChild = model:FindFirstChild("Screen")
                end

                if targetChild then
                    closestPart, closestDistSq = checkPart(camera, targetChild, mousePos, closestPart, closestDistSq, fovRadiusSq)
                end
            end
        end
    end

    if self._targetCameras then
        for _, model in ipairs(Workspace:GetChildren()) do
            if model:IsA("Model") then
                local folder = model:FindFirstChildWhichIsA("Folder")
                local defaultCameras = folder and folder:FindFirstChild("DefaultCameras")
                if defaultCameras then
                    for _, defaultCam in ipairs(defaultCameras:GetChildren()) do
                        if defaultCam:IsA("Model") then
                            local dot = defaultCam:FindFirstChild("Dot")
                            closestPart, closestDistSq = checkPart(camera, dot, mousePos, closestPart, closestDistSq, fovRadiusSq)
                        end
                    end
                end
            end
        end
    end

    return closestPart
end

function Module:_installHook()
    if self._hooked then
        return true
    end

    local okRequire, gunModuleOrErr = pcall(function()
        return require(ReplicatedStorage.Modules.Items.Item.Gun)
    end)
    if not okRequire or type(gunModuleOrErr) ~= "table" then
        return false, "gun module require failed: " .. tostring(gunModuleOrErr)
    end

    self._gunModule = gunModuleOrErr
    local originalRef = self._gunModule.get_shoot_look
    if not isCallable(originalRef) then
        return false, "get_shoot_look is not callable"
    end
    self._originalGetShootLook = type(originalRef) == "function" and clonefunction(originalRef) or originalRef

    self._gunModule.get_shoot_look = setmetatable({}, {
        __call = newcclosure(function(_, weapon)
            local okOriginal, originalCFrame = pcall(function()
                return self._originalGetShootLook(weapon)
            end)
            if not okOriginal or typeof(originalCFrame) ~= "CFrame" then
                return CFrame.new()
            end

            if not self._enabled then
                return originalCFrame
            end

            local okTarget, targetPart = pcall(function()
                return self:_getClosestTarget()
            end)
            if not okTarget or not targetPart then
                return originalCFrame
            end

            if self._debug then
                print("[SilentAim] target:", targetPart:GetFullName())
            end

            local weaponPos = originalCFrame.Position
            local direction = (targetPart.Position - weaponPos).Unit
            local targetCFrame = CFrame.lookAt(weaponPos, weaponPos + direction)

            if self._smoothness < 1 then
                return originalCFrame:Lerp(targetCFrame, self._smoothness)
            end
            return targetCFrame
        end),
        __metatable = "locked",
    })

    self._hooked = true
    return true
end

function Module:init(force)
    if self._initialized and not force then
        return true
    end

    local okHook, hookErr = self:_installHook()
    if not okHook then
        return false, hookErr
    end

    self._initialized = true
    return true
end

function Module:load(force)
    return self:init(force)
end

function Module:isLoaded()
    return self._initialized
end

function Module:setEnabled(state)
    local okInit, initErr = self:init(false)
    if not okInit then
        return false, initErr
    end

    self._enabled = state == true
    return true
end

function Module:setFov(value)
    if type(value) ~= "number" or value <= 0 then
        return false, "invalid fov"
    end
    self._fovRadius = value
    return true
end

function Module:setSmoothness(value)
    if type(value) ~= "number" then
        return false, "invalid smoothness"
    end
    self._smoothness = math.clamp(value, 0.01, 1)
    return true
end

function Module:setTargeting(targetPlayers, targetGadgets, targetCameras)
    if targetPlayers ~= nil then self._targetPlayers = targetPlayers == true end
    if targetGadgets ~= nil then self._targetGadgets = targetGadgets == true end
    if targetCameras ~= nil then self._targetCameras = targetCameras == true end
    return true
end

function Module:unload()
    if self._hooked and self._gunModule and self._originalGetShootLook then
        self._gunModule.get_shoot_look = self._originalGetShootLook
    end

    self._hooked = false
    self._initialized = false
    self._enabled = false
    return true
end

return Module
