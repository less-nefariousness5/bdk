---@diagnostic disable: undefined-global, lowercase-global
local izi = require("common/izi_sdk")
local enums = require("common/enums")
local BUFFS = enums.buff_db
local SPELLS = require("spells")
local menu = require("menu")
local unit_helper = require("common/utility/unit_helper")
local dungeons_helper = require("common/utility/dungeons_helper")
local legion_esp = require("modules/qol/legion_remix_esp")
local legion_remix = require("modules/qol/legion_remix")
local auto_loot = require("modules/qol/auto_loot")
local anti_afk = require("modules/qol/anti_afk")
local health_potion = require("modules/qol/health_potion")

-- Cached values (updated each frame)
local ping_ms = 0
local ping_sec = 0
local gcd = 0
local runic_power = 0
local runic_power_deficit = 0
local runes = 0
local bone_shield_stacks = 0
local bone_shield_remains = 0  -- Cached: remaining duration of Bone Shield buff in seconds
local block_rune_spending = false  -- Cached: should we block rune spenders for Bone Shield emergency

-- Remix Time spell tables
local REMIX_TIME_OFFENSIVE_SPELLS = {
    SPELLS.DANCING_RUNE_WEAPON,
    SPELLS.TOMBSTONE,
    SPELLS.BONESTORM,
}

local REMIX_TIME_DEFENSIVE_SPELLS = {
    SPELLS.DANCING_RUNE_WEAPON,
    SPELLS.ICEBOUND_FORTITUDE,
    SPELLS.VAMPIRIC_BLOOD,
}

-- State tracking for DRW Blood Boil
local drw_blood_boil_casted = false  -- Track if Blood Boil was cast in current DRW window
local last_drw_start_time = 0  -- Track when DRW started
local last_death_strike_time = 0  -- Track last Death Strike cast time to prevent back-to-back

-- Death Strike debugging
local function log_death_strike(me, reason)
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

-- Use BUFFS from buff_db where available, otherwise use spell IDs directly
local BUFF_BONE_SHIELD = BUFFS.BONE_SHIELD
local BUFF_DANCING_RUNE_WEAPON = BUFFS.DANCING_RUNE_WEAPON
local BUFF_DEATH_AND_DECAY = BUFFS.DEATH_AND_DECAY
local DEBUFF_BLOOD_PLAGUE = BUFFS.BLOOD_PLAGUE

-- Blood DK specific buffs not in buff_db (use spell IDs)
local BUFF_VAMPIRIC_BLOOD = 55233
local BUFF_ICEBOUND_FORTITUDE = 48792
local BUFF_ANTI_MAGIC_SHELL = 48707
local BUFF_CRIMSON_SCOURGE = 81141
local BUFF_COAGULOPATHY = 391481
local BUFF_REAPER_OF_SOULS = 440002
local BUFF_ESSENCE_OF_THE_BLOOD_QUEEN = 433925
local BUFF_VAMPIRIC_STRIKE = 433895
local BUFF_INFLICTION_OF_SORROW = 460049
local BUFF_EXTERMINATE = 441416
local BUFF_VISCERAL_STRENGTH = 441417  -- San'layn Visceral Strength buff
local DEBUFF_SOUL_REAPER = 343294
local DEBUFF_BONESTORM = 194844
local DEBUFF_REAPERS_MARK = 439843  -- Reaper's Mark debuff (same as spell ID)

-- Blood Plague pandemic threshold (30% of 24 second duration)
local BLOOD_PLAGUE_DURATION_SEC = 24
local BLOOD_PLAGUE_PANDEMIC_THRESHOLD_SEC = BLOOD_PLAGUE_DURATION_SEC * 0.30
local BLOOD_PLAGUE_PANDEMIC_MS = BLOOD_PLAGUE_PANDEMIC_THRESHOLD_SEC * 1000

-- Hero tree tracking
local HERO_TREE_DEATHBRINGER = 1
local HERO_TREE_SANLAYN = 2
local detected_hero_tree = 0

-- Helper function: Check if player has ghoul
---@param unit game_object
---@return boolean
local function unit_has_ghoul(unit)
    local minions = unit:get_all_minions()
    for i = 1, #minions do
        local minion = minions[i]
        if minion and minion:is_valid() then
            local npc_id = minion:get_npc_id()
            -- Ghoul NPC IDs: 26125 (normal), 31216 (army)
            if npc_id == 26125 or npc_id == 31216 then
                return true
            end
        end
    end
    return false
end

-- Helper function: Check if Blood Plague is ticking from DRW
---@param me game_object
---@return boolean
local function drw_bp_ticking(me, enemies)
    -- Check if DRW recently cast Blood Boil (within last 2 seconds)
    local drw_remains = me:buff_remains_sec(BUFF_DANCING_RUNE_WEAPON)
    if drw_remains <= 0 then
        return false
    end

    -- Check if any enemy has Blood Plague
    for i = 1, #enemies do
        local enemy = enemies[i]
        if enemy and enemy:is_valid() and enemy:has_debuff(DEBUFF_BLOOD_PLAGUE) then
            return true
        end
    end

    return false
end

---Check if Reaper's Mark debuff will explode soon (within 5 seconds)
---@param target game_object
---@return boolean
local function reapers_mark_explodes_soon(target)
    if not target or not target:is_valid() then
        return false
    end
    local debuff_remains = target:debuff_remains_sec(DEBUFF_REAPERS_MARK)
    return debuff_remains > 0 and debuff_remains <= 5
end

-- Detect hero tree (based on heroic talent IDs)
---@param me game_object
---@return number|nil Returns HERO_TREE_DEATHBRINGER, HERO_TREE_SANLAYN, or nil for leveling
local function detect_hero_tree(me)
    -- Check menu override first
    local menu_choice = menu.HERO_TREE_SELECT:get()
    if menu_choice == 2 then
        return HERO_TREE_DEATHBRINGER
    elseif menu_choice == 3 then
        return HERO_TREE_SANLAYN
    end

    -- Auto-detect based on heroic talent IDs
    -- Talent 439843 (Reaper's Mark spell) = Deathbringer rotation
    -- Talent/Spell 433901 = San'layn rotation
    -- Use spell.is_learned() to check if talents/spells are learned
    local has_reapers_mark_talent = SPELLS.REAPERS_MARK:is_learned()
    
    -- Check San'layn talent/spell (433901) - create a temporary spell object to check
    local sanlayn_spell = izi.spell(433901)
    local has_sanlayn_talent = sanlayn_spell:is_learned()
    
    if has_reapers_mark_talent then
        return HERO_TREE_DEATHBRINGER
    elseif has_sanlayn_talent then
        return HERO_TREE_SANLAYN
    end

    -- Neither talent learned = leveling (return nil to use default/leveling rotation)
    -- The rotation continues naturally without special routing
    return nil  -- Indicates leveling/no hero tree
end

-- ============================================================================
-- RESOURCE FORECASTING & POOLING HELPERS
-- ============================================================================

---Get rune forecast information
---@param me game_object
---@return table {current_rune_count, time_to_1_rune, time_to_2_runes, time_to_3_runes, time_to_4_runes}
local function get_rune_forecast(me)
    return {
        current_rune_count = me:rune_count(),
        time_to_1_rune = me:rune_time_to_x(1),
        time_to_2_runes = me:rune_time_to_x(2),
        time_to_3_runes = me:rune_time_to_x(3),
        time_to_4_runes = me:rune_time_to_x(4),
    }
end

---Check if we should save runes for a specific ability
---@param me game_object
---@param runes_needed integer
---@param forecast_window number Optional forecast window in seconds (default from menu)
---@return boolean should_save
local function should_save_runes_for_ability(me, runes_needed, forecast_window)
    forecast_window = forecast_window or menu.RUNE_FORECAST_WINDOW:get()
    
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

---Check if we can afford a rune spender considering future rune availability
---@param me game_object
---@param rune_cost integer
---@param check_future boolean Check future rune availability
---@return boolean can_afford
local function can_afford_rune_spender(me, rune_cost, check_future)
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

---Check if we should pool RP for DRW
---@param me game_object
---@return boolean should_pool
local function should_pool_rp_for_drw(me)
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
---@param me game_object
---@return boolean should_pool
local function should_pool_rp_for_emergency(me)
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

---Check if we should avoid spending RP (will generate RP soon from runes)
---@param me game_object
---@return boolean should_wait
local function should_wait_for_rune_rp_generation(me)
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

---Get effective RP capping threshold based on context
---@param me game_object
---@param has_drw boolean
---@return number threshold
local function get_rp_capping_threshold(me, has_drw)
    local base_threshold = menu.RP_CAPPING_THRESHOLD:get()
    
    -- Use aggressive threshold if aggressive spending is enabled
    if menu.AGGRESSIVE_RESOURCE_SPENDING:get_state() then
        base_threshold = base_threshold - 5
    end
    
    -- During DRW, RP generation is higher, so cap more aggressively
    if has_drw then
        return base_threshold + 10
    end
    
    -- Don't cap if DRW is coming soon (pool for burst)
    if should_pool_rp_for_drw(me) then
        return base_threshold + 20
    end
    
    return base_threshold
end

-- ============================================================================
-- CUSTOM FUNCTIONS: Utility
-- ============================================================================

---@param me game_object
---@return boolean
local function utility(me)
    -- Auto summon ghoul (only in combat)
    if menu.AUTO_RAISE_DEAD_CHECK:get_state() then
        if me:affecting_combat() then
            if not unit_has_ghoul(me) then
                if SPELLS.RAISE_DEAD:cast_safe(nil, "Raise Dead") then
                    return true
                end
            end
        end
    end

    -- Raise Ally (in-combat resurrection with mouseover logic)
    if menu.RAISE_ALLY_CHECK:get_state() then
        -- Only use in combat (Raise Ally is combat rez)
        if me:affecting_combat() then
            -- Don't attempt rez if already casting or channeling
            if not me:is_casting() and not me:is_channeling() then
                -- Get mouseover target using core API
                local mouseover = core.object_manager.get_mouse_over_object()
                
                -- Check if mouseover is a dead party/raid member
                if mouseover and mouseover:is_valid() then
                    if mouseover:is_dead() and not mouseover:is_ghost() then
                        -- Check if it's a party member
                        if mouseover:is_party_member() then
                            -- Check if spell is learned and castable
                            if SPELLS.RAISE_ALLY:is_learned() and SPELLS.RAISE_ALLY:is_castable() then
                                if SPELLS.RAISE_ALLY:cast_safe(mouseover, "Raise Ally") then
                                    return true
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Taunts (Dark Command and Death Grip)
    -- Only taunt when we have NO threat (threat_percent = 0 or very low)
    -- Dark Command is used first, Death Grip is fallback
    if menu.DARK_COMMAND_CHECK:get_state() or menu.DEATH_GRIP_TAUNT_CHECK:get_state() then
        if me:affecting_combat() then
            local enemies = izi.enemies(40)
            if enemies then
                for _, enemy in ipairs(enemies) do
                    if enemy and enemy:is_valid() and enemy:is_alive() and me:can_attack(enemy) then
                        -- Check if enemy is a boss (skip bosses)
                        if unit_helper:is_boss(enemy) then
                            goto continue_taunt
                        end
                        
                        -- Check threat status using get_threat_situation
                        local threat_data = enemy:get_threat_situation(me)
                        
                        -- Only taunt if we have NO threat (threat_percent is 0 or very low, < 1%)
                        -- This ensures we only taunt when we've lost threat, not when we have any threat
                        if threat_data and (threat_data.threat_percent == nil or threat_data.threat_percent < 1.0) then
                            -- Try Dark Command first (if enabled and in a dungeon)
                            -- Dark Command should only be used in dungeons, not open world
                            if menu.DARK_COMMAND_CHECK:get_state() then
                                -- Check if we're in a dungeon (heroic, mythic, or mythic+)
                                local in_dungeon = dungeons_helper:is_heroic_dungeon() or 
                                                 dungeons_helper:is_mythic_dungeon() or 
                                                 dungeons_helper:is_mythic_plus_dungeon()
                                
                                if in_dungeon and SPELLS.DARK_COMMAND:is_learned() and SPELLS.DARK_COMMAND:is_castable() then
                                    if SPELLS.DARK_COMMAND:cast_safe(enemy, "Dark Command (Taunt)") then
                                        return true
                                    end
                                end
                            end
                            
                            -- Fallback to Death Grip as taunt (only if Dark Command is disabled or not available)
                            if menu.DEATH_GRIP_TAUNT_CHECK:get_state() then
                                -- Only use Death Grip if Dark Command is disabled or not available
                                local use_death_grip = not menu.DARK_COMMAND_CHECK:get_state() or 
                                                      (SPELLS.DARK_COMMAND:is_learned() and not SPELLS.DARK_COMMAND:is_castable())
                                if use_death_grip and SPELLS.DEATH_GRIP:is_learned() and SPELLS.DEATH_GRIP:is_castable() then
                                    if SPELLS.DEATH_GRIP:cast_safe(enemy, "Death Grip (Taunt)") then
                                        return true
                                    end
                                end
                            end
                        end
                        
                        ::continue_taunt::
                    end
                end
            end
        end
    end

    -- Auto loot (out of combat only)
    if menu.AUTO_LOOT:get_state() and not me:affecting_combat() then
        auto_loot.update(me, menu)
    end

    -- Anti-AFK (always runs when enabled, not just in combat)
    anti_afk.update(me, menu)

    -- Health potion
    health_potion.update(me, menu)

    -- Remix Time (automatically refresh cooldowns)
    local remix_time_mode = menu.REMIX_TIME_MODE:get()
    if remix_time_mode > 1 then
        -- Get the appropriate spell table based on mode (2 = Offensive, 3 = Defensive)
        local spell_table = remix_time_mode == 2 and REMIX_TIME_OFFENSIVE_SPELLS or REMIX_TIME_DEFENSIVE_SPELLS
        
        -- Check if all spells in the table are learned and on cooldown
        local all_learned = true
        local all_on_cooldown = true
        local max_cooldown_sec = 0
        
        for _, spell in ipairs(spell_table) do
            -- First check if spell is learned (ALL must be learned)
            if not spell:is_learned() then
                all_learned = false
                break
            end
            
            -- Check if buff/debuff is active (don't use Remix Time if any cooldown is currently active)
            local is_active = false
            
            -- Check for active buffs (DRW has a buff, others might not)
            if spell == SPELLS.DANCING_RUNE_WEAPON then
                is_active = me:has_buff(BUFF_DANCING_RUNE_WEAPON)
            elseif spell == SPELLS.BONESTORM then
                is_active = me:has_debuff(DEBUFF_BONESTORM)
            end
            
            -- If any cooldown is active, don't use Remix Time
            if is_active then
                all_on_cooldown = false
                break
            end
            
            -- Get cooldown remaining time
            local cooldown_sec = spell:cooldown_remains()
            
            -- Track max cooldown for reference
            if cooldown_sec > max_cooldown_sec then
                max_cooldown_sec = cooldown_sec
            end
            
            -- If any spell is not on cooldown (cooldown is 0 or negative), don't use Remix Time
            if cooldown_sec <= 0 then
                all_on_cooldown = false
                break
            end
            
            -- Check if this spell's cooldown meets the minimum threshold
            -- ALL spells must be >= threshold for Remix Time to be used
            local min_cooldown_sec = menu.REMIX_TIME_MIN_COOLDOWN:get()
            if cooldown_sec < min_cooldown_sec then
                all_on_cooldown = false
                break
            end
        end
        
        -- Only cast Remix Time if ALL spells are learned, ALL are on cooldown,
        -- and ALL cooldowns are >= minimum threshold
        if all_learned and all_on_cooldown then
            -- Check if Remix Time spell is available
            if SPELLS.REMIX_TIME:is_learned() then
                if SPELLS.REMIX_TIME:is_castable() then
                    if SPELLS.REMIX_TIME:cast_safe(nil, "Remix Time (Refresh Cooldowns)") then
                        return true
                    end
                end
            end
        end
    end

    return false
end

-- ============================================================================
-- CUSTOM FUNCTIONS: Defensives
-- ============================================================================

---Check if we should avoid stacking defensive cooldowns
---@param me game_object
---@return boolean true if we already have a strong defensive active
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

-- ============================================================================
-- HELPER: Check if Anti-Magic Zone should be used (performance-optimized)
-- ============================================================================
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

---@param me game_object
---@param target game_object
---@return boolean
local function defensives(me, target)
    -- Priority 0: Icebound Fortitude Stun Break (emergency)
    -- Break stuns immediately - critical for survival
    if SPELLS.ICEBOUND_FORTITUDE:is_learned() and SPELLS.ICEBOUND_FORTITUDE:is_castable() then
        if not me:has_buff(BUFF_ICEBOUND_FORTITUDE) then
            -- Check if player is stunned
            local is_stunned, _ = me:is_stunned()
            if is_stunned then
                local opts = { skip_gcd = true }
                if SPELLS.ICEBOUND_FORTITUDE:cast_safe(me, "Icebound Fortitude [Stun Break]", opts) then
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
            if SPELLS.ANTI_MAGIC_SHELL:is_castable() then
                local is_magical_relevant = me:is_magical_damage_taken_relevant()
                local magical_pct = me:get_magical_damage_taken_percentage(3.0)
                local magic_threshold = menu.AMS_MAGICAL_DMG_PCT:get()
                local current_hp = me:get_health_percentage()
                local hp_threshold = menu.AMS_HP:get()
                
                -- Check if all interrupts are on cooldown (last resort scenario)
                local all_interrupts_on_cd = false
                if SPELLS.ASPHYXIATE:is_learned() and SPELLS.BLINDING_SLEET:is_learned() then
                    local asphyxiate_on_cd = not SPELLS.ASPHYXIATE:cooldown_up()
                    local blinding_sleet_on_cd = not SPELLS.BLINDING_SLEET:cooldown_up()
                    local death_grip_on_cd = SPELLS.DEATH_GRIP:is_learned() and SPELLS.DEATH_GRIP:charges() == 0
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
                        if SPELLS.ANTI_MAGIC_SHELL:cast_safe(me, message, opts) then
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
    if SPELLS.ANTI_MAGIC_ZONE:is_learned() and SPELLS.ANTI_MAGIC_ZONE:is_castable() then
        if should_use_anti_magic_zone(me) then
            local self_pos = me:get_position()
            if SPELLS.ANTI_MAGIC_ZONE:cast_safe(nil, "Anti-Magic Zone", {cast_pos = self_pos}) then
                return true
            end
        end
    end

    -- Priority 2: Vampiric Blood (~50%+ mitigation)
    -- Can be used reactively - health drops by up to 23% when buff expires
    -- Only check if we're not already stacking too many defensives
    if not has_stacked_defensive(me) then
        if menu.validate_vampiric_blood(me) then
            if not me:has_buff(BUFF_VAMPIRIC_BLOOD) then
                ---@type defensive_filters
                local vb_filters = {
                    health_percentage_threshold_raw = menu.VAMPIRIC_BLOOD_HP:get(),
                    health_percentage_threshold_incoming = menu.VAMPIRIC_BLOOD_INCOMING_HP:get(),
                }
                local opts = { skip_gcd = true }
                if SPELLS.VAMPIRIC_BLOOD_DEFENSIVE:cast_defensive(me, vb_filters, "Vampiric Blood", opts) then
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
            if SPELLS.DANCING_RUNE_WEAPON:is_castable() then
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
                        if SPELLS.DANCING_RUNE_WEAPON:cast_safe(nil, "Dancing Rune Weapon [Defensive]") then
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
                if SPELLS.ICEBOUND_FORTITUDE:cast_defensive(me, icebound_filters, "Icebound Fortitude", opts) then
                    return true
                end
            end
        end
    end

    -- Priority 5: Rune Tap (20% mitigation)
    -- Different usage pattern - costs RP generation potential
    -- Can be used even when stacking defensives (it's a weaker cooldown)
    if menu.validate_rune_tap(me) then
        if SPELLS.RUNE_TAP:is_learned() and SPELLS.RUNE_TAP:is_castable() then
            local opts = { skip_gcd = true }
            if SPELLS.RUNE_TAP:cast_safe(nil, "Rune Tap", opts) then
                return true
            end
        end
    end

    -- Death Strike Emergency Healing (separate from defensive cooldowns)
    -- This is our reactive healing, not a defensive cooldown
    if menu.validate_death_strike_emergency(me) then
        if target and target:is_valid() then
            if SPELLS.DEATH_STRIKE:cast_safe(target, "Death Strike [Emergency]") then
                log_death_strike(me, "EMERGENCY - HP threshold")
                return true
            end
        end
    end

    return false
end

-- ============================================================================
-- BONE SHIELD EMERGENCY: Prevent Rune Spending with Forecasting
-- ============================================================================

---Check if we need to save runes for Bone Shield emergency
---@param me game_object
---@param target game_object
---@return boolean true if we successfully cast Marrowrend, false to allow RP spending
local function bone_shield_emergency(me, target)
    local min_stacks = menu.BONE_SHIELD_MIN_STACKS:get()
    local refresh_threshold = menu.BONE_SHIELD_REFRESH_THRESHOLD:get()

    -- Check if we need Bone Shield refresh: low stacks OR duration expiring soon
    local needs_refresh = bone_shield_stacks < min_stacks or bone_shield_remains <= refresh_threshold
    
    -- If we don't need refresh, no emergency
    if not needs_refresh then
        return false
    end

    -- We're below minimum - need to rebuild Bone Shield (Marrowrend costs 2 runes)
    -- Use forecast helper to check if we should save runes
    local should_save = should_save_runes_for_ability(me, 2)
    local forecast = get_rune_forecast(me)
    
    -- Check if we have 2 runes NOW
    if forecast.current_rune_count >= 2 then
        -- Try to cast Marrowrend on current target
        if target and target:is_valid() then
            if SPELLS.MARROWREND:cast_safe(target, "Marrowrend [Emergency]") then
                return true
            end
        end

        -- If no valid target for Marrowrend, try Death's Caress (ranged)
        if SPELLS.DEATHS_CARESS:cast_safe(target, "Death's Caress [Emergency]") then
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
                log_death_strike(me, string.format("PRE-BONE SHIELD HEAL - Runes in %.2fs", forecast.time_to_2_runes))
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

---Check if we should save runes for Marrowrend (Bone Shield refresh)
---This prevents spending runes on other abilities when Bone Shield needs refresh soon
---@param me game_object
---@return boolean should_save_for_marrowrend
local function should_save_runes_for_marrowrend(me)
    local min_stacks = menu.BONE_SHIELD_MIN_STACKS:get()
    local refresh_threshold = menu.BONE_SHIELD_REFRESH_THRESHOLD:get()
    
    -- Check if Bone Shield needs refresh: low stacks OR duration expiring soon
    local needs_refresh = bone_shield_stacks < min_stacks or bone_shield_remains <= refresh_threshold
    
    -- If we don't need refresh, no need to save
    if not needs_refresh then
        return false
    end
    
    -- We need Bone Shield refresh (Marrowrend costs 2 runes)
    -- Check if we should save runes for it
    return should_save_runes_for_ability(me, 2)
end

-- ============================================================================
-- HELPER: Check if enemies are in Blood Boil range
-- ============================================================================
---@param me game_object
---@param enemies table
---@return boolean has_enemies_in_range
---@return number count Number of enemies in range
local function has_enemies_in_blood_boil_range(me, enemies)
    if not enemies or #enemies == 0 then
        return false, 0
    end
    
    local blood_boil_range = 10  -- Blood Boil has 10 yard range
    local count = 0
    
    for _, enemy in ipairs(enemies) do
        if enemy and enemy:is_valid() and enemy:is_alive() and me:can_attack(enemy) then
            if enemy:is_in_range(blood_boil_range) then
                count = count + 1
            end
        end
    end
    
    return count > 0, count
end

-- ============================================================================
-- INTERRUPTS & STUNS
-- ============================================================================

---Handle interrupts and CC (Comprehensive priority system)
---Priority: Asphyxiate (non-interruptable) > Blinding Sleet (AoE) > Death Grip (magic casters at range) > Anti-Magic Shell (last resort)
---@param me game_object
---@param target game_object
---@return boolean
local function handle_interrupts(me, target)
    if not menu.AUTO_INTERRUPT:get_state() then
        return false
    end

    -- Check all enemies for casting interrupts
    local enemies = izi.enemies(40)  -- Extended range for Blinding Sleet and Death Grip
    if not enemies or #enemies == 0 then
        return false
    end

    -- Collect casting enemies and categorize them
    local casting_enemies = {}
    local non_interruptable_enemies = {}  -- Enemies casting non-interruptable spells
    local magic_casters_at_range = {}     -- Magic casters at range for Death Grip
    local casting_count = 0
    
    for _, enemy in ipairs(enemies) do
        if enemy and enemy:is_valid() and enemy:is_alive() and me:can_attack(enemy) then
            if enemy:is_casting() or enemy:is_channeling() then
                local cast_remaining_ms = enemy:get_cast_remaining_ms()
                local cast_pct = enemy:get_cast_pct()
                
                -- Only consider casts that have meaningful time remaining (avoid wasted interrupts)
                if cast_remaining_ms > 300 and cast_remaining_ms < 3000 then  -- 0.3s to 3s remaining
                    table.insert(casting_enemies, {
                        enemy = enemy,
                        remaining_ms = cast_remaining_ms,
                        remaining_sec = cast_remaining_ms / 1000,
                        cast_pct = cast_pct,
                        is_interruptable = enemy:is_active_spell_interruptable(),
                        distance = enemy:distance()
                    })
                    casting_count = casting_count + 1
                    
                    -- Categorize for priority targeting
                    if not enemy:is_active_spell_interruptable() then
                        table.insert(non_interruptable_enemies, enemy)
                    end
                    
                    -- Check if enemy is a magic caster at range (for Death Grip priority)
                    if enemy:distance() > 5 and enemy:distance() <= 30 then
                        -- Check if spell is magic school (most interrupts work on magic)
                        local spell_id = enemy:get_active_spell_id()
                        if spell_id and spell_id > 0 then
                            table.insert(magic_casters_at_range, enemy)
                        end
                    end
                end
            end
        end
    end
    
    if casting_count == 0 then
        return false
    end

    -- Priority 1: Asphyxiate for non-interruptable casts (melee range)
    -- Use when conventional interrupts won't work
    if menu.ASPHYXIATE_CHECK:get_state() and SPELLS.ASPHYXIATE:is_learned() and SPELLS.ASPHYXIATE:is_castable() then
        for _, cast_info in ipairs(casting_enemies) do
            if not cast_info.is_interruptable and cast_info.distance <= 5 then
                if SPELLS.ASPHYXIATE:cast_safe(cast_info.enemy, string.format("Asphyxiate (Non-Interruptable %.1fs)", cast_info.remaining_sec)) then
                    return true
                end
            end
        end
    end

    -- Priority 2: Blinding Sleet for AoE interrupts (multiple enemies casting)
    -- Use when 2+ enemies are casting (AoE cone in front of player)
    if SPELLS.BLINDING_SLEET:is_learned() and SPELLS.BLINDING_SLEET:is_castable() then
        if casting_count >= 2 then
            -- Blinding Sleet is self-cast (cone AoE in front of player)
            if SPELLS.BLINDING_SLEET:cast_safe(nil, string.format("Blinding Sleet (AoE Interrupt %d casters)", casting_count)) then
                return true
            end
        end
    end

    -- Priority 3: Death Grip for magic casters at range
    -- Prioritize pulling magic casters to melee, especially with Death's Echo (2 charges)
    if menu.DEATH_GRIP_CHECK:get_state() and SPELLS.DEATH_GRIP:is_learned() then
        if SPELLS.DEATH_GRIP:is_castable() then
            -- Check for Death's Echo talent (ID 356367) - gives 2 charges
            local deaths_echo_learned = core.spell_book.is_spell_learned(356367)
            local death_grip_charges = SPELLS.DEATH_GRIP:charges()
            
            -- Prioritize magic casters at range
            for _, cast_info in ipairs(casting_enemies) do
                if cast_info.distance > 5 and cast_info.distance <= 30 then
                    -- Check if this is a magic caster (prioritize)
                    local is_magic_caster = false
                    for _, magic_caster in ipairs(magic_casters_at_range) do
                        if magic_caster == cast_info.enemy then
                            is_magic_caster = true
                            break
                        end
                    end
                    
                    -- Use Death Grip on magic casters at range
                    if is_magic_caster or death_grip_charges >= 2 then
                        if SPELLS.DEATH_GRIP:cast_safe(cast_info.enemy, string.format("Death Grip (Magic Caster %.1fs)", cast_info.remaining_sec)) then
                            return true
                        end
                    end
                end
            end
            
            -- Fallback: Any caster at range if we have charges
            if death_grip_charges >= 2 then
                for _, cast_info in ipairs(casting_enemies) do
                    if cast_info.distance > 5 and cast_info.distance <= 30 then
                        if SPELLS.DEATH_GRIP:cast_safe(cast_info.enemy, string.format("Death Grip (Interrupt %.1fs)", cast_info.remaining_sec)) then
                            return true
                        end
                    end
                end
            end
        end
    end

    -- Note: Anti-Magic Shell usage is handled in defensives() function
    -- which runs before interrupts and considers magical damage scenarios
    -- including when interrupts are unavailable

    return false
end

-- ============================================================================
-- SIMC ROTATION: High Priority Actions
-- ============================================================================

---@param me game_object
---@param target game_object
---@return boolean
local function high_prio_actions(me, target)
    -- raise_dead (off GCD) - handled in utility()

    -- blood_tap,if=(rune<=2&rune.time_to_3>gcd&charges_fractional>=1.8)
    if SPELLS.BLOOD_TAP:is_learned() and SPELLS.BLOOD_TAP:is_castable() then
        local forecast = get_rune_forecast(me)
        local charges = SPELLS.BLOOD_TAP:charges()

        if forecast.current_rune_count <= 2 and forecast.time_to_3_runes > gcd and charges >= 1.8 then
            if SPELLS.BLOOD_TAP:cast_safe(nil, "Blood Tap") then
                return true
            end
        end

        -- blood_tap,if=(rune<=1&rune.time_to_3>gcd)
        if forecast.current_rune_count <= 1 and forecast.time_to_3_runes > gcd then
            if SPELLS.BLOOD_TAP:cast_safe(nil, "Blood Tap") then
                return true
            end
        end
    end

    -- death_strike,if=buff.coagulopathy.up&buff.coagulopathy.remains<=gcd
    if me:has_buff(BUFF_COAGULOPATHY) then
        local coag_remains = me:buff_remains_sec(BUFF_COAGULOPATHY)
        if coag_remains <= gcd and coag_remains > 0 then
            if SPELLS.DEATH_STRIKE:cast_safe(target, "Death Strike [Coag Snipe]") then
                log_death_strike(me, string.format("COAGULOPATHY SNIPE - %.2fs remaining", coag_remains))
                return true
            end
        end
    end

    -- dancing_rune_weapon
    if menu.DRW_CHECK:get_state() and SPELLS.DANCING_RUNE_WEAPON:is_castable() then
        local ttd = target:time_to_die()
        if menu.validate_drw(ttd) then
            if SPELLS.DANCING_RUNE_WEAPON:cast_safe(nil, "Dancing Rune Weapon") then
                return true
            end
        end
    end

    return false
end

-- ============================================================================
-- SIMC ROTATION: Deathbringer
-- ============================================================================

---Deathbringer Rotation - Priority List Implementation
---@param me game_object
---@param target game_object
---@param enemies table
---@return boolean
local function deathbringer_rotation(me, target, enemies)
    local active_enemies = #enemies
    local has_drw = me:has_buff(BUFF_DANCING_RUNE_WEAPON)
    local now = izi.now()

    -- Priority 1: Death Strike below 70% health
    if me:get_health_percentage() < 70 then
        -- Prevent back-to-back Death Strikes (wait at least 1 second)
        if (now - last_death_strike_time) >= 1.0 then
            if SPELLS.DEATH_STRIKE:cast_safe(target, "Death Strike [<70% HP]") then
                last_death_strike_time = now
                log_death_strike(me, "<70% HP")
                return true
            end
        end
    end

    -- Priority 2: Marrowrend for Bone Shield maintenance
    if not block_rune_spending then
        local bone_shield_active = me:has_buff(BUFF_BONE_SHIELD)
        local bone_shield_low = not bone_shield_active or bone_shield_remains < 5 or bone_shield_stacks < 3
        
        -- Check Exterminate + Reaper's Mark conditions
        local has_exterminate = me:has_buff(BUFF_EXTERMINATE)
        local rm_off_cd = SPELLS.REAPERS_MARK:cooldown_up()
        local rm_near_cd = SPELLS.REAPERS_MARK:cooldown_remains() <= 3
        local exterminate_expires_soon = has_exterminate and me:buff_remains_sec(BUFF_EXTERMINATE) < 5
        local exterminate_with_rm = has_exterminate and (rm_off_cd or rm_near_cd or exterminate_expires_soon)
        
        if bone_shield_low or exterminate_with_rm then
            if can_afford_rune_spender(me, 2, true) then
                if SPELLS.MARROWREND:cast_safe(target, "Marrowrend [Bone Shield]") then
                    return true
                end
            end
        end
    end

    -- Priority 3: Blood Boil for Blood Plague
    if not block_rune_spending then
        if SPELLS.BLOOD_BOIL:is_castable() and can_afford_rune_spender(me, 1, true) then
            -- Filter enemies to only those we can attack AND are in range (10 yards)
            local blood_boil_range = 10
            local valid_enemies = {}
            for _, enemy in ipairs(enemies) do
                if enemy and enemy:is_valid() and enemy:is_alive() and me:can_attack(enemy) then
                    if enemy:is_in_range(blood_boil_range) then
                        table.insert(valid_enemies, enemy)
                    end
                end
            end
            
            if #valid_enemies > 0 then
                -- Use spread_dot to refresh Blood Plague on all enemies that need it (pandemic threshold)
                if izi.spread_dot(SPELLS.BLOOD_BOIL, valid_enemies, BLOOD_PLAGUE_PANDEMIC_MS, 3, "Blood Boil [Plague]") then
                    if has_drw then
                        drw_blood_boil_casted = true
                    end
                    return true
                end
            end
        end
    end

    -- Priority 5: Bonestorm
    if menu.BONESTORM_CHECK:get_state() and SPELLS.BONESTORM:is_learned() and SPELLS.BONESTORM:is_castable() then
        -- Check DRW buff directly to ensure it's not active (don't rely on cached has_drw)
        local drw_active = me:has_buff(BUFF_DANCING_RUNE_WEAPON)
        local drw_cd = SPELLS.DANCING_RUNE_WEAPON:cooldown_remains()
        local drw_on_cd = not drw_active and drw_cd > 0
        
        if bone_shield_stacks > 6 and me:has_buff(BUFF_DEATH_AND_DECAY) and drw_on_cd then
            if SPELLS.BONESTORM:cast_safe(nil, "Bonestorm") then
                return true
            end
        end
    end

    -- Priority 6: Death Strike RP Capping
    -- RP > 105 (or RP > 99 when DRW active)
    local drw_active = me:has_buff(BUFF_DANCING_RUNE_WEAPON)
    local rp_threshold = drw_active and 99 or 105
    if runic_power > rp_threshold then
        -- Prevent back-to-back Death Strikes
        if (now - last_death_strike_time) >= 1.0 then
            if SPELLS.DEATH_STRIKE:cast_safe(target, "Death Strike [RP Cap]") then
                last_death_strike_time = now
                log_death_strike(me, string.format("RP CAP (threshold: %d)", rp_threshold))
                return true
            end
        end
    end

    -- Priority 7: Reaper's Mark
    if menu.REAPERS_MARK_CHECK:get_state() and SPELLS.REAPERS_MARK:is_learned() and SPELLS.REAPERS_MARK:is_castable() then
        if SPELLS.REAPERS_MARK:cast_safe(target, "Reaper's Mark") then
            return true
        end
    end

    -- Priority 8: Soul Reaper
    if menu.SOUL_REAPER_CHECK:get_state() and SPELLS.SOUL_REAPER:is_learned() and SPELLS.SOUL_REAPER:is_castable() then
        -- With 1 priority target (1-2 enemies) or if priority damage is desired
        if active_enemies <= 2 then
            -- Scan enemies in range to find the best eligible target for Soul Reaper
            -- Eligible: below 35% health OR Reaper of Souls buff is active
            local reaper_of_souls_active = me:has_buff(BUFF_REAPER_OF_SOULS)
            
            -- Get all enemies in range (40 yards) and filter for eligible targets
            local eligible_targets = {}
            local enemies = izi.enemies(40)
            
            for _, enemy in ipairs(enemies) do
                if enemy and enemy:is_valid() and enemy:is_alive() and me:can_attack(enemy) then
                    local hp_pct = enemy:get_health_percentage()
                    local ttd = enemy:time_to_die()
                    local sr_remains = enemy:debuff_remains_sec(DEBUFF_SOUL_REAPER)
                    
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
                    if SPELLS.SOUL_REAPER:cast_safe(best_target, "Soul Reaper") then
                        return true
                    end
                end
            end
        end
    end

    -- Priority 9: Marrowrend for Bone Shield stacks
    if not block_rune_spending then
        -- Condition 1: Below 7 stacks of Bone Shield and Bonestorm is not active
        local below_7_stacks = bone_shield_stacks < 7
        local no_bonestorm = not me:has_debuff(DEBUFF_BONESTORM)
        local bone_shield_condition = below_7_stacks and no_bonestorm
        
        -- Condition 2: At 2 stacks of Exterminate and Reaper's Mark debuff will explode in next 5 seconds
        local exterminate_stacks = me:get_buff_stacks(BUFF_EXTERMINATE)
        local at_2_exterminate = exterminate_stacks == 2
        local exterminate_condition = false
        
        if at_2_exterminate and target and target:is_valid() and me:can_attack(target) then
            local rm_explodes_soon = reapers_mark_explodes_soon(target)
            exterminate_condition = rm_explodes_soon
        end
        
        -- Cast if either condition is met
        if bone_shield_condition or exterminate_condition then
            if can_afford_rune_spender(me, 2, true) then
                if SPELLS.MARROWREND:cast_safe(target, "Marrowrend [Stack Maintenance]") then
                    return true
                end
            end
        end
    end

    -- Priority 10: Tombstone
    if menu.TOMBSTONE_CHECK:get_state() and SPELLS.TOMBSTONE:is_learned() and SPELLS.TOMBSTONE:is_castable() then
        -- Check DRW buff directly to ensure it's not active (don't rely on cached has_drw)
        if bone_shield_stacks > 7 and me:has_buff(BUFF_DEATH_AND_DECAY) and not me:has_buff(BUFF_DANCING_RUNE_WEAPON) then
            local drw_cd = SPELLS.DANCING_RUNE_WEAPON:cooldown_remains()
            if drw_cd > 25 then
                if SPELLS.TOMBSTONE:cast_safe(nil, "Tombstone") then
                    return true
                end
            end
        end
    end

    -- Priority 11: Death and Decay
    if not block_rune_spending then
        if not me:has_buff(BUFF_DEATH_AND_DECAY) then
            if not me:is_moving() and can_afford_rune_spender(me, 1, true) then
                local self_pos = me:get_position()
                if SPELLS.DEATH_AND_DECAY:cast_safe(nil, "Death and Decay", { cast_pos = self_pos }) then
                    return true
                end
            end
        end
    end

    -- Priority 12: Blood Boil first in DRW
    if not block_rune_spending then
        if has_drw and not drw_blood_boil_casted then
            if SPELLS.BLOOD_BOIL:is_castable() and can_afford_rune_spender(me, 1, true) then
                -- Check if enemies are in range before casting
                local has_enemies, enemy_count = has_enemies_in_blood_boil_range(me, enemies)
                if has_enemies then
                    if SPELLS.BLOOD_BOIL:cast_safe(nil, "Blood Boil [First in DRW]") then
                        drw_blood_boil_casted = true
                        return true
                    end
                end
            end
        end
    end

    -- Priority 13: Marrowrend with Exterminate
    if not block_rune_spending then
        if me:has_buff(BUFF_EXTERMINATE) and not has_drw then
            if can_afford_rune_spender(me, 2, true) then
                if SPELLS.MARROWREND:cast_safe(target, "Marrowrend [Exterminate]") then
                    return true
                end
            end
        end
    end

    -- Priority 14: Heart Strike with 2+ runes
    if not block_rune_spending then
        if me:rune_count() >= 2 and can_afford_rune_spender(me, 1, true) then
            if SPELLS.HEART_STRIKE:cast_safe(target, "Heart Strike") then
                return true
            end
        end
    end

    -- Priority 15: Consumption
    if not block_rune_spending then
        if SPELLS.CONSUMPTION:is_learned() and SPELLS.CONSUMPTION:is_castable() then
            if can_afford_rune_spender(me, 1, true) then
                if SPELLS.CONSUMPTION:cast_safe(nil, "Consumption") then
                    return true
                end
            end
        end
    end

    -- Priority 16: Blood Boil
    if not block_rune_spending then
        if SPELLS.BLOOD_BOIL:is_castable() and can_afford_rune_spender(me, 1, true) then
            -- Check if enemies are in range before casting
            local has_enemies, enemy_count = has_enemies_in_blood_boil_range(me, enemies)
            if has_enemies then
                if SPELLS.BLOOD_BOIL:cast_safe(nil, "Blood Boil") then
                    if has_drw then
                        drw_blood_boil_casted = true
                    end
                    return true
                end
            end
        end
    end

    -- Priority 17: Heart Strike
    if not block_rune_spending then
        if can_afford_rune_spender(me, 1, true) then
            if SPELLS.HEART_STRIKE:cast_safe(target, "Heart Strike") then
                return true
            end
        end
    end

    -- Priority 18: Death's Caress
    if SPELLS.DEATHS_CARESS:is_castable() then
        if SPELLS.DEATHS_CARESS:cast_safe(target, "Death's Caress") then
            return true
        end
    end

    return false
end

-- ============================================================================
-- SIMC ROTATION: San'layn during DRW
-- ============================================================================

---@param me game_object
---@param target game_object
---@param enemies table
---@return boolean
local function san_drw_rotation(me, target, enemies)
    local active_enemies = #enemies

    -- RUNE-COSTING ABILITIES: Block if we're saving runes for Bone Shield
    if not block_rune_spending then
        -- heart_strike,if=buff.essence_of_the_blood_queen.remains<1.5&buff.essence_of_the_blood_queen.remains
        if me:has_buff(BUFF_ESSENCE_OF_THE_BLOOD_QUEEN) then
            local essence_remains = me:buff_remains_sec(BUFF_ESSENCE_OF_THE_BLOOD_QUEEN)
            if essence_remains < 1.5 and essence_remains > 0 and can_afford_rune_spender(me, 1, true) then
                if SPELLS.HEART_STRIKE:cast_safe(target, "Heart Strike [Essence Snipe]") then
                    return true
                end
            end
        end
    end

    -- bonestorm,if=buff.bone_shield.stack>=5&buff.death_and_decay.up&!buff.dancing_rune_weapon.up
    if menu.BONESTORM_CHECK:get_state() and SPELLS.BONESTORM:is_learned() and SPELLS.BONESTORM:is_castable() then
        -- Check DRW buff directly to ensure it's not active
        local drw_active = me:has_buff(BUFF_DANCING_RUNE_WEAPON)
        
        if bone_shield_stacks >= 5 and me:has_buff(BUFF_DEATH_AND_DECAY) and not drw_active then
            if SPELLS.BONESTORM:cast_safe(nil, "Bonestorm") then
                return true
            end
        end
    end

    -- death_strike,if=runic_power.deficit<threshold (with resource pooling awareness)
    local rp_threshold = get_rp_capping_threshold(me, true) -- DRW is active in this rotation
    local should_wait_for_rp = should_wait_for_rune_rp_generation(me)
    
    if runic_power_deficit < rp_threshold then
        -- Don't cap if we should pool for emergencies
        if not should_pool_rp_for_emergency(me) then
            -- Don't cap if runes will generate RP soon (unless we're really high)
            if not should_wait_for_rp or runic_power_deficit < 10 then
                if SPELLS.DEATH_STRIKE:cast_safe(target, "Death Strike [Capping]") then
                    log_death_strike(me, "CAPPING RP (San'layn DRW)")
                    return true
                end
            end
        end
    end

    -- RUNE-COSTING ABILITIES: Block if we're saving runes for Bone Shield
    if not block_rune_spending then
        -- blood_boil,if=!drw.bp_ticking
        local bp_ticking = drw_bp_ticking(me, enemies)
        if not bp_ticking and SPELLS.BLOOD_BOIL:is_castable() and can_afford_rune_spender(me, 1, true) then
            -- Check if enemies are in range before casting
            local has_enemies, enemy_count = has_enemies_in_blood_boil_range(me, enemies)
            if has_enemies then
                if SPELLS.BLOOD_BOIL:cast_safe(nil, "Blood Boil") then
                    return true
                end
            end
        end

        -- any_dnd,if=(active_enemies<=3&buff.crimson_scourge.remains)|(active_enemies>3&!buff.death_and_decay.remains)
        local has_dnd = me:has_buff(BUFF_DEATH_AND_DECAY)
        local has_crimson = me:has_buff(BUFF_CRIMSON_SCOURGE)
        if (active_enemies <= 3 and has_crimson) or (active_enemies > 3 and not has_dnd) then
            -- Only cast if not moving and at self position
            if not me:is_moving() and can_afford_rune_spender(me, 1, true) then
                local self_pos = me:get_position()
                if SPELLS.DEATH_AND_DECAY:cast_safe(nil, "Death and Decay", { cast_pos = self_pos }) then
                    return true
                end
            end
        end

        -- heart_strike
        if can_afford_rune_spender(me, 1, true) then
            if SPELLS.HEART_STRIKE:cast_safe(target, "Heart Strike") then
                return true
            end
        end
    end  -- End of rune-costing block

    -- death_strike filler (only if RP very high and no runes available soon)
    if runic_power > 80 then
        local forecast = get_rune_forecast(me)
        -- Only use if we have no runes and they won't be available soon
        if forecast.current_rune_count == 0 then
            if forecast.time_to_1_rune > (gcd + menu.RUNE_FORECAST_WINDOW:get()) or forecast.time_to_1_rune <= 0 then
                if not should_pool_rp_for_emergency(me) then
                    if SPELLS.DEATH_STRIKE:cast_safe(target, "Death Strike [Filler]") then
                        log_death_strike(me, "FILLER (San'layn DRW)")
                        return true
                    end
                end
            end
        end
    end
    -- Otherwise, wait for runes to regenerate

    -- RUNE-COSTING ABILITIES: Block if we're saving runes for Bone Shield
    if not block_rune_spending then
        -- consumption
        if SPELLS.CONSUMPTION:is_learned() and SPELLS.CONSUMPTION:is_castable() then
            if can_afford_rune_spender(me, 1, true) then
                if SPELLS.CONSUMPTION:cast_safe(nil, "Consumption") then
                    return true
                end
            end
        end

        -- blood_boil
        if SPELLS.BLOOD_BOIL:is_castable() and can_afford_rune_spender(me, 1, true) then
            -- Check if enemies are in range before casting
            local has_enemies, enemy_count = has_enemies_in_blood_boil_range(me, enemies)
            if has_enemies then
                if SPELLS.BLOOD_BOIL:cast_safe(nil, "Blood Boil") then
                    return true
                end
            end
        end
    end  -- End of rune-costing block

    return false
end

-- ============================================================================
-- SIMC ROTATION: San'layn
-- ============================================================================

---San'layn Rotation - Priority List Implementation
---@param me game_object
---@param target game_object
---@param enemies table
---@return boolean
local function sanlayn_rotation(me, target, enemies)
    local active_enemies = #enemies
    local has_drw = me:has_buff(BUFF_DANCING_RUNE_WEAPON)
    local now = izi.now()

    -- Priority 1: Death Strike below 70% health
    if me:get_health_percentage() < 70 then
        -- Prevent back-to-back Death Strikes (wait at least 1 second)
        if (now - last_death_strike_time) >= 1.0 then
            if SPELLS.DEATH_STRIKE:cast_safe(target, "Death Strike [<70% HP]") then
                last_death_strike_time = now
                log_death_strike(me, "<70% HP")
                return true
            end
        end
    end

    -- Priority 2: Bone Shield Maintenance (2a/2b/2c)
    if not block_rune_spending then
        local bone_shield_active = me:has_buff(BUFF_BONE_SHIELD)
        local bone_shield_low = not bone_shield_active or bone_shield_remains < 5 or bone_shield_stacks < 3
        
        if bone_shield_low then
            -- Priority 2a: Blood Boil (if 2+ enemies)
            if active_enemies >= 2 then
                if SPELLS.BLOOD_BOIL:is_castable() and can_afford_rune_spender(me, 1, true) then
                    -- Check if enemies are in range before casting
                    local has_enemies, enemy_count = has_enemies_in_blood_boil_range(me, enemies)
                    if has_enemies then
                        if SPELLS.BLOOD_BOIL:cast_safe(nil, "Blood Boil [Bone Shield]") then
                            if has_drw then
                                drw_blood_boil_casted = true
                            end
                            return true
                        end
                    end
                end
            end
            
            -- Priority 2b: Death's Caress
            if SPELLS.DEATHS_CARESS:is_castable() then
                if SPELLS.DEATHS_CARESS:cast_safe(target, "Death's Caress [Bone Shield]") then
                    return true
                end
            end
            
            -- Priority 2c: Marrowrend
            if can_afford_rune_spender(me, 2, true) then
                if SPELLS.MARROWREND:cast_safe(target, "Marrowrend [Bone Shield]") then
                    return true
                end
            end
        end
    end

    -- Priority 3: Blood Boil for Blood Plague
    if not block_rune_spending then
        if SPELLS.BLOOD_BOIL:is_castable() and can_afford_rune_spender(me, 1, true) then
            -- Filter enemies to only those we can attack AND are in range (10 yards)
            local blood_boil_range = 10
            local valid_enemies = {}
            for _, enemy in ipairs(enemies) do
                if enemy and enemy:is_valid() and enemy:is_alive() and me:can_attack(enemy) then
                    if enemy:is_in_range(blood_boil_range) then
                        table.insert(valid_enemies, enemy)
                    end
                end
            end
            
            if #valid_enemies > 0 then
                -- Use spread_dot to refresh Blood Plague on all enemies that need it (pandemic threshold)
                if izi.spread_dot(SPELLS.BLOOD_BOIL, valid_enemies, BLOOD_PLAGUE_PANDEMIC_MS, 3, "Blood Boil [Plague]") then
                    if has_drw then
                        drw_blood_boil_casted = true
                    end
                    return true
                end
            end
        end
    end

    -- Priority 4: Heart Strike with DRW for Essence of the Blood Queen
    if not block_rune_spending then
        if has_drw and me:has_buff(BUFF_ESSENCE_OF_THE_BLOOD_QUEEN) then
            local essence_remains = me:buff_remains_sec(BUFF_ESSENCE_OF_THE_BLOOD_QUEEN)
            if essence_remains < 1.5 and essence_remains > 0 then
                if can_afford_rune_spender(me, 1, true) then
                    if SPELLS.HEART_STRIKE:cast_safe(target, "Heart Strike [Essence]") then
                        return true
                    end
                end
            end
        end
    end

    -- Priority 5: Bonestorm
    if menu.BONESTORM_CHECK:get_state() and SPELLS.BONESTORM:is_learned() and SPELLS.BONESTORM:is_castable() then
        -- Check DRW buff directly to ensure it's not active (don't rely on cached has_drw)
        local drw_active = me:has_buff(BUFF_DANCING_RUNE_WEAPON)
        
        -- Bonestorm should only be used when DRW is NOT active and Death and Decay IS active
        if bone_shield_stacks > 6 and me:has_buff(BUFF_DEATH_AND_DECAY) and not drw_active then
            if SPELLS.BONESTORM:cast_safe(nil, "Bonestorm") then
                return true
            end
        end
    end

    -- Priority 6: Death Strike RP Capping
    -- RP > 105 (or RP > 99 when DRW active)
    local drw_active = me:has_buff(BUFF_DANCING_RUNE_WEAPON)
    local rp_threshold = drw_active and 99 or 105
    if runic_power > rp_threshold then
        -- Prevent back-to-back Death Strikes
        if (now - last_death_strike_time) >= 1.0 then
            if SPELLS.DEATH_STRIKE:cast_safe(target, "Death Strike [RP Cap]") then
                last_death_strike_time = now
                log_death_strike(me, string.format("RP CAP (threshold: %d)", rp_threshold))
                return true
            end
        end
    end

    -- Priority 8: Soul Reaper
    if menu.SOUL_REAPER_CHECK:get_state() and SPELLS.SOUL_REAPER:is_learned() and SPELLS.SOUL_REAPER:is_castable() then
        if active_enemies <= 2 and target and target:is_valid() and not has_drw then
            local hp_pct = target:get_health_percentage()
            if hp_pct <= 35 then
                local ttd = target:time_to_die()
                local sr_remains = target:debuff_remains_sec(DEBUFF_SOUL_REAPER)
                if ttd > (sr_remains + 5) then
                    if SPELLS.SOUL_REAPER:cast_safe(target, "Soul Reaper") then
                        return true
                    end
                end
            end
        end
    end

    -- Priority 9: Bone Shield Maintenance (9a/9b/9c)
    if not block_rune_spending then
        local below_8_stacks = bone_shield_stacks < 8
        local below_7_stacks = bone_shield_stacks < 7
        local no_bonestorm = not me:has_debuff(DEBUFF_BONESTORM)
        
        if (below_8_stacks or below_7_stacks) and no_bonestorm then
            -- Priority 9a: Blood Boil if below 8 stacks AND Bonestorm not active AND 2+ enemies
            if below_8_stacks and active_enemies >= 2 then
                if SPELLS.BLOOD_BOIL:is_castable() and can_afford_rune_spender(me, 1, true) then
                    -- Check if enemies are in range before casting
                    local has_enemies, enemy_count = has_enemies_in_blood_boil_range(me, enemies)
                    if has_enemies then
                        if SPELLS.BLOOD_BOIL:cast_safe(nil, "Blood Boil [Stack Maintenance]") then
                            if has_drw then
                                drw_blood_boil_casted = true
                            end
                            return true
                        end
                    end
                end
            end
            
            -- Priority 9b: Death's Caress if below 7 stacks AND Bonestorm not active
            if below_7_stacks then
                if SPELLS.DEATHS_CARESS:is_castable() then
                    if SPELLS.DEATHS_CARESS:cast_safe(target, "Death's Caress [Stack Maintenance]") then
                        return true
                    end
                end
            end
            
            -- Priority 9c: Marrowrend if below 7 stacks AND Bonestorm not active
            if below_7_stacks then
                if can_afford_rune_spender(me, 2, true) then
                    if SPELLS.MARROWREND:cast_safe(target, "Marrowrend [Stack Maintenance]") then
                        return true
                    end
                end
            end
        end
    end

    -- Priority 10: Tombstone
    if menu.TOMBSTONE_CHECK:get_state() and SPELLS.TOMBSTONE:is_learned() and SPELLS.TOMBSTONE:is_castable() then
        -- Check DRW buff directly to ensure it's not active (don't rely on cached has_drw)
        local drw_active = me:has_buff(BUFF_DANCING_RUNE_WEAPON)
        
        -- Tombstone should only be used when DRW is NOT active and Death and Decay IS active
        if bone_shield_stacks > 7 and me:has_buff(BUFF_DEATH_AND_DECAY) and not drw_active then
            local drw_cd = SPELLS.DANCING_RUNE_WEAPON:cooldown_remains()
            if drw_cd > 25 then
                if SPELLS.TOMBSTONE:cast_safe(nil, "Tombstone") then
                    return true
                end
            end
        end
    end

    -- Priority 11: Death and Decay
    if not block_rune_spending then
        if not me:has_buff(BUFF_DEATH_AND_DECAY) then
            local has_crimson = me:has_buff(BUFF_CRIMSON_SCOURGE)
            local has_visceral = me:has_buff(BUFF_VISCERAL_STRENGTH)
            
            -- 4+ targets OR (Crimson Scourge active AND Visceral Strength not active)
            if active_enemies >= 4 or (has_crimson and not has_visceral) then
                if not me:is_moving() and can_afford_rune_spender(me, 1, true) then
                    local self_pos = me:get_position()
                    if SPELLS.DEATH_AND_DECAY:cast_safe(nil, "Death and Decay", { cast_pos = self_pos }) then
                        return true
                    end
                end
            end
        end
    end

    -- Priority 12: Blood Boil first in DRW
    if not block_rune_spending then
        if has_drw and not drw_blood_boil_casted then
            if SPELLS.BLOOD_BOIL:is_castable() and can_afford_rune_spender(me, 1, true) then
                -- Check if enemies are in range before casting
                local has_enemies, enemy_count = has_enemies_in_blood_boil_range(me, enemies)
                if has_enemies then
                    if SPELLS.BLOOD_BOIL:cast_safe(nil, "Blood Boil [First in DRW]") then
                        drw_blood_boil_casted = true
                        return true
                    end
                end
            end
        end
    end

    -- Priority 14: Heart Strike with 2+ runes
    if not block_rune_spending then
        if me:rune_count() >= 2 and can_afford_rune_spender(me, 1, true) then
            if SPELLS.HEART_STRIKE:cast_safe(target, "Heart Strike") then
                return true
            end
        end
    end

    -- Priority 15: Consumption
    if not block_rune_spending then
        if SPELLS.CONSUMPTION:is_learned() and SPELLS.CONSUMPTION:is_castable() then
            if can_afford_rune_spender(me, 1, true) then
                if SPELLS.CONSUMPTION:cast_safe(nil, "Consumption") then
                    return true
                end
            end
        end
    end

    -- Priority 16: Blood Boil
    if not block_rune_spending then
        if SPELLS.BLOOD_BOIL:is_castable() and can_afford_rune_spender(me, 1, true) then
            -- Check if enemies are in range before casting
            local has_enemies, enemy_count = has_enemies_in_blood_boil_range(me, enemies)
            if has_enemies then
                if SPELLS.BLOOD_BOIL:cast_safe(nil, "Blood Boil") then
                    if has_drw then
                        drw_blood_boil_casted = true
                    end
                    return true
                end
            end
        end
    end

    -- Priority 17: Heart Strike
    if not block_rune_spending then
        if can_afford_rune_spender(me, 1, true) then
            if SPELLS.HEART_STRIKE:cast_safe(target, "Heart Strike") then
                return true
            end
        end
    end

    -- Priority 18: Death's Caress
    if SPELLS.DEATHS_CARESS:is_castable() then
        if SPELLS.DEATHS_CARESS:cast_safe(target, "Death's Caress") then
            return true
        end
    end

    return false
end

-- ============================================================================
-- MAIN CALLBACK
-- ============================================================================

core.register_on_update_callback(function()
    -- Check if rotation is enabled
    if not menu:is_enabled() then
        return
    end

    -- Get local player
    local me = izi.me()
    if not (me and me.is_valid and me:is_valid()) then
        return
    end

    -- Update cached values
    ping_ms = core.get_ping()
    ping_sec = ping_ms / 1000
    gcd = me:gcd()
    runic_power = me:runic_power_current()
    runic_power_deficit = me:runic_power_deficit()
    runes = me:rune_count()
    bone_shield_stacks = me:get_buff_stacks(BUFF_BONE_SHIELD)
    bone_shield_remains = me:buff_remains_sec(BUFF_BONE_SHIELD) or 0

    -- Track DRW state and reset Blood Boil tracking when DRW starts
    local has_drw_now = me:has_buff(BUFF_DANCING_RUNE_WEAPON)
    if has_drw_now then
        -- If DRW just started (wasn't active before), reset Blood Boil tracking
        if last_drw_start_time == 0 or (izi.now() - last_drw_start_time) > 60 then
            drw_blood_boil_casted = false
            last_drw_start_time = izi.now()
        end
    else
        -- DRW not active, reset tracking
        if last_drw_start_time > 0 then
            drw_blood_boil_casted = false
            last_drw_start_time = 0
        end
    end

    -- Cache Bone Shield emergency state with forecasting (only calculated once per frame)
    local min_bone_shield = menu.BONE_SHIELD_MIN_STACKS:get()
    local refresh_threshold = menu.BONE_SHIELD_REFRESH_THRESHOLD:get()
    
    -- Check if we need Bone Shield refresh: low stacks OR duration expiring soon
    local needs_refresh = bone_shield_stacks < min_bone_shield or bone_shield_remains <= refresh_threshold
    
    if needs_refresh then
        -- Use helper function to check if we should save runes for Marrowrend
        block_rune_spending = should_save_runes_for_marrowrend(me)
    else
        -- Bone Shield is fine, don't block
        block_rune_spending = false
    end

    -- Detect hero tree
    detected_hero_tree = detect_hero_tree(me)

    -- Skip if mounted
    if me:is_mounted() then
        return
    end

    -- Get enemies for AoE detection
    local enemies = izi.enemies(30)

    -- Always run utility (pet summoning, etc.)
    if utility(me) then
        return
    end

    -- Always check defensives (separate from DPS rotation)
    if defensives(me, nil) then
        return
    end

    -- Gorefiend's Grasp (Mythic+ utility)
    if menu.validate_gorefriends_grasp(#enemies) then
        if SPELLS.GOREFRIENDS_GRASP:is_castable() then
            -- Cast at cursor or target position
            if SPELLS.GOREFRIENDS_GRASP:cast_safe(nil, "Gorefiend's Grasp") then
                return
            end
        end
    end

    -- Racials during DRW
    if menu.RACIALS_CHECK:get_state() and me:has_buff(BUFF_DANCING_RUNE_WEAPON) then
        if SPELLS.BLOOD_FURY:is_learned() and SPELLS.BLOOD_FURY:is_castable() then
            SPELLS.BLOOD_FURY:cast_safe(nil, "Blood Fury")
        end
        if SPELLS.BERSERKING:is_learned() and SPELLS.BERSERKING:is_castable() then
            SPELLS.BERSERKING:cast_safe(nil, "Berserking")
        end
        if SPELLS.ANCESTRAL_CALL:is_learned() and SPELLS.ANCESTRAL_CALL:is_castable() then
            SPELLS.ANCESTRAL_CALL:cast_safe(nil, "Ancestral Call")
        end
        if SPELLS.FIREBLOOD:is_learned() and SPELLS.FIREBLOOD:is_castable() then
            SPELLS.FIREBLOOD:cast_safe(nil, "Fireblood")
        end
    end

    -- Iterate through target selector targets
    local targets = izi.get_ts_targets()
    for i = 1, #targets do
        local target = targets[i]

        if not (target and target.is_valid and target:is_valid()) then
            goto continue
        end

        -- Skip targets we cannot attack (not in combat with us or not in our group)
        if not me:can_attack(target) then
            goto continue
        end

        -- Skip immune targets
        if target:is_damage_immune(target.DMG.ANY) then
            goto continue
        end

        -- Skip weak CC (breaks on damage)
        if target:is_cc_weak() then
            goto continue
        end

        -- BONE SHIELD EMERGENCY: Block rune spending if below minimum stacks
        if bone_shield_emergency(me, target) then
            return
        end

        -- Interrupts and stuns (high priority)
        if handle_interrupts(me, target) then
            return
        end

        -- High priority actions first
        if high_prio_actions(me, target) then
            return
        end

        -- Legion Remix abilities (Twisted Crusade + Felspike)
        if legion_remix.Execute(legion_remix, me, target, menu) then
            return
        end

        -- Route to correct rotation based on hero tree
        -- If detected_hero_tree is nil, skip rotation routing (leveling - rotation continues naturally)
        if detected_hero_tree == HERO_TREE_DEATHBRINGER then
            if deathbringer_rotation(me, target, enemies) then
                return
            end
        elseif detected_hero_tree == HERO_TREE_SANLAYN then
            -- San'layn has special DRW rotation
            if me:has_buff(BUFF_DANCING_RUNE_WEAPON) then
                if san_drw_rotation(me, target, enemies) then
                    return
                end
            else
                if sanlayn_rotation(me, target, enemies) then
                    return
                end
            end
        end
        -- If detected_hero_tree is nil, no special rotation routing - continue with default/leveling behavior

        ::continue::
    end
end)

-- ============================================================================
-- ESP MODULE REGISTRATION
-- ============================================================================

-- Initialize ESP module
if legion_esp then
    legion_esp:Initialize()
end

-- Initialize QoL modules
if anti_afk then
    anti_afk:Initialize()
end

if health_potion then
    health_potion:Initialize()
end

-- Register ESP update callback (runs every frame)
core.register_on_update_callback(function()
    -- Only run ESP when enabled in menu
    if menu.LEGION_REMIX:get_state() then
        legion_esp:OnUpdate()
    end
end)

-- Register ESP render callback (runs every frame for drawing)
core.register_on_render_callback(function()
    -- Only run ESP when enabled in menu
    if menu.LEGION_REMIX:get_state() then
        legion_esp:OnRender()
    end
end)
