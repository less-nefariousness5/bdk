---@diagnostic disable: undefined-global, lowercase-global
--[[
    Blood Death Knight - Deathbringer Hero Tree Rotation

    Complete 18-priority rotation system for the Deathbringer hero tree.
    Features Reaper's Mark, Soul Reaper, and Exterminate priority logic.

    Version: 1.0.0
]]

local izi = require("common/izi_sdk")
local enums = require("common/enums")

-- Module table
local M = {}

-- ============================================================================
-- CONSTANTS
-- ============================================================================

-- Buff/Debuff IDs (Deathbringer specific)
local BUFF_REAPER_OF_SOULS = 440002
local BUFF_EXTERMINATE = 441416

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

---Check if Reaper's Mark debuff will explode soon (within 5 seconds)
---@param target game_object
---@param base table Base rotation module
---@return boolean
local function reapers_mark_explodes_soon(target, base)
    if not target or not target:is_valid() then
        return false
    end
    local debuff_remains = target:debuff_remains_sec(base.DEBUFF_REAPERS_MARK)
    return debuff_remains > 0 and debuff_remains <= 5
end

---Check if we can afford a rune spender considering future rune availability
---@param me game_object
---@param rune_cost integer
---@param check_future boolean Check future rune availability
---@param menu table Menu configuration
---@param gcd number Current GCD duration
---@return boolean can_afford
local function can_afford_rune_spender(me, rune_cost, check_future, menu, gcd)
    if me:rune_count() >= rune_cost then
        return true
    end

    if not check_future then
        return false
    end

    -- Check if we'll have enough runes soon (within forecast window)
    local forecast_window = menu.RUNE_FORECAST_WINDOW:get()
    local time_to_needed = me:rune_time_to_x(rune_cost)

    -- If runes will be available within forecast window + GCD, we can afford it
    return time_to_needed <= (forecast_window + gcd) and time_to_needed > 0
end

-- ============================================================================
-- DEATHBRINGER ROTATION
-- ============================================================================

---Execute Deathbringer rotation priority list (18 priorities)
---@param me game_object
---@param spells table Spell definitions
---@param menu table Menu configuration
---@param buffs table Buff tracker
---@param debuffs table Debuff tracker
---@param resource_manager table Resource pooling/forecasting
---@param bone_shield_manager table Bone Shield state
---@param targeting table Target selection helpers
---@param base table Base rotation module
---@param gcd number Current GCD duration
---@return boolean success True if an action was taken
function M.execute(me, spells, menu, buffs, debuffs, resource_manager, bone_shield_manager, targeting, base, gcd)
    local target = targeting.current_target
    local enemies = targeting.enemies
    local active_enemies = #enemies

    if not (target and target:is_valid() and me:can_attack(target)) then
        return false
    end

    local has_drw = me:has_buff(base.BUFF_DANCING_RUNE_WEAPON)
    local now = izi.now()

    -- Priority 1: Death Strike below 70% health
    if me:get_health_percentage() < 70 then
        -- Prevent back-to-back Death Strikes (wait at least 1 second)
        if (now - resource_manager.last_death_strike_time) >= 1.0 then
            local success, new_time = base.cast_death_strike(
                me, target, spells, "<70% HP",
                resource_manager.runic_power,
                resource_manager.runic_power_deficit,
                resource_manager.runes,
                resource_manager.last_death_strike_time
            )
            if success then
                resource_manager.last_death_strike_time = new_time
                return true
            end
        end
    end

    -- Priority 2: Marrowrend for Bone Shield maintenance
    if not bone_shield_manager.block_rune_spending then
        local bone_shield_active = me:has_buff(base.BUFF_BONE_SHIELD)
        local bone_shield_low = not bone_shield_active or bone_shield_manager.bone_shield_remains < 5 or bone_shield_manager.bone_shield_stacks < 3

        -- Check Exterminate + Reaper's Mark conditions
        local has_exterminate = me:has_buff(BUFF_EXTERMINATE)
        local rm_off_cd = spells.REAPERS_MARK:cooldown_up()
        local rm_near_cd = spells.REAPERS_MARK:cooldown_remains() <= 3
        local exterminate_expires_soon = has_exterminate and me:buff_remains_sec(BUFF_EXTERMINATE) < 5
        local exterminate_with_rm = has_exterminate and (rm_off_cd or rm_near_cd or exterminate_expires_soon)

        if bone_shield_low or exterminate_with_rm then
            if can_afford_rune_spender(me, 2, true, menu, gcd) then
                if spells.MARROWREND:cast_safe(target, "Marrowrend [Bone Shield]") then
                    return true
                end
            end
        end
    end

    -- Priority 3: Blood Boil for Blood Plague
    if not bone_shield_manager.block_rune_spending then
        if spells.BLOOD_BOIL:is_castable() and can_afford_rune_spender(me, 1, true, menu, gcd) then
            local success, new_drw_state = base.cast_blood_boil(
                me, enemies, spells, "Blood Boil [Plague]",
                nil, resource_manager.drw_blood_boil_casted
            )
            if success then
                resource_manager.drw_blood_boil_casted = new_drw_state
                return true
            end
        end
    end

    -- Priority 5: Bonestorm
    if menu.BONESTORM_CHECK:get_state() and spells.BONESTORM:is_learned() and spells.BONESTORM:is_castable() then
        -- Check DRW buff directly to ensure it's not active (don't rely on cached has_drw)
        local drw_active = me:has_buff(base.BUFF_DANCING_RUNE_WEAPON)
        local drw_cd = spells.DANCING_RUNE_WEAPON:cooldown_remains()
        local drw_on_cd = not drw_active and drw_cd > 0

        if bone_shield_manager.bone_shield_stacks > 6 and me:has_buff(base.BUFF_DEATH_AND_DECAY) and drw_on_cd then
            if spells.BONESTORM:cast_safe(nil, "Bonestorm") then
                return true
            end
        end
    end

    -- Priority 6: Death Strike RP Capping
    -- RP > 105 (or RP > 99 when DRW active)
    local drw_active = me:has_buff(base.BUFF_DANCING_RUNE_WEAPON)
    local rp_threshold = drw_active and 99 or 105
    if resource_manager.runic_power > rp_threshold then
        -- Prevent back-to-back Death Strikes
        if (now - resource_manager.last_death_strike_time) >= 1.0 then
            local success, new_time = base.cast_death_strike(
                me, target, spells, string.format("RP CAP (threshold: %d)", rp_threshold),
                resource_manager.runic_power,
                resource_manager.runic_power_deficit,
                resource_manager.runes,
                resource_manager.last_death_strike_time
            )
            if success then
                resource_manager.last_death_strike_time = new_time
                return true
            end
        end
    end

    -- Priority 7: Reaper's Mark
    if menu.REAPERS_MARK_CHECK:get_state() and spells.REAPERS_MARK:is_learned() and spells.REAPERS_MARK:is_castable() then
        if spells.REAPERS_MARK:cast_safe(target, "Reaper's Mark") then
            return true
        end
    end

    -- Priority 8: Soul Reaper
    if menu.SOUL_REAPER_CHECK:get_state() and spells.SOUL_REAPER:is_learned() and spells.SOUL_REAPER:is_castable() then
        -- With 1 priority target (1-2 enemies) or if priority damage is desired
        if active_enemies <= 2 then
            -- Scan enemies in range to find the best eligible target for Soul Reaper
            -- Eligible: below 35% health OR Reaper of Souls buff is active
            local reaper_of_souls_active = me:has_buff(BUFF_REAPER_OF_SOULS)

            -- Get all enemies in range (40 yards) and filter for eligible targets
            local eligible_targets = {}
            local enemies_40y = izi.enemies(40)

            for _, enemy in ipairs(enemies_40y) do
                if enemy and enemy:is_valid() and enemy:is_alive() and me:can_attack(enemy) then
                    local hp_pct = enemy:get_health_percentage()
                    local ttd = enemy:time_to_die()
                    local sr_remains = enemy:debuff_remains_sec(base.DEBUFF_SOUL_REAPER)

                    -- Check eligibility: below 35% health OR Reaper of Souls active
                    local execute_condition = hp_pct < 35
                    local is_eligible = execute_condition or reaper_of_souls_active

                    -- Only consider if eligible and target will live long enough to benefit
                    if is_eligible and ttd > (sr_remains + 5) then
                        table.insert(eligible_targets, enemy)
                    end
                end
            end

            -- If we found eligible targets, pick the one with lowest HP (best for execute)
            if #eligible_targets > 0 then
                local best_target = nil
                local lowest_hp = 100

                -- Find the enemy with lowest HP percentage
                for _, enemy in ipairs(eligible_targets) do
                    if enemy and enemy:is_valid() then
                        local hp_pct = enemy:get_health_percentage()
                        if hp_pct < lowest_hp then
                            lowest_hp = hp_pct
                            best_target = enemy
                        end
                    end
                end

                if best_target and best_target:is_valid() and me:can_attack(best_target) then
                    if spells.SOUL_REAPER:cast_safe(best_target, "Soul Reaper") then
                        return true
                    end
                end
            end
        end
    end

    -- Priority 9: Marrowrend for Bone Shield stacks
    if not bone_shield_manager.block_rune_spending then
        -- Condition 1: Below 7 stacks of Bone Shield and Bonestorm is not active
        local below_7_stacks = bone_shield_manager.bone_shield_stacks < 7
        local no_bonestorm = not me:has_debuff(base.DEBUFF_BONESTORM)
        local bone_shield_condition = below_7_stacks and no_bonestorm

        -- Condition 2: At 2 stacks of Exterminate and Reaper's Mark debuff will explode in next 5 seconds
        local exterminate_stacks = me:get_buff_stacks(BUFF_EXTERMINATE)
        local at_2_exterminate = exterminate_stacks == 2
        local exterminate_condition = false

        if at_2_exterminate and target and target:is_valid() and me:can_attack(target) then
            local rm_explodes_soon = reapers_mark_explodes_soon(target, base)
            exterminate_condition = rm_explodes_soon
        end

        -- Cast if either condition is met
        if bone_shield_condition or exterminate_condition then
            if can_afford_rune_spender(me, 2, true, menu, gcd) then
                if spells.MARROWREND:cast_safe(target, "Marrowrend [Stack Maintenance]") then
                    return true
                end
            end
        end
    end

    -- Priority 10: Tombstone
    if menu.TOMBSTONE_CHECK:get_state() and spells.TOMBSTONE:is_learned() and spells.TOMBSTONE:is_castable() then
        -- Check DRW buff directly to ensure it's not active (don't rely on cached has_drw)
        if bone_shield_manager.bone_shield_stacks > 7 and me:has_buff(base.BUFF_DEATH_AND_DECAY) and not me:has_buff(base.BUFF_DANCING_RUNE_WEAPON) then
            local drw_cd = spells.DANCING_RUNE_WEAPON:cooldown_remains()
            if drw_cd > 25 then
                if spells.TOMBSTONE:cast_safe(nil, "Tombstone") then
                    return true
                end
            end
        end
    end

    -- Priority 11: Death and Decay
    if not bone_shield_manager.block_rune_spending then
        if not me:has_buff(base.BUFF_DEATH_AND_DECAY) then
            if can_afford_rune_spender(me, 1, true, menu, gcd) then
                if base.cast_death_and_decay(me, spells, menu) then
                    return true
                end
            end
        end
    end

    -- Priority 12: Blood Boil first in DRW
    if not bone_shield_manager.block_rune_spending then
        if has_drw and not resource_manager.drw_blood_boil_casted then
            if spells.BLOOD_BOIL:is_castable() and can_afford_rune_spender(me, 1, true, menu, gcd) then
                local success, new_drw_state = base.cast_blood_boil_simple(
                    me, enemies, spells, "Blood Boil [First in DRW]",
                    resource_manager.drw_blood_boil_casted
                )
                if success then
                    resource_manager.drw_blood_boil_casted = new_drw_state
                    return true
                end
            end
        end
    end

    -- Priority 13: Marrowrend with Exterminate
    if not bone_shield_manager.block_rune_spending then
        if me:has_buff(BUFF_EXTERMINATE) and not has_drw then
            if can_afford_rune_spender(me, 2, true, menu, gcd) then
                if spells.MARROWREND:cast_safe(target, "Marrowrend [Exterminate]") then
                    return true
                end
            end
        end
    end

    -- Priority 14: Heart Strike with 2+ runes
    if not bone_shield_manager.block_rune_spending then
        if me:rune_count() >= 2 and can_afford_rune_spender(me, 1, true, menu, gcd) then
            if base.cast_heart_strike(target, spells, "Heart Strike") then
                return true
            end
        end
    end

    -- Priority 15: Consumption
    if not bone_shield_manager.block_rune_spending then
        if spells.CONSUMPTION:is_learned() and spells.CONSUMPTION:is_castable() then
            if can_afford_rune_spender(me, 1, true, menu, gcd) then
                if spells.CONSUMPTION:cast_safe(nil, "Consumption") then
                    return true
                end
            end
        end
    end

    -- Priority 16: Blood Boil
    if not bone_shield_manager.block_rune_spending then
        if spells.BLOOD_BOIL:is_castable() and can_afford_rune_spender(me, 1, true, menu, gcd) then
            local success, new_drw_state = base.cast_blood_boil_simple(
                me, enemies, spells, "Blood Boil",
                resource_manager.drw_blood_boil_casted
            )
            if success then
                resource_manager.drw_blood_boil_casted = new_drw_state
                return true
            end
        end
    end

    -- Priority 17: Heart Strike
    if not bone_shield_manager.block_rune_spending then
        if can_afford_rune_spender(me, 1, true, menu, gcd) then
            if base.cast_heart_strike(target, spells, "Heart Strike") then
                return true
            end
        end
    end

    -- Priority 18: Death's Caress
    if spells.DEATHS_CARESS:is_castable() then
        if spells.DEATHS_CARESS:cast_safe(target, "Death's Caress") then
            return true
        end
    end

    return false
end

return M
