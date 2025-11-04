---@diagnostic disable: undefined-global, lowercase-global
--[[
    Blood Death Knight - Defensive Systems Module

    Purpose: All defensive cooldown logic in priority order
    Main function: execute(me, spells, menu, buffs, debuffs, resource_manager, targeting, gcd)

    Handles:
    - IBF (stun break)
    - AMS (Anti-Magic Shell)
    - AMZ (Anti-Magic Zone)
    - Vampiric Blood
    - DRW (Dancing Rune Weapon - defensive usage)
    - Rune Tap

    Priority Order:
    0. Icebound Fortitude (Stun Break) - Emergency
    1. Anti-Magic Shell (100% magic mitigation)
    1.5. Anti-Magic Zone (Group magic DR)
    2. Vampiric Blood (~50%+ mitigation)
    3. Dancing Rune Weapon (~50% parry if parryable, defensive only)
    4. Icebound Fortitude (30%+ mitigation)
    5. Rune Tap (20% mitigation)

    Extracted from: main.lua (defensives() function)
]]

local izi = require("common/izi_sdk")
local enums = require("common/enums")
local BUFFS = enums.buff_db

local M = {}

-- Buff constants
local BUFF_DANCING_RUNE_WEAPON = BUFFS.DANCING_RUNE_WEAPON
local BUFF_VAMPIRIC_BLOOD = 55233
local BUFF_ICEBOUND_FORTITUDE = 48792
local BUFF_ANTI_MAGIC_SHELL = 48707

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

---Safe wrapper for SDK calls with error handling
---@param fn function
---@param default any
---@return any
local function safe_call(fn, default)
    local success, result = pcall(fn)
    if not success then
        return default
    end
    return result
end

---Check if we have multiple strong defensives active (avoid stacking)
---@param me game_object
---@return boolean
local function has_stacked_defensive(me)
    -- Check for multiple strong defensives active
    local active_count = 0
    if me:has_buff(BUFF_VAMPIRIC_BLOOD) then
        active_count = active_count + 1
    end
    if me:has_buff(BUFF_DANCING_RUNE_WEAPON) then
        active_count = active_count + 1
    end
    if me:has_buff(BUFF_ICEBOUND_FORTITUDE) then
        active_count = active_count + 1
    end
    if me:has_buff(BUFF_ANTI_MAGIC_SHELL) then
        active_count = active_count + 1
    end

    -- Only stack if we have 2+ active (for extreme situations)
    return active_count >= 2
end

---Check if Anti-Magic Zone should be used (performance-optimized)
---@param me game_object
---@return boolean should_use
local function should_use_anti_magic_zone(me)
    -- Fast self check first (avoids party iteration if not needed)
    if not me:is_magical_damage_taken_relevant() then
        return false
    end

    -- Only check party if self has magical damage
    local party_members = me:get_party_members_in_range(40)
    if not party_members or #party_members == 0 then
        return false
    end

    -- Check if at least one party member has magical damage
    for _, member in ipairs(party_members) do
        if member and member:is_valid() and member:is_alive() then
            if member:is_magical_damage_taken_relevant() then
                return true  -- Self + at least one party member taking magical damage
            end
        end
    end

    return false
end

---Death Strike debugging helper
---@param me game_object
---@param reason string
---@param runic_power number
---@param runic_power_deficit number
---@param runes number
local function log_death_strike(me, reason, runic_power, runic_power_deficit, runes)
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
-- MAIN DEFENSIVE EXECUTION FUNCTION
-- ============================================================================

---Execute defensive cooldown logic
---@param me game_object Player unit
---@param spells table Spell table from spells.lua
---@param menu table Menu configuration
---@param buffs table Buff constants
---@param debuffs table Debuff constants (unused but kept for consistency)
---@param resource_manager table Resource manager with runic_power, runes, etc
---@param targeting table Targeting information (target, enemies, etc)
---@param gcd number Global cooldown duration
---@return boolean true if an action was taken, false otherwise
function M.execute(me, spells, menu, buffs, debuffs, resource_manager, targeting, gcd)
    if not me or not me:is_valid() then
        return false
    end

    -- Extract resources for convenience
    local runic_power = resource_manager.runic_power or 0
    local runic_power_deficit = resource_manager.runic_power_deficit or 0
    local runes = resource_manager.runes or 0
    local target = targeting.target

    -- Priority 0: Icebound Fortitude Stun Break (emergency)
    -- Break stuns immediately - critical for survival
    if spells.ICEBOUND_FORTITUDE:is_learned() and spells.ICEBOUND_FORTITUDE:is_castable() then
        if not me:has_buff(BUFF_ICEBOUND_FORTITUDE) then
            -- Check if player is stunned
            local is_stunned, _ = me:is_stunned()
            if is_stunned then
                local opts = { skip_gcd = true }
                if spells.ICEBOUND_FORTITUDE:cast_safe(me, "Icebound Fortitude [Stun Break]", opts) then
                    return true
                end
            end
        end
    end

    -- Priority 1: Anti-Magic Shell (100% mitigation if magic)
    -- Situational: Prevent debuff application and mitigate magic damage
    -- Also used as last resort when interrupts are unavailable and we have incoming damage
    -- Don't stack unless necessary (magic damage is extreme)
    if menu.AMS_CHECK:get_state() then
        if not me:has_buff(BUFF_ANTI_MAGIC_SHELL) then
            if spells.ANTI_MAGIC_SHELL:is_castable() then
                local is_magical_relevant = me:is_magical_damage_taken_relevant()
                local magical_pct = me:get_magical_damage_taken_percentage(3.0)
                local magic_threshold = menu.AMS_MAGICAL_DMG_PCT:get()
                local current_hp = me:get_health_percentage()
                local hp_threshold = menu.AMS_HP:get()

                -- Check if all interrupts are on cooldown (last resort scenario)
                local all_interrupts_on_cd = false
                if spells.ASPHYXIATE:is_learned() and spells.BLINDING_SLEET:is_learned() then
                    local asphyxiate_on_cd = not spells.ASPHYXIATE:cooldown_up()
                    local blinding_sleet_on_cd = not spells.BLINDING_SLEET:cooldown_up()
                    local death_grip_on_cd = spells.DEATH_GRIP:is_learned() and spells.DEATH_GRIP:charges() == 0
                    all_interrupts_on_cd = asphyxiate_on_cd and blinding_sleet_on_cd and death_grip_on_cd
                end

                -- Check for incoming casts at us (when interrupts unavailable)
                local has_incoming_casts = false
                if all_interrupts_on_cd then
                    local enemies = izi.enemies(40)
                    if enemies then
                        for _, enemy in ipairs(enemies) do
                            if enemy and enemy:is_valid() and enemy:is_alive() and me:can_attack(enemy) then
                                if (enemy:is_casting() or enemy:is_channeling()) and enemy:get_target() == me then
                                    has_incoming_casts = true
                                    break
                                end
                            end
                        end
                    end
                end

                -- Use on magical damage OR if HP threshold met with magical damage
                -- OR as last resort when interrupts are on CD and we have incoming damage
                local use_ams = false
                if (is_magical_relevant or magical_pct > magic_threshold) and current_hp <= hp_threshold then
                    use_ams = true
                elseif all_interrupts_on_cd and (has_incoming_casts or current_hp < 80) then
                    -- Last resort: interrupts unavailable and incoming damage
                    use_ams = true
                end

                if use_ams then
                    -- Check TTD from target selector (only use if target will live at least 10 seconds)
                    local valid_ttd = false
                    local targets = izi.get_ts_targets()
                    if targets and #targets > 0 then
                        for _, ts_target in ipairs(targets) do
                            if ts_target and ts_target:is_valid() and ts_target:is_alive() and me:can_attack(ts_target) then
                                local ttd = ts_target:time_to_die()
                                if ttd >= 10 then
                                    valid_ttd = true
                                    break
                                end
                            end
                        end
                    else
                        -- If no targets, assume valid (use for defensive purposes)
                        valid_ttd = true
                    end

                    if valid_ttd then
                        local message = all_interrupts_on_cd and "Anti-Magic Shell (Interrupts on CD)"
                                      or string.format("Anti-Magic Shell (%.0f%% magic)", magical_pct)
                        local opts = { skip_gcd = true }
                        if spells.ANTI_MAGIC_SHELL:cast_safe(me, message, opts) then
                            return true
                        end
                    end
                end
            end
        end
    end

    -- Priority 1.5: Anti-Magic Zone (Group magic DR ground-targeted)
    -- Use when both self and at least one party member are taking magical damage
    -- Performance-optimized: checks self first, only checks party if needed
    if spells.ANTI_MAGIC_ZONE:is_learned() and spells.ANTI_MAGIC_ZONE:is_castable() then
        if should_use_anti_magic_zone(me) then
            local self_pos = me:get_position()
            if spells.ANTI_MAGIC_ZONE:cast_safe(nil, "Anti-Magic Zone", {cast_pos = self_pos}) then
                return true
            end
        end
    end

    -- Priority 2: Vampiric Blood (~50%+ mitigation)
    -- Can be used reactively - health drops by up to 23% when buff expires
    -- Only check if we're not already stacking too many defensives
    -- Note: Vampiric Blood is a base health increase defensive, not damage-type specific
    if not has_stacked_defensive(me) then
        if menu.validate_vampiric_blood(me) then
            if not me:has_buff(BUFF_VAMPIRIC_BLOOD) then
                ---@type defensive_filters
                local vb_filters = {
                    health_percentage_threshold_raw = menu.VAMPIRIC_BLOOD_HP:get(),
                    health_percentage_threshold_incoming = menu.VAMPIRIC_BLOOD_INCOMING_HP:get(),
                    -- No physical/magical thresholds: VB is HP-based, not damage-type specific
                }
                local opts = { skip_gcd = true }
                if spells.VAMPIRIC_BLOOD_DEFENSIVE:cast_defensive(me, vb_filters, "Vampiric Blood", opts) then
                    return true
                end
            end
        end
    end

    -- Priority 3: Dancing Rune Weapon (~50% mitigation if parryable)
    -- NOTE: DRW is primarily used offensively and handled in rotation logic
    -- This defensive check is only for emergency situations when RP is low
    -- DRW increases RP generation when RP is low, making it more valuable defensively
    if menu.DRW_CHECK:get_state() then
        if not me:has_buff(BUFF_DANCING_RUNE_WEAPON) then
            if spells.DANCING_RUNE_WEAPON:is_castable() then
                -- Use defensively if RP is low AND health is low
                local rp_threshold = 40  -- Low RP threshold
                local hp_threshold = 50  -- Emergency HP threshold

                if runic_power < rp_threshold and me:get_health_percentage() <= hp_threshold then
                    -- Check TTD from target selector
                    local valid_ttd = false
                    local targets = izi.get_ts_targets()
                    if targets and #targets > 0 then
                        for _, ts_target in ipairs(targets) do
                            if ts_target and ts_target:is_valid() and ts_target:is_alive() and me:can_attack(ts_target) then
                                local ttd = ts_target:time_to_die()
                                if menu.validate_drw(ttd) then
                                    valid_ttd = true
                                    break
                                end
                            end
                        end
                    else
                        -- If no targets, assume valid (use for defensive purposes)
                        valid_ttd = true
                    end

                    if valid_ttd then
                        if spells.DANCING_RUNE_WEAPON:cast_safe(nil, "Dancing Rune Weapon [Defensive]") then
                            return true
                        end
                    end
                end
            end
        end
    end

    -- Priority 4: Icebound Fortitude (30%+ mitigation)
    -- Stun break and immunity - extremely useful when applicable
    -- Only check if we're not already stacking too many defensives
    if not has_stacked_defensive(me) then
        if menu.validate_icebound(me) then
            if not me:has_buff(BUFF_ICEBOUND_FORTITUDE) then
                ---@type defensive_filters
                local icebound_filters = {
                    health_percentage_threshold_raw = menu.ICEBOUND_HP:get(),
                    health_percentage_threshold_incoming = menu.ICEBOUND_INCOMING_HP:get(),
                }
                local opts = { skip_gcd = true }
                if spells.ICEBOUND_FORTITUDE:cast_defensive(me, icebound_filters, "Icebound Fortitude", opts) then
                    return true
                end
            end
        end
    end

    -- Priority 5: Rune Tap (20% mitigation)
    -- Different usage pattern - costs RP generation potential
    -- Can be used even when stacking defensives (it's a weaker cooldown)
    if menu.validate_rune_tap(me) then
        if spells.RUNE_TAP:is_learned() and spells.RUNE_TAP:is_castable() then
            local opts = { skip_gcd = true }
            if spells.RUNE_TAP:cast_safe(nil, "Rune Tap", opts) then
                return true
            end
        end
    end

    -- Death Strike Emergency Healing (separate from defensive cooldowns)
    -- This is our reactive healing, not a defensive cooldown
    if menu.validate_death_strike_emergency(me) then
        if target and target:is_valid() then
            if spells.DEATH_STRIKE:cast_safe(target, "Death Strike [Emergency]") then
                log_death_strike(me, "EMERGENCY - HP threshold", runic_power, runic_power_deficit, runes)
                return true
            end
        end
    end

    return false
end

return M
