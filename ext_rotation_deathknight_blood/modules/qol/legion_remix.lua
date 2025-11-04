--[[
    Blood Death Knight - Legion Remix Abilities

    Handles Twisted Crusade and Felspike Legion Remix spells.
    Updated to match main.lua implementation with IZI SDK cast() method and GCD+ping timing.

    Logic:
    - Cast Twisted Crusade when available (60s cooldown)
    - When Twisted Crusade buff is active:
      * 3+ enemies: Felspike should be used immediately
      * 1-2 enemies: Wait until GCD + ping remaining, then Felspike (last possible GCD)
    - Uses IZI SDK cast() method for dynamic spell compatibility
    - Three-tier fallback system: aura detection → learned + TC active → timing fallback

    Note: Felspike is a player-activated ability that becomes available 
    as a hidden buff (1242997) after using Twisted Crusade.

    Priority: After major offensive CDs in the rotation
]]

local C = require("constants")
local S = require("spells")
local enums = require("common/enums")

---@class LegionRemix
local M = {}

-- State tracking for Felspike aura changes
M.last_felspike_state = nil
M.last_twisted_debug = 0

---Execute Legion Remix rotation
---@param player game_object
---@param target game_object
---@param menu table
---@return boolean action_taken
function M:Execute(player, target, menu)
    -- Validate player and target
    if not (player and player.is_valid and player:is_valid()) then
        return false
    end

    if not (target and target.is_valid and target:is_valid() and target:is_alive()) then
        return false
    end

    -- Check if main Legion Remix is enabled
    local success_main, main_enabled = pcall(function()
        return menu.LEGION_REMIX:get_state()
    end)
    if not success_main or not main_enabled then
        return false
    end
    
    local twisted_crusade_buff_active = player:buff_up(C.LEGION_REMIX.TWISTED_CRUSADE_BUFF)
    local felspike_spell_available = false
    
    -- Check if we have Felspike aura OR if Twisted Crusade has transformed
    local felspike_aura_active = player:buff_up(C.LEGION_REMIX.FELSPIKE_BUFF)
    local felspike_spell_learned = S.FELSPIKE:is_learned()
    local twisted_spell_learned = S.TWISTED_CRUSADE:is_learned()
    
    -- State tracking for Felspike aura changes (no logging)
    M.last_felspike_state = M.last_felspike_state or felspike_aura_active
    if M.last_felspike_state ~= felspike_aura_active then
        M.last_felspike_state = felspike_aura_active
    end
    
    -- Determine if Felspike spell is available
    if twisted_crusade_buff_active then
        if felspike_aura_active then
            felspike_spell_available = true
        elseif felspike_spell_learned then
            felspike_spell_available = true
        else
            felspike_spell_available = true
        end
    end
    
    if twisted_crusade_buff_active and felspike_spell_available then
        -- Felspike is available: Use main.lua timing logic
        local twisted_crusade_remaining_sec = player:buff_remains_sec(C.LEGION_REMIX.TWISTED_CRUSADE_BUFF) or 0
        local nearby_enemies = target:get_enemies_in_splash_range_count(8)
        
        -- Use main.lua timing: GCD + ping for last possible GCD
        local gcd = player:gcd() or 1.5
        local ping_sec = 0.1  -- Approximate ping
        local minimum_twisted_crusade_remaining_sec = gcd + ping_sec
        
        local should_cast_felspike = false
        
        if nearby_enemies >= 3 then
            -- 3+ enemies: Use Felspike immediately
            should_cast_felspike = true
        elseif twisted_crusade_remaining_sec < minimum_twisted_crusade_remaining_sec then
            -- Single target: Use main.lua timing logic (last possible GCD)
            should_cast_felspike = true
        end
        
        if should_cast_felspike then
            -- Replicate main.lua logic: Try Felspike with cast() not cast_safe()
            local felspike_cast_result = false
            
            -- Method 1: Try Felspike spell directly using cast() (like main.lua)
            if felspike_spell_learned then
                felspike_cast_result = S.FELSPIKE:cast()  -- Use cast() not cast_safe()
            end
            
            -- Method 2: Fallback to Twisted Crusade ID using cast()
            if not felspike_cast_result and twisted_spell_learned then
                felspike_cast_result = S.TWISTED_CRUSADE:cast()  -- Use cast() not cast_safe()
            end
            
            if felspike_cast_result then
                return true
            end
        end
    else
        -- Felspike not available: Cast Twisted Crusade
        if S.TWISTED_CRUSADE:cast_safe(player, "Twisted Crusade", {skip_facing = true, skip_range = true, skip_gcd = true}) then
            return true
        end
    end

    return false
end

return M

