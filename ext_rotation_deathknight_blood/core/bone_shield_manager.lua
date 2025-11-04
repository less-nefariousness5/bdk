---@diagnostic disable: undefined-global, lowercase-global
--[[
    Bone Shield Manager - Bone Shield Maintenance and Emergency Handling

    Purpose:
    - Manages Bone Shield stack maintenance
    - Handles emergency Bone Shield refresh situations
    - Determines when to save runes for Marrowrend
    - Coordinates with resource manager for rune forecasting

    Dependencies:
    - menu: Configuration values
    - sdk_helpers: Safe validation functions
    - resource_manager: Rune forecasting
]]

local M = {}

-- ============================================================================
-- BONE SHIELD STATE CHECKING
-- ============================================================================

---Check if Bone Shield needs refresh
---Checks both stack count and duration thresholds
---@param bone_shield_stacks number Current Bone Shield stack count
---@param bone_shield_remains number Bone Shield remaining duration in seconds
---@param menu table The menu configuration table
---@return boolean needs_refresh True if Bone Shield needs refresh
function M.needs_refresh(bone_shield_stacks, bone_shield_remains, menu)
    local min_stacks = menu and menu.BONE_SHIELD_MIN_STACKS:get() or 5
    local refresh_threshold = menu and menu.BONE_SHIELD_REFRESH_THRESHOLD:get() or 6

    -- Need refresh if stacks are low OR duration is expiring soon
    return bone_shield_stacks < min_stacks or bone_shield_remains <= refresh_threshold
end

---Check if Bone Shield is low (used for maintenance casts)
---Less strict than needs_refresh, used for proactive maintenance
---@param me game_object The player object
---@param bone_shield_stacks number Current Bone Shield stack count
---@param bone_shield_remains number Bone Shield remaining duration in seconds
---@param BUFF_BONE_SHIELD number Bone Shield buff ID
---@return boolean is_low True if Bone Shield is low
function M.is_low(me, bone_shield_stacks, bone_shield_remains, BUFF_BONE_SHIELD)
    if not me or not me:is_valid() then
        return false
    end

    local bone_shield_active = me:has_buff(BUFF_BONE_SHIELD)
    local bone_shield_low = not bone_shield_active or bone_shield_remains < 5 or bone_shield_stacks < 3

    return bone_shield_low
end

-- ============================================================================
-- RUNE SAVING LOGIC
-- ============================================================================

---Check if we should save runes for Marrowrend (Bone Shield refresh)
---This prevents spending runes on other abilities when Bone Shield needs refresh soon
---@param me game_object The player object
---@param bone_shield_stacks number Current Bone Shield stack count
---@param bone_shield_remains number Bone Shield remaining duration in seconds
---@param menu table The menu configuration table
---@param resource_manager table Resource manager module
---@return boolean should_save True if we should save runes for Marrowrend
function M.should_save_runes_for_marrowrend(me, bone_shield_stacks, bone_shield_remains, menu, resource_manager)
    if not me or not me:is_valid() then
        return false
    end

    -- Check if Bone Shield needs refresh: low stacks OR duration expiring soon
    if not M.needs_refresh(bone_shield_stacks, bone_shield_remains, menu) then
        return false
    end

    -- We need Bone Shield refresh (Marrowrend costs 2 runes)
    -- Check if we should save runes for it
    return resource_manager.should_save_runes_for_ability(me, 2, nil, menu)
end

-- ============================================================================
-- EMERGENCY BONE SHIELD HANDLING
-- ============================================================================

---Handle Bone Shield emergency - cast Marrowrend or Death's Caress ASAP
---This is the highest priority action when Bone Shield is critically low
---@param me game_object The player object
---@param target game_object The current target
---@param bone_shield_stacks number Current Bone Shield stack count
---@param bone_shield_remains number Bone Shield remaining duration in seconds
---@param runic_power number Current runic power
---@param menu table The menu configuration table
---@param SPELLS table Spell objects table
---@param resource_manager table Resource manager module
---@param log_death_strike function|nil Optional Death Strike logging function
---@return boolean casted True if we successfully cast Marrowrend or Death Strike
function M.emergency_cast(me, target, bone_shield_stacks, bone_shield_remains, runic_power, menu, SPELLS, resource_manager, log_death_strike)
    if not me or not me:is_valid() then
        return false
    end

    -- Check if we need Bone Shield refresh: low stacks OR duration expiring soon
    if not M.needs_refresh(bone_shield_stacks, bone_shield_remains, menu) then
        return false
    end

    -- We're below minimum - need to rebuild Bone Shield (Marrowrend costs 2 runes)
    -- Use forecast helper to check if we should save runes
    local should_save = resource_manager.should_save_runes_for_ability(me, 2, nil, menu)
    local forecast = resource_manager.get_rune_forecast(me)

    -- Check if we have 2 runes NOW
    if forecast.current_rune_count >= 2 then
        -- Try to cast Marrowrend on current target
        if target and target:is_valid() then
            if SPELLS.MARROWREND:cast_safe(target, "Marrowrend [Emergency]") then
                return true
            end
        end

        -- If no valid target for Marrowrend, try Death's Caress (ranged)
        if SPELLS.DEATHS_CARESS and SPELLS.DEATHS_CARESS:cast_safe(target, "Death's Caress [Emergency]") then
            return true
        end
    end

    -- We don't have 2 runes NOW, but check if they'll be available SOON
    if should_save and forecast.time_to_2_runes > 0 then
        -- Runes will be available soon (< forecast window)
        -- Check health to decide: use Death Strike first if low, or wait if healthy
        local hp_pct = me:get_health_percentage()
        local _, incoming_hp = me:get_health_percentage_inc(2.0)

        -- If health is low and we have RP, use Death Strike first, then refresh Bone Shield
        if (hp_pct < 60 or incoming_hp < 50) and runic_power >= 45 then
            -- Use Death Strike for healing now, then use regenerated runes for Bone Shield
            if SPELLS.DEATH_STRIKE:cast_safe(target, "Death Strike [Pre-Bone Shield]") then
                if log_death_strike then
                    log_death_strike(me, string.format("PRE-BONE SHIELD HEAL - Runes in %.2fs", forecast.time_to_2_runes))
                end
                return true
            end
        end
        -- Otherwise, return false to allow waiting for runes (don't block rune spending if runes coming soon)
        return false
    end

    -- We have less than 2 runes AND they won't be available soon
    -- Block rune spending to save for Bone Shield refresh
    return false
end

-- ============================================================================
-- BONE SHIELD MAINTENANCE
-- ============================================================================

---Check if we should prioritize Bone Shield stacking (proactive maintenance)
---Used in rotation to determine if we should use Marrowrend for stacks
---@param bone_shield_stacks number Current Bone Shield stack count
---@param target_stacks number Target stack count (usually 7-8)
---@param has_bonestorm boolean Whether Bonestorm buff is active
---@return boolean should_stack True if we should stack Bone Shield
function M.should_stack(bone_shield_stacks, target_stacks, has_bonestorm)
    -- Don't stack if Bonestorm is active (we're already getting stacks)
    if has_bonestorm then
        return false
    end

    -- Stack if below target
    return bone_shield_stacks < target_stacks
end

---Check if Bone Shield is at optimal stacks
---Used to determine if we can safely spend runes on other abilities
---@param bone_shield_stacks number Current Bone Shield stack count
---@param optimal_stacks number Optimal stack count (usually 7+)
---@return boolean is_optimal True if at optimal stacks
function M.is_optimal(bone_shield_stacks, optimal_stacks)
    return bone_shield_stacks >= optimal_stacks
end

return M
