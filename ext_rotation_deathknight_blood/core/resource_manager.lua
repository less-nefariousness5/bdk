---@diagnostic disable: undefined-global, lowercase-global
--[[
    Resource Manager - RP/Rune Forecasting and Pooling

    Purpose:
    - Manages runic power and rune resource forecasting
    - Implements pooling strategies for burst windows
    - Validates resource spending decisions
    - Prevents resource capping and waste

    Dependencies:
    - menu: Configuration values
    - sdk_helpers: Safe validation functions
]]

local M = {}

-- ============================================================================
-- RUNE FORECASTING
-- ============================================================================

---Get rune forecast information
---Provides detailed information about current and future rune availability
---@param me game_object The player object
---@return table forecast {current_rune_count, time_to_1_rune, time_to_2_runes, time_to_3_runes, time_to_4_runes}
function M.get_rune_forecast(me)
    if not me or not me:is_valid() then
        return {
            current_rune_count = 0,
            time_to_1_rune = 999,
            time_to_2_runes = 999,
            time_to_3_runes = 999,
            time_to_4_runes = 999,
        }
    end

    return {
        current_rune_count = me:rune_count(),
        time_to_1_rune = me:rune_time_to_x(1),
        time_to_2_runes = me:rune_time_to_x(2),
        time_to_3_runes = me:rune_time_to_x(3),
        time_to_4_runes = me:rune_time_to_x(4),
    }
end

---Check if we should save runes for a specific ability
---Determines if runes will be available soon enough to warrant saving
---@param me game_object The player object
---@param runes_needed integer Number of runes required
---@param forecast_window number|nil Optional forecast window in seconds (default from menu)
---@param menu table The menu configuration table
---@return boolean should_save True if we should save runes for this ability
function M.should_save_runes_for_ability(me, runes_needed, forecast_window, menu)
    if not me or not me:is_valid() then
        return false
    end

    -- Use menu value if not specified
    forecast_window = forecast_window or (menu and menu.RUNE_FORECAST_WINDOW:get() or 3.0)

    -- If we have enough runes now, no need to save
    if me:rune_count() >= runes_needed then
        return false
    end

    -- Check if we'll have enough runes soon
    local time_to_needed = me:rune_time_to_x(runes_needed)

    -- If runes will be available within forecast window, we should save
    if time_to_needed <= forecast_window and time_to_needed > 0 then
        return true
    end

    return false
end

---Check if we can afford a rune spender considering future availability
---Validates if we have runes now or will have them soon
---@param me game_object The player object
---@param rune_cost integer Rune cost of the ability
---@param check_future boolean Whether to check future rune availability
---@param gcd number Current GCD duration
---@param menu table The menu configuration table
---@return boolean can_afford True if we can afford this ability
function M.can_afford_rune_spender(me, rune_cost, check_future, gcd, menu)
    if not me or not me:is_valid() then
        return false
    end

    if me:rune_count() >= rune_cost then
        return true
    end

    if not check_future then
        return false
    end

    -- Check if we'll have enough runes soon (within forecast window)
    local forecast_window = menu and menu.RUNE_FORECAST_WINDOW:get() or 3.0
    local time_to_needed = me:rune_time_to_x(rune_cost)

    -- If runes will be available within forecast window + GCD, we can afford it
    return time_to_needed <= (forecast_window + gcd) and time_to_needed > 0
end

-- ============================================================================
-- RUNIC POWER POOLING
-- ============================================================================

---Check if we should pool RP for Dancing Rune Weapon
---Pools RP when DRW is coming off cooldown soon
---@param me game_object The player object
---@param SPELLS table Spell objects table
---@param BUFF_DANCING_RUNE_WEAPON number DRW buff ID
---@return boolean should_pool True if we should pool RP for DRW
function M.should_pool_rp_for_drw(me, SPELLS, BUFF_DANCING_RUNE_WEAPON)
    if not me or not me:is_valid() then
        return false
    end

    if not SPELLS.DANCING_RUNE_WEAPON:is_learned() then
        return false
    end

    -- If DRW is already active, don't pool
    if me:has_buff(BUFF_DANCING_RUNE_WEAPON) then
        return false
    end

    -- Pool if DRW is coming off cooldown soon (within 15 seconds)
    local drw_cd = SPELLS.DANCING_RUNE_WEAPON:cooldown_remains()
    return drw_cd <= 15 and drw_cd > 0
end

---Check if we should pool RP for emergency healing
---Pools RP when health is low or incoming damage is significant
---@param me game_object The player object
---@param runic_power number Current runic power
---@param menu table The menu configuration table
---@return boolean should_pool True if we should pool RP for emergency
function M.should_pool_rp_for_emergency(me, runic_power, menu)
    if not me or not me:is_valid() then
        return false
    end

    local pooling_threshold = menu and menu.RP_POOLING_THRESHOLD:get() or 60

    -- If we're below pooling threshold, try to save RP
    if runic_power < pooling_threshold then
        return true
    end

    -- Check if we're taking significant damage
    local hp_pct = me:get_health_percentage()
    local _, incoming_hp = me:get_health_percentage_inc(2.0)

    -- Pool if health is low or incoming damage is significant
    if hp_pct < 60 or incoming_hp < 50 then
        return runic_power < (pooling_threshold + 30)
    end

    return false
end

---Check if we should avoid spending RP (will generate RP soon from runes)
---Prevents spending RP when rune-based RP generation is imminent
---@param me game_object The player object
---@param gcd number Current GCD duration
---@return boolean should_wait True if we should wait for rune RP generation
function M.should_wait_for_rune_rp_generation(me, gcd)
    if not me or not me:is_valid() then
        return false
    end

    -- If we have runes available, we'll generate RP soon, so don't spend RP unnecessarily
    if me:rune_count() >= 1 then
        return true
    end

    -- If runes will regenerate soon (within GCD), wait for RP generation
    local time_to_1_rune = me:rune_time_to_x(1)
    if time_to_1_rune <= gcd and time_to_1_rune > 0 then
        return true
    end

    return false
end

-- ============================================================================
-- RP CAPPING MANAGEMENT
-- ============================================================================

---Get effective RP capping threshold based on context
---Adjusts threshold based on DRW status and aggressive spending settings
---@param me game_object The player object
---@param has_drw boolean Whether DRW is active
---@param menu table The menu configuration table
---@param SPELLS table Spell objects table
---@param BUFF_DANCING_RUNE_WEAPON number DRW buff ID
---@return number threshold RP capping threshold
function M.get_rp_capping_threshold(me, has_drw, menu, SPELLS, BUFF_DANCING_RUNE_WEAPON)
    if not me or not me:is_valid() then
        return 90
    end

    local base_threshold = menu and menu.RP_CAPPING_THRESHOLD:get() or 90

    -- Use aggressive threshold if aggressive spending is enabled
    if menu and menu.AGGRESSIVE_RESOURCE_SPENDING:get_state() then
        base_threshold = base_threshold - 5
    end

    -- During DRW, RP generation is higher, so cap more aggressively
    if has_drw then
        return base_threshold + 10
    end

    -- Don't cap if DRW is coming soon (pool for burst)
    if M.should_pool_rp_for_drw(me, SPELLS, BUFF_DANCING_RUNE_WEAPON) then
        return base_threshold + 20
    end

    return base_threshold
end

---Check if we're at risk of capping runic power
---Determines if we should spend RP to avoid waste
---@param runic_power number Current runic power
---@param threshold number RP capping threshold
---@return boolean is_capping True if we're at risk of capping
function M.is_runic_power_capping(runic_power, threshold)
    return runic_power >= threshold
end

-- ============================================================================
-- RESOURCE SPENDING VALIDATION
-- ============================================================================

---Check if we should spend runic power
---Validates RP spending based on pooling strategies and capping risk
---@param me game_object The player object
---@param runic_power number Current runic power
---@param rp_cost number RP cost of the ability
---@param menu table The menu configuration table
---@param SPELLS table Spell objects table
---@param BUFF_DANCING_RUNE_WEAPON number DRW buff ID
---@return boolean should_spend True if we should spend RP
---@return string reason Reason for the decision (for debugging)
function M.should_spend_rp(me, runic_power, rp_cost, menu, SPELLS, BUFF_DANCING_RUNE_WEAPON)
    if not me or not me:is_valid() then
        return false, "Invalid player object"
    end

    -- Can't spend if we don't have enough
    if runic_power < rp_cost then
        return false, "Insufficient RP"
    end

    -- Check if we're pooling for DRW
    if M.should_pool_rp_for_drw(me, SPELLS, BUFF_DANCING_RUNE_WEAPON) then
        -- Only spend if we're at risk of capping
        local has_drw = me:has_buff(BUFF_DANCING_RUNE_WEAPON)
        local threshold = M.get_rp_capping_threshold(me, has_drw, menu, SPELLS, BUFF_DANCING_RUNE_WEAPON)
        if not M.is_runic_power_capping(runic_power, threshold) then
            return false, "Pooling for DRW"
        end
    end

    -- Check if we're pooling for emergency
    if M.should_pool_rp_for_emergency(me, runic_power, menu) then
        local hp_pct = me:get_health_percentage()
        -- Only spend if health is critical (< 40%)
        if hp_pct >= 40 then
            return false, "Pooling for emergency"
        end
    end

    return true, "OK to spend"
end

return M
