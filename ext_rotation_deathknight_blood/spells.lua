local izi = require("common/izi_sdk")
local BUFFS = require("common/enums").buff_db

local SPELLS = {
    -- Core Rotation Abilities
    MARROWREND = izi.spell(195182),                -- Bone Shield builder
    HEART_STRIKE = izi.spell(206930),              -- Main filler
    BLOOD_BOIL = izi.spell(50842),                 -- AoE + charges
    DEATH_STRIKE = izi.spell(49998),               -- Healing + RP dump
    DEATH_AND_DECAY = izi.spell(43265),            -- Ground AoE
    DEATHS_CARESS = izi.spell(195292),             -- Ranged Bone Shield builder

    -- Major Cooldowns
    DANCING_RUNE_WEAPON = izi.spell(49028),        -- Primary burst cooldown
    VAMPIRIC_BLOOD = izi.spell(55233),             -- Major defensive cooldown

    -- Pet
    RAISE_DEAD = izi.spell(46585),                 -- Summon ghoul
    
    -- Resurrection
    RAISE_ALLY = izi.spell(61999),                -- In-combat resurrection

    -- Talent Abilities
    BONESTORM = izi.spell(194844),                 -- AoE + damage reduction
    TOMBSTONE = izi.spell(219809),                 -- Converts Bone Shield to shield
    BLOODDRINKER = izi.spell(206931),              -- Channel heal
    CONSUMPTION = izi.spell(274156),               -- AoE leech
    BLOOD_TAP = izi.spell(221699),                 -- Rune generation
    RUNE_TAP = izi.spell(194679),                  -- Short defensive

    -- Hero Tree: Deathbringer
    REAPERS_MARK = izi.spell(439843),              -- Mark target for Deathbringer
    SOUL_REAPER = izi.spell(343294),               -- Execute + buff

    -- Hero Tree: San'layn
    VAMPIRIC_STRIKE = izi.spell(433895),           -- San'layn empowered strike

    -- Defensives
    ICEBOUND_FORTITUDE = izi.spell(48792),         -- 30% DR cooldown
    ANTI_MAGIC_SHELL = izi.spell(48707),           -- Magic absorb + RP gen
    ANTI_MAGIC_ZONE = izi.spell(51052),            -- Group magic DR ground-targeted (15% DR)
    VAMPIRIC_BLOOD_DEFENSIVE = izi.spell(55233),   -- Same as offensive but for defensive logic

    -- Utility
    GOREFRIENDS_GRASP = izi.spell(108199),         -- Mass grip (Mythic+)
    MIND_FREEZE = izi.spell(47528),               -- Standard interrupt (15s CD)
    ASPHYXIATE = izi.spell(221562),                 -- Stun/Interrupt (4s stun, 45s CD)
    DEATH_GRIP = izi.spell(49576),                  -- Pull interrupt (30yd range, 25s CD, 2 charges with Death's Echo)
    BLINDING_SLEET = izi.spell(207167),             -- AoE cone interrupt/damage smoothing (1m CD)
    DARK_COMMAND = izi.spell(56222),                -- Taunt (taunts enemies that have lost threat)

    -- Racials (for SimC compatibility)
    BLOOD_FURY = izi.spell(20572, 33697, 33702),   -- Orc racial
    BERSERKING = izi.spell(26297),                 -- Troll racial
    ANCESTRAL_CALL = izi.spell(274738),            -- Mag'har Orc racial
    FIREBLOOD = izi.spell(265221),                 -- Dark Iron Dwarf racial
    ARCANE_TORRENT = izi.spell(50613),             -- Blood Elf racial

    -- Legion Remix
    TWISTED_CRUSADE = izi.spell(1237711),
    FELSPIKE = izi.spell(1242973),
    REMIX_TIME = izi.spell(4598228),
}

-- Track important debuffs
SPELLS.BLOOD_BOIL:track_debuff(BUFFS.BLOOD_PLAGUE)
SPELLS.DEATHS_CARESS:track_debuff(BUFFS.BLOOD_PLAGUE)
SPELLS.SOUL_REAPER:track_debuff(BUFFS.SOUL_REAPER)

return SPELLS
