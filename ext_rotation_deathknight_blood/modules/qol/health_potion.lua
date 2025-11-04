--[[
    Blood Death Knight - Auto Health Consumables

    Automatically uses health potions when HP falls below threshold.
    Uses izi_sdk for best potion detection and safe usage.
]]

local izi = require("common/izi_sdk")

local M = {}

-- State tracking
local state = {
    last_potion_time = 0,
    total_potions_used = 0,
}

-- Cooldowns
local POTION_COOLDOWN = 60.0  -- 60 seconds (1 minute)

---Check if potion is off cooldown
---@return boolean
local function is_potion_ready()
    local current_time = core.time()
    local time_since_last = current_time - state.last_potion_time

    return time_since_last >= POTION_COOLDOWN
end

---Use health potion using IZI SDK best function
---@param player game_object
---@param hp_threshold number
---@return boolean success
local function use_health_potion(player, hp_threshold)
    -- Check HP threshold
    local current_hp_pct = player:get_health_percentage()
    if current_hp_pct > hp_threshold then
        return false
    end

    -- Check potion cooldown
    if not is_potion_ready() then
        return false
    end

    -- Use IZI SDK's best health potion function
    local success = izi.use_best_health_potion_safe()
    
    if success then
        state.last_potion_time = core.time()
        state.total_potions_used = state.total_potions_used + 1
        
        -- Log with error handling
        pcall(function()
            core.log("Auto-potion: Used health potion at " .. string.format("%.1f%%", current_hp_pct) .. " HP (total: " .. state.total_potions_used .. ")")
        end)
    end
    
    return success
end

---Main auto-potion update function
---@param player game_object
---@param menu table
function M.update(player, menu)
    if not player or not player:is_valid() then
        return
    end

    -- Check if auto-potion is enabled
    if not menu.AUTO_POTION:get_state() then
        return
    end

    -- Get HP threshold from menu
    local hp_threshold = 40  -- Default: 40%
    local success_threshold, threshold_val = pcall(function()
        return menu.POTION_HP_THRESHOLD:get()
    end)
    if success_threshold then
        hp_threshold = threshold_val
    end

    -- Attempt to use health potion
    use_health_potion(player, hp_threshold)
end

---Initialize auto-potion module
function M:Initialize()
    -- Log initialization
    pcall(function()
        core.log("[Auto-Potion] Initialized - Using IZI SDK best health potion detection")
    end)
end

return M

