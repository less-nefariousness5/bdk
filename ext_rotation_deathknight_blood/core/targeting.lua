---@diagnostic disable: undefined-global, lowercase-global
--[[
    Targeting - Target Selection and Validation Helpers

    Purpose:
    - Smart target selection using SDK's pick_enemy
    - Enemy detection and range checking
    - Hero tree detection and configuration
    - Blood Boil range detection for AoE decisions

    Dependencies:
    - menu: Configuration values
    - sdk_helpers: Safe validation functions
    - izi: IZI SDK for pick_enemy
]]

local M = {}

-- Hero tree constants
M.HERO_TREE_DEATHBRINGER = 1
M.HERO_TREE_SANLAYN = 2

-- ============================================================================
-- SMART TARGET SELECTION (SDK)
-- ============================================================================

---Pick best enemy using SDK's pick_enemy helper
---Selects lowest HP target within range for execute priority
---@param me game_object The player object
---@param radius number Search radius
---@param menu table The menu configuration table
---@param izi table IZI SDK module
---@return game_object|nil target Best target or nil if none found
function M.pick_best_enemy(me, radius, menu, izi)
    if not me or not me:is_valid() then
        return nil
    end

    if not menu or not menu.SMART_TARGETING:get_state() then
        return nil
    end

    -- Use SDK's pick_enemy to find lowest HP target
    return izi.pick_enemy(radius, false, function(u)
        if not (u and u:is_valid() and u:is_alive()) then
            return nil
        end
        -- Return HP percentage for sorting (lower is better for execute)
        return u:get_health_percentage()
    end, "min")
end

-- ============================================================================
-- HERO TREE DETECTION
-- ============================================================================

---Detect hero tree (based on heroic talent IDs)
---Auto-detects or uses menu override for hero tree selection
---@param me game_object The player object
---@param menu table The menu configuration table
---@param SPELLS table Spell objects table
---@param izi table IZI SDK module
---@return number|nil hero_tree HERO_TREE_DEATHBRINGER, HERO_TREE_SANLAYN, or nil for leveling
function M.detect_hero_tree(me, menu, SPELLS, izi)
    if not me or not me:is_valid() then
        return nil
    end

    -- Check menu override first
    local menu_choice = menu and menu.HERO_TREE_SELECT:get() or 1
    if menu_choice == 2 then
        return M.HERO_TREE_DEATHBRINGER
    elseif menu_choice == 3 then
        return M.HERO_TREE_SANLAYN
    end

    -- Auto-detect based on heroic talent IDs
    -- Talent 439843 (Reaper's Mark spell) = Deathbringer rotation
    -- Talent/Spell 433901 = San'layn rotation
    -- Use spell.is_learned() to check if talents/spells are learned
    local has_reapers_mark_talent = SPELLS.REAPERS_MARK and SPELLS.REAPERS_MARK:is_learned()

    -- Check San'layn talent/spell (433901) - create a temporary spell object to check
    local sanlayn_spell = izi.spell(433901)
    local has_sanlayn_talent = sanlayn_spell and sanlayn_spell:is_learned()

    if has_reapers_mark_talent then
        return M.HERO_TREE_DEATHBRINGER
    elseif has_sanlayn_talent then
        return M.HERO_TREE_SANLAYN
    end

    -- Neither talent learned = leveling (return nil to use default/leveling rotation)
    -- The rotation continues naturally without special routing
    return nil  -- Indicates leveling/no hero tree
end

-- ============================================================================
-- ENEMY DETECTION & RANGE CHECKING
-- ============================================================================

---Get enemies in range with validation
---Returns a validated list of enemies within the specified range
---@param me game_object The player object
---@param radius number Search radius
---@param izi table IZI SDK module
---@return table enemies List of valid enemies in range
function M.get_enemies_in_range(me, radius, izi)
    if not me or not me:is_valid() then
        return {}
    end

    local enemies = izi.enemies(radius)
    if not enemies then
        return {}
    end

    -- Filter and validate enemies
    local valid_enemies = {}
    for _, enemy in ipairs(enemies) do
        if enemy and enemy:is_valid() and enemy:is_alive() and me:can_attack(enemy) then
            table.insert(valid_enemies, enemy)
        end
    end

    return valid_enemies
end

---Check if enemies are in Blood Boil range
---Used to determine if Blood Boil is worth casting
---@param me game_object The player object
---@param enemies table List of enemy units
---@return boolean has_enemies True if at least one enemy is in range
---@return number count Number of enemies in Blood Boil range
function M.has_enemies_in_blood_boil_range(me, enemies)
    if not me or not me:is_valid() then
        return false, 0
    end

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

---Count enemies in melee range
---@param me game_object The player object
---@param enemies table List of enemy units
---@param melee_range number Melee range threshold (default 5)
---@return number count Number of enemies in melee range
function M.count_enemies_in_melee(me, enemies, melee_range)
    if not me or not me:is_valid() then
        return 0
    end

    if not enemies or #enemies == 0 then
        return 0
    end

    melee_range = melee_range or 5
    local count = 0

    for _, enemy in ipairs(enemies) do
        if enemy and enemy:is_valid() and enemy:is_alive() and me:can_attack(enemy) then
            if enemy:is_in_range(melee_range) then
                count = count + 1
            end
        end
    end

    return count
end

-- ============================================================================
-- TARGET VALIDATION
-- ============================================================================

---Validate target for offensive abilities
---Comprehensive check for target validity and attackability
---@param me game_object The player object
---@param target game_object|nil The target to validate
---@return boolean is_valid True if target is valid for attacking
function M.validate_offensive_target(me, target)
    if not me or not me:is_valid() then
        return false
    end

    if not target or not target:is_valid() then
        return false
    end

    if not target:is_alive() then
        return false
    end

    if not me:can_attack(target) then
        return false
    end

    return true
end

---Check if target is in range for ability
---@param target game_object The target to check
---@param range number Range threshold
---@return boolean in_range True if target is in range
function M.is_target_in_range(target, range)
    if not target or not target:is_valid() then
        return false
    end

    return target:is_in_range(range)
end

-- ============================================================================
-- SPELL CLASSIFICATION
-- ============================================================================

-- Melee spells (require melee range ~5 yards)
local MELEE_SPELLS = {
    [195182] = true,  -- MARROWREND
    [206930] = true,  -- HEART_STRIKE
    [49998] = true,   -- DEATH_STRIKE
    [50842] = true,   -- BLOOD_BOIL (10 yard range, but effectively melee)
    [274156] = true,  -- CONSUMPTION
    [433895] = true,  -- VAMPIRIC_STRIKE
}

-- Ranged spells (can cast from range)
local RANGED_SPELLS = {
    [195292] = true,  -- DEATHS_CARESS (30 yard range)
    [439843] = true,  -- REAPERS_MARK (30 yard range)
    [343294] = true,  -- SOUL_REAPER (30 yard range)
    [49576] = true,   -- DEATH_GRIP (30 yard range)
}

---Check if spell requires melee range
---@param spell_id number Spell ID to check
---@return boolean is_melee True if spell requires melee range
function M.is_spell_melee(spell_id)
    return MELEE_SPELLS[spell_id] == true
end

---Check if spell can be cast from range
---@param spell_id number Spell ID to check
---@return boolean is_ranged True if spell can be cast from range
function M.is_spell_ranged(spell_id)
    return RANGED_SPELLS[spell_id] == true
end

-- ============================================================================
-- SMART TARGET SELECTION
-- ============================================================================

---Get best melee target (always finds target in melee range)
---Prefers manual target if in melee range, otherwise finds nearest enemy in melee range
---@param me game_object The player object
---@param manual_target game_object|nil The manually selected HUD target
---@param enemies table List of enemy units
---@param melee_range number Melee range threshold (default 5)
---@return game_object|nil target Best melee target or nil if none found
function M.get_best_melee_target(me, manual_target, enemies, melee_range)
    if not me or not me:is_valid() then
        return nil
    end

    melee_range = melee_range or 5

    -- Prefer manual target if it's valid and in melee range
    if manual_target and manual_target:is_valid() and manual_target:is_alive() then
        if me:can_attack(manual_target) and manual_target:is_in_range(melee_range) then
            return manual_target
        end
    end

    -- Find nearest enemy in melee range
    if not enemies or #enemies == 0 then
        return nil
    end

    local best_target = nil
    local closest_distance = math.huge

    for _, enemy in ipairs(enemies) do
        if enemy and enemy:is_valid() and enemy:is_alive() and me:can_attack(enemy) then
            if enemy:is_in_range(melee_range) then
                local distance = me:distance_to(enemy)
                if distance < closest_distance then
                    closest_distance = distance
                    best_target = enemy
                end
            end
        end
    end

    return best_target
end

---Get best ranged target (prefers manual target if in range, otherwise finds best target)
---For ranged spells, prefer manual target even if slightly out of range (for movement)
---@param me game_object The player object
---@param manual_target game_object|nil The manually selected HUD target
---@param enemies table List of enemy units
---@param max_range number Maximum range for the spell (default 30)
---@return game_object|nil target Best ranged target or nil if none found
function M.get_best_ranged_target(me, manual_target, enemies, max_range)
    if not me or not me:is_valid() then
        return nil
    end

    max_range = max_range or 30

    -- Prefer manual target if it's valid and in range (or close to range for movement)
    if manual_target and manual_target:is_valid() and manual_target:is_alive() then
        if me:can_attack(manual_target) then
            -- Use manual target if in range, or if slightly out of range (within 5 yards extra for movement)
            if manual_target:is_in_range(max_range) or manual_target:is_in_range(max_range + 5) then
                return manual_target
            end
        end
    end

    -- Find best target in range (prefer lowest HP for execute priority)
    if not enemies or #enemies == 0 then
        return nil
    end

    local best_target = nil
    local lowest_hp = 100

    for _, enemy in ipairs(enemies) do
        if enemy and enemy:is_valid() and enemy:is_alive() and me:can_attack(enemy) then
            if enemy:is_in_range(max_range) then
                local hp_pct = enemy:get_health_percentage()
                if hp_pct < lowest_hp then
                    lowest_hp = hp_pct
                    best_target = enemy
                end
            end
        end
    end

    return best_target
end

-- ============================================================================
-- SPECIAL TARGET CHECKS
-- ============================================================================

---Check if target has a specific debuff that will explode soon
---Used for Reaper's Mark and other time-sensitive debuffs
---@param target game_object The target to check
---@param debuff_id number The debuff ID to check
---@param time_threshold number Time threshold in seconds (default 5)
---@return boolean explodes_soon True if debuff will explode soon
function M.debuff_explodes_soon(target, debuff_id, time_threshold)
    if not target or not target:is_valid() then
        return false
    end

    time_threshold = time_threshold or 5
    local debuff_remains = target:debuff_remains_sec(debuff_id)
    return debuff_remains > 0 and debuff_remains <= time_threshold
end

---Check if player has a ghoul pet active
---@param unit game_object The player unit
---@return boolean has_ghoul True if ghoul is active
function M.has_ghoul(unit)
    if not unit or not unit:is_valid() then
        return false
    end

    local minions = unit:get_all_minions()
    if not minions then
        return false
    end

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

return M
