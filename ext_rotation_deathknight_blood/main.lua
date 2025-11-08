---@diagnostic disable: undefined-global, lowercase-global
--[[
    Blood Death Knight - Main Rotation (Refactored)

    Version: 2.0.0 (Modular Architecture)

    Architecture:
    - Modular design with clear separation of concerns
    - Core modules: SDK helpers, resource management, bone shield, targeting
    - Systems modules: Defensives, interrupts, utilities
    - Rotation modules: Base functions, Deathbringer, San'layn

    This file serves as the main orchestrator, delegating to specialized modules.
]]

-- ============================================================================
-- IMPORTS
-- ============================================================================

-- SDK and Core
local izi = require("common/izi_sdk")
local enums = require("common/enums")
local BUFFS = enums.buff_db
local SPELLS = require("spells")
local menu = require("menu")
local state_manager = require("state_manager")

-- QoL Modules
local legion_esp = require("modules/qol/legion_remix_esp")
local legion_remix = require("modules/qol/legion_remix")

-- Core Modules (new)
local sdk_helpers = require("core/sdk_helpers")
local resource_manager = require("core/resource_manager")
local bone_shield_manager = require("core/bone_shield_manager")
local targeting = require("core/targeting")

-- Systems Modules (new)
local defensives = require("systems/defensives")
local interrupts = require("systems/interrupts")
local utilities = require("systems/utilities")

-- Rotation Modules (new)
local base = require("rotations/base")
local deathbringer = require("rotations/deathbringer")
local sanlayn = require("rotations/sanlayn")

-- ============================================================================
-- CONSTANTS
-- ============================================================================

-- Buff/Debuff Tables
local BUFFS_TABLE = {
    BONE_SHIELD = BUFFS.BONE_SHIELD,
    DANCING_RUNE_WEAPON = BUFFS.DANCING_RUNE_WEAPON,
    DEATH_AND_DECAY = BUFFS.DEATH_AND_DECAY,
    BLOOD_PLAGUE = BUFFS.BLOOD_PLAGUE,
}

local DEBUFFS_TABLE = {
    SOUL_REAPER = 343294,
    BONESTORM = 194844,
    REAPERS_MARK = 439843,
}

-- Constants for utilities module (Remix Time spell tables)
local CONSTANTS = {
    REMIX_TIME_OFFENSIVE_SPELLS = {
        SPELLS.DANCING_RUNE_WEAPON,
        SPELLS.TOMBSTONE,
        SPELLS.BONESTORM,
    },
    REMIX_TIME_DEFENSIVE_SPELLS = {
        SPELLS.DANCING_RUNE_WEAPON,
        SPELLS.ICEBOUND_FORTITUDE,
        SPELLS.VAMPIRIC_BLOOD,
    },
}

-- Hero Tree Detection
local HERO_TREE_NONE = 0
local HERO_TREE_DEATHBRINGER = 1
local HERO_TREE_SANLAYN = 2

-- ============================================================================
-- CACHED STATE
-- ============================================================================

-- Player state (updated each frame)
local me = nil
local ping_ms = 0
local ping_sec = 0
local gcd = 0

-- Resource manager state (updated each frame)
local resource_state = {
    runic_power = 0,
    runic_power_deficit = 0,
    runes = 0,
    last_death_strike_time = 0,
    drw_blood_boil_casted = false,
}

-- Bone shield manager state (updated each frame)
local bone_shield_state = {
    bone_shield_stacks = 0,
    bone_shield_remains = 0,
    block_rune_spending = false,
}

-- Targeting state (updated each frame)
local targeting_state = {
    manual_target = nil,  -- Manually selected HUD target
    melee_target = nil,   -- Best target for melee spells (always in melee range)
    ranged_target = nil,  -- Best target for ranged spells (prefers manual if in range)
    current_target = nil, -- Legacy field (kept for compatibility, same as manual_target)
    enemies = {},
    detected_hero_tree = HERO_TREE_NONE,
}

-- ============================================================================
-- MODULE INITIALIZATION
-- ============================================================================

-- Initialize state manager (event-driven DRW tracking)
if menu.USE_EVENT_SYSTEM:get_state() then
    state_manager.init(me, SPELLS, BUFFS_TABLE)
end

-- Initialize Legion Remix ESP (visual helper for Legion Timewalking)
legion_esp.init()

-- Initialize Legion Remix (Timewalking cooldown refresh system)
legion_remix.init(menu.REMIX_TIME_MODE)

-- ============================================================================
-- MAIN UPDATE LOOP
-- ============================================================================

core.register_on_update_callback(function()
    -- Get player unit
    me = izi.me()
    if not sdk_helpers.validate_player(me) then
        return
    end

    -- Update ping/latency
    ping_ms = core.get_ping()
    ping_sec = ping_ms / 1000
    gcd = me:gcd()

    -- ========================================================================
    -- UPDATE STATE MANAGERS
    -- ========================================================================

    -- Update state manager (event-driven or polling fallback)
    if menu.USE_EVENT_SYSTEM:get_state() then
        state_manager.update(me)
        resource_state.drw_blood_boil_casted = state_manager.get_drw_blood_boil_casted()
        resource_state.last_death_strike_time = state_manager.get_last_death_strike_time()
    end

    -- Update resource state
    resource_state.runic_power = sdk_helpers.safe_get_runic_power(me)
    resource_state.runic_power_deficit = me:power_max(enums.power_type.RUNICPOWER) - resource_state.runic_power
    resource_state.runes = sdk_helpers.safe_get_rune_count(me)

    -- Update bone shield state
    bone_shield_state.bone_shield_stacks = sdk_helpers.safe_get_buff_stacks(me, BUFFS_TABLE.BONE_SHIELD)
    bone_shield_state.bone_shield_remains = sdk_helpers.safe_get_buff_remains(me, BUFFS_TABLE.BONE_SHIELD)

    -- Check if we need to block rune spending for emergency Bone Shield refresh
    bone_shield_state.block_rune_spending = bone_shield_manager.should_save_runes_for_marrowrend(
        me,
        bone_shield_state.bone_shield_stacks,
        bone_shield_state.bone_shield_remains,
        menu,
        resource_manager
    )

    -- Update targeting state
    targeting_state.manual_target = me:get_target()
    targeting_state.current_target = targeting_state.manual_target  -- Legacy compatibility
    targeting_state.enemies = izi.enemies(40)

    -- Detect hero tree (cache for this frame)
    if targeting_state.detected_hero_tree == HERO_TREE_NONE then
        targeting_state.detected_hero_tree = targeting.detect_hero_tree(me, menu, SPELLS, izi)
    end

    -- Validate manual target
    if not sdk_helpers.validate_target(me, targeting_state.manual_target) then
        targeting_state.manual_target = nil
        targeting_state.current_target = nil
    end

    -- Update smart targets using new targeting functions
    targeting_state.melee_target = targeting.get_best_melee_target(me, targeting_state.manual_target, targeting_state.enemies, 5)
    targeting_state.ranged_target = targeting.get_best_ranged_target(me, targeting_state.manual_target, targeting_state.enemies, 30)

    -- ========================================================================
    -- ROTATION PRIORITY SYSTEM
    -- ========================================================================

    -- Priority 1: Utilities (pet, rez, taunts, loot, AFK, potions)
    if utilities.execute(me, SPELLS, menu, CONSTANTS) then
        return
    end

    -- Priority 2: Defensive cooldowns (IBF, AMS, AMZ, VB, DRW, Rune Tap)
    if defensives.execute(
        me,
        SPELLS,
        menu,
        BUFFS_TABLE,
        DEBUFFS_TABLE,
        resource_state,
        targeting_state,
        gcd
    ) then
        return
    end

    -- Priority 2.5: Legion Remix (Twisted Crusade/Felspike)
    if targeting_state.current_target and me:affecting_combat() then
        if legion_remix.Execute(legion_remix, me, targeting_state.current_target, menu) then
            return
        end
    end

    -- Priority 3: Interrupts (Asphyxiate, Mind Freeze, Blinding Sleet, Death Grip)
    if interrupts.execute(
        me,
        SPELLS,
        menu,
        targeting_state,
        gcd
    ) then
        return
    end

    -- Priority 4: Combat rotation (Deathbringer or San'layn)
    if targeting_state.current_target and me:affecting_combat() then
        -- Route to appropriate rotation based on hero tree
        if targeting_state.detected_hero_tree == HERO_TREE_DEATHBRINGER then
            deathbringer.execute(
                me,
                SPELLS,
                menu,
                BUFFS_TABLE,
                DEBUFFS_TABLE,
                resource_state,
                bone_shield_state,
                targeting_state,
                base,
                gcd
            )
        elseif targeting_state.detected_hero_tree == HERO_TREE_SANLAYN then
            -- Check if DRW is active and use appropriate rotation
            local has_drw = me:has_buff(BUFFS_TABLE.DANCING_RUNE_WEAPON)

            if has_drw then
                -- Use aggressive DRW rotation when DRW buff is active
                sanlayn.execute_drw(
                    me,
                    SPELLS,
                    menu,
                    BUFFS_TABLE,
                    DEBUFFS_TABLE,
                    resource_state,
                    bone_shield_state,
                    targeting_state,
                    base,
                    gcd
                )
            else
                -- Use normal San'layn rotation when DRW is not active
                sanlayn.execute(
                    me,
                    SPELLS,
                    menu,
                    BUFFS_TABLE,
                    DEBUFFS_TABLE,
                    resource_state,
                    bone_shield_state,
                    targeting_state,
                    base,
                    state_manager,
                    gcd
                )
            end
        else
            -- No hero tree detected, log warning (once)
            core.log("[BDK] No hero tree detected - ensure Reaper's Mark or Vampiric Strike is learned")
        end
    end
end)
