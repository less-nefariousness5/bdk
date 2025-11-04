---@diagnostic disable: undefined-global, lowercase-global
--[[
    SDK Helpers - Safe SDK Wrappers and Error Handling

    Purpose:
    - Provides defensive wrappers for SDK calls with error handling
    - Validates player and target objects before operations
    - Prevents crashes from invalid API calls

    Dependencies:
    - None (standalone module)
]]

local M = {}

-- ============================================================================
-- SAFE CALL WRAPPERS
-- ============================================================================

---Safe wrapper for SDK calls with error handling
---Catches and handles errors gracefully, returning a default value on failure
---@param fn function The function to call safely
---@param default any The default value to return on error
---@return any result The function result or default value
function M.safe_call(fn, default)
    local success, result = pcall(fn)
    if not success then
        return default
    end
    return result
end

---Safe get health percentage with fallback
---Returns 100 if unit is invalid to prevent false low-health triggers
---@param unit game_object The unit to check
---@return number health_pct Health percentage (0-100)
function M.safe_get_health_pct(unit)
    if not M.validate_unit(unit) then
        return 100
    end
    return M.safe_call(function() return unit:get_health_percentage() end, 100)
end

---Safe get runic power with fallback
---Returns 0 if unit is invalid
---@param unit game_object The unit to check
---@return number runic_power Current runic power
function M.safe_get_runic_power(unit)
    if not M.validate_unit(unit) then
        return 0
    end
    return M.safe_call(function() return unit:runic_power_current() end, 0)
end

---Safe get rune count with fallback
---Returns 0 if unit is invalid
---@param unit game_object The unit to check
---@return number rune_count Current rune count
function M.safe_get_rune_count(unit)
    if not M.validate_unit(unit) then
        return 0
    end
    return M.safe_call(function() return unit:rune_count() end, 0)
end

---Safe get buff stacks with fallback
---Returns 0 if unit is invalid or buff not present
---@param unit game_object The unit to check
---@param buff_id number The buff ID to check
---@return number stacks Buff stack count
function M.safe_get_buff_stacks(unit, buff_id)
    if not M.validate_unit(unit) then
        return 0
    end
    return M.safe_call(function() return unit:get_buff_stacks(buff_id) end, 0)
end

---Safe get buff remains with fallback
---Returns 0 if unit is invalid or buff not present
---@param unit game_object The unit to check
---@param buff_id number The buff ID to check
---@return number remains Buff remaining duration in seconds
function M.safe_get_buff_remains(unit, buff_id)
    if not M.validate_unit(unit) then
        return 0
    end
    return M.safe_call(function() return unit:buff_remains_sec(buff_id) or 0 end, 0)
end

---Safe get debuff remains with fallback
---Returns 0 if target is invalid or debuff not present
---@param unit game_object The unit to check
---@param debuff_id number The debuff ID to check
---@return number remains Debuff remaining duration in seconds
function M.safe_get_debuff_remains(unit, debuff_id)
    if not M.validate_unit(unit) then
        return 0
    end
    return M.safe_call(function() return unit:debuff_remains_sec(debuff_id) or 0 end, 0)
end

-- ============================================================================
-- VALIDATION HELPERS
-- ============================================================================

---Validate unit object
---Checks if unit exists, is valid, and is alive
---@param unit game_object|nil The unit to validate
---@return boolean is_valid True if unit is valid and alive
function M.validate_unit(unit)
    if not unit then
        return false
    end

    if not unit.is_valid then
        return false
    end

    if not unit:is_valid() then
        return false
    end

    return true
end

---Validate player object
---Checks if player exists and is valid (stricter than validate_unit)
---@param player game_object|nil The player to validate
---@return boolean is_valid True if player is valid
function M.validate_player(player)
    if not M.validate_unit(player) then
        return false
    end

    -- Additional player-specific checks
    if not player:is_alive() then
        return false
    end

    return true
end

---Validate target object for offensive actions
---Checks if target exists, is valid, alive, and attackable
---@param me game_object The player object
---@param target game_object|nil The target to validate
---@return boolean is_valid True if target is valid for attacking
function M.validate_target(me, target)
    if not M.validate_unit(target) then
        return false
    end

    if not target:is_alive() then
        return false
    end

    if not M.validate_player(me) then
        return false
    end

    -- Check if we can attack the target
    return M.safe_call(function() return me:can_attack(target) end, false)
end

---Validate target for healing actions
---Checks if target exists, is valid, and is a healable friendly
---@param target game_object|nil The target to validate
---@return boolean is_valid True if target is valid for healing
function M.validate_heal_target(target)
    if not M.validate_unit(target) then
        return false
    end

    -- Must be alive to heal
    if not target:is_alive() then
        return false
    end

    -- Must be friendly (party member or self)
    return M.safe_call(function() return target:is_party_member() end, false)
end

-- ============================================================================
-- HEALTH CHECK HELPERS
-- ============================================================================

---Get health percentage with incoming damage prediction
---@param unit game_object The unit to check
---@param time_window number Time window for incoming damage in seconds
---@return number current_hp Current health percentage
---@return number incoming_hp Health percentage including incoming damage
function M.get_health_with_incoming(unit, time_window)
    if not M.validate_unit(unit) then
        return 100, 100
    end

    local current_hp = M.safe_get_health_pct(unit)
    local _, incoming_hp = M.safe_call(
        function() return unit:get_health_percentage_inc(time_window) end,
        {current_hp, current_hp}
    )

    return current_hp, incoming_hp or current_hp
end

return M
