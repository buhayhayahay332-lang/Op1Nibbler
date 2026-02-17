local cloneref = cloneref or function(obj) return obj end
local clonefunction = clonefunction or function(fn) return fn end

local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local UserInputService  = cloneref(game:GetService("UserInputService"))
local Workspace         = cloneref(game:GetService("Workspace"))

local GunModule = require(ReplicatedStorage.Modules.Items.Item.Gun)

local original_get_shoot_look = clonefunction(GunModule.get_shoot_look)

local CONFIG = {
    enabled = true,
    fov_radius = 60,
    target_players = true,
    target_gadgets = true,
    target_cameras = true,
    smoothness = 1,  -- 1 = instant, 0.1 = smooth
    debug = false,
}

local FOV_RADIUS_SQ = CONFIG.fov_radius * CONFIG.fov_radius

local TARGET_PARTS = {
    "head", "torso", "shoulder1", "shoulder2",
    "arm1", "arm2", "hip1", "hip2",
    "leg1", "leg2", "Sleeve", "Glove", "Boot"
}

local viewmodelsFolder = nil
local camera = Workspace.CurrentCamera


local function checkPart(part, mousePos, closestPart, closestDistSq)
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

    if distSq <= FOV_RADIUS_SQ and distSq < closestDistSq then
        return part, distSq
    end

    return closestPart, closestDistSq
end

local function getClosestTargetToCursor()
    local closestPart, closestDistSq = nil, math.huge
    local mousePos = UserInputService:GetMouseLocation()

    if not viewmodelsFolder then
        viewmodelsFolder = Workspace:FindFirstChild("Viewmodels")
    end

    -- Players
    if CONFIG.target_players and viewmodelsFolder then
        for _, vm in ipairs(viewmodelsFolder:GetChildren()) do
            if vm.Name == "LocalViewmodel" or vm.Name ~= "Viewmodel" then continue end
            
            local torso = vm:FindFirstChild("torso")
            if torso and torso.Transparency == 1 then continue end

            for _, partName in ipairs(TARGET_PARTS) do
                local part = vm:FindFirstChild(partName)
                closestPart, closestDistSq = checkPart(part, mousePos, closestPart, closestDistSq)
            end
        end
    end

    -- Gadgets
    if CONFIG.target_gadgets then
        for _, model in ipairs(Workspace:GetChildren()) do
            if not model:IsA("Model") then continue end
            local modelName = model.Name
            local targetChild = nil

            if modelName == "Drone" then
                targetChild = model:FindFirstChild("HumanoidRootPart")
            elseif modelName == "Claymore" then
                targetChild = model:FindFirstChild("Laser")
            elseif modelName == "ProximityAlarm" then
                targetChild = model:FindFirstChild("RedDot")
            elseif modelName == "StickyCamera" then
                targetChild = model:FindFirstChild("Cam")
            elseif modelName == "SignalDisruptor" then
                targetChild = model:FindFirstChild("Screen")
            end

            if targetChild then
                closestPart, closestDistSq = checkPart(targetChild, mousePos, closestPart, closestDistSq)
            end
        end
    end

    -- Cameras
    if CONFIG.target_cameras then
        for _, model in ipairs(Workspace:GetChildren()) do
            if not model:IsA("Model") then continue end
            local folder = model:FindFirstChildWhichIsA("Folder")
            if not folder then continue end
            local defaultCameras = folder:FindFirstChild("DefaultCameras")
            if not defaultCameras then continue end
            
            for _, defaultCam in ipairs(defaultCameras:GetChildren()) do
                if not defaultCam:IsA("Model") then continue end
                local cam = defaultCam:FindFirstChild("Dot")
                if cam then
                    closestPart, closestDistSq = checkPart(cam, mousePos, closestPart, closestDistSq)
                end
            end
        end
    end

    return closestPart
end


local aimbot_proxy = setmetatable({}, {
    __call = newcclosure(function(proxy_table, self)
        
        local originalCFrame = original_get_shoot_look(self)
        
        if not CONFIG.enabled then
            return originalCFrame
        end
        
        local success, targetPart = pcall(getClosestTargetToCursor)
        
        if success and targetPart then
            if CONFIG.debug then
                print("🎯 Locked on:", targetPart:GetFullName())
            end
            
            local weaponPos = originalCFrame.Position
            local direction = (targetPart.Position - weaponPos).Unit
            local targetCFrame = CFrame.lookAt(weaponPos, weaponPos + direction)
            
            -- Apply smoothness
            if CONFIG.smoothness < 1 then
                return originalCFrame:Lerp(targetCFrame, CONFIG.smoothness)
            end
            
            return targetCFrame
        end
        
        return originalCFrame
    end),
    
    __metatable = "locked",
    
    __tostring = function()
        return "function: get_shoot_look"
    end
})

GunModule.get_shoot_look = aimbot_proxy


getgenv().toggle_aimbot = function(enabled)
    CONFIG.enabled = enabled
    print("🎯 Aimbot:", enabled and "ON" or "OFF")
end

getgenv().set_aimbot_fov = function(fov)
    CONFIG.fov_radius = fov
    FOV_RADIUS_SQ = fov * fov
    print("🎯 FOV set to:", fov)
end

getgenv().unhook_aimbot = function()
    -- Restore original function
    GunModule.get_shoot_look = original_get_shoot_look
    print("✅ Aimbot unhooked")
end
