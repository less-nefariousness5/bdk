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

---Check if Death and Decay needs refresh (for 100% uptime with charges)
---@param me game_object
---@param spells table Spell definitions
---@param gcd number Global cooldown duration
---@return boolean needs_refresh True if buff needs refresh
function M.should_refresh_death_and_decay(me, spells, gcd)
    -- Check if buff is missing
    if not me:has_buff(M.BUFF_DEATH_AND_DECAY) then
        return true
    end

    -- Check if spell has charges available
    local charges = spells.DEATH_AND_DECAY:charges()
    if charges <= 0 then
        return false  -- No charges available, can't refresh
    end

    -- Refresh when buff is about to expire (GCD + ping + small buffer)
    local buff_remains = me:buff_remains_sec(M.BUFF_DEATH_AND_DECAY) or 0
    local ping_sec = core.get_ping() / 1000
    local refresh_threshold = gcd + ping_sec + 0.5  -- Small buffer for safety

    return buff_remains <= refresh_threshold
end

---Cast Death and Decay with advanced SDK prediction options
---Ground-targeted AoE spell - always cast on nil, never on target
---Saves one charge for self when enemies are at range
---@param me game_object
---@param spells table Spell definitions
---@param menu table Menu configuration
---@param enemies table|nil Enemy list (optional, for range checking)
---@return boolean success True if cast was successful
function M.cast_death_and_decay(me, spells, menu, enemies)
    if not spells.DEATH_AND_DECAY:is_castable() then
        return false
    end

    -- Check charges
    local charges = spells.DEATH_AND_DECAY:charges()
    
    -- If buff is missing, always cast (even with 1 charge)
    local buff_missing = not me:has_buff(M.BUFF_DEATH_AND_DECAY)
    
    -- If enemies are at range (not in melee), save one charge for self
    if not buff_missing and enemies and #enemies > 0 then
        local has_melee_enemies = false
        for _, enemy in ipairs(enemies) do
            if enemy and enemy:is_valid() and enemy:is_alive() and me:can_attack(enemy) then
                if enemy:is_in_range(5) then  -- Melee range
                    has_melee_enemies = true
                    break
                end
            end
        end
        
        -- If no melee enemies, save one charge for self
        if not has_melee_enemies then
            if charges <= 1 then
                return false  -- Save the charge
            end
        end
    end

    -- Use advanced cast options with prediction for optimal placement
    local cast_opts = {
        use_prediction = menu.USE_PREDICTION:get_state(),
        prediction_type = "MOST_HITS",
        geometry = "CIRCLE",
        aoe_radius = 10,
        min_hits = menu.DND_MIN_HITS:get(),  -- Default: 1 for 100% uptime
    }

    -- Always provide a fallback position to ensure we never cast on target
    -- When prediction is enabled and finds a better position, it will override this
    -- When prediction is disabled or fails, this ensures we cast at player position
    cast_opts.cast_pos = me:get_position()

    -- Always cast on nil (no target) - this is a ground-targeted spell
    -- The prediction system will determine the best position based on enemy positions
    -- If prediction fails or is disabled, cast_pos ensures we cast at player position
    return spells.DEATH_AND_DECAY:cast_safe(nil, "Death and Decay", cast_opts)
end

---Cast Blood Boil with spread_dot logic for Blood Plague
---Only casts if enemies without Blood Plague exist, and prevents using both charges back-to-back
---@param me game_object
---@param enemies table Enemy list
---@param spells table Spell definitions
---@param reason string Cast reason for logging
---@param state_manager table|nil State manager (optional)
---@param drw_blood_boil_casted boolean Current DRW Blood Boil state
---@param manual_target game_object|nil Manual target for primary check
---@return boolean success True if cast was successful
---@return boolean new_drw_state New DRW Blood Boil casted state
function M.cast_blood_boil(me, enemies, spells, reason, state_manager, drw_blood_boil_casted, manual_target)
    if not spells.BLOOD_BOIL:is_castable() then
        return false, drw_blood_boil_casted
    end

    -- Check charges - don't use if we only have 1 charge (save it)
    local charges = spells.BLOOD_BOIL:charges()
    if charges <= 1 then
        -- Only use if primary target doesn't have Blood Plague
        if manual_target and manual_target:is_valid() and manual_target:is_alive() and me:can_attack(manual_target) then
            if manual_target:is_in_range(M.BLOOD_BOIL_RANGE) then
                if not manual_target:has_debuff(M.DEBUFF_BLOOD_PLAGUE) then
                    -- Primary target needs Blood Plague, allow using last charge
                else
                    -- Primary target already has Blood Plague, save the charge
                    return false, drw_blood_boil_casted
                end
            else
                -- Primary target out of range, save the charge
                return false, drw_blood_boil_casted
            end
        else
            -- No primary target, save the charge
            return false, drw_blood_boil_casted
        end
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

    -- Check if any enemies need Blood Plague (don't have it or need refresh)
    local enemies_need_plague = false
    
    -- Check primary target first
    if manual_target and manual_target:is_valid() and manual_target:is_alive() and me:can_attack(manual_target) then
        if manual_target:is_in_range(M.BLOOD_BOIL_RANGE) then
            if not manual_target:has_debuff(M.DEBUFF_BLOOD_PLAGUE) then
                enemies_need_plague = true
            else
                -- Check if debuff needs refresh (pandemic threshold)
                local debuff_remains = manual_target:debuff_remains_ms(M.DEBUFF_BLOOD_PLAGUE) or 0
                if debuff_remains <= M.BLOOD_PLAGUE_PANDEMIC_MS then
                    enemies_need_plague = true
                end
            end
        end
    end
    
    -- If primary target already has Blood Plague, check additional enemies
    if not enemies_need_plague then
        for _, enemy in ipairs(valid_enemies) do
            -- Skip if this is the primary target (already checked)
            if not (manual_target and enemy == manual_target) then
                if not enemy:has_debuff(M.DEBUFF_BLOOD_PLAGUE) then
                    enemies_need_plague = true
                    break
                else
                    -- Check if debuff needs refresh
                    local debuff_remains = enemy:debuff_remains_ms(M.DEBUFF_BLOOD_PLAGUE) or 0
                    if debuff_remains <= M.BLOOD_PLAGUE_PANDEMIC_MS then
                        enemies_need_plague = true
                        break
                    end
                end
            end
        end
    end

    -- Only cast if enemies need Blood Plague
    if not enemies_need_plague then
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
---Only casts if enemies without Blood Plague exist, and prevents using both charges back-to-back
---@param me game_object
---@param enemies table Enemy list
---@param spells table Spell definitions
---@param reason string Cast reason for logging
---@param drw_blood_boil_casted boolean Current DRW Blood Boil state
---@param manual_target game_object|nil Manual target for primary check
---@return boolean success True if cast was successful
---@return boolean new_drw_state New DRW Blood Boil casted state
function M.cast_blood_boil_simple(me, enemies, spells, reason, drw_blood_boil_casted, manual_target)
    if not spells.BLOOD_BOIL:is_castable() then
        return false, drw_blood_boil_casted
    end

    -- Check charges - don't use if we only have 1 charge (save it)
    local charges = spells.BLOOD_BOIL:charges()
    if charges <= 1 then
        -- Only use if primary target doesn't have Blood Plague
        if manual_target and manual_target:is_valid() and manual_target:is_alive() and me:can_attack(manual_target) then
            if manual_target:is_in_range(M.BLOOD_BOIL_RANGE) then
                if not manual_target:has_debuff(M.DEBUFF_BLOOD_PLAGUE) then
                    -- Primary target needs Blood Plague, allow using last charge
                else
                    -- Primary target already has Blood Plague, save the charge
                    return false, drw_blood_boil_casted
                end
            else
                -- Primary target out of range, save the charge
                return false, drw_blood_boil_casted
            end
        else
            -- No primary target, save the charge
            return false, drw_blood_boil_casted
        end
    end

    -- Check if enemies are in range before casting
    local has_enemies, enemy_count = M.has_enemies_in_blood_boil_range(me, enemies)
    if not has_enemies then
        return false, drw_blood_boil_casted
    end

    -- Check if any enemies need Blood Plague
    local enemies_need_plague = false
    
    -- Check primary target first
    if manual_target and manual_target:is_valid() and manual_target:is_alive() and me:can_attack(manual_target) then
        if manual_target:is_in_range(M.BLOOD_BOIL_RANGE) then
            if not manual_target:has_debuff(M.DEBUFF_BLOOD_PLAGUE) then
                enemies_need_plague = true
            end
        end
    end
    
    -- If primary target already has Blood Plague, check additional enemies
    if not enemies_need_plague then
        for _, enemy in ipairs(enemies) do
            if enemy and enemy:is_valid() and enemy:is_alive() and me:can_attack(enemy) then
                if enemy:is_in_range(M.BLOOD_BOIL_RANGE) then
                    -- Skip if this is the primary target (already checked)
                    if not (manual_target and enemy == manual_target) then
                        if not enemy:has_debuff(M.DEBUFF_BLOOD_PLAGUE) then
                            enemies_need_plague = true
                            break
                        end
                    end
                end
            end
        end
    end

    -- Only cast if enemies need Blood Plague
    if not enemies_need_plague then
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
