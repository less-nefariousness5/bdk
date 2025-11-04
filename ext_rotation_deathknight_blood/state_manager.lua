---@diagnostic disable: undefined-global, lowercase-global
--[[
    Blood Death Knight - State Manager

    Event-driven state management to reduce polling overhead.
    Uses IZI SDK event subscriptions for buff/debuff tracking.
]]

local izi = require("common/izi_sdk")
local BUFFS = require("common/enums").buff_db

local M = {}

-- State tracking
local state = {
    -- Dancing Rune Weapon tracking
    drw = {
        active = false,
        blood_boil_casted = false,
        start_time = 0,
    },

    -- Last ability usage tracking
    last_abilities = {
        death_strike = 0,
    },

    -- Bone Shield tracking
    bone_shield = {
        stacks = 0,
        remains = 0,
    },

    -- Resource tracking (cached per frame)
    resources = {
        runic_power = 0,
        runic_power_deficit = 0,
        runes = 0,
    },

    -- Combat state
    combat = {
        in_combat = false,
        combat_start_time = 0,
    },
}

-- Event unsubscribe functions (for cleanup)
local unsubscribers = {}

---Initialize event subscriptions
function M.init()
    -- Dancing Rune Weapon gain
    table.insert(unsubscribers, izi.on_buff_gain(function(ev)
        local me = izi.me()
        if not me or not me:is_valid() then return end

        if ev.unit == me and ev.buff_id == BUFFS.DANCING_RUNE_WEAPON then
            state.drw.active = true
            state.drw.blood_boil_casted = false
            state.drw.start_time = izi.now()
            core.log("[State] DRW gained - reset Blood Boil tracking")
        end
    end))

    -- Dancing Rune Weapon loss
    table.insert(unsubscribers, izi.on_buff_lose(function(ev)
        local me = izi.me()
        if not me or not me:is_valid() then return end

        if ev.unit == me and ev.buff_id == BUFFS.DANCING_RUNE_WEAPON then
            state.drw.active = false
            state.drw.blood_boil_casted = false
            state.drw.start_time = 0
            core.log("[State] DRW lost - reset tracking")
        end
    end))

    -- Combat start
    table.insert(unsubscribers, izi.on_combat_start(function(ev)
        local me = izi.me()
        if not me or not me:is_valid() then return end

        if ev.unit == me then
            state.combat.in_combat = true
            state.combat.combat_start_time = izi.now()
        end
    end))

    -- Combat finish
    table.insert(unsubscribers, izi.on_combat_finish(function(ev)
        local me = izi.me()
        if not me or not me:is_valid() then return end

        if ev.unit == me then
            state.combat.in_combat = false
        end
    end))

    core.log("[State Manager] Initialized event-driven state tracking")
end

---Update cached state (call once per frame)
---@param me game_object
function M.update(me)
    if not (me and me.is_valid and me:is_valid()) then
        return
    end

    -- Cache resources (these change frequently, so we cache per frame)
    state.resources.runic_power = me:runic_power_current()
    state.resources.runic_power_deficit = me:runic_power_deficit()
    state.resources.runes = me:rune_count()

    -- Cache Bone Shield state
    state.bone_shield.stacks = me:get_buff_stacks(BUFFS.BONE_SHIELD)
    state.bone_shield.remains = me:buff_remains_sec(BUFFS.BONE_SHIELD) or 0
end

---Get current state
---@return table
function M.get_state()
    return state
end

---Record Death Strike cast time
---@param time number
function M.record_death_strike(time)
    state.last_abilities.death_strike = time
end

---Get time since last Death Strike
---@param now number
---@return number
function M.time_since_death_strike(now)
    return now - state.last_abilities.death_strike
end

---Mark Blood Boil as casted during DRW
function M.mark_drw_blood_boil_casted()
    state.drw.blood_boil_casted = true
end

---Check if Blood Boil was casted during current DRW window
---@return boolean
function M.was_drw_blood_boil_casted()
    return state.drw.blood_boil_casted
end

---Check if DRW is active
---@return boolean
function M.is_drw_active()
    return state.drw.active
end

---Cleanup event subscriptions
function M.cleanup()
    for _, unsub in ipairs(unsubscribers) do
        unsub()
    end
    unsubscribers = {}
    core.log("[State Manager] Cleaned up event subscriptions")
end

return M
