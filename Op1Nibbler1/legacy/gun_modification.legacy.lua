local CONFIG = {
    recoil_reduction = 0,       -- 0.1 = 90% reduction
    horizontal_recoil = 0,        -- 0 = none
    no_spread = true,             -- true = perfect accuracy
    accuracy_multiplier = 1,      -- Movement accuracy
    custom_firerate = 1200,       -- RPM
    reload_speed = 0.1,           -- 0.1 = very fast
    force_auto = true,            -- Make all guns full auto
    instant_ads = true,           -- Instant aim
    custom_zoom = 1.5,            -- Zoom level
}

-- CLONE CORE FUNCTIONS (localized once)
local cloneref = cloneref
local clonefunction = clonefunction
local newcclosure = newcclosure
local pcall = clonefunction(pcall)
local setmetatable = clonefunction(setmetatable)
local typeof = clonefunction(typeof)
local rawget = clonefunction(rawget)

-- SERVICES (cloned references)
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local UserInputService  = cloneref(game:GetService("UserInputService"))
local Workspace         = cloneref(game:GetService("Workspace"))

-- MODULE
local GunModule = require(ReplicatedStorage.Modules.Items.Item.Gun)

-- CLONE ORIGINAL FUNCTIONS
local original_recoil_function = clonefunction(GunModule.recoil_function)
local original_send_shoot       = clonefunction(GunModule.send_shoot)
local original_input_render     = clonefunction(GunModule.input_render)
local original_reload_begin     = clonefunction(GunModule.reload_begin)
local original_sights           = clonefunction(GunModule.sights)
local original_update_sight_lens = clonefunction(GunModule.update_sight_lens)

-- ─────────────────────────────────────────────
-- PRE-CREATE ALL CACHED FUNCTIONS (ONCE!)
-- ─────────────────────────────────────────────

-- Recoil get functions (cached, wrapped)
local recoil_up_get = newcclosure(function(original_state)
    local val = original_state:get()
    return (typeof(val) == "number" and val * CONFIG.recoil_reduction) or 0
end)

local recoil_side_get = newcclosure(function()
    return CONFIG.horizontal_recoil
end)

-- Spread/firerate get functions (cached, wrapped)
local spread_get = newcclosure(function()
    return CONFIG.no_spread and 0 or 1
end)

local firerate_get = newcclosure(function()
    return CONFIG.custom_firerate
end)

-- Reload speed get function (cached, wrapped)
local reload_speed_get = newcclosure(function()
    return CONFIG.reload_speed
end)

-- ADS/Zoom get functions (cached, wrapped)
local ads_get = newcclosure(function()
    return CONFIG.instant_ads and 0.01 or 0.3
end)

local zoom_get = newcclosure(function()
    return CONFIG.custom_zoom
end)

-- Pre-create accuracy table (reuse)
local perfect_accuracy = { Value = CONFIG.accuracy_multiplier }


local recoil_proxy_mt = {
    __index = newcclosure(function(t, key)
        local real_states = rawget(t, "__real_states")
        if not real_states then return nil end
        
        local state = real_states[key]
        if typeof(state) == "table" and state.get then
            if key == "recoil_up" then
                return { get = function()
                    return recoil_up_get(state)
                end }
            elseif key == "recoil_side" then
                return { get = recoil_side_get }
            end
        end
        return state
    end),
    __metatable = "locked"
}

local spread_firerate_proxy_mt = {
    __index = newcclosure(function(t, key)
        local real_states = rawget(t, "__real_states")
        if not real_states then return nil end
        
        local state = real_states[key]
        if typeof(state) == "table" and state.get then
            if key == "spread" then
                return { get = spread_get }
            elseif key == "firerate" then
                return { get = firerate_get }
            end
        end
        return state
    end),
    __metatable = "locked"
}

local firerate_proxy_mt = {
    __index = newcclosure(function(t, key)
        local real_states = rawget(t, "__real_states")
        if not real_states then return nil end
        
        local state = real_states[key]
        if typeof(state) == "table" and state.get and key == "firerate" then
            return { get = firerate_get }
        end
        return state
    end),
    __metatable = "locked"
}

local reload_proxy_mt = {
    __index = newcclosure(function(t, key)
        local real_states = rawget(t, "__real_states")
        if not real_states then return nil end
        
        local state = real_states[key]
        if typeof(state) == "table" and state.get and key == "reload_speed" then
            return { get = reload_speed_get }
        end
        return state
    end),
    __metatable = "locked"
}

local sights_proxy_mt = {
    __index = newcclosure(function(t, key)
        local real_states = rawget(t, "__real_states")
        if not real_states then return nil end
        
        local state = real_states[key]
        if typeof(state) == "table" and state.get then
            if key == "ads" then
                return { get = ads_get }
            elseif key == "zoom" then
                return { get = zoom_get }
            end
        end
        return state
    end),
    __metatable = "locked"
}


GunModule.recoil_function = newcclosure(function(self, owner)
    if not self or not self.states then 
        return original_recoil_function(self, owner)
    end
    
    local real_states = self.states
    
    -- Reuse metatable, just update reference
    local proxy_states = { __real_states = real_states }
    setmetatable(proxy_states, recoil_proxy_mt)
    
    self.states = proxy_states
    
    local success, err = pcall(original_recoil_function, self, owner)
    
    -- Always restore
    self.states = real_states
    
    if not success then
        warn("Recoil error:", err)
    end
end)

GunModule.send_shoot = newcclosure(function(self)
    if not self or not self.states then
        return original_send_shoot(self)
    end
    
    local real_states = self.states
    local real_accuracy = self.accuracy
    
    local proxy_states = { __real_states = real_states }
    setmetatable(proxy_states, spread_firerate_proxy_mt)
    
    self.states = proxy_states
    self.accuracy = perfect_accuracy
    
    local success, err = pcall(original_send_shoot, self)
    
    self.states = real_states
    self.accuracy = real_accuracy
    
    if not success then
        warn("Shoot error:", err)
    end
end)

GunModule.input_render = newcclosure(function(self, ...)
    if not self or not self.states then
        return original_input_render(self, ...)
    end
    
    local real_states = self.states
    
    local proxy_states = { __real_states = real_states }
    setmetatable(proxy_states, firerate_proxy_mt)
    
    self.states = proxy_states
    
    local success, err = pcall(original_input_render, self, ...)
    
    self.states = real_states
    
    if not success then
        warn("Render error:", err)
    end
end)

GunModule.reload_begin = newcclosure(function(self, ...)
    if not self or not self.states then
        return original_reload_begin(self, ...)
    end
    
    local real_states = self.states
    
    local proxy_states = { __real_states = real_states }
    setmetatable(proxy_states, reload_proxy_mt)
    
    self.states = proxy_states
    
    local success, err = pcall(original_reload_begin, self, ...)
    
    self.states = real_states
    
    if not success then
        warn("Reload error:", err)
    end
end)

GunModule.sights = newcclosure(function(self, ...)
    if not self or not self.states then
        return original_sights(self, ...)
    end
    
    local real_states = self.states
    
    local proxy_states = { __real_states = real_states }
    setmetatable(proxy_states, sights_proxy_mt)
    
    self.states = proxy_states
    
    local success, err = pcall(original_sights, self, ...)
    
    self.states = real_states
    
    if not success then
        warn("Sights error:", err)
    end
end)

GunModule.update_sight_lens = newcclosure(function(self, ...)
    if not self or not self.states then
        return original_update_sight_lens(self, ...)
    end
    
    local real_states = self.states
    
    local proxy_states = { __real_states = real_states }
    setmetatable(proxy_states, sights_proxy_mt)
    
    self.states = proxy_states
    
    local success, err = pcall(original_update_sight_lens, self, ...)
    
    self.states = real_states
    
    if not success then
        warn("Update sight lens error:", err)
    end
end)

-- Force auto
if CONFIG.force_auto then
    GunModule.automatic = true
end
