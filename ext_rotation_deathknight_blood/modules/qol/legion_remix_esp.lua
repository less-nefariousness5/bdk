--[[
    Blood Death Knight - Legion Remix ESP

    Draws labels on Legion Remix collectible objects.
    Performance-optimized with 500ms caching system.
]]

local color = require("common/color")

local M = {}

-- Object ID lookup table (O(1) constant-time lookups)
-- These are Legion Remix collectibles that appear in the game world
local TRACKED_OBJECTS = {
    [517167] = true,  -- Legion Remix Object
    [517221] = true,  -- Legion Remix Object
    [517222] = true,  -- Legion Remix Object
    [517223] = true,  -- Legion Remix Object
    [517224] = true,  -- Legion Remix Object
    [517225] = true,  -- Legion Remix Object
    [517226] = true,  -- Legion Remix Object
    [517227] = true,  -- Legion Remix Object
    [517228] = true,  -- Legion Remix Object
    [517229] = true,  -- Legion Remix Object
    [517231] = true,  -- Legion Remix Object
    [517232] = true,  -- Legion Remix Object
    [517233] = true,  -- Legion Remix Object
    [517328] = true,  -- Legion Remix Object
}

-- Drawing constants
local TEXT_COLOR = color.cyan(255)      -- Cyan text with full opacity
local TEXT_SIZE = 14                     -- Font size
local TEXT_CENTERED = true               -- Center text on object
local TEXT_FONT = 10                     -- Font ID
local TEXT_Z_OFFSET = -0.25              -- Z-axis offset for text positioning

-- Cache update interval (seconds)
local CACHE_UPDATE_INTERVAL = 0.5  -- Update cache every 0.5 seconds (2Hz instead of 60Hz)

-- State
local last_cache_update = 0.0
local cached_objects = {}

---Render callback (runs every frame ~60 FPS)
---Draws labels on cached objects without querying object manager
function M:OnRender()
    -- Traditional for loop (faster than ipairs)
    for i = 1, #cached_objects do
        local obj = cached_objects[i]

        -- Validate object before accessing properties
        if not obj or not obj:is_valid() then
            goto continue
        end

        -- Get object name and position
        local name = obj:get_name()
        local pos = obj:get_position()

        if not name or not pos then
            goto continue
        end

        -- Adjust Z position based on object scale
        local scale = obj:get_scale()
        pos.z = pos.z + TEXT_Z_OFFSET * scale

        -- Draw 3D text at object position
        core.graphics.text_3d(
            name,
            pos,
            TEXT_SIZE,
            TEXT_COLOR,
            TEXT_CENTERED,
            TEXT_FONT
        )

        ::continue::
    end
end

---Update callback (cache refresh at configurable interval)
---Queries object manager and filters by ID lookup table
function M:OnUpdate()
    local current_time = core.time()

    -- Only update cache at specified interval (performance optimization)
    if current_time - last_cache_update < CACHE_UPDATE_INTERVAL then
        return
    end

    last_cache_update = current_time

    -- Clear old cache
    cached_objects = {}

    -- Get all objects from object manager
    local all_objects = core.object_manager:get_all_objects()
    if not all_objects then
        return
    end

    -- Filter objects by ID lookup table (O(1) per object)
    for i = 1, #all_objects do
        local obj = all_objects[i]

        if obj and obj:is_valid() then
            local obj_id = obj:get_npc_id()

            -- Check if this object ID is tracked
            if TRACKED_OBJECTS[obj_id] then
                -- Add to cache
                cached_objects[#cached_objects + 1] = obj
            end
        end
    end
end

---Count table keys
---@param tbl table
---@return number
local function count_table_keys(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

---Initialize ESP module
function M:Initialize()
    -- Log initialization
    core.log("[Legion Remix ESP] Initialized - Tracking " ..
             count_table_keys(TRACKED_OBJECTS) .. " object IDs")
end

return M

