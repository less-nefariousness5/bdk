---@diagnostic disable: undefined-global, lowercase-global
--[[
    Blood Death Knight - Interrupt Systems Module

    Purpose: Interrupt priority system
    Main function: execute(me, spells, menu, targeting, gcd)

    Handles:
    - Mind Freeze (standard interrupt - Priority 1)
    - Asphyxiate (non-interruptable but stunnable casts)
    - Blinding Sleet (AoE interrupt)
    - Death Grip (ranged interrupts for magic casters)

    Priority Order:
    1. Mind Freeze (standard interrupt, interruptable casts)
    2. Asphyxiate (non-interruptable but stunnable casts)
    3. Blinding Sleet (AoE interrupt, 2+ casters)
    4. Death Grip (magic casters at range)

    Note: Anti-Magic Shell usage as last resort interrupt is handled in defensives module

    Extracted from: main.lua (handle_interrupts() function)
]]

local izi = require("common/izi_sdk")

local M = {}

-- ============================================================================
-- INTERRUPT EXECUTION FUNCTION
-- ============================================================================

---Execute interrupt priority system
---@param me game_object Player unit
---@param spells table Spell table from spells.lua
---@param menu table Menu configuration
---@param targeting table Targeting information (target, enemies, etc)
---@param gcd number Global cooldown duration
---@return boolean true if an action was taken, false otherwise
function M.execute(me, spells, menu, targeting, gcd)
    if not me or not me:is_valid() then
        return false
    end

    -- Check if auto-interrupt is enabled
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

    -- Priority 1: Mind Freeze (standard interrupt for interruptable casts)
    -- Use on any interruptable cast at melee range
    if spells.MIND_FREEZE:is_learned() and spells.MIND_FREEZE:is_castable() then
        for _, cast_info in ipairs(casting_enemies) do
            if cast_info.is_interruptable and cast_info.distance <= 5 then
                if spells.MIND_FREEZE:cast_safe(cast_info.enemy, string.format("Mind Freeze (%.1fs)", cast_info.remaining_sec)) then
                    return true
                end
            end
        end
    end

    -- Priority 2: Asphyxiate for non-interruptable but stunnable casts (melee range)
    -- Use when spell is non-interruptable but mob is stunnable
    if menu.ASPHYXIATE_CHECK:get_state() and spells.ASPHYXIATE:is_learned() and spells.ASPHYXIATE:is_castable() then
        for _, cast_info in ipairs(casting_enemies) do
            if not cast_info.is_interruptable and cast_info.distance <= 5 then
                -- Check if enemy is stunnable (not currently stunned)
                -- If not stunned, we can attempt to stun them
                local is_stunned, _ = cast_info.enemy:is_stunned()
                if not is_stunned then
                    if spells.ASPHYXIATE:cast_safe(cast_info.enemy, string.format("Asphyxiate (Non-Interruptable %.1fs)", cast_info.remaining_sec)) then
                        return true
                    end
                end
            end
        end
    end

    -- Priority 3: Blinding Sleet for AoE interrupts (multiple enemies casting)
    -- Use when 2+ enemies are casting (AoE cone in front of player)
    if spells.BLINDING_SLEET:is_learned() and spells.BLINDING_SLEET:is_castable() then
        if casting_count >= 2 then
            -- Blinding Sleet is self-cast (cone AoE in front of player)
            if spells.BLINDING_SLEET:cast_safe(nil, string.format("Blinding Sleet (AoE Interrupt %d casters)", casting_count)) then
                return true
            end
        end
    end

    -- Priority 4: Death Grip for magic casters at range
    -- Prioritize pulling magic casters to melee, especially with Death's Echo (2 charges)
    if menu.DEATH_GRIP_CHECK:get_state() and spells.DEATH_GRIP:is_learned() then
        if spells.DEATH_GRIP:is_castable() then
            -- Check for Death's Echo talent (ID 356367) - gives 2 charges
            local deaths_echo_learned = core.spell_book.is_spell_learned(356367)
            local death_grip_charges = spells.DEATH_GRIP:charges()

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
                        if spells.DEATH_GRIP:cast_safe(cast_info.enemy, string.format("Death Grip (Magic Caster %.1fs)", cast_info.remaining_sec)) then
                            return true
                        end
                    end
                end
            end

            -- Fallback: Any caster at range if we have charges
            if death_grip_charges >= 2 then
                for _, cast_info in ipairs(casting_enemies) do
                    if cast_info.distance > 5 and cast_info.distance <= 30 then
                        if spells.DEATH_GRIP:cast_safe(cast_info.enemy, string.format("Death Grip (Interrupt %.1fs)", cast_info.remaining_sec)) then
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

return M
