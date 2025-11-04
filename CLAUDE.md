# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a World of Warcraft addon/bot for Blood Death Knight rotation automation, built on the IZI SDK framework. The project implements an intelligent combat rotation system with defensive cooldown management, interrupts, taunts, and quality-of-life features.

**Key Characteristics:**
- Language: Lua
- Framework: IZI SDK (`izi_sdk` from `common/izi_sdk`)
- Target: WoW Blood Death Knight (validates class/spec in header.lua)
- Execution: Frame-based update loop in main.lua

## Architecture

### Core Files

```
ext_rotation_deathknight_blood/
├── header.lua          # Plugin metadata & class/spec validation
├── constants.lua       # Centralized configuration (Legion Remix buffs, thresholds)
├── spells.lua          # Spell definitions using izi.spell()
├── menu.lua            # In-game configuration UI (checkboxes, sliders, keybinds)
└── main.lua            # Rotation logic (2000+ lines)
```

### Module System (QoL)

Quality-of-life features are isolated in `modules/qol/`:
- `auto_loot.lua` - Out-of-combat corpse looting
- `health_potion.lua` - Emergency health potion usage
- `anti_afk.lua` - Prevents AFK kicks
- `legion_remix.lua` - Twisted Crusade/Felspike mechanics
- `legion_remix_esp.lua` - Visual ESP for Legion Remix buffs

Each module exports an `update(player, menu)` function called from main.lua's update loop.

### Spell Definition Pattern

All spells are defined in `spells.lua` using IZI SDK's spell constructor:

```lua
SPELLS.MARROWREND = izi.spell(195182)
SPELLS.BLOOD_FURY = izi.spell(20572, 33697, 33702)  -- Multiple spell IDs for racial variants
```

Debuff tracking is configured via:
```lua
SPELLS.BLOOD_BOIL:track_debuff(BUFFS.BLOOD_PLAGUE)
```

### Menu System

The menu system in `menu.lua` follows this pattern:

```lua
-- Define menu elements
menu.VAMPIRIC_BLOOD_CHECK = m.checkbox(default_value, unique_id)
menu.VAMPIRIC_BLOOD_HP = m.slider_int(min, max, default, unique_id)

-- Validation functions
function menu.validate_vampiric_blood(me)
    if not menu.VAMPIRIC_BLOOD_CHECK:get_state() then
        return false
    end
    local current_hp = me:get_health_percentage()
    return current_hp <= menu.VAMPIRIC_BLOOD_HP:get()
end

-- Render callback
core.register_on_render_menu_callback(function()
    menu.MAIN_TREE:render("Blood Death Knight", function()
        menu.VAMPIRIC_BLOOD_CHECK:render("Enabled", "Description")
        if menu.VAMPIRIC_BLOOD_CHECK:get_state() then
            menu.VAMPIRIC_BLOOD_HP:render("HP Threshold", "Cast when HP % <= this value")
        end
    end)
end)
```

**Important:** All menu IDs must be unique across the entire addon. Use the `id(key)` helper function (lines 7-10 in menu.lua).

### Rotation Logic Structure (main.lua)

The rotation follows a priority system executed in `plugin.update(unit)`:

1. **Cache Resources** (lines 15-24): GCD, runic power, runes, bone shield stacks
2. **QoL Updates**: Call module update functions (auto_loot, health_potion, etc.)
3. **Hero Tree Detection**: Auto-detect Deathbringer vs San'layn (lines 147-178)
4. **Target Validation**: Ensure valid enemy target
5. **Priority List Execution**:
   - Emergency defensives (Death Strike < 50% HP)
   - Defensive cooldowns (Vampiric Blood, Icebound Fortitude, Anti-Magic Shell)
   - Interrupts (Asphyxiate, Death Grip)
   - Taunts (Dark Command, Death Grip taunt mode)
   - Offensive cooldowns (Dancing Rune Weapon, Bonestorm, Tombstone)
   - Core rotation (Marrowrend, Heart Strike, Blood Boil, Death Strike)

### Resource Management System

The addon includes sophisticated resource forecasting (lines 180-280 in main.lua):

**Key Functions:**
- `get_rune_forecast(me)` - Returns table with current runes and time-to-X projections
- `should_save_runes_for_ability(me, runes_needed, forecast_window)` - Determines if runes should be pooled
- `can_afford_rune_spender(me, rune_cost, check_future)` - Checks affordability with forecasting
- `should_pool_rp_for_drw(me)` - Determines if Runic Power should be saved for Dancing Rune Weapon

**Configuration:**
- `menu.RUNE_FORECAST_WINDOW` - Seconds ahead to forecast (default: 3.0)
- `menu.RP_CAPPING_THRESHOLD` - RP deficit to prevent capping (default: 30)
- `menu.RP_POOLING_THRESHOLD` - Minimum RP for emergencies (default: 20)

### Hero Tree System

The addon supports two hero trees with auto-detection:

**Detection Logic (lines 147-178):**
1. Check menu override (`menu.HERO_TREE_SELECT:get()`)
2. Auto-detect via `SPELLS.REAPERS_MARK:is_learned()` → Deathbringer
3. Auto-detect via San'layn spell (433901) → San'layn
4. If neither learned → Leveling/default rotation

**Implementation:**
- Deathbringer: Uses Reaper's Mark (439843) and tracks debuff explosion timing
- San'layn: Uses Vampiric Strike (433895) and tracks Essence of the Blood Queen buff (433925)

### Legion Remix Integration

Legion Remix mechanics are handled via:

**Constants (constants.lua):**
```lua
M.LEGION_REMIX = {
    TWISTED_CRUSADE_BUFF = 1237711,
    FELSPIKE_BUFF = 1242997,
    DEFAULT_ENEMY_THRESHOLD = 3,
}
```

**Menu Toggle:** `menu.LEGION_REMIX:get_state()` enables Twisted Crusade and Felspike usage

**Remix Time Feature:** `menu.REMIX_TIME_MODE:get()` offers:
- 1 = Off
- 2 = Offensive (casts with DRW/Tombstone/Bonestorm)
- 3 = Defensive (casts with DRW/Icebound/Vampiric Blood)

### Common Patterns

**Spell Casting:**
```lua
if SPELLS.MARROWREND:cast() then
    return true  -- Exit priority list on successful cast
end
```

**Buff/Debuff Checking:**
```lua
local bone_shield_stacks = me:buff_stacks(BUFF_BONE_SHIELD)
local bone_shield_remains = me:buff_remains_sec(BUFF_BONE_SHIELD)
local has_blood_plague = target:has_debuff(DEBUFF_BLOOD_PLAGUE)
```

**Enemy Counting:**
```lua
local enemies = me:get_enemies_in_range(10)
local enemy_count = #enemies
```

**Health Prediction:**
```lua
local current_hp = me:get_health_percentage()
local _, incoming_hp = me:get_health_percentage_inc(2.0)  -- 2 second prediction
local recent_damage = me:get_incoming_damage(5.0)  -- Damage taken in last 5 seconds
```

## Extending the Addon

### Adding a New Spell

1. **Define in spells.lua:**
   ```lua
   SPELLS.NEW_SPELL = izi.spell(spell_id)
   ```

2. **Add menu option in menu.lua:**
   ```lua
   menu.NEW_SPELL_CHECK = m.checkbox(true, id("new_spell_enabled"))
   ```

3. **Add render in menu callback:**
   ```lua
   menu.NEW_SPELL_CHECK:render("New Spell", "Description")
   ```

4. **Add to rotation in main.lua:**
   ```lua
   if menu.NEW_SPELL_CHECK:get_state() and SPELLS.NEW_SPELL:cast() then
       return true
   end
   ```

### Adding a New QoL Module

1. **Create `modules/qol/new_feature.lua`:**
   ```lua
   local M = {}

   function M.update(player, menu)
       -- Implementation
   end

   return M
   ```

2. **Import in main.lua:**
   ```lua
   local new_feature = require("modules/qol/new_feature")
   ```

3. **Call in update loop:**
   ```lua
   new_feature.update(me, menu)
   ```

4. **Add menu toggle in menu.lua:**
   ```lua
   menu.NEW_FEATURE_CHECK = m.checkbox(false, id("new_feature"))
   ```

### Defensive Logic Pattern

Defensives typically check HP thresholds and incoming damage:

```lua
function menu.validate_defensive(me)
    if not menu.DEFENSIVE_CHECK:get_state() then
        return false
    end

    local current_hp = me:get_health_percentage()
    local hp_threshold = menu.DEFENSIVE_HP:get()

    local _, incoming_hp = me:get_health_percentage_inc(2.0)
    local incoming_threshold = menu.DEFENSIVE_INCOMING_HP:get()

    return current_hp <= hp_threshold or incoming_hp <= incoming_threshold
end
```

## Key Constants

**Buff IDs (main.lua lines 66-86):**
- `BUFF_BONE_SHIELD` - Core tanking buff (from buff_db)
- `BUFF_DANCING_RUNE_WEAPON` - Major cooldown buff (from buff_db)
- `BUFF_VAMPIRIC_BLOOD = 55233` - Defensive cooldown
- `BUFF_CRIMSON_SCOURGE = 81141` - Free Death and Decay proc
- `BUFF_COAGULOPATHY = 391481` - Blood Shield buff

**Blood Plague Pandemic (main.lua lines 88-90):**
```lua
local BLOOD_PLAGUE_DURATION_SEC = 24
local BLOOD_PLAGUE_PANDEMIC_THRESHOLD_SEC = BLOOD_PLAGUE_DURATION_SEC * 0.30  -- 7.2 seconds
```

## IZI SDK Framework

This project relies heavily on the IZI SDK framework (not included in this repository). Key SDK patterns:

**Spell Objects:**
- `spell:cast()` - Attempts to cast, returns boolean success
- `spell:is_learned()` - Checks if spell/talent is known
- `spell:is_castable()` - Checks cooldown, resources, range
- `spell:track_debuff(debuff_id)` - Registers debuff for tracking

**Game Objects (player/enemies):**
- `unit:get_health_percentage()` - Current HP %
- `unit:get_health_percentage_inc(seconds)` - Predicted HP % after damage
- `unit:get_incoming_damage(seconds)` - Damage taken in last X seconds
- `unit:rune_count()` - Available runes
- `unit:rune_time_to_x(count)` - Seconds until X runes available
- `unit:buff_stacks(buff_id)` - Stack count of buff
- `unit:buff_remains_sec(buff_id)` - Remaining duration in seconds
- `unit:has_debuff(debuff_id)` - Boolean debuff check
- `unit:get_enemies_in_range(range)` - Returns table of enemy objects

**Core APIs:**
- `core.time()` - Game time in seconds
- `core.log(message)` - Debug logging
- `core.input.loot_object(unit)` - Opens loot window
- `core.game_ui.get_loot_item_count()` - Returns loot slot count

## Notes

- The addon validates Blood Death Knight class/spec on load (header.lua:11-35)
- All spell IDs are retail WoW spell IDs
- The rotation is designed for both leveling and endgame content
- Aggressive resource spending mode exists for leveling (`menu.AGGRESSIVE_RESOURCE_SPENDING`)
- State tracking variables are cached at the top of each frame (main.lua lines 16-43)
- Death Strike timing uses cooldown tracking to prevent back-to-back casts (`last_death_strike_time`)
