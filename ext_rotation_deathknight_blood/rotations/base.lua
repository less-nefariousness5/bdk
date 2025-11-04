---@diagnostic disable: undefined-global, lowercase-global
--[[
    Blood Death Knight - Base Rotation Functions

    Shared rotation functions used by both Deathbringer and San'layn hero trees.
    Provides common casting logic with SDK advanced features.

    Version: 1.0.0
]]

local izi = require("common/izi_sdk")
local enums = require("common/enums")
local BUFFS = enums.buff_db

-- Module table
local M = {}

-- ============================================================================
-- CONSTANTS
-- ============================================================================

-- Buff/Debuff IDs
M.BUFF_BONE_SHIELD = BUFFS.BONE_SHIELD
M.BUFF_DANCING_RUNE_WEAPON = BUFFS.DANCING_RUNE_WEAPON
M.BUFF_DEATH_AND_DECAY = BUFFS.DEATH_AND_DECAY
M.DEBUFF_BLOOD_PLAGUE = BUFFS.BLOOD_PLAGUE
M.DEBUFF_SOUL_REAPER = 343294
M.DEBUFF_BONESTORM = 194844
M.DEBUFF_REAPERS_MARK = 439843

-- Blood Plague pandemic threshold (30% of 24 second duration)
M.BLOOD_PLAGUE_DURATION_SEC = 24
M.BLOOD_PLAGUE_PANDEMIC_THRESHOLD_SEC = M.BLOOD_PLAGUE_DURATION_SEC * 0.30
M.BLOOD_PLAGUE_PANDEMIC_MS = M.BLOOD_PLAGUE_PANDEMIC_THRESHOLD_SEC * 1000

-- Blood Boil range
M.BLOOD_BOIL_RANGE = 10

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

---Check if enemies are in Blood Boil range
---@param me game_object
---@param enemies table
---@return boolean has_enemies_in_range
---@return number count Number of enemies in range
function M.has_enemies_in_blood_boil_range(me, enemies)
    if not enemies or #enemies == 0 then
        return false, 0
    end

    local count = 0

    for _, enemy in ipairs(enemies) do
        if enemy and enemy:is_valid() and enemy:is_alive() and me:can_attack(enemy) then
            if enemy:is_in_range(M.BLOOD_BOIL_RANGE) then
                count = count + 1
            end
        end
    end

    return count > 0, count
end

---Log Death Strike cast with debug information
---@param me game_object
---@param reason string
---@param runic_power number
---@param runic_power_deficit number
---@param runes number
function M.log_death_strike(me, reason, runic_power, runic_power_deficit, runes)
    local hp_pct = me:get_health_percentage()
    local _, incoming_hp = me:get_health_percentage_inc(2.0)
    local recent_damage = me:get_incoming_damage(5.0)
    local max_hp = me:max_health()
    local damage_pct = (recent_damage / max_hp) * 100

    core.log(string.format(
        "[DEATH STRIKE] Reason: %s | RP: %d/%d (deficit: %d) | Runes: %d | HP: %.1f%% | Incoming HP: %.1f%% | Recent Dmg: %.1f%% max HP",
        reason,
        runic_power,
        me:power_max(enums.power_type.RUNICPOWER),
        runic_power_deficit,
        runes,
        hp_pct,
        incoming_hp,
        damage_pct
    ))
end

-- ============================================================================
-- ROTATION CAST FUNCTIONS
-- ============================================================================

---Cast Death and Decay with advanced SDK prediction options
---@param me game_object
---@param spells table Spell definitions
---@param menu table Menu configuration
---@return boolean success True if cast was successful
function M.cast_death_and_decay(me, spells, menu)
    if not spells.DEATH_AND_DECAY:is_castable() then
        return false
    end

    -- Use advanced cast options with prediction for optimal placement
    local cast_opts = {
        use_prediction = menu.USE_PREDICTION:get_state(),
        prediction_type = "MOST_HITS",
        geometry = "CIRCLE",
        aoe_radius = 10,
        min_hits = menu.DND_MIN_HITS:get(),  -- Default: 1 for 100% uptime
    }

    -- Fallback to self position if prediction disabled
    if not cast_opts.use_prediction then
        cast_opts.cast_pos = me:get_position()
    end

    return spells.DEATH_AND_DECAY:cast_safe(nil, "Death and Decay", cast_opts)
end

---Cast Blood Boil with spread_dot logic for Blood Plague
---@param me game_object
---@param enemies table Enemy list
---@param spells table Spell definitions
---@param reason string Cast reason for logging
---@param state_manager table|nil State manager (optional)
---@param drw_blood_boil_casted boolean Current DRW Blood Boil state
---@return boolean success True if cast was successful
---@return boolean new_drw_state New DRW Blood Boil casted state
function M.cast_blood_boil(me, enemies, spells, reason, state_manager, drw_blood_boil_casted)
    if not spells.BLOOD_BOIL:is_castable() then
        return false, drw_blood_boil_casted
    end

    -- Filter enemies to only those we can attack AND are in range (10 yards)
    local valid_enemies = {}
    for _, enemy in ipairs(enemies) do
        if enemy and enemy:is_valid() and enemy:is_alive() and me:can_attack(enemy) then
            if enemy:is_in_range(M.BLOOD_BOIL_RANGE) then
                table.insert(valid_enemies, enemy)
            end
        end
    end

    if #valid_enemies == 0 then
        return false, drw_blood_boil_casted
    end

    -- Use spread_dot to refresh Blood Plague on all enemies that need it (pandemic threshold)
    if izi.spread_dot(spells.BLOOD_BOIL, valid_enemies, M.BLOOD_PLAGUE_PANDEMIC_MS, 3, reason) then
        local has_drw = me:has_buff(M.BUFF_DANCING_RUNE_WEAPON)
        if has_drw then
            drw_blood_boil_casted = true
        end
        return true, drw_blood_boil_casted
    end

    return false, drw_blood_boil_casted
end

---Cast Blood Boil without spread_dot (simple cast)
---@param me game_object
---@param enemies table Enemy list
---@param spells table Spell definitions
---@param reason string Cast reason for logging
---@param drw_blood_boil_casted boolean Current DRW Blood Boil state
---@return boolean success True if cast was successful
---@return boolean new_drw_state New DRW Blood Boil casted state
function M.cast_blood_boil_simple(me, enemies, spells, reason, drw_blood_boil_casted)
    if not spells.BLOOD_BOIL:is_castable() then
        return false, drw_blood_boil_casted
    end

    -- Check if enemies are in range before casting
    local has_enemies, enemy_count = M.has_enemies_in_blood_boil_range(me, enemies)
    if not has_enemies then
        return false, drw_blood_boil_casted
    end

    if spells.BLOOD_BOIL:cast_safe(nil, reason) then
        local has_drw = me:has_buff(M.BUFF_DANCING_RUNE_WEAPON)
        if has_drw then
            drw_blood_boil_casted = true
        end
        return true, drw_blood_boil_casted
    end

    return false, drw_blood_boil_casted
end

---Cast Heart Strike
---@param target game_object
---@param spells table Spell definitions
---@param reason string Cast reason for logging
---@return boolean success True if cast was successful
function M.cast_heart_strike(target, spells, reason)
    if not spells.HEART_STRIKE:is_castable() then
        return false
    end

    return spells.HEART_STRIKE:cast_safe(target, reason)
end

---Cast Death Strike with logging
---@param me game_object
---@param target game_object
---@param spells table Spell definitions
---@param reason string Cast reason for logging
---@param runic_power number Current runic power
---@param runic_power_deficit number Current runic power deficit
---@param runes number Current rune count
---@param last_death_strike_time number Last Death Strike timestamp
---@return boolean success True if cast was successful
---@return number new_last_death_strike_time Updated last Death Strike timestamp
function M.cast_death_strike(me, target, spells, reason, runic_power, runic_power_deficit, runes, last_death_strike_time)
    if not spells.DEATH_STRIKE:is_castable() then
        return false, last_death_strike_time
    end

    if spells.DEATH_STRIKE:cast_safe(target, "Death Strike [" .. reason .. "]") then
        M.log_death_strike(me, reason, runic_power, runic_power_deficit, runes)
        return true, izi.now()
    end

    return false, last_death_strike_time
end

return M
