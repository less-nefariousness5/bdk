---@diagnostic disable: undefined-global, lowercase-global
local m = core.menu
local color = require("common/color")
local key_helper = require("common/utility/key_helper")
local control_panel_utility = require("common/utility/control_panel_helper")

local id_base = "ext_rotation_deathknight_blood"
local function id(key)
    return id_base .. "_" .. key
end

local WHITE = color.white(150)

---@class blood_dk_menu
local menu = {
    -- Global
    MAIN_TREE = m.tree_node(),
    GLOBAL_CHECK = m.checkbox(false, id("global_toggle")),

    -- Keybinds
    KEYBIND_TREE = m.tree_node(),
    ROTATION_KEYBIND = m.keybind(999, false, id("rotation_toggle")),

    -- Hero Tree
    HERO_TREE_SELECT = m.combobox(1, id("hero_tree")), -- 1=Auto, 2=Deathbringer, 3=San'layn

    -- Defensives
    DEFENSIVES_TREE = m.tree_node(),

    -- Vampiric Blood
    VAMPIRIC_BLOOD_TREE = m.tree_node(),
    VAMPIRIC_BLOOD_CHECK = m.checkbox(true, id("vb_enabled")),
    VAMPIRIC_BLOOD_HP = m.slider_int(1, 100, 65, id("vb_hp")),
    VAMPIRIC_BLOOD_INCOMING_HP = m.slider_int(1, 100, 55, id("vb_incoming_hp")),

    -- Icebound Fortitude
    ICEBOUND_TREE = m.tree_node(),
    ICEBOUND_CHECK = m.checkbox(true, id("icebound_enabled")),
    ICEBOUND_HP = m.slider_int(1, 100, 45, id("icebound_hp")),
    ICEBOUND_INCOMING_HP = m.slider_int(1, 100, 35, id("icebound_incoming_hp")),

    -- Anti-Magic Shell
    AMS_TREE = m.tree_node(),
    AMS_CHECK = m.checkbox(true, id("ams_enabled")),
    AMS_HP = m.slider_int(1, 100, 75, id("ams_hp")),
    AMS_MAGICAL_DMG_PCT = m.slider_float(0, 20, 3.5, id("ams_mag_pct")),

    -- Rune Tap
    RUNE_TAP_TREE = m.tree_node(),
    RUNE_TAP_CHECK = m.checkbox(true, id("rune_tap_enabled")),
    RUNE_TAP_HP = m.slider_int(1, 100, 70, id("rune_tap_hp")),

    -- Death Strike Emergency
    DEATH_STRIKE_EMERGENCY_TREE = m.tree_node(),
    DEATH_STRIKE_EMERGENCY_CHECK = m.checkbox(true, id("ds_emergency_enabled")),
    DEATH_STRIKE_EMERGENCY_HP = m.slider_int(1, 100, 50, id("ds_emergency_hp")),

    -- Cooldowns
    COOLDOWNS_TREE = m.tree_node(),

    -- Dancing Rune Weapon
    DRW_TREE = m.tree_node(),
    DRW_CHECK = m.checkbox(true, id("drw_enabled")),
    DRW_TTD = m.slider_int(1, 120, 20, id("drw_ttd")),

    -- Bonestorm
    BONESTORM_CHECK = m.checkbox(true, id("bonestorm_enabled")),

    -- Tombstone
    TOMBSTONE_CHECK = m.checkbox(true, id("tombstone_enabled")),

    -- Blooddrinker
    BLOODDRINKER_CHECK = m.checkbox(true, id("blooddrinker_enabled")),

    -- Soul Reaper
    SOUL_REAPER_CHECK = m.checkbox(true, id("soul_reaper_enabled")),

    -- Reapers Mark
    REAPERS_MARK_CHECK = m.checkbox(true, id("reapers_mark_enabled")),

    -- Utility
    UTILITY_TREE = m.tree_node(),
    AUTO_RAISE_DEAD_CHECK = m.checkbox(true, id("auto_raise_dead")),
    RAISE_ALLY_CHECK = m.checkbox(true, id("raise_ally_enabled")),
    GOREFRIENDS_GRASP_CHECK = m.checkbox(true, id("grasp_enabled")),
    GOREFRIENDS_GRASP_ENEMIES = m.slider_int(1, 20, 4, id("grasp_enemies")),
    
    -- Taunts
    TAUNTS_TREE = m.tree_node(),
    DARK_COMMAND_CHECK = m.checkbox(true, id("dark_command_enabled")),
    DEATH_GRIP_TAUNT_CHECK = m.checkbox(true, id("death_grip_taunt_enabled")),

    -- Interrupts
    INTERRUPTS_TREE = m.tree_node(),
    AUTO_INTERRUPT = m.checkbox(true, id("auto_interrupt")),
    ASPHYXIATE_CHECK = m.checkbox(true, id("asphyxiate_enabled")),
    DEATH_GRIP_CHECK = m.checkbox(true, id("death_grip_enabled")),

    -- Bone Shield
    BONE_SHIELD_TREE = m.tree_node(),
    BONE_SHIELD_MIN_STACKS = m.slider_int(0, 10, 5, id("bone_shield_min")),
    BONE_SHIELD_REFRESH_THRESHOLD = m.slider_float(1.0, 15.0, 5.0, id("bone_shield_refresh")),

    -- Racials
    RACIALS_CHECK = m.checkbox(true, id("racials_enabled")),

    -- Resource Management
    RESOURCE_MANAGEMENT_TREE = m.tree_node(),
    RP_CAPPING_THRESHOLD = m.slider_int(15, 50, 30, id("rp_capping_threshold")),
    RP_POOLING_THRESHOLD = m.slider_int(10, 50, 20, id("rp_pooling_threshold")),
    RUNE_FORECAST_WINDOW = m.slider_float(1.0, 5.0, 3.0, id("rune_forecast_window")),
    AGGRESSIVE_RESOURCE_SPENDING = m.checkbox(false, id("aggressive_resource_spending")),

    -- QoL
    QOL_TREE = m.tree_node(),
    AUTO_LOOT = m.checkbox(false, id("auto_loot")),
    AUTO_POTION = m.checkbox(false, id("auto_potion")),
    POTION_HP_THRESHOLD = m.slider_int(1, 100, 40, id("potion_hp_threshold")),
    ANTI_AFK = m.checkbox(false, id("anti_afk")),
    LEGION_REMIX = m.checkbox(false, id("legion_remix")),
    
    -- Remix Time
    REMIX_TIME_MODE = m.combobox(1, id("remix_time_mode")), -- 1 = Off, 2 = Offensive, 3 = Defensive
    REMIX_TIME_MIN_COOLDOWN = m.slider_int(10, 120, 30, id("remix_time_min_cd")), -- Minimum cooldown time in seconds

    -- Advanced
    ADVANCED_TREE = m.tree_node(),
    USE_PREDICTION = m.checkbox(true, id("use_prediction")),
    USE_EVENT_SYSTEM = m.checkbox(true, id("use_event_system")),
    DND_MIN_HITS = m.slider_int(1, 5, 1, id("dnd_min_hits")),
    SMART_TARGETING = m.checkbox(true, id("smart_targeting")),
}

-- Validation Functions

function menu:is_enabled()
    if not self.GLOBAL_CHECK:get_state() then
        return false
    end

    local keybind_state = self.ROTATION_KEYBIND:get_toggle_state()
    if not keybind_state then
        return false
    end

    return true
end

function menu.validate_vampiric_blood(me)
    if not menu.VAMPIRIC_BLOOD_CHECK:get_state() then
        return false
    end

    local current_hp = me:get_health_percentage()
    local hp_threshold = menu.VAMPIRIC_BLOOD_HP:get()

    local _, incoming_hp = me:get_health_percentage_inc(2.0)
    local incoming_threshold = menu.VAMPIRIC_BLOOD_INCOMING_HP:get()

    return current_hp <= hp_threshold or incoming_hp <= incoming_threshold
end

function menu.validate_icebound(me)
    if not menu.ICEBOUND_CHECK:get_state() then
        return false
    end

    local current_hp = me:get_health_percentage()
    local hp_threshold = menu.ICEBOUND_HP:get()

    local _, incoming_hp = me:get_health_percentage_inc(2.0)
    local incoming_threshold = menu.ICEBOUND_INCOMING_HP:get()

    return current_hp <= hp_threshold or incoming_hp <= incoming_threshold
end

function menu.validate_ams(me)
    if not menu.AMS_CHECK:get_state() then
        return false
    end

    local current_hp = me:get_health_percentage()
    local hp_threshold = menu.AMS_HP:get()

    local is_magical_relevant = me:is_magical_damage_taken_relevant()

    return (current_hp <= hp_threshold) and is_magical_relevant
end

function menu.validate_rune_tap(me)
    if not menu.RUNE_TAP_CHECK:get_state() then
        return false
    end

    local current_hp = me:get_health_percentage()
    local hp_threshold = menu.RUNE_TAP_HP:get()

    return current_hp <= hp_threshold
end

function menu.validate_death_strike_emergency(me)
    if not menu.DEATH_STRIKE_EMERGENCY_CHECK:get_state() then
        return false
    end

    local current_hp = me:get_health_percentage()
    local hp_threshold = menu.DEATH_STRIKE_EMERGENCY_HP:get()

    return current_hp <= hp_threshold
end

function menu.validate_drw(ttd)
    if not menu.DRW_CHECK:get_state() then
        return false
    end

    return ttd > menu.DRW_TTD:get()
end

function menu.validate_gorefriends_grasp(enemy_count)
    if not menu.GOREFRIENDS_GRASP_CHECK:get_state() then
        return false
    end

    return enemy_count >= menu.GOREFRIENDS_GRASP_ENEMIES:get()
end

function menu.get_hero_tree()
    return menu.HERO_TREE_SELECT:get()
end

-- Render registration
local M = menu
core.register_on_render_menu_callback(function()
    M.MAIN_TREE:render("Blood Death Knight", function()
        M.GLOBAL_CHECK:render("Enabled", "Toggles Blood DK rotation on / off")

        M.KEYBIND_TREE:render("Keybinds", function()
            M.ROTATION_KEYBIND:render("Rotation Toggle", "Toggle rotation on / off")
        end)

        -- Hero Tree Selection
        local hero_tree_options = { "Auto Detect", "Deathbringer", "San'layn" }
        M.HERO_TREE_SELECT:render("Hero Tree", hero_tree_options)

        M.DEFENSIVES_TREE:render("Defensives", function()
            M.VAMPIRIC_BLOOD_TREE:render("Vampiric Blood", function()
                M.VAMPIRIC_BLOOD_CHECK:render("Enabled", "Toggles Vampiric Blood usage")
                if M.VAMPIRIC_BLOOD_CHECK:get_state() then
                    M.VAMPIRIC_BLOOD_HP:render("HP Threshold", "Cast when HP % <= this value")
                    M.VAMPIRIC_BLOOD_INCOMING_HP:render("Incoming HP Threshold", "Cast when predicted HP % <= this value")
                end
            end)

            M.ICEBOUND_TREE:render("Icebound Fortitude", function()
                M.ICEBOUND_CHECK:render("Enabled", "Toggles Icebound Fortitude usage")
                if M.ICEBOUND_CHECK:get_state() then
                    M.ICEBOUND_HP:render("HP Threshold", "Cast when HP % <= this value")
                    M.ICEBOUND_INCOMING_HP:render("Incoming HP Threshold", "Cast when predicted HP % <= this value")
                end
            end)

            M.AMS_TREE:render("Anti-Magic Shell", function()
                M.AMS_CHECK:render("Enabled", "Toggles Anti-Magic Shell usage")
                if M.AMS_CHECK:get_state() then
                    M.AMS_HP:render("HP Threshold", "Cast when HP % <= this value")
                    M.AMS_MAGICAL_DMG_PCT:render("Magical Damage %", "Cast when magical damage % >= this value")
                end
            end)

            M.RUNE_TAP_TREE:render("Rune Tap", function()
                M.RUNE_TAP_CHECK:render("Enabled", "Toggles Rune Tap usage")
                if M.RUNE_TAP_CHECK:get_state() then
                    M.RUNE_TAP_HP:render("HP Threshold", "Cast when HP % <= this value")
                end
            end)

            M.DEATH_STRIKE_EMERGENCY_TREE:render("Death Strike Emergency", function()
                M.DEATH_STRIKE_EMERGENCY_CHECK:render("Enabled", "Toggles emergency Death Strike usage")
                if M.DEATH_STRIKE_EMERGENCY_CHECK:get_state() then
                    M.DEATH_STRIKE_EMERGENCY_HP:render("HP Threshold", "Cast when HP % <= this value")
                end
            end)
        end)

        M.COOLDOWNS_TREE:render("Cooldowns", function()
            M.DRW_TREE:render("Dancing Rune Weapon", function()
                M.DRW_CHECK:render("Enabled", "Toggles Dancing Rune Weapon usage")
                if M.DRW_CHECK:get_state() then
                    M.DRW_TTD:render("Min TTD", "Minimum Time To Die (in seconds) to use DRW")
                end
            end)

            M.BONESTORM_CHECK:render("Bonestorm", "Toggles Bonestorm usage")
            M.TOMBSTONE_CHECK:render("Tombstone", "Toggles Tombstone usage")
            M.BLOODDRINKER_CHECK:render("Blooddrinker", "Toggles Blooddrinker usage")
            M.SOUL_REAPER_CHECK:render("Soul Reaper", "Toggles Soul Reaper usage")
            M.REAPERS_MARK_CHECK:render("Reaper's Mark", "Toggles Reaper's Mark usage")
        end)

        M.UTILITY_TREE:render("Utility", function()
            M.AUTO_RAISE_DEAD_CHECK:render("Auto Raise Dead", "Automatically summon ghoul (only in combat)")
            M.RAISE_ALLY_CHECK:render("Raise Ally (Mouseover)", "Resurrect dead party member on mouseover (in-combat only)")
            M.GOREFRIENDS_GRASP_CHECK:render("Gorefiend's Grasp", "Use Gorefiend's Grasp in Mythic+")
            if M.GOREFRIENDS_GRASP_CHECK:get_state() then
                M.GOREFRIENDS_GRASP_ENEMIES:render("Min Enemies", "Minimum enemies to use Gorefiend's Grasp")
            end
            
            M.TAUNTS_TREE:render("Taunts", function()
                M.DARK_COMMAND_CHECK:render("Dark Command", "Taunt enemies that have lost threat (does not taunt bosses)")
                M.DEATH_GRIP_TAUNT_CHECK:render("Death Grip (Taunt)", "Use Death Grip as taunt when threat is lost (does not taunt bosses)")
            end)
        end)

        M.INTERRUPTS_TREE:render("Interrupts", function()
            M.AUTO_INTERRUPT:render("Auto Interrupt", "Automatically interrupt/stun casting enemies")
            if M.AUTO_INTERRUPT:get_state() then
                M.DEATH_GRIP_CHECK:render("Death Grip", "Use Death Grip to pull and interrupt ranged casting enemies (30yd, 25s CD)")
                M.ASPHYXIATE_CHECK:render("Asphyxiate", "Use Asphyxiate to interrupt/stun melee enemies (4s stun, 45s CD)")
            end
        end)

        M.BONE_SHIELD_TREE:render("Bone Shield", function()
            M.BONE_SHIELD_MIN_STACKS:render("Min Stacks", "Minimum Bone Shield stacks to maintain")
            M.BONE_SHIELD_REFRESH_THRESHOLD:render("Refresh Threshold", "Refresh Bone Shield when duration <= this many seconds (default: 5.0)")
        end)
        M.RACIALS_CHECK:render("Use Racial Abilities", "Use racial cooldowns during DRW")

        M.RESOURCE_MANAGEMENT_TREE:render("Resource Management", function()
            M.RP_CAPPING_THRESHOLD:render("RP Capping Threshold", "Runic Power deficit threshold to prevent capping (default: 30)")
            M.RP_POOLING_THRESHOLD:render("RP Pooling Threshold", "Minimum RP to maintain for emergencies (default: 20)")
            M.RUNE_FORECAST_WINDOW:render("Rune Forecast Window", "Seconds ahead to forecast rune availability (default: 3.0)")
            M.AGGRESSIVE_RESOURCE_SPENDING:render("Aggressive Resource Spending", "More aggressive resource spending for leveling")
        end)

        M.QOL_TREE:render("Quality of Life", function()
            M.AUTO_LOOT:render("Auto Loot", "Automatically loot corpses out of combat")
            M.AUTO_POTION:render("Auto Health Potion", "Automatically use health potions")
            if M.AUTO_POTION:get_state() then
                M.POTION_HP_THRESHOLD:render("Potion HP Threshold", "Use potion when HP drops below this percentage")
            end
            M.ANTI_AFK:render("Anti-AFK", "Prevent AFK kick with tiny movements")
            M.LEGION_REMIX:render("Legion Remix", "Enable Twisted Crusade and Felspike abilities")

            local remix_time_options = { "Off", "Offensive", "Defensive" }
            M.REMIX_TIME_MODE:render("Remix Time Mode", remix_time_options, "Off = Disabled, Offensive = DRW/Tombstone/Bonestorm, Defensive = DRW/Icebound/Vampiric Blood")
            if M.REMIX_TIME_MODE:get() > 1 then
                M.REMIX_TIME_MIN_COOLDOWN:render("Min Cooldown Time", "Minimum cooldown time (seconds) before casting Remix Time (default: 30)")
            end
        end)

        M.ADVANCED_TREE:render("Advanced (SDK Features)", function()
            M.USE_PREDICTION:render("Use Position Prediction", "Use IZI SDK position prediction for ground-targeted abilities (Death and Decay)")
            M.USE_EVENT_SYSTEM:render("Use Event System", "Use event-driven state management instead of polling (recommended)")
            M.DND_MIN_HITS:render("Death and Decay Min Hits", "Minimum enemies to hit with Death and Decay when using prediction (1 = 100% uptime)")
            M.SMART_TARGETING:render("Smart Target Selection", "Use SDK helpers to pick optimal targets (lowest HP, etc.)")
        end)
    end)
end)

-- Control Panel Registration
core.register_on_render_control_panel_callback(function()
    local rotation_toggle_key = M.ROTATION_KEYBIND:get_key_code()
    local rotation_toggle =
    {
        name = string.format("[Blood DK] Enabled (%s)", key_helper:get_key_name(rotation_toggle_key)),
        keybind = M.ROTATION_KEYBIND
    }

    local control_panel_elements = {}

    -- Always render control panel toggle, regardless of enable state
    control_panel_utility:insert_toggle_(control_panel_elements, rotation_toggle.name, rotation_toggle.keybind, false)

    return control_panel_elements
end)

return menu
