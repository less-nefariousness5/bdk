---@diagnostic disable: undefined-global, lowercase-global
--[[
    Blood Death Knight - Utilities Systems Module

    Purpose: Utility functions (pet, rez, taunts, loot, AFK, potions)
    Main function: execute(me, spells, menu, constants)

    Handles:
    - Raise Dead (auto-summon ghoul)
    - Raise Ally (combat resurrection)
    - Dark Command (taunt)
    - Death Grip (taunt fallback)
    - Remix Time (cooldown refresh for Legion content)
    - Health Potions (via health_potion module)
    - Auto Loot (via auto_loot module)
    - Anti-AFK (via anti_afk module)

    Extracted from: main.lua (utility() function)
]]

local izi = require("common/izi_sdk")
local enums = require("common/enums")
local unit_helper = require("common/utility/unit_helper")
local dungeons_helper = require("common/utility/dungeons_helper")
local auto_loot = require("modules/qol/auto_loot")
local anti_afk = require("modules/qol/anti_afk")
local health_potion = require("modules/qol/health_potion")

local M = {}

-- Buff constants
local BUFFS = enums.buff_db
local BUFF_DANCING_RUNE_WEAPON = BUFFS.DANCING_RUNE_WEAPON
local BUFF_ICEBOUND_FORTITUDE = 48792
local BUFF_VAMPIRIC_BLOOD = 55233
local DEBUFF_BONESTORM = 194844

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

---Check if player has ghoul pet
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

-- ============================================================================
-- MAIN UTILITY EXECUTION FUNCTION
-- ============================================================================

---Execute utility functions
---@param me game_object Player unit
---@param spells table Spell table from spells.lua
---@param menu table Menu configuration
---@param constants table Optional constants table (for Remix Time spell tables)
---@return boolean true if an action was taken, false otherwise
function M.execute(me, spells, menu, constants)
    if not me or not me:is_valid() then
        return false
    end

    -- ========================================================================
    -- PET MANAGEMENT
    -- ========================================================================

    -- Auto summon ghoul (only in combat)
    if menu.AUTO_RAISE_DEAD_CHECK:get_state() then
        if me:affecting_combat() then
            if not unit_has_ghoul(me) then
                if spells.RAISE_DEAD:cast_safe(nil, "Raise Dead") then
                    return true
                end
            end
        end
    end

    -- ========================================================================
    -- COMBAT RESURRECTION
    -- ========================================================================

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
                            -- Check if spell is learned and castable to the mouseover unit
                            if spells.RAISE_ALLY:is_learned() then
                                -- Check if spell is castable to the specific mouseover unit
                                -- Use options to skip range/facing checks for dead units
                                local cast_opts = {
                                    skip_range = true,  -- Dead units may fail range checks
                                    skip_facing = true  -- Dead units may fail facing checks
                                }
                                
                                if spells.RAISE_ALLY:is_castable_to_unit(mouseover, cast_opts) then
                                    if spells.RAISE_ALLY:cast_safe(mouseover, "Raise Ally", cast_opts) then
                                        return true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- ========================================================================
    -- TAUNT SYSTEM
    -- ========================================================================

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

                                if in_dungeon and spells.DARK_COMMAND:is_learned() and spells.DARK_COMMAND:is_castable() then
                                    if spells.DARK_COMMAND:cast_safe(enemy, "Dark Command (Taunt)") then
                                        return true
                                    end
                                end
                            end

                            -- Fallback to Death Grip as taunt (only if Dark Command is disabled or not available)
                            if menu.DEATH_GRIP_TAUNT_CHECK:get_state() then
                                -- Only use Death Grip if Dark Command is disabled or not available
                                local use_death_grip = not menu.DARK_COMMAND_CHECK:get_state() or
                                                      (spells.DARK_COMMAND:is_learned() and not spells.DARK_COMMAND:is_castable())
                                if use_death_grip and spells.DEATH_GRIP:is_learned() and spells.DEATH_GRIP:is_castable() then
                                    if spells.DEATH_GRIP:cast_safe(enemy, "Death Grip (Taunt)") then
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

    -- ========================================================================
    -- LEGION REMIX TIME SYSTEM
    -- ========================================================================

    -- Remix Time (automatically refresh cooldowns for Legion Timewalking content)
    local remix_time_mode = menu.REMIX_TIME_MODE:get()
    if remix_time_mode > 1 and constants then
        -- Get the appropriate spell table based on mode (2 = Offensive, 3 = Defensive)
        local spell_table = constants.REMIX_TIME_OFFENSIVE_SPELLS
        if remix_time_mode == 3 then
            spell_table = constants.REMIX_TIME_DEFENSIVE_SPELLS
        end

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
            if spell == spells.DANCING_RUNE_WEAPON then
                is_active = me:has_buff(BUFF_DANCING_RUNE_WEAPON)
            elseif spell == spells.BONESTORM then
                is_active = me:has_debuff(DEBUFF_BONESTORM)
            elseif spell == spells.ICEBOUND_FORTITUDE then
                is_active = me:has_buff(BUFF_ICEBOUND_FORTITUDE)
            elseif spell == spells.VAMPIRIC_BLOOD then
                is_active = me:has_buff(BUFF_VAMPIRIC_BLOOD)
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
            if spells.REMIX_TIME:is_learned() then
                if spells.REMIX_TIME:is_castable() then
                    if spells.REMIX_TIME:cast_safe(nil, "Remix Time (Refresh Cooldowns)") then
                        return true
                    end
                end
            end
        end
    end

    -- ========================================================================
    -- QUALITY OF LIFE MODULES
    -- ========================================================================

    -- Auto loot (out of combat only)
    if menu.AUTO_LOOT:get_state() and not me:affecting_combat() then
        auto_loot.update(me, menu)
    end

    -- Anti-AFK (always runs when enabled, not just in combat)
    anti_afk.update(me, menu)

    -- Health potion
    health_potion.update(me, menu)

    return false
end

return M
