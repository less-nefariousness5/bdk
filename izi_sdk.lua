-- Example:
-- ---@type enums
-- local c = require("common/izi_sdk")

---@meta
---@diagnostic disable: undefined-global, missing-fields, lowercase-global

---@alias sort_mode '"max"'|'"min"'
---@alias aura_spec number|number[]|any
---@alias target_filter fun(u: game_object): number|nil
---@alias adv_condition boolean|fun(u: game_object): boolean

---@class cast_opts
---@field skip_charges? boolean
---@field skip_learned? boolean
---@field skip_usable? boolean
---@field skip_back? boolean validated in is_castable_to_unit
---@field skip_moving? boolean
---@field skip_mount? boolean
---@field skip_casting? boolean
---@field skip_channeling? boolean

---@class unit_cast_opts: cast_opts
---@field skip_facing? boolean
---@field skip_range? boolean
---@field skip_gcd? boolean

---@alias prediction_type_opt   "AUTO"|"ACCURACY"|"MOST_HITS"|number
---@alias geometry_type_opt "CIRCLE"|"LINE"|number

---@class pos_cast_opts: unit_cast_opts
---@field check_los? boolean
---@field use_prediction? boolean                 -- default true for position casts
---@field prediction_type? prediction_type_opt    -- "AUTO"|"ACCURACY"|"MOST_HITS"|number
---@field geometry? geometry_type_opt             -- "CIRCLE"|"LINE"|number
---@field aoe_radius? number                      -- overrides defaults & hardcoded
---@field min_hits? integer                       -- default 1
---@field source_position? vec3                   -- custom origin for prediction
---@field cast_time? number                       -- override cast time (milliseconds); skips SDK lookup
---@field projectile_speed? number                -- override projectile speed (game units/sec); 0 = instant
---@field is_heal? boolean                        -- prediction becomes for allies instead of enemies
---@field use_intersection? boolean               -- use intersection position instead of center (for accuracy type)
---@field max_range? number

---@alias unit_predicate fun(u: game_object): boolean
---@alias unit_predicate_list unit_predicate[]

--------------------------------------------------------------------------------
-- game_object (methods patched by izi_module.apply -> patch_game_object_methods)
--------------------------------------------------------------------------------

---@class game_object
---@field get_health_percentage       fun(self: game_object): number                           -- 1..100 (e.g., 90 means ~90% HP)
---@field is_dummy                    fun(self: game_object): boolean                          -- True if training dummy
---@field is_alive                    fun(self: game_object): boolean                          -- Convenience alive check
---@field is_valid_enemy              fun(self: game_object): boolean                          -- Enemy of local player
---@field is_valid_ally               fun(self: game_object): boolean                          -- Ally of local player
---@field get_incoming_damage         fun(self: game_object, deadline_time_in_seconds: number, is_exception?: boolean): number -- Heuristic incoming damage
---@field get_incoming_damage_types   fun(self: game_object, deadline_time_in_seconds?: number, is_exception?: boolean): damage_types_table   -- Recent+predicted dmg profile | note: params are optional if you dont understand them, dont fill them
---@field get_physical_damage_taken_percentage fun(self: game_object, deadline_time_in_seconds?: number, is_exception?: boolean): number  -- 0–100%% of incoming dmg that is PHYSICAL | note: params are optional if you dont understand them, dont fill them
---@field get_magical_damage_taken_percentage  fun(self: game_object, deadline_time_in_seconds?: number, is_exception?: boolean): number  -- 0–100%% of incoming dmg that is MAGICAL | note: params are optional if you dont understand them, dont fill them
---@field get_health_percentage_inc   fun(self: game_object, deadline_time_in_seconds?: number): (number, number, number, number) -- Future HP% (1..100), incoming, current HP%, incoming%
---@field is_damage_immune            fun(self: game_object, type_flags?: integer, min_remaining_ms?: number): (boolean, number, number) -- PvP immunity: (is, rem_ms, expire_time)
---@field is_cc_immune                fun(self: game_object, type_flags?: integer, min_remaining_ms?: number, ignore_dot?: boolean, dot_blacklist?: number[]): (boolean, number, number) -- PvP CC immunity
---@field has_burst_active            fun(self: game_object, min_remaining_ms?: number): boolean -- PvP burst window

---@class game_object
---@field get_buff_data               fun(self: game_object, spec: aura_spec): any|nil         -- Resolved buff data (cached)
---@field has_buff                    fun(self: game_object, spec: aura_spec): boolean         -- Buff present?
---@field buff_up                     fun(self: game_object, spec: aura_spec): boolean         -- Alias of has_buff
---@field buff_down                   fun(self: game_object, spec: aura_spec): boolean         -- not has_buff
---@field get_buff_stacks             fun(self: game_object, spec: aura_spec): number          -- Stacks (0 if absent)
---@field buff_remains                fun(self: game_object, spec: aura_spec): number          -- Remaining secs (>=0)
---@field buff_remains_ms             fun(self: game_object, spec: aura_spec): number          -- Remaining ms (>=0)
---@field buff_remains_sec            fun(self: game_object, spec: aura_spec): number          -- Alias of buff_remains
---@field get_all_buffs               fun(self: game_object): any[]                            -- Buff cache snapshot

---@class game_object
---@field get_debuff_data             fun(self: game_object, spec: aura_spec): any|nil         -- Resolved debuff data (cached; includes fake window)
---@field has_debuff                  fun(self: game_object, spec: aura_spec): boolean         -- Debuff present?
---@field debuff_up                   fun(self: game_object, spec: aura_spec): boolean         -- Alias of has_debuff
---@field debuff_down                 fun(self: game_object, spec: aura_spec): boolean         -- not has_debuff
---@field get_debuff_stacks           fun(self: game_object, spec: aura_spec): number          -- Stacks (0 if absent; fake window => 1)
---@field debuff_remains              fun(self: game_object, spec: aura_spec): number          -- Remaining secs (>=0; fake window => ~10)
---@field debuff_remains_ms           fun(self: game_object, spec: aura_spec): number          -- Remaining ms (>=0; fake window => ~10000)
---@field debuff_remains_sec          fun(self: game_object, spec: aura_spec): number          -- Alias of debuff_remains
---@field get_all_debuffs             fun(self: game_object): any[]                            -- Debuff cache snapshot

---@class game_object
---@field get_aura_data               fun(self: game_object, spec: aura_spec): any|nil         -- Any aura via aura cache
---@field has_aura                    fun(self: game_object, spec: aura_spec): boolean         -- Any aura present?
---@field aura_up                     fun(self: game_object, spec: aura_spec): boolean         -- Alias of has_aura
---@field aura_down                   fun(self: game_object, spec: aura_spec): boolean         -- not has_aura
---@field get_aura_stacks             fun(self: game_object, spec: aura_spec): number          -- Stacks (0 if absent)
---@field aura_remains                fun(self: game_object, spec: aura_spec): number          -- Remaining secs (>=0)
---@field aura_remains_ms             fun(self: game_object, spec: aura_spec): number          -- Remaining ms (>=0)
---@field aura_remains_sec            fun(self: game_object, spec: aura_spec): number          -- Alias of aura_remains
---@field get_all_auras               fun(self: game_object): any[]                            -- Aura cache snapshot

---@class game_object
---@field is_tank                     fun(self: game_object): boolean                           -- Role heuristic
---@field is_dps                      fun(self: game_object): boolean                           -- Role heuristic
---@field affecting_combat            fun(self: game_object): boolean                           -- In combat?
---@field time_to_die                 fun(self: game_object): number                            -- Forecasted TTD (seconds)
---@field get_time_to_death           fun(self: game_object): number                            -- Forecasted TTD (seconds)
---@field is_spell_in_range           fun(self: game_object, spell: integer|izi_spell|{id:fun(self):integer}): boolean -- Range vs local player
---@field is_in_range                 fun(self: game_object, meters: number): boolean           -- Distance <= meters
---@field is_in_melee_range           fun(self: game_object, meters: number): boolean           -- Distance <= (meters + target_radius)
---@field distance                    fun(self: game_object): number                            -- Distance to local player

---@class game_object
---@field get_enemies_in_splash_range       fun(self: game_object, meters: number): game_objects_table -- Enemies within meters (+radius), PvP-aware
---@field get_enemies_in_splash_range_count fun(self: game_object, meters: number): number        -- Count enemies within meters (+radius)
---@field level                       fun(self: game_object): number                             -- Unit level
---@field get_guid                    fun(self: game_object): game_object                        -- Underlying game_object reference
---@field npc_id                      fun(self: game_object): integer                            -- NPC id (0 for players)
---@field is_dead_or_ghost            fun(self: game_object): boolean                            -- True if dead or ghost

---@class game_object
---@field is_casting                              fun(self: game_object): boolean                    -- True if casting
---@field is_channeling                           fun(self: game_object): boolean                    -- True if channeling
---@field is_channeling_or_casting                fun(self: game_object): boolean                    -- True if channeling or casting
---@field get_active_cast_or_channel_id           fun(self: game_object): number                     -- Active spell id, prefers channel id then cast id, 0 if none
-- Casting timing
---@field get_cast_start_ms                       fun(self: game_object): number                     -- Cast start, ms since epoch/game time, 0 if none
---@field get_cast_end_ms                         fun(self: game_object): number                     -- Cast end, ms, 0 if none
---@field get_cast_duration_ms                    fun(self: game_object): number                     -- Total cast duration in ms
---@field get_cast_elapsed_ms                     fun(self: game_object): number                     -- Elapsed cast time in ms, 0 if not casting
---@field get_cast_remaining_ms                   fun(self: game_object): number                     -- Remaining cast time in ms, 0 if not casting
---@field get_cast_remaining_sec                  fun(self: game_object): number                     -- Remaining cast time in seconds
---@field get_cast_ratio                          fun(self: game_object): number                     -- Cast progress ratio 0..1
---@field get_cast_pct                            fun(self: game_object): number                     -- Cast progress percentage 0..100
-- Channel timing
---@field get_channel_start_ms                    fun(self: game_object): number                     -- Channel start, ms, 0 if none
---@field get_channel_end_ms                      fun(self: game_object): number                     -- Channel end, ms, 0 if none
---@field get_channel_duration_ms                 fun(self: game_object): number                     -- Total channel duration in ms
---@field get_channel_elapsed_ms                  fun(self: game_object): number                     -- Elapsed channel time in ms, 0 if not channeling
---@field get_channel_remaining_ms                fun(self: game_object): number                     -- Remaining channel time in ms, 0 if not channeling
---@field get_channel_remaining_sec               fun(self: game_object): number                     -- Remaining channel time in seconds
---@field get_channel_ratio                       fun(self: game_object): number                     -- Channel progress ratio 0..1
---@field get_channel_pct                         fun(self: game_object): number                     -- Channel progress percentage 0..100
-- Combined helpers
---@field get_channeling_or_casting_remaining_ms  fun(self: game_object): number                     -- Remaining time in ms, prefers channel then cast
---@field get_channeling_or_casting_remaining_sec fun(self: game_object): number                     -- Remaining time in seconds, prefers channel then cast
---@field get_channeling_or_casting_pct           fun(self: game_object): number                     -- Progress percentage 0..100, prefers channel then cast
---@field get_channeling_or_casting_ratio         fun(self: game_object): number                     -- Progress ratio 0..1, prefers channel then cast
-- Friendly aliases
---@field casting_pct                             fun(self: game_object): number                     -- Alias of get_cast_pct
---@field channeling_pct                          fun(self: game_object): number                     -- Alias of get_channel_pct
---@field casting_percentage                      fun(self: game_object): number                     -- Alias of get_cast_pct
---@field channeling_percentage                   fun(self: game_object): number                     -- Alias of get_channel_pct
---@field get_any_remaining_ms                    fun(self: game_object): number                     -- Alias of get_channeling_or_casting_remaining_ms
---@field get_any_remaining_sec                   fun(self: game_object): number                     -- Alias of get_channeling_or_casting_remaining_sec
---@field get_any_active_spell_id                 fun(self: game_object): number                     -- Alias of get_active_cast_or_channel_id

---@class game_object
---@field power_max                   fun(self: game_object, power_type: integer): number        -- Max power for a given type
---@field power_current               fun(self: game_object, power_type: integer): number        -- Current power for a given type
---@field power_pct                   fun(self: game_object, power_type: integer): number        -- Power percentage 0..100
---@field power_deficit               fun(self: game_object, power_type: integer): number        -- Max - current power
---@field power_deficit_pct           fun(self: game_object, power_type: integer): number        -- Deficit / max * 100

---@class game_object
---@field mana_max                    fun(self: game_object): number
---@field mana_current                fun(self: game_object): number
---@field mana_pct                    fun(self: game_object): number
---@field mana_deficit                fun(self: game_object): number

---@class game_object
---@field rage_max                    fun(self: game_object): number
---@field rage_current                fun(self: game_object): number
---@field rage_pct                    fun(self: game_object): number
---@field rage_deficit                fun(self: game_object): number

---@class game_object
---@field focus_max                   fun(self: game_object): number
---@field focus_current               fun(self: game_object): number
---@field focus_pct                   fun(self: game_object): number
---@field focus_deficit               fun(self: game_object): number
---@field focus_regen                 fun(self: game_object): number
---@field focus_regen_pct             fun(self: game_object): number
---@field focus_time_to_max           fun(self: game_object): number
---@field focus_time_to_x             fun(self: game_object, amount: number): number
---@field focus_time_to_x_pct         fun(self: game_object, pct: number): number

---@class game_object
---@field energy_max                  fun(self: game_object, max_offset?: number): number
---@field energy_current              fun(self: game_object): number
---@field energy_pct                  fun(self: game_object, max_offset?: number): number
---@field energy_deficit              fun(self: game_object, max_offset?: number): number
---@field energy_deficit_pct          fun(self: game_object, max_offset?: number): number
---@field energy_regen                fun(self: game_object): number
---@field energy_regen_pct            fun(self: game_object, max_offset?: number): number
---@field energy_time_to_max          fun(self: game_object, max_offset?: number): number
---@field energy_time_to_x            fun(self: game_object, amount: number, offset?: number): number
---@field energy_time_to_x_pct        fun(self: game_object, pct: number): number
---@field energy_cast_regen           fun(self: game_object, offset?: number): number
---@field energy_predicted            fun(self: game_object, offset?: number, max_offset?: number): number
---@field energy_deficit_predicted    fun(self: game_object, offset?: number, max_offset?: number): number
---@field energy_time_to_max_predicted fun(self: game_object, offset?: number, max_offset?: number): number

---@class game_object
---@field runic_power_max             fun(self: game_object): number
---@field runic_power_current         fun(self: game_object): number
---@field runic_power_pct             fun(self: game_object): number
---@field runic_power_deficit         fun(self: game_object): number

---@class game_object
---@field soul_shards_max             fun(self: game_object): number
---@field soul_shards_current         fun(self: game_object): number
---@field soul_shards_deficit         fun(self: game_object): number

---@class game_object
---@field astral_power_max            fun(self: game_object): number
---@field astral_power_current        fun(self: game_object): number
---@field astral_power_pct            fun(self: game_object): number
---@field astral_power_deficit        fun(self: game_object): number
---@field astral_power_deficit_pct    fun(self: game_object): number

---@class game_object
---@field chi_max                     fun(self: game_object): number
---@field chi_current                 fun(self: game_object): number
---@field chi_pct                     fun(self: game_object): number
---@field chi_deficit                 fun(self: game_object): number
---@field chi_deficit_pct             fun(self: game_object): number

---@class game_object
---@field combo_points_max            fun(self: game_object): number
---@field combo_points_current        fun(self: game_object): number
---@field combo_points_deficit        fun(self: game_object): number
---@field charged_combo_points        fun(self: game_object): number

---@class game_object
---@field haste_pct                   fun(self: game_object): number
---@field spell_haste_multiplier      fun(self: game_object): number
---@field gcd                         fun(self: game_object): number
---@field gcd_remains                 fun(self: game_object): number
---@field is_standing_still           fun(self: game_object, min_still?: number): boolean
---@field can_cast_while_moving       fun(self: game_object): boolean

---@class game_object
---@field rune_count                  fun(self: game_object): integer
---@field rune_time_to_x              fun(self: game_object, value: integer): number
---@field rune_type_count             fun(self: game_object, index: integer): integer

---@class game_object
---@field max_health                  fun(self: game_object): number
---@field stagger_amount              fun(self: game_object): number
---@field stagger_pct                 fun(self: game_object): number
---@field is_stagger_medium_or_more   fun(self: game_object): boolean
---@field is_stagger_heavy            fun(self: game_object): boolean

---@class game_object
---@field time_in_combat              fun(self: game_object): number
---@field get_totem_info              fun(self: game_object, i: integer): (boolean, string, number, number)

---@class game_object
---@field get_enemies_in_range        fun(self: game_object, meters: number, players_only?: boolean): game_objects_table -- includes combat filter for non-player controlled units
---@field get_enemies_in_melee_range  fun(self: game_object, meters: number, players_only?: boolean): game_objects_table -- includes combat filter for non-player controlled units
---@field get_friends_in_range        fun(self: game_object, meters: number, players_only?: boolean): game_objects_table
---@field get_party_members_in_range  fun(self: game_object, meters: number, players_only?: boolean): game_objects_table
---@field get_all_minions             fun(self: game_object, meters?: number): game_objects_table

---@class game_object
---@field get_enemies_in_range_if fun(self: game_object, meters: number, players_only?: boolean, filter?: unit_predicate|unit_predicate_list): game_objects_table -- includes units in combat, blacklisted and dead, you must perform all the filters yourself
---@field get_enemies_in_melee_range_if fun(self: game_object, meters: number, players_only?: boolean, filter?: unit_predicate|unit_predicate_list): game_objects_table -- includes units in combat, blacklisted and dead, you must perform all the filters yourself
---@field get_friends_in_range_if fun(self: game_object, meters: number, players_only?: boolean, filter?: unit_predicate|unit_predicate_list): game_objects_table

---@class game_object
---@field stealth_remains             fun(self: game_object, check_combat?: boolean, check_special?: boolean): number
---@field stealth_up                  fun(self: game_object, check_combat?: boolean, check_special?: boolean): boolean
---@field stealth_down                fun(self: game_object, check_combat?: boolean, check_special?: boolean): boolean
---@field is_behind_unit fun(self: game_object, unit: game_object): boolean  -- true if self is in the rear arc of `unit`
---@field is_behind      fun(self: game_object, unit: game_object): boolean  -- alias of is_behind_unit

---@class game_object
---@field predict_position fun(self: game_object, time?: number): vec3|nil  -- Predicted position after `time` seconds (default 1.0)
---@field distance_to fun(self: game_object, other: game_object): number     -- Distance to another unit
---@field distance_from_position fun(self: game_object, pos: vec3): number   -- Distance to a world position
---@field predict_distance fun(self: game_object, time?: number, other?: game_object): number  -- Predicted distance after `time` seconds, this unit moves, other stays
---@field los_to fun(self: game_object, other: game_object): boolean         -- True if line of sight exists between two units
---@field los_to_position fun(self: game_object, pos: vec3): boolean         -- True if line of sight exists from this unit to a position
---@field is_behind_future fun(self: game_object, unit: game_object, time?: number): boolean  -- True if behind unit's predicted facing after optional `time` offset
---@field is_moving_towards_me fun(self: game_object, unit: game_object, angle_limit?: number): (boolean, number)  -- Returns (is_towards, angle)

---@class game_object
-- True if incoming physical damage is relevant (heuristic: >= 3.3% of current health).
---@field is_physical_damage_taken_relevant fun(self: game_object): boolean

---@class game_object
-- True if incoming magical damage is relevant (heuristic: >= 3.3% of current health).
---@field is_magical_damage_taken_relevant fun(self: game_object): boolean

---@class game_object
-- True if any incoming damage (physical + magical) is relevant (heuristic: >= 3.3% of current health).
---@field is_any_damage_taken_relevant fun(self: game_object): boolean

-------------------------------------------------------------------------------
-- izi_spell (snake_case only; no CAPS aliases)
--------------------------------------------------------------------------------

---@class izi_spell
---@field ids                 integer[]                     -- Candidate spell IDs
---@field max_enemies         integer                       -- Utility knob for AoE heuristics
---@field last_cast_time      number                        -- Last time (sec) this spell was queued to cast
---@field minimum_range       number                        -- Spellbook min range (0 if none)
---@field maximum_range       number                        -- Spellbook max range (0 if none)
---@field _gcd_value          number|nil                    -- Cached per-spell GCD (nil → fallback to global)
---@field _tracked_debuff_spec (number|number[])|nil  -- override for target debuff spec
---@field _tracked_buff_spec   (number|number[])|nil  -- override for self/ally buff spec
---@field id                  fun(self: izi_spell): integer
---@field name                fun(self: izi_spell): string
---@field is_learned          fun(self: izi_spell): boolean
---@field is_usable           fun(self: izi_spell): boolean
---@field is_available        fun(self: izi_spell): boolean
---@field cast_time           fun(self: izi_spell): number
---@field cast_time_ms        fun(self: izi_spell): number
---@field charges             fun(self: izi_spell): integer
---@field max_charges         fun(self: izi_spell): integer
---@field charges_info        fun(self: izi_spell): (integer, integer, integer, integer, number) -- (cur, max, startMS, durationMS, modRate)
---@field charges_fractional  fun(self: izi_spell, recharge_ms?: number): number
---@field recharge            fun(self: izi_spell): number
---@field cooldown_remains    fun(self: izi_spell): number
---@field cooldown            fun(self: izi_spell): number
---@field cooldown_up         fun(self: izi_spell): boolean
---@field cooldown_down       fun(self: izi_spell): boolean
---@field get_gcd             fun(self: izi_spell): number
---@field skips_gcd           fun(self: izi_spell): boolean
---@field is_usable_while_moving fun(self: izi_spell): boolean
---@field requires_back       fun(self: izi_spell): boolean
---@field since_last_cast     fun(self: izi_spell): number
---@field in_gcd_window       fun(self: izi_spell, threshold?: number): boolean
---@field in_recharge         fun(self: izi_spell): boolean
---@field has_charges_at      fun(self: izi_spell, t?: number): boolean
---@field track_debuff        fun(self: izi_spell, spec: (number|number[])|nil): izi_spell
---@field track_buff          fun(self: izi_spell, spec: (number|number[])|nil): izi_spell
---@field get_tracked_debuff_spec fun(self: izi_spell): (number|number[])
---@field get_tracked_buff_spec   fun(self: izi_spell): (number|number[])

---@class izi_spell
---@field is_castable fun(self: izi_spell, opts?: cast_opts): boolean

---@class izi_spell
---@field is_castable_to_unit fun(
---   self: izi_spell,
---   target?: game_object,
---   opts?: unit_cast_opts ): boolean

---@class izi_spell
---@field is_castable_to_position fun(
---   self: izi_spell,
---   target?: game_object,         -- context (defaults to target/self)
---   cast_pos?: vec3,              -- if nil -> target:get_position()
---   opts?: pos_cast_opts ): boolean

---@class izi_cast_meta
---@field cast_position? vec3                    -- set if a skillshot was queued
---@field hit_time? number                       -- cast time plus projectile travel, if available
---@field predicted? boolean                     -- true if position came from prediction
---@field hits? integer                          -- predicted amount of hits, if available
---@field prediction_meta? table                 -- raw prediction block from _compute_cast_position
---@field target? game_object                    -- target for targeted casts
---@field unit? game_object                      -- candidate unit for *_target_if helpers
---@field rank_index? integer                    -- index chosen in ranked lists
---@field attempted? integer                     -- how many candidates were attempted
---@field reason? string                         -- failure reason code on false
---@field err? string                            -- optional lower level error string

---@class izi_spell
---@field cast fun(
---   self: izi_spell,
---   target?: game_object,
---   message?: string,
---   opts?: pos_cast_opts): (boolean, izi_cast_meta)

---@class izi_spell
---@field cast_safe fun(
---   self: izi_spell,
---   target?: game_object,
---   message?: string,
---   opts?: unit_cast_opts|pos_cast_opts): (boolean, izi_cast_meta)

---@class izi_spell
---@field cast_target_if fun(
---   self: izi_spell,
---   units: game_objects_table,
---   mode: "max"|"min",
---   filter: fun(u: game_object): (number|nil),
---   adv_condition?: (boolean|fun(u: game_object): boolean|nil),
---   another_condition?: boolean,
---   max_attempts?: integer,
---   message?: string): (boolean, izi_cast_meta)

---@class izi_spell
---@field cast_target_if_safe fun(
---   self: izi_spell,
---   units: game_objects_table,
---   mode: "max"|"min",
---   filter: fun(u: game_object): (number|nil),
---   adv_condition?: (boolean|fun(u: game_object): boolean|nil),
---   another_condition?: boolean,
---   max_attempts?: integer,
---   message?: string,
---   opts?: unit_cast_opts): (boolean, izi_cast_meta)

---@class izi_api
---@field cast fun(
---   spell: izi_spell,
---   target?: game_object,
---   message?: string,
---   opts?: pos_cast_opts): (boolean, izi_cast_meta)

---@class izi_api
---@field cast_safe fun(
---   spell: izi_spell,
---   target?: game_object,
---   message?: string,
---   opts?: unit_cast_opts|pos_cast_opts): (boolean, izi_cast_meta)

---@class izi_api
---@field cast_target_if fun(
---   spell: izi_spell,
---   units: game_objects_table,
---   mode: "max"|"min",
---   filter: fun(u: game_object): (number|nil),
---   adv_condition?: (boolean|fun(u: game_object): boolean|nil),
---   another_condition?: boolean,
---   max_attempts?: integer,
---   message?: string): (boolean, izi_cast_meta)

---@class izi_api
---@field cast_target_if_safe fun(
---   spell: izi_spell,
---   units: game_objects_table,
---   mode: "max"|"min",
---   filter: fun(u: game_object): (number|nil),
---   adv_condition?: (boolean|fun(u: game_object): boolean|nil),
---   another_condition?: boolean,
---   max_attempts?: integer,
---   message?: string,
---   opts?: unit_cast_opts): (boolean, izi_cast_meta)

---@class izi_module
---@field cast_charge_spell fun(
---   spell: izi_spell,                       -- the empower spell wrapper
---   stage: 1|2|3|4,                         -- target empower stage to release at
---   target?: game_object,                   -- optional target or nil to use player target or self
---   message?: string,                       -- optional queue message
---   opts?: unit_cast_opts|pos_cast_opts ): boolean      -- forwarded to :cast_safe for the initial press

---@class defensive_filters
---@field block_time? number                                        -- seconds to block further defensives after success (default 1)
---@field health_percentage_threshold_raw? number                   -- cast if current HP % <= this (default 50)
---@field health_percentage_threshold_incoming? number              -- cast if forecasted HP % <= this (default 40)
---@field physical_damage_percentage_threshold? number              -- if >0, cast if incoming physical % >= this and relevant (default 0, ignored)
---@field magical_damage_percentage_threshold? number               -- similar for magical (default 0, ignored)

---@class izi_spell
-- Cast this spell as a defensive on self with extra filters to decide if the cast should proceed.
-- Prevents casting more than one defensive within the block time.
-- See izi_module.cast_defensive for details on filters.
---@field cast_defensive fun(
---   self: izi_spell,
---   target: game_object,
---   filters?: defensive_filters,                            -- optional filters table
---   message?: string,                                       -- optional queue message
---   opts?: unit_cast_opts ): boolean                        -- forwarded to :cast_safe

---@class izi_api
-- Cast a defensive spell on self with extra filters to decide if the cast should proceed.
-- Prevents casting more than one defensive within the block time.
---@field cast_defensive fun(
---   spell: izi_spell,                                       -- the defensive spell wrapper
---   target: game_object,
---   filters?: defensive_filters,                            -- optional filters table
---   message?: string,                                       -- optional queue message
---   opts?: unit_cast_opts ): boolean                        -- forwarded to spell:cast_safe

--------------------------------------------------------------------------------
-- izi_api (module surface)
--------------------------------------------------------------------------------

---@class izi_api
---@field print fun(...: any): nil
---@field printf fun(fmt: string, ...: any): nil
---@field log fun(filename: string, ...: any): nil
---@field logf fun(filename: string, fmt: string, ...: any): nil

---@class izi_api
---@field apply fun(): nil
---@field on_buff_gain    fun(cb: fun(ev: { unit: game_object, buff_id: integer })) : (fun())      -- unsubscribe() return
---@field on_buff_lose    fun(cb: fun(ev: { unit: game_object, buff_id: integer })) : (fun())
---@field on_debuff_gain  fun(cb: fun(ev: { unit: game_object, debuff_id: integer })) : (fun())
---@field on_debuff_lose  fun(cb: fun(ev: { unit: game_object, debuff_id: integer })) : (fun())
---@field on_combat_start fun(cb: fun(ev: { unit: game_object })) : (fun())
---@field on_combat_finish fun(cb: fun(ev: { unit: game_object })) : (fun())
---@field on_spell_begin  fun(cb: fun(ev: { spell_id: integer, caster: game_object, target: game_object|nil })) : (fun())
---@field on_spell_success fun(cb: fun(ev: { spell_id: integer, caster: game_object, target: game_object|nil })) : (fun())
---@field on_spell_cancel fun(cb: fun(ev: { spell_id: integer, caster: game_object, target: game_object|nil })) : (fun())
---@field on_key_release  fun(key: integer|string, cb: fun(key: integer|string)) : (fun())

---@class izi_api
---@field get_ts_target  fun(): game_object|nil                    -- First TS target or nil
---@field get_ts_targets fun(limit?: integer): game_objects_table        -- Up to `limit` TS targets (game_objects)

---@class izi_api
---@field spell fun(...: any): izi_spell
---@overload fun(id: integer): izi_spell
---@overload fun(id1: integer, id2: integer, ...: integer): izi_spell
---@overload fun(ids: integer[]): izi_spell

---@class izi_api
---@field me                        fun(): game_object|nil                                          -- Local player or nil
---@field get_player                fun(): game_object|nil                                          -- Alias of me()
---@field is_arena                  fun(): boolean                                                  -- Return if local client is inside an arena map type
---@field in_arena                  fun(): boolean                                                  -- Return if local client is inside an arena map type
---@field is_in_arena               fun(): boolean                                                  -- Return if local client is inside an arena map type
---@field get_time_to_die_global    fun(): number                                                   -- Return global time to die in seconds
---@field target                    fun(): game_object|nil                                          -- Current target or nil
---@field ts                        fun(i?: integer): game_object|nil                               -- Target selector i (default 1)
---@field enemies                   fun(radius?: number, players_only?: boolean): game_objects_table     -- Enemies around player
---@field friends                   fun(radius?: number, players_only?: boolean): game_objects_table     -- Allies around player
---@field party                     fun(radius?: number): game_objects_table                             -- Party members around player
---@field after                     fun(seconds: number, fn: fun()): (fun())                        -- Schedule fn after N seconds; returns cancel()

---@class izi_api
---@field enemies_if fun(radius?: number, filter?: unit_predicate|unit_predicate_list): game_objects_table
---@field friends_if fun(radius?: number, filter?: unit_predicate|unit_predicate_list): game_objects_table

---@class izi_api
---@field pick_enemy  fun(radius?: number, players_only?: boolean, filter: fun(u: game_object): number|nil, mode: sort_mode): game_object|nil
---@field spread_dot  fun(spell: izi_spell, enemies?: game_objects_table, refresh_below_ms?: number, max_attempts?: integer, message?: string): boolean

---@class izi_api
---@field now               fun(): number                     -- core timer seconds (same source as core.now())
---@field now_seconds       fun(): number                     -- alias of now()
---@field now_ms            fun(): number                     -- core timer milliseconds
---@field now_game_time_ms  fun(): number                     -- game_time() in ms (if available)

---@class izi_item
---@field id               fun(self: izi_item): integer
---@field name             fun(self: izi_item): string
---@field object           fun(self: izi_item): game_object|nil
---@field equipped_slot    fun(self: izi_item): integer|nil
---@field equipped         fun(self: izi_item): boolean
---@field count            fun(self: izi_item): integer
---@field in_inventory     fun(self: izi_item): boolean
---@field is_usable        fun(self: izi_item): boolean
---@field cooldown_remains fun(self: izi_item): number          -- seconds
---@field cooldown_up      fun(self: izi_item): boolean
---@field has_range        fun(self: izi_item): boolean
---@field is_in_range      fun(self: izi_item, target?: game_object): boolean
---@field use_self         fun(self: izi_item, message?: string, fast?: boolean): boolean
---@field use_on           fun(self: izi_item, target?: game_object, message?: string, fast?: boolean): boolean
---@field use_at_position  fun(self: izi_item, position: vec3, message?: string, fast?: boolean): boolean
---@field use_self_safe    fun(self: izi_item, message?: string, opts?: item_use_opts): boolean
---@field use_on_safe      fun(self: izi_item, target?: game_object, message?: string, opts?: item_use_opts): boolean
---@field use_at_position_safe fun(self: izi_item, target?: game_object, position: vec3, message?: string, opts?: item_use_opts): boolean

---@class item_use_opts
---@field skip_usable? boolean
---@field skip_cooldown? boolean
---@field skip_range? boolean
---@field skip_moving? boolean
---@field skip_mount? boolean
---@field skip_casting? boolean
---@field skip_channeling? boolean
---@field skip_gcd? boolean
---@field check_los? boolean

---@class izi_api
---@field item fun(id: integer): izi_item
---@field best_health_potion_id fun(): integer|nil
---@field best_mana_potion_id fun(): integer|nil
---@field use_best_health_potion_safe fun(opts?: item_use_opts): boolean
---@field use_best_mana_potion_safe fun(opts?: item_use_opts): boolean

--------------------------------------------------------------------------------
-- PvP helpers
-- Notes:
-- • cc_flags and dmg_type flags are bitmasks, combine with bitwise OR.
-- • source_mask is a bitmask for source filters (for example player, pet, totem), engine-defined.
-- • Returns for is_cc-like queries: (active:boolean, applied_mask:integer, remaining_ms:integer [, immune:boolean] [, weak:boolean])
-- • DR, diminishing returns. get_dr returns the multiplicative DR, 1.0, 0.5, 0.25, 0.0. get_dr_time returns seconds to reset.
-- • Slows: movement multiplier (mult) in [0..1]. Example mult 0.6 means 40% slow. is_slowed(threshold) compares against 1 - mult.
-- • has_burst is a friendly alias of has_burst_active inside pvp_helper.
--------------------------------------------------------------------------------

---@alias CCFlagMask integer           -- Bitmask of CC flags
---@alias DMGTypeMask integer          -- Bitmask of damage-type flags
---@alias SourceMask integer           -- Bitmask of source filters
---@alias Milliseconds integer

---@class PurgeEntry
---@field buff_id integer
---@field buff_name string
---@field priority integer
---@field min_remaining number          -- seconds

---@class PurgeScanResult
---@field is_purgeable boolean
---@field table PurgeEntry[]            -- list of purge candidate buffs
---@field current_remaining_ms integer
---@field expire_time number            -- engine time in seconds when shortest candidate expires

--------------------------------------------------------------------------------
-- Scenario and basic typing helpers
--------------------------------------------------------------------------------

---@class game_object
--- True if in a PvP context, arena, battleground, duel, war mode versus player.
--- Aliases: isPvP, in_pvp, inPvP
---@field is_pvp fun(self: game_object): boolean
--- Treat special targets flagged like players as playerlike.
--- Aliases: isPlayerLike, is_player_or_dummy, isPlayerOrDummy
---@field is_playerlike fun(self: game_object): boolean

--------------------------------------------------------------------------------
-- Crowd control state
--------------------------------------------------------------------------------

---@class game_object
--- Generic CC query with optional filters.
--- Defaults: min_remaining_ms = 1000, cc_flags = CC.ANY, source_mask = ANY
--- Returns:
---   active: boolean, true if any matching CC is active
---   applied_mask: CCFlagMask, bitmask of matched CC categories
---   remaining_ms: Milliseconds, best remaining among matches
---   immune: boolean, true if currently immune to the queried CC set
---   weak: boolean, true if only weak CC is present, breaks on damage
--- Aliases: isCC, crowd_controlled, isCrowdControlled
---@field is_cc fun(self: game_object, min_remaining_ms?: Milliseconds, cc_flags?: CCFlagMask, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds, boolean, boolean)
--- Weak CC, breaks on damage, convenience wrapper.
--- Defaults: min_remaining_ms = 500
--- Returns: active, applied_mask, remaining_ms
--- Aliases: isWeakCC, weak_cc
---@field is_cc_weak fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
--- Root check.
--- Defaults: min_remaining_ms = 500
--- Returns: active, CC.ROOT, remaining_ms
--- Aliases: rooted, isRooted
---@field is_rooted fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
--- Stun check.
--- Defaults: min_remaining_ms = 500
--- Returns: active, CC.STUN, remaining_ms
--- Aliases: stunned, isStunned
---@field is_stunned fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
--- Fear check.
--- Defaults: min_remaining_ms = 500
--- Returns: active, CC.FEAR, remaining_ms
--- Aliases: feared, isFeared
---@field is_feared fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
--- Sap check.
--- Defaults: min_remaining_ms = 500
--- Returns: active, CC.SAP, remaining_ms
--- Aliases: sapped, isSapped
---@field is_sapped fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
--- Silence check.
--- Defaults: min_remaining_ms = 500
--- Returns: active, CC.SILENCE, remaining_ms
--- Aliases: silenced, isSilenced
---@field is_silenced fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
--- Cyclone check.
--- Defaults: min_remaining_ms = 500
--- Returns: active, CC.CYCLONE, remaining_ms
--- Aliases: cycloned, isCycloned
---@field is_cycloned fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
--- Disarm check.
--- Defaults: min_remaining_ms = 500
--- Returns: active, CC.DISARM, remaining_ms
--- Aliases: disarmed, isDisarmed
---@field is_disarmed fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
--- Disorient check.
--- Defaults: min_remaining_ms = 500
--- Returns: active, CC.DISORIENT, remaining_ms
--- Aliases: isDisorient, isDisoriented
---@field is_disoriented fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
--- Incapacitate check.
--- Defaults: min_remaining_ms = 500
--- Returns: active, CC.INCAPACITATE, remaining_ms
--- Aliases: is_incapacitated, isIncapacitated
---@field is_incap fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

--------------------------------------------------------------------------------
-- Diminishing returns, DR
--------------------------------------------------------------------------------

---@class game_object
--- DR multiplier for a CC category.
--- category can be a CC flag integer or a case-insensitive name:
---   "stun", "root", "fear", "sap", "disorient", "incapacitate",
---   "silence", "disarm", "knockback", "cyclone", "horror", "mind_control"
--- Defaults: hit_at_sec = 0, pass 0 to evaluate now
--- Returns: 1.0, 0.5, 0.25, 0.0, values greater than 1.01 indicate not tracked yet
--- Aliases: dr, dr_for, getDR, DR
---@field get_dr fun(self: game_object, category: (integer|string), hit_at_sec?: number): number
--- Seconds left until DR fully resets for the category.
--- category accepts the same values as get_dr.
--- Aliases: dr_time, drTimeLeft, getDRTime
---@field get_dr_time fun(self: game_object, category: (integer|string)): number

--------------------------------------------------------------------------------
-- CC immunity and reduction
--------------------------------------------------------------------------------

---@class game_object
--- Immunity to CC.
--- Defaults: cc_flags = CC.ANY, min_remaining_ms = 100, ignore_dot = false, dot_blacklist = nil, source_mask = ANY
--- Returns:
---   immune: boolean, true if immune to the queried set
---   applied_mask: CCFlagMask, mask of immunity sources relevant to the queried set
---   remaining_ms: Milliseconds, best remaining among sources
--- Aliases: immune_cc, isCCImmune
---@field is_cc_immune fun(self: game_object, cc_flags?: CCFlagMask, min_remaining_ms?: Milliseconds, ignore_dot?: boolean, dot_blacklist?: table<integer, true>, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
--- CC reduction percentage.
--- Defaults: cc_flags = CC.ANY, min_remaining_ms = 100
--- Returns:
---   percent: number, 0..100
---   applied_mask: CCFlagMask
---   remaining_ms: Milliseconds
--- Aliases: cc_reduction, getCCReduce, getCCReduction
---@field get_cc_reduction fun(self: game_object, cc_flags?: CCFlagMask, min_remaining_ms?: Milliseconds, ignore_dot?: boolean, dot_blacklist?: table<integer, true>, source_mask?: SourceMask): (number, CCFlagMask, Milliseconds)

--------------------------------------------------------------------------------
-- Slows
--------------------------------------------------------------------------------

---@class game_object
--- Is slowed past a threshold.
--- Defaults: threshold = 0.30, min_remaining_ms = 2000
--- Returns:
---   is_slowed: boolean
---   mult: number, movement multiplier 0..1, example 0.6 means 40 percent slow
---   remaining_ms: Milliseconds
--- Aliases: isSlowed, slowed
---@field is_slowed fun(self: game_object, threshold?: number, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, number, Milliseconds)
--- Get current slow multiplier and remaining time.
--- Defaults: min_remaining_ms = 2000
--- Returns: mult 0..1, remaining_ms
--- Aliases: slow_mult, getSlow
---@field get_slow fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (number, Milliseconds)
--- Slow immunity.
--- Defaults: min_remaining_ms = 100
--- Returns: immune: boolean, remaining_ms
--- Aliases: slow_immune, isSlowImmune
---@field is_slow_immune fun(self: game_object, source_mask?: SourceMask, min_remaining_ms?: Milliseconds): (boolean, Milliseconds)

--------------------------------------------------------------------------------
-- Damage reduction and immunity
--------------------------------------------------------------------------------

---@class game_object
--- Damage reduction percentage for a set of damage types.
--- Defaults: type_flags = DMG.ANY, min_remaining_ms = 100
--- Returns: percent 0..100, type_mask: DMGTypeMask, remaining_ms
--- Aliases: getDRPct, dmg_reduction, dmgRed, getDamageReduction
---@field get_damage_reduction fun(self: game_object, type_flags?: DMGTypeMask, min_remaining_ms?: Milliseconds): (number, DMGTypeMask, Milliseconds)
--- Damage immunity for a set of damage types.
--- Defaults: type_flags = DMG.ANY, min_remaining_ms = 25
--- Returns: immune: boolean, type_mask: DMGTypeMask, remaining_ms
--- Aliases: isImmune, isDamageImmune, immune_dmg
---@field is_damage_immune fun(self: game_object, type_flags?: DMGTypeMask, min_remaining_ms?: Milliseconds): (boolean, DMGTypeMask, Milliseconds)

--------------------------------------------------------------------------------
-- Burst windows and text helpers
--------------------------------------------------------------------------------

---@class game_object
--- True if the unit has an offensive burst window active with at least min_remaining_ms left.
--- Defaults: min_remaining_ms = 1600
--- Aliases: is_bursting, bursting, hasBurst
---@field has_burst fun(self: game_object, min_remaining_ms?: Milliseconds): boolean
--- Human readable CC list for a mask, useful for HUDs.
--- Aliases: CCText, cc_desc
---@field cc_text fun(self: game_object, cc_mask: CCFlagMask): string
--- Human readable damage-type list for a mask, useful for HUDs.
--- Aliases: DMGText, dmg_desc
---@field dmg_text fun(self: game_object, dmg_mask: DMGTypeMask): string

--------------------------------------------------------------------------------
-- Purge and disarm
--------------------------------------------------------------------------------

---@class game_object
--- Scan for purgeable buffs on the target.
--- Defaults: min_remaining_ms = 250
--- Returns: PurgeScanResult table, see type above
--- Aliases, all map to the same function:
---   isPurgable, is_purgeable, isPurgeable, can_be_purged, canBePurged
---@field is_purgable fun(self: game_object, min_remaining_ms?: Milliseconds): PurgeScanResult
--- Whether the target can be disarmed now.
--- include_all: if supported by backend, include off-hand or special cases
--- Returns: boolean
--- Aliases: isDisarmable, can_be_disarmed, canBeDisarmed
---@field is_disarmable fun(self: game_object, include_all?: boolean): boolean

--------------------------------------------------------------------------------
-- Exposed flag tables, bitmask constants provided by runtime
--------------------------------------------------------------------------------

---@class game_object
---@field CC cc_flags_table              -- CC flags, for example CC.STUN, CC.ROOT, CC.ANY
---@field DMG damage_type_flags_table    -- DMG flags, for example DMG.PHYSICAL, DMG.MAGICAL, DMG.ANY

--------------------------------------------------------------------------------
-- Aliases section, optional helpers for IDEs that do not pick up alias names automatically.
-- You can copy these as @field entries to surface every alias with the same types.
--------------------------------------------------------------------------------

---@class game_object
---@field isPvP fun(self: game_object): boolean
---@field in_pvp fun(self: game_object): boolean
---@field inPvP fun(self: game_object): boolean

---@class game_object
---@field isPlayerLike fun(self: game_object): boolean
---@field is_player_or_dummy fun(self: game_object): boolean
---@field isPlayerOrDummy fun(self: game_object): boolean

---@class game_object
---@field isCC fun(self: game_object, min_remaining_ms?: Milliseconds, cc_flags?: CCFlagMask, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds, boolean, boolean)
---@field crowd_controlled fun(self: game_object, min_remaining_ms?: Milliseconds, cc_flags?: CCFlagMask, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds, boolean, boolean)
---@field isCrowdControlled fun(self: game_object, min_remaining_ms?: Milliseconds, cc_flags?: CCFlagMask, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds, boolean, boolean)

---@class game_object
---@field isWeakCC fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
---@field weak_cc fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

---@class game_object
---@field rooted fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
---@field isRooted fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

---@class game_object
---@field stunned fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
---@field isStunned fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

---@class game_object
---@field feared fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
---@field isFeared fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

---@class game_object
---@field sapped fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
---@field isSapped fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

---@class game_object
---@field silenced fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
---@field isSilenced fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

---@class game_object
---@field cycloned fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
---@field isCycloned fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

---@class game_object
---@field disarmed fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
---@field isDisarmed fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

---@class game_object
---@field isDisorient fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
---@field isDisoriented fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

---@class game_object
---@field is_incapacitated fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
---@field isIncapacitated fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

---@class game_object
---@field dr fun(self: game_object, category: (integer|string), hit_at_sec?: number): number
---@field dr_for fun(self: game_object, category: (integer|string), hit_at_sec?: number): number
---@field getDR fun(self: game_object, category: (integer|string), hit_at_sec?: number): number
---@field DR fun(self: game_object, category: (integer|string), hit_at_sec?: number): number

---@class game_object
---@field dr_time fun(self: game_object, category: (integer|string)): number
---@field drTimeLeft fun(self: game_object, category: (integer|string)): number
---@field getDRTime fun(self: game_object, category: (integer|string)): number

---@class game_object
---@field immune_cc fun(self: game_object, cc_flags?: CCFlagMask, min_remaining_ms?: Milliseconds, ignore_dot?: boolean, dot_blacklist?: table<integer, true>, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)
---@field isCCImmune fun(self: game_object, cc_flags?: CCFlagMask, min_remaining_ms?: Milliseconds, ignore_dot?: boolean, dot_blacklist?: table<integer, true>, source_mask?: SourceMask): (boolean, CCFlagMask, Milliseconds)

---@class game_object
---@field cc_reduction fun(self: game_object, cc_flags?: CCFlagMask, min_remaining_ms?: Milliseconds, ignore_dot?: boolean, dot_blacklist?: table<integer, true>, source_mask?: SourceMask): (number, CCFlagMask, Milliseconds)
---@field getCCReduce fun(self: game_object, cc_flags?: CCFlagMask, min_remaining_ms?: Milliseconds, ignore_dot?: boolean, dot_blacklist?: table<integer, true>, source_mask?: SourceMask): (number, CCFlagMask, Milliseconds)
---@field getCCReduction fun(self: game_object, cc_flags?: CCFlagMask, min_remaining_ms?: Milliseconds, ignore_dot?: boolean, dot_blacklist?: table<integer, true>, source_mask?: SourceMask): (number, CCFlagMask, Milliseconds)

---@class game_object
---@field isSlowed fun(self: game_object, threshold?: number, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, number, Milliseconds)
---@field slowed fun(self: game_object, threshold?: number, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (boolean, number, Milliseconds)

---@class game_object
---@field slow_mult fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (number, Milliseconds)
---@field getSlow fun(self: game_object, min_remaining_ms?: Milliseconds, source_mask?: SourceMask): (number, Milliseconds)

---@class game_object
---@field slow_immune fun(self: game_object, source_mask?: SourceMask, min_remaining_ms?: Milliseconds): (boolean, Milliseconds)
---@field isSlowImmune fun(self: game_object, source_mask?: SourceMask, min_remaining_ms?: Milliseconds): (boolean, Milliseconds)

---@class game_object
---@field getDRPct fun(self: game_object, type_flags?: DMGTypeMask, min_remaining_ms?: Milliseconds): (number, DMGTypeMask, Milliseconds)
---@field dmg_reduction fun(self: game_object, type_flags?: DMGTypeMask, min_remaining_ms?: Milliseconds): (number, DMGTypeMask, Milliseconds)
---@field dmgRed fun(self: game_object, type_flags?: DMGTypeMask, min_remaining_ms?: Milliseconds): (number, DMGTypeMask, Milliseconds)
---@field getDamageReduction fun(self: game_object, type_flags?: DMGTypeMask, min_remaining_ms?: Milliseconds): (number, DMGTypeMask, Milliseconds)

---@class game_object
---@field isImmune fun(self: game_object, type_flags?: DMGTypeMask, min_remaining_ms?: Milliseconds): (boolean, DMGTypeMask, Milliseconds)
---@field isDamageImmune fun(self: game_object, type_flags?: DMGTypeMask, min_remaining_ms?: Milliseconds): (boolean, DMGTypeMask, Milliseconds)
---@field immune_dmg fun(self: game_object, type_flags?: DMGTypeMask, min_remaining_ms?: Milliseconds): (boolean, DMGTypeMask, Milliseconds)

---@class game_object
---@field is_bursting fun(self: game_object, min_remaining_ms?: Milliseconds): boolean
---@field bursting fun(self: game_object, min_remaining_ms?: Milliseconds): boolean
---@field hasBurst fun(self: game_object, min_remaining_ms?: Milliseconds): boolean

---@class game_object
---@field CCText fun(self: game_object, cc_mask: CCFlagMask): string
---@field cc_desc fun(self: game_object, cc_mask: CCFlagMask): string

---@class game_object
---@field DMGText fun(self: game_object, dmg_mask: DMGTypeMask): string
---@field dmg_desc fun(self: game_object, dmg_mask: DMGTypeMask): string

---@class game_object
---@field isPurgable fun(self: game_object, min_remaining_ms?: Milliseconds): PurgeScanResult
---@field is_purgeable fun(self: game_object, min_remaining_ms?: Milliseconds): PurgeScanResult
---@field isPurgeable fun(self: game_object, min_remaining_ms?: Milliseconds): PurgeScanResult
---@field can_be_purged fun(self: game_object, min_remaining_ms?: Milliseconds): PurgeScanResult
---@field canBePurged fun(self: game_object, min_remaining_ms?: Milliseconds): PurgeScanResult

---@class game_object
---@field isDisarmable fun(self: game_object, include_all?: boolean): boolean
---@field can_be_disarmed fun(self: game_object, include_all?: boolean): boolean
---@field canBeDisarmed fun(self: game_object, include_all?: boolean): boolean

-- Cheatsheet
-- local me    = core.object_manager.get_local_player()
-- local enemy = me:get_target() -- just a quick example

-- -- quick flags
-- if enemy:is_stunned() or enemy:is_rooted() then ...
-- if enemy:is_cc() then ... end                         -- any CC
-- if enemy:is_cc_weak() then ... end                    -- breaks on damage

-- -- DR: multiplier and time until DR fully resets
-- local mult = enemy:get_dr("stun")                     -- 1, 0.5, 0.25, 0
-- local tsec = enemy:get_dr_time("stun")

-- -- slow & immunity
-- local slowed = enemy:is_slowed()                      -- true/false
-- local imm_slow = enemy:is_slow_immune()

-- -- damage reduction / immunities
-- local pct, type_mask, rem = enemy:get_damage_reduction()       -- defaults to ANY dmg
-- if enemy:is_damage_immune() then ... end

-- -- CC immunity / reduction (by type)
-- local immune_cc = enemy:is_cc_immune()                -- any CC
-- local cc_pct = select(1, enemy:get_cc_reduction())    -- % reduction (0–100)

-- -- burst windows (offensive cooldowns)
-- if enemy:has_burst() then ... end

-- -- constants for more control
-- if enemy:is_cc(750, enemy.CC.STUN) then ... end
-- if enemy:is_damage_immune(enemy.DMG.MAGICAL) then ... end

-- local enemy = me:get_target()
-- if enemy:is_purgable() then
--   local why = enemy:purge_text()
--   -- e.g., "Magic (Haste, Shield)" for UI
-- end

-- if enemy:is_disarmable() then
--   -- disarm now
-- end

-- local output = enemy:is_purgable()
-- if output.is_purgeable then
-- output.table
-- output.current_remaining_ms
-- evaluate / purge now
-- end

---@alias queue_kind '"none"'|'"pve"'|'"pvp"'

---@class queue_pve_meta
---@field proposal boolean

---@class queue_pvp_slot
---@field idx integer
---@field status any
---@field is_call boolean|nil
---@field expires_at_ms integer|nil

---@class queue_pvp_meta
---@field slots queue_pvp_slot[]

---@class queue_popup_info
---@field kind queue_kind
---@field since_sec number
---@field since_ms integer
---@field age_sec number
---@field age_ms integer
---@field expire_sec number|nil
---@field expire_ms integer|nil
---@field pve queue_pve_meta|nil
---@field pvp queue_pvp_meta|nil

---@class izi_api
---@field set_pvp_queue_provider fun(fn: fun(): queue_pvp_slot[]|nil): nil
---@field queue_popup_info fun(): (boolean, queue_popup_info)    -- has_popup, info
---@field queue_has_popup fun(): boolean
---@field queue_accept fun(kind?: queue_kind, idx?: integer): boolean
---@field queue_decline fun(kind?: queue_kind, idx?: integer): boolean

---@type izi_api
local tbl
return tbl
