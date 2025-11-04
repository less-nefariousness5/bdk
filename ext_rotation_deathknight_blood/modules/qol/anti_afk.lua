--[[
    Blood Death Knight - Anti-AFK

    Prevents AFK kick by performing tiny movement every 5 minutes.
]]

local M = {}

-- State tracking
local last_seen_move_s = 0
local nudge_active = false
local nudge_start_s = 0

-- Constants
local NUDGE_GAP_S = 300.0   -- How long to wait before nudging (5 minutes = 300 seconds)
local NUDGE_HOLD_S = 0.05  -- How long to hold forward key (50ms)

---Main update function
---@param player game_object
---@param menu table
function M.update(player, menu)
    if not player or not player:is_valid() then
        return
    end

    -- Check if anti-AFK is enabled
    if not menu.ANTI_AFK:get_state() then
        return
    end

    local now_s = core.time()

    -- Track real movement (any movement resets the AFK timer)
    if player:is_moving() then
        last_seen_move_s = now_s
    end

    -- Finish a running nudge after hold time
    if nudge_active and (now_s - nudge_start_s) >= NUDGE_HOLD_S then
        nudge_active = false
        if core.input and core.input.move_forward_stop then
            core.input.move_forward_stop()
        end
    end

    -- Start a new nudge if needed
    if (now_s - last_seen_move_s) >= NUDGE_GAP_S and not nudge_active then
        -- Do a tiny forward tap
        if core.input and core.input.move_forward_start then
            core.input.move_forward_start()
            nudge_active = true
            nudge_start_s = now_s
            last_seen_move_s = now_s  -- Schedule next nudge in 5m
        end
    end
end

---Initialize anti-AFK module
function M:Initialize()
    -- Initialize AFK timer so we don't instantly nudge on load
    last_seen_move_s = core.time()
end

return M

