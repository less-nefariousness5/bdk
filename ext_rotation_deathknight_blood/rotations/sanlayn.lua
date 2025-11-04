---@diagnostic disable: undefined-global, lowercase-global
--[[
    Blood Death Knight - San'layn Hero Tree Rotations

    Complete rotation system for the San'layn hero tree.
    Features two rotation functions:
    - execute(): Normal San'layn rotation
    - execute_drw(): Aggressive DRW rotation with Vampiric Strike windows

    Version: 1.0.0
]]

local izi = require("common/izi_sdk")
local enums = require("common/enums")

-- Module table
local M = {}

-- ============================================================================
-- CONSTANTS
-- ============================================================================

-- Buff/Debuff IDs (San'layn specific)
local BUFF_ESSENCE_OF_THE_BLOOD_QUEEN = 433925
local BUFF_VAMPIRIC_STRIKE = 433895
local BUFF_CRIMSON_SCOURGE = 81141
local BUFF_VISCERAL_STRENGTH = 441417

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

---Check if Blood Plague is ticking from DRW
---@param me game_object
---@param enemies table
---@param base table Base rotation module
---@return boolean
local function drw_bp_ticking(me, enemies, base)
    -- Check if DRW recently cast Blood Boil (within last 2 seconds)
    local drw_remains = me:buff_remains_sec(base.BUFF_DANCING_RUNE_WEAPON)
    if drw_remains <= 0 then
        return false
    end

    -- Check if any enemy has Blood Plague
    for i = 1, #enemies do
        local enemy = enemies[i]
        if enemy and enemy:is_valid() and enemy:has_debuff(base.DEBUFF_BLOOD_PLAGUE) then
            return true
        end
    end

    return false
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

---Get effective RP capping threshold based on context
---@param me game_object
---@param has_drw boolean
---@param menu table Menu configuration
---@return number threshold
local function get_rp_capping_threshold(me, has_drw, menu)
    local base_threshold = menu.RP_CAPPING_THRESHOLD:get()

    -- Use aggressive threshold if aggressive spending is enabled
    if menu.AGGRESSIVE_RESOURCE_SPENDING:get_state() then
        base_threshold = base_threshold - 5
    end

    -- During DRW, RP generation is higher, so cap more aggressively
    if has_drw then
        return base_threshold + 10
    end

    return base_threshold
end

---Check if we should wait for rune RP generation
---@param me game_object
---@param gcd number Current GCD duration
---@return boolean should_wait
local function should_wait_for_rune_rp_generation(me, gcd)
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

---Check if we should pool RP for emergency healing
---@param me game_object
---@param runic_power number Current runic power
---@param menu table Menu configuration
---@return boolean should_pool
local function should_pool_rp_for_emergency(me, runic_power, menu)
    local pooling_threshold = menu.RP_POOLING_THRESHOLD:get()

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

---Get rune forecast information
---@param me game_object
---@return table {current_rune_count, time_to_1_rune}
local function get_rune_forecast(me)
    return {
        current_rune_count = me:rune_count(),
        time_to_1_rune = me:rune_time_to_x(1),
    }
end

-- ============================================================================
-- SAN'LAYN DRW ROTATION
-- ============================================================================

---Execute San'layn DRW rotation (aggressive Blood Boil spam, Vampiric Strike windows)
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
function M.execute_drw(me, spells, menu, buffs, debuffs, resource_manager, bone_shield_manager, targeting, base, gcd)
    local target = targeting.current_target
    local enemies = targeting.enemies
    local active_enemies = #enemies

    if not (target and target:is_valid() and me:can_attack(target)) then
        return false
    end

    -- RUNE-COSTING ABILITIES: Block if we're saving runes for Bone Shield
    if not bone_shield_manager.block_rune_spending then
        -- heart_strike,if=buff.essence_of_the_blood_queen.remains<1.5&buff.essence_of_the_blood_queen.remains
        if me:has_buff(BUFF_ESSENCE_OF_THE_BLOOD_QUEEN) then
            local essence_remains = me:buff_remains_sec(BUFF_ESSENCE_OF_THE_BLOOD_QUEEN)
            if essence_remains < 1.5 and essence_remains > 0 and can_afford_rune_spender(me, 1, true, menu, gcd) then
                if base.cast_heart_strike(target, spells, "Heart Strike [Essence Snipe]") then
                    return true
                end
            end
        end
    end

    -- bonestorm,if=buff.bone_shield.stack>=5&buff.death_and_decay.up&!buff.dancing_rune_weapon.up
    if menu.BONESTORM_CHECK:get_state() and spells.BONESTORM:is_learned() and spells.BONESTORM:is_castable() then
        -- Check DRW buff directly to ensure it's not active
        local drw_active = me:has_buff(base.BUFF_DANCING_RUNE_WEAPON)

        if bone_shield_manager.bone_shield_stacks >= 5 and me:has_buff(base.BUFF_DEATH_AND_DECAY) and not drw_active then
            if spells.BONESTORM:cast_safe(nil, "Bonestorm") then
                return true
            end
        end
    end

    -- death_strike,if=runic_power.deficit<threshold (with resource pooling awareness)
    local rp_threshold = get_rp_capping_threshold(me, true, menu) -- DRW is active in this rotation
    local should_wait_for_rp = should_wait_for_rune_rp_generation(me, gcd)

    if resource_manager.runic_power_deficit < rp_threshold then
        -- Don't cap if we should pool for emergencies
        if not should_pool_rp_for_emergency(me, resource_manager.runic_power, menu) then
            -- Don't cap if runes will generate RP soon (unless we're really high)
            if not should_wait_for_rp or resource_manager.runic_power_deficit < 10 then
                local success, new_time = base.cast_death_strike(
                    me, target, spells, "CAPPING RP (San'layn DRW)",
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
    end

    -- RUNE-COSTING ABILITIES: Block if we're saving runes for Bone Shield
    if not bone_shield_manager.block_rune_spending then
        -- blood_boil,if=!drw.bp_ticking
        local bp_ticking = drw_bp_ticking(me, enemies, base)
        if not bp_ticking and spells.BLOOD_BOIL:is_castable() and can_afford_rune_spender(me, 1, true, menu, gcd) then
            local success, new_drw_state = base.cast_blood_boil_simple(
                me, enemies, spells, "Blood Boil",
                resource_manager.drw_blood_boil_casted
            )
            if success then
                resource_manager.drw_blood_boil_casted = new_drw_state
                return true
            end
        end

        -- any_dnd,if=(active_enemies<=3&buff.crimson_scourge.remains)|(active_enemies>3&!buff.death_and_decay.remains)
        local has_dnd = me:has_buff(base.BUFF_DEATH_AND_DECAY)
        local has_crimson = me:has_buff(BUFF_CRIMSON_SCOURGE)
        if (active_enemies <= 3 and has_crimson) or (active_enemies > 3 and not has_dnd) then
            if can_afford_rune_spender(me, 1, true, menu, gcd) then
                if base.cast_death_and_decay(me, spells, menu) then
                    return true
                end
            end
        end

        -- heart_strike
        if can_afford_rune_spender(me, 1, true, menu, gcd) then
            if base.cast_heart_strike(target, spells, "Heart Strike") then
                return true
            end
        end
    end  -- End of rune-costing block

    -- death_strike filler (only if RP very high and no runes available soon)
    if resource_manager.runic_power > 80 then
        local forecast = get_rune_forecast(me)
        -- Only use if we have no runes and they won't be available soon
        if forecast.current_rune_count == 0 then
            if forecast.time_to_1_rune > (gcd + menu.RUNE_FORECAST_WINDOW:get()) or forecast.time_to_1_rune <= 0 then
                if not should_pool_rp_for_emergency(me, resource_manager.runic_power, menu) then
                    local success, new_time = base.cast_death_strike(
                        me, target, spells, "FILLER (San'layn DRW)",
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
        end
    end
    -- Otherwise, wait for runes to regenerate

    -- RUNE-COSTING ABILITIES: Block if we're saving runes for Bone Shield
    if not bone_shield_manager.block_rune_spending then
        -- consumption
        if spells.CONSUMPTION:is_learned() and spells.CONSUMPTION:is_castable() then
            if can_afford_rune_spender(me, 1, true, menu, gcd) then
                if spells.CONSUMPTION:cast_safe(nil, "Consumption") then
                    return true
                end
            end
        end

        -- blood_boil
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
    end  -- End of rune-costing block

    return false
end

-- ============================================================================
-- SAN'LAYN NORMAL ROTATION
-- ============================================================================

---Execute San'layn normal rotation priority list
---@param me game_object
---@param spells table Spell definitions
---@param menu table Menu configuration
---@param buffs table Buff tracker
---@param debuffs table Debuff tracker
---@param resource_manager table Resource pooling/forecasting
---@param bone_shield_manager table Bone Shield state
---@param targeting table Target selection helpers
---@param base table Base rotation module
---@param state_manager table State manager for DRW tracking
---@param gcd number Current GCD duration
---@return boolean success True if an action was taken
function M.execute(me, spells, menu, buffs, debuffs, resource_manager, bone_shield_manager, targeting, base, state_manager, gcd)
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

    -- Priority 2: Bone Shield Maintenance (2a/2b/2c)
    if not bone_shield_manager.block_rune_spending then
        local bone_shield_active = me:has_buff(base.BUFF_BONE_SHIELD)
        local bone_shield_low = not bone_shield_active or bone_shield_manager.bone_shield_remains < 5 or bone_shield_manager.bone_shield_stacks < 3

        if bone_shield_low then
            -- Priority 2a: Blood Boil (if 2+ enemies)
            if active_enemies >= 2 then
                if spells.BLOOD_BOIL:is_castable() and can_afford_rune_spender(me, 1, true, menu, gcd) then
                    local success, new_drw_state = base.cast_blood_boil_simple(
                        me, enemies, spells, "Blood Boil [Bone Shield]",
                        resource_manager.drw_blood_boil_casted
                    )
                    if success then
                        resource_manager.drw_blood_boil_casted = new_drw_state
                        return true
                    end
                end
            end

            -- Priority 2b: Death's Caress
            if spells.DEATHS_CARESS:is_castable() then
                if spells.DEATHS_CARESS:cast_safe(target, "Death's Caress [Bone Shield]") then
                    return true
                end
            end

            -- Priority 2c: Marrowrend
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

    -- Priority 4: Heart Strike with DRW for Essence of the Blood Queen
    if not bone_shield_manager.block_rune_spending then
        if has_drw and me:has_buff(BUFF_ESSENCE_OF_THE_BLOOD_QUEEN) then
            local essence_remains = me:buff_remains_sec(BUFF_ESSENCE_OF_THE_BLOOD_QUEEN)
            if essence_remains < 1.5 and essence_remains > 0 then
                if can_afford_rune_spender(me, 1, true, menu, gcd) then
                    if base.cast_heart_strike(target, spells, "Heart Strike [Essence]") then
                        return true
                    end
                end
            end
        end
    end

    -- Priority 5: Bonestorm
    if menu.BONESTORM_CHECK:get_state() and spells.BONESTORM:is_learned() and spells.BONESTORM:is_castable() then
        -- Check DRW buff directly to ensure it's not active (don't rely on cached has_drw)
        local drw_active = me:has_buff(base.BUFF_DANCING_RUNE_WEAPON)

        -- Bonestorm should only be used when DRW is NOT active and Death and Decay IS active
        if bone_shield_manager.bone_shield_stacks > 6 and me:has_buff(base.BUFF_DEATH_AND_DECAY) and not drw_active then
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

    -- Priority 8: Soul Reaper
    if menu.SOUL_REAPER_CHECK:get_state() and spells.SOUL_REAPER:is_learned() and spells.SOUL_REAPER:is_castable() then
        if active_enemies <= 2 and target and target:is_valid() and not has_drw then
            local hp_pct = target:get_health_percentage()
            if hp_pct <= 35 then
                local ttd = target:time_to_die()
                local sr_remains = target:debuff_remains_sec(base.DEBUFF_SOUL_REAPER)
                if ttd > (sr_remains + 5) then
                    if spells.SOUL_REAPER:cast_safe(target, "Soul Reaper") then
                        return true
                    end
                end
            end
        end
    end

    -- Priority 9: Bone Shield Maintenance (9a/9b/9c)
    if not bone_shield_manager.block_rune_spending then
        local below_8_stacks = bone_shield_manager.bone_shield_stacks < 8
        local below_7_stacks = bone_shield_manager.bone_shield_stacks < 7
        local no_bonestorm = not me:has_debuff(base.DEBUFF_BONESTORM)

        if (below_8_stacks or below_7_stacks) and no_bonestorm then
            -- Priority 9a: Blood Boil if below 8 stacks AND Bonestorm not active AND 2+ enemies
            if below_8_stacks and active_enemies >= 2 then
                if spells.BLOOD_BOIL:is_castable() and can_afford_rune_spender(me, 1, true, menu, gcd) then
                    local success, new_drw_state = base.cast_blood_boil_simple(
                        me, enemies, spells, "Blood Boil [Stack Maintenance]",
                        resource_manager.drw_blood_boil_casted
                    )
                    if success then
                        resource_manager.drw_blood_boil_casted = new_drw_state
                        return true
                    end
                end
            end

            -- Priority 9b: Death's Caress if below 7 stacks AND Bonestorm not active
            if below_7_stacks then
                if spells.DEATHS_CARESS:is_castable() then
                    if spells.DEATHS_CARESS:cast_safe(target, "Death's Caress [Stack Maintenance]") then
                        return true
                    end
                end
            end

            -- Priority 9c: Marrowrend if below 7 stacks AND Bonestorm not active
            if below_7_stacks then
                if can_afford_rune_spender(me, 2, true, menu, gcd) then
                    if spells.MARROWREND:cast_safe(target, "Marrowrend [Stack Maintenance]") then
                        return true
                    end
                end
            end
        end
    end

    -- Priority 10: Tombstone
    if menu.TOMBSTONE_CHECK:get_state() and spells.TOMBSTONE:is_learned() and spells.TOMBSTONE:is_castable() then
        -- Check DRW buff directly to ensure it's not active (don't rely on cached has_drw)
        local drw_active = me:has_buff(base.BUFF_DANCING_RUNE_WEAPON)

        -- Tombstone should only be used when DRW is NOT active and Death and Decay IS active
        if bone_shield_manager.bone_shield_stacks > 7 and me:has_buff(base.BUFF_DEATH_AND_DECAY) and not drw_active then
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
            local has_crimson = me:has_buff(BUFF_CRIMSON_SCOURGE)
            local has_visceral = me:has_buff(BUFF_VISCERAL_STRENGTH)

            -- 4+ targets OR (Crimson Scourge active AND Visceral Strength not active)
            if active_enemies >= 4 or (has_crimson and not has_visceral) then
                if can_afford_rune_spender(me, 1, true, menu, gcd) then
                    if base.cast_death_and_decay(me, spells, menu) then
                        return true
                    end
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
