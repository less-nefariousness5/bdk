--[[
    Blood Death Knight - Auto Loot (Out of Combat) - IZI SDK Enhanced

    Automatically loots dead enemies after combat using core loot APIs.
    OUT OF COMBAT restriction prevents in-combat interference.
    Enhanced with IZI SDK for better performance.
]]

local core = _G.core  ---@type core
local izi = require("common/izi_sdk")  ---@type izi_api

-- Apply IZI SDK patches
izi.apply()

local M = {}

-- Throttling state
local last_loot_attempt = 0

---Finds nearest lootable corpse within range using IZI SDK
---@param player game_object
---@param max_range number
---@return game_object|nil, number|nil
local function find_nearest_lootable_corpse(player, max_range)
    if not player then return nil, nil end

    -- Use IZI SDK's filtered enemy scanning for dead units
    local corpses = player:get_enemies_in_range_if(max_range, false, function(unit)
        -- Filter: Only units, dead, and lootable
        if unit:is_dead() and unit:can_be_looted() then
            return true
        end
        return false
    end)
    
    if not corpses or #corpses == 0 then
        return nil, nil
    end
    
    -- Find nearest corpse using IZI SDK distance method
    local nearest_corpse = nil
    local nearest_distance = max_range + 1
    
    for _, corpse in ipairs(corpses) do
        local distance = corpse:distance()
        if distance < nearest_distance then
            nearest_corpse = corpse
            nearest_distance = distance
        end
    end
    
    return nearest_corpse, nearest_distance
end

---Attempts to loot a corpse using core loot APIs
---@param corpse game_object
---@param loot_mode_index number 1 = "All Items", 2 = "Gold Only"
---@return boolean success, string debug_msg
local function loot_corpse(corpse, loot_mode_index)
    -- Open loot window on corpse
    core.input.loot_object(corpse)

    -- Small delay for loot window to open
    local loot_count = core.game_ui.get_loot_item_count()

    -- If loot window didn't open or no items, return false
    if not loot_count or loot_count == 0 then
        return false, "Loot window failed to open or no items (loot_count=" .. tostring(loot_count) .. ")"
    end

    local items_looted = 0
    local mode_name = (loot_mode_index == 2) and "Gold Only" or "All Items"

    -- Loop through all loot slots (1-indexed in WoW)
    for i = 1, loot_count do
        local should_loot = false

        if loot_mode_index == 2 then
            -- Gold Only mode: Only loot gold
            if core.game_ui.get_loot_is_gold(i) then
                should_loot = true
            end
        else
            -- All Items mode (index 1): Loot everything
            should_loot = true
        end

        if should_loot then
            core.input.loot_item(i)
            items_looted = items_looted + 1
        end
    end

    -- Close loot window
    core.input.close_loot()

    return true, "Looted " .. items_looted .. "/" .. loot_count .. " items (mode: " .. mode_name .. ")"
end

---Main auto-loot update function (OUT OF COMBAT ONLY) - IZI SDK Enhanced
---@param player game_object
---@param menu table
function M.update(player, menu)
    -- Check if enabled
    if not menu.AUTO_LOOT:get_state() then
        return
    end

    -- CRITICAL: Only loot OUT of combat
    if player:affecting_combat() then
        return
    end

    -- Do not loot if player is moving
    if player:is_moving() then
        return
    end

    -- Check throttle
    local current_time = core.time()
    local throttle_ms = 1000  -- Default 1 second throttle
    local throttle_seconds = throttle_ms / 1000.0

    if (current_time - last_loot_attempt) < throttle_seconds then
        return
    end

    -- Get settings (using defaults since blood DK menu doesn't have these options)
    local loot_range = 5.0  -- Default 5 yards
    local loot_mode = 1     -- Default: All Items

    -- Only loot corpses within interaction range (maximum 5 yards)
    local max_loot_distance = math.min(loot_range, 5.0)

    -- Find nearest lootable corpse
    local corpse, corpse_distance = find_nearest_lootable_corpse(player, max_loot_distance)

    if not corpse then
        return
    end

    -- Double-check distance is within interaction range
    if corpse_distance and corpse_distance > 5.0 then
        return
    end

    -- Attempt to loot
    local success_loot, debug_msg = loot_corpse(corpse, loot_mode)

    if success_loot then
        last_loot_attempt = current_time
        -- Add debug logging with error handling
        pcall(function()
            core.log("Auto-loot: " .. debug_msg)
        end)
    end
end

return M

