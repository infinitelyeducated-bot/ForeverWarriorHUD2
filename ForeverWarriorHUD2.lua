--[[ ForeverWarriorHUD2: the "2" build of ForeverWarriorHUD, written by make2.cjs. Do not edit by
hand; change ForeverWarriorHUD (or the generator) and text2_section.lua, then run
make2.cjs again. Added over the original: the Text tab (/fw2 text), the
Frames tab (/fw2 frames) and the engines behind them. FUNCTIONS.md lists
every function in this file. ]]
--[[
ForeverWarriorHUD2 2.0.0
A warrior HUD for WoW: Forever (Interface 16001, product wowf / Camelot).
Ported from ForeverWarriorHUD2 1.9.2; standalone, shares nothing with it, and can
be enabled next to any other Forever<Class>HUD.

What it shows:
  * Resource bar: rage, rage gained per second.
  * Resource regeneration bar: measured per second over a one second window.
  * Swing timer with the full option set (colour, spark, text modes, ticks,
    ready flash, source, manual speed, reset on target change).
  * Combo points: present but off by default; this class has none.
  * 37 ability icons, each with a cooldown sweep, a numeric countdown and a
    ready flash. The countdown has its own toggle (Config tab, /fw2 cooldown).
  * 40 skins, named profiles, CTRL-drag with grid / snap / sticky edges,
    auto-hide out of combat, a reflowing four-tab options window.

New relative to the rogue reference:
  * Countdown text on every icon (whole seconds under a minute, m:ss under an
    hour), drawn on its own frame above the sweep and driven from the one
    existing update pass.
  * Ready flash: the icon border pulses to the skin's spark colour for 0.25 s
    when a cooldown ends.
  * Spell IDs are re-resolved from the client by spellbook name at login and
    whenever the spellbook changes, so the icon and the cooldown follow the rank
    this character actually knows. The table IDs are only the fallback.
  * Icons default to a 9-wide grid above the HUD instead of one stacked point.

Forever rules kept:
  * Cooldowns come from C_Spell.GetSpellCooldown(id) under pcall. A nil, secret
    or unreadable startTime / duration draws no number and raises no error; a
    duration at or under 1.51 s is the global cooldown and is ignored.
  * Secret values only feed widgets, never comparisons or arithmetic.
  * BackdropTemplate on every backdrop frame. Events registered one at a time
    under pcall. Public APIs only: no protected calls, no combat automation, no
    combat log, no writes outside SavedVariables.

Slash commands:
  /fw2                        open the options panel
  /fw2 config | skins | profiles
  /fw2 skin <name>            apply a skin by name or key
  /fw2 save <name> | load <name>
  /fw2 show | hide            whole HUD on or off
  /fw2 energy|regen|swing|combo on|off   ("energy" is the rage bar)
  /fw2 cooldown on|off        countdown numbers on the icons
  /fw2 sticky | grid
  /fw2 orient h | v
  /fw2 scale 0.5..2.5
  /fw2 lock | unlock
  /fw2 reset
]]

local ADDON_NAME = ...
local FRHW2_VERSION = "2.0.0"

-- Grid overlay + snap helpers (declared early; the frames are built later)
local gridFrame
local ALL_ITEMS = {}   -- filled once every element and icon exists
local db               -- declared here so Snap() below sees the real table
local ME = {}          -- mouse editing, notifications, menu art (see "Mouse editing")

-- How close two items must come, in screen pixels, before their edges stick.
local STICK_DISTANCE = 14

local function Snap(v)
    if not db or not db.gridSnap then return v end
    local g = db.gridSize or 20
    if g < 4 then g = 4 end
    return math.floor(v / g + 0.5) * g
end

local function ShowGrid()
    if not gridFrame then return end
    gridFrame:Show()
    gridFrame:Update()
end
local function HideGrid()
    if gridFrame then gridFrame:Hide() end
end

-----------------------------------------------------------------------
-- Warrior abilities we can track
-----------------------------------------------------------------------
-- id is the rank 1 spell ID and only a fallback: ResolveSpells() asks the client
-- for the ID behind each spellbook name, so a higher rank is followed
-- automatically. Unmarked IDs come from the spell table GlowingBars 2.8.2
-- ships for this client; the ones marked UNVERIFIED are classic rank 1 IDs
-- that were not confirmed here. "on" ships the icon enabled.
local ABILITIES = {
    { key = "charge",             name = "Charge",              id = 100    , on = true },
    { key = "intercept",          name = "Intercept",           id = 20252  , on = true },
    { key = "pummel",             name = "Pummel",              id = 6552   , on = true },
    { key = "overpower",          name = "Overpower",           id = 7384   , on = true },
    { key = "shieldbash",         name = "Shield Bash",         id = 72 },
    { key = "whirlwind",          name = "Whirlwind",           id = 1680   , on = true },
    { key = "bloodrage",          name = "Bloodrage",           id = 2687   , on = true },
    { key = "berserkerrage",      name = "Berserker Rage",      id = 18499  , on = true },
    { key = "revenge",            name = "Revenge",             id = 6572 },
    { key = "thunderclap",        name = "Thunder Clap",        id = 6343 },
    { key = "taunt",              name = "Taunt",               id = 355 },
    { key = "mockingblow",        name = "Mocking Blow",        id = 694 },
    { key = "disarm",             name = "Disarm",              id = 676 },
    { key = "intimidatingshout",  name = "Intimidating Shout",  id = 5246 },   -- UNVERIFIED on this client
    { key = "shieldblock",        name = "Shield Block",        id = 2565 },
    { key = "recklessness",       name = "Recklessness",        id = 1719 },
    { key = "retaliation",        name = "Retaliation",         id = 20230 },
    { key = "shieldwall",         name = "Shield Wall",         id = 871 },
    { key = "mortalstrike",       name = "Mortal Strike",       id = 12294 },
    { key = "bloodthirst",        name = "Bloodthirst",         id = 23881 },
    { key = "shieldslam",         name = "Shield Slam",         id = 23922 },
    { key = "laststand",          name = "Last Stand",          id = 12975 },
    { key = "deathwish",          name = "Death Wish",          id = 12328 },
    { key = "sweepingstrikes",    name = "Sweeping Strikes",    id = 12292 },
    { key = "piercinghowl",       name = "Piercing Howl",       id = 12323 },
    { key = "concussionblow",     name = "Concussion Blow",     id = 12809 },   -- UNVERIFIED on this client
    { key = "heroicstrike",       name = "Heroic Strike",       id = 78 },
    { key = "rend",               name = "Rend",                id = 772 },
    { key = "execute",            name = "Execute",             id = 5308 },
    { key = "hamstring",          name = "Hamstring",           id = 1715 },
    { key = "sunderarmor",        name = "Sunder Armor",        id = 7386 },
    { key = "cleave",             name = "Cleave",              id = 845 },
    { key = "slam",               name = "Slam",                id = 1464 },
    { key = "battleshout",        name = "Battle Shout",        id = 6673 },
    { key = "demoshout",          name = "Demoralizing Shout",  id = 1160 },
    { key = "victoryrush",        name = "Victory Rush",        id = 402927 },
    { key = "spearingstrike",     name = "Spearing Strike",     id = 1310222 },
}
local GLOBAL_COOLDOWN = 1.51

-----------------------------------------------------------------------
-- Saved defaults
-----------------------------------------------------------------------
-- The only decorative texture this addon draws with: tinted per skin.
local WHITE = "Interface\\BUTTONS\\WHITE8X8"
local SKIN_DEFAULT = "rogue_classic"

local DEFAULTS = {
    baseX = 0, baseY = -140,
    scale = 1.0,
    shown = true,
    locked = false,
    autoHide = true,
    autoHideOOC = false, -- hide the whole HUD while out of combat
    orientation = "h",
    gridSnap = true,     -- snap items to the grid overlay while dragging
    gridSize = 20,       -- grid cell size in screen pixels
    sticky = true,       -- items stick to each other's edges when moved close
    skin = SKIN_DEFAULT, -- palette + edge style, one of SKINS below
    custom = {},         -- custom colours: overrides on top of the skin, by palette part
    customOn = false,
    schemes = {},        -- saved custom colour sets, by name (kept by Reset to default)
    art = "high",        -- menu artwork: "high", "low" or "off" (needs the ForeverArt addon)
    artBanner = "a",     -- which header picture: "a" painted, "b" the alternate
    notify = { sweep = true, cooldownDark = true, readyFlash = true, activeGlow = true, usableDim = true, rangeTint = true },
    cooldownText = true, -- numeric countdown on every ability icon
    -- Text engine. One block per HUD text; sizes match the fonts the
    -- original inherited (GameFontHighlightSmall 10, GameFontNormal 12).
    text = {
        font = "default", outline = "", shadow = true,
        useSkinColor = true, r = 1, g = 1, b = 1,
        energy = { size = 10, anchor = "CENTER", x = 0, y = 0, format = "cur_max" },
        regen  = { size = 10, anchor = "CENTER", x = 0, y = 0, format = "rate", decimals = 1 },
        swing  = { size = 10, anchor = "CENTER", x = 0, y = 0, decimals = 2 },
        timer  = { size = 10, anchor = "BOTTOMRIGHT", x = -1, y = 1, format = "auto" },
    },
    elements = {
        energy = { enabled = true, x = 0, y = 0,   w = 220, h = 16, alpha = 1.0, scale = 1.0, rot = 0,
                   showText = true },
        -- Energy regeneration, its own element so it can be moved and sized
        -- apart from the energy bar. It shows the measured energy per second
        -- against regenMax; the reading is our own arithmetic on values that
        -- passed IsReadable, never on a secret one.
        regen  = { enabled = false, x = 0, y = -44, w = 220, h = 8, alpha = 1.0, scale = 1.0, rot = 0,
                   regenMax = 25, showRate = true },
        -- The swing timer keeps its 1.9.0 options in the same table as its
        -- position and size, so profiles and Reset to default carry them
        -- without any extra bookkeeping. The defaults reproduce the 1.8.0 bar.
        swing  = { enabled = true, x = 0, y = -22, w = 220, h = 10, alpha = 1.0, scale = 1.0, rot = 0,
                   useSkinColor = true, r = 0.85, g = 0.85, b = 0.95, bgAlpha = 0.7,
                   spark = true, sparkSize = 20,
                   text = true, textMode = "elapsed",
                   ticks = false, tickCount = 4,
                   flash = false,
                   source = "event",
                   manual = false, manualSpeed = 2.0,
                   resetOnTarget = false },
        combo  = { enabled = false, x = 0, y = 22,  w = 12,  h = 10, alpha = 1.0, scale = 1.0, rot = 0 },
        -- the last few spells cast, newest first
        trail  = { enabled = true, x = 0, y = -72, w = 22, h = 22, alpha = 1.0, scale = 1.0, rot = 0 },
    },
    spells = {},
}
-- Nine icons to a row, centred over the HUD, so switching several on never
-- stacks them on one point.
for i, a in ipairs(ABILITIES) do
    local col, row = (i - 1) % 9, math.floor((i - 1) / 9)
    DEFAULTS.spells[a.key] = { enabled = a.on == true, x = (col - 4) * 30, y = 60 + row * 30,
                               w = 26, h = 26, alpha = 1.0, scale = 1.0, rot = 0 }
end
-- Everything a named profile stores. "profiles" is deliberately NOT in this
-- list: saved setups are kept apart from the live configuration, so resetting
-- to defaults or loading a profile can never delete them.
local CONFIG_KEYS = {
    "baseX", "baseY", "scale", "shown", "locked", "autoHide", "autoHideOOC",
    "orientation", "gridSnap", "gridSize", "sticky", "skin", "cooldownText", "notify", "custom", "customOn", "text", "frames", "map", "elements", "spells",
}
DEFAULTS.profiles = {}
local panel

-- Swing text modes, in the order the mode button cycles through them.
local SWING_TEXT_ORDER = { "elapsed", "remaining", "percent", "none" }
local SWING_TEXT_LABEL = {
    elapsed   = "Text: elapsed / total",
    remaining = "Text: remaining",
    percent   = "Text: percent",
    none      = "Text: none",
}

-----------------------------------------------------------------------
-- Skins: 40 palettes plus an edge style each
-----------------------------------------------------------------------
-- A skin only recolours. bar = energy fill, swing = swing fill, combo = combo
-- points, barBg = energy background, spark = swing spark and ready flash,
-- text = every label, accent = headers / rules / selected tab, border = bar
-- outlines and the window edge, panel = window background, iconEdge = spell
-- icon border. Bar colours are kept dark enough for the light text to read on
-- top of them (the test suite checks the contrast of every skin but the first,
-- which is the 1.8.0 look kept as it was).
--
-- style picks the edge treatment drawn around bars, combo points and icons:
--   flat   no outline                     line   1 px outline
--   bevel  outline, light top, dark base  rune   outline with corner pips
--   ember  outline with a glowing base    frost  outline with an icy top edge
--   gilded outline with accent inlays top and bottom
local SKINS = {
    { key = "rogue_classic", name = "Rogue Classic", style = "flat",
      bar = { 1.00, 0.96, 0.41 }, swing = { 0.85, 0.85, 0.95 }, combo = { 1.00, 0.60, 0.00 },
      accent = { 0.20, 0.80, 1.00 }, text = { 1.00, 1.00, 1.00 }, spark = { 1.00, 1.00, 1.00 },
      barBg = { 0.25, 0.24, 0.1025, 0.70 }, border = { 0.35, 0.35, 0.40, 1.00 },
      panel = { 0.05, 0.05, 0.07, 0.94 }, iconEdge = { 0.20, 0.20, 0.20, 1.00 } },
    { key = "emberforge", name = "Emberforge", style = "ember",
      bar = { 0.86, 0.36, 0.10 }, swing = { 0.66, 0.30, 0.18 }, combo = { 1.00, 0.62, 0.15 },
      accent = { 1.00, 0.55, 0.18 }, text = { 1.00, 0.95, 0.88 }, spark = { 1.00, 0.85, 0.50 },
      barBg = { 0.16, 0.06, 0.03, 0.80 }, border = { 0.50, 0.22, 0.08, 1.00 },
      panel = { 0.09, 0.05, 0.04, 0.95 }, iconEdge = { 0.62, 0.27, 0.10, 1.00 } },
    { key = "frostgrave", name = "Frostgrave", style = "frost",
      bar = { 0.20, 0.50, 0.80 }, swing = { 0.34, 0.52, 0.66 }, combo = { 0.55, 0.85, 1.00 },
      accent = { 0.60, 0.88, 1.00 }, text = { 0.93, 0.97, 1.00 }, spark = { 0.85, 0.95, 1.00 },
      barBg = { 0.04, 0.09, 0.16, 0.80 }, border = { 0.30, 0.50, 0.66, 1.00 },
      panel = { 0.04, 0.07, 0.11, 0.95 }, iconEdge = { 0.40, 0.65, 0.85, 1.00 } },
    { key = "venomdusk", name = "Venomdusk", style = "line",
      bar = { 0.28, 0.56, 0.14 }, swing = { 0.42, 0.30, 0.58 }, combo = { 0.70, 0.95, 0.20 },
      accent = { 0.66, 0.92, 0.26 }, text = { 0.94, 1.00, 0.90 }, spark = { 0.80, 1.00, 0.50 },
      barBg = { 0.05, 0.11, 0.04, 0.80 }, border = { 0.26, 0.44, 0.14, 1.00 },
      panel = { 0.05, 0.07, 0.06, 0.95 }, iconEdge = { 0.36, 0.60, 0.18, 1.00 } },
    { key = "runeblade", name = "Runeblade", style = "rune",
      bar = { 0.22, 0.42, 0.78 }, swing = { 0.40, 0.40, 0.72 }, combo = { 0.45, 0.80, 1.00 },
      accent = { 0.40, 0.78, 1.00 }, text = { 0.92, 0.96, 1.00 }, spark = { 0.70, 0.90, 1.00 },
      barBg = { 0.04, 0.07, 0.15, 0.80 }, border = { 0.24, 0.38, 0.62, 1.00 },
      panel = { 0.04, 0.05, 0.10, 0.95 }, iconEdge = { 0.30, 0.55, 0.90, 1.00 } },
    { key = "cryptlight", name = "Cryptlight", style = "bevel",
      bar = { 0.36, 0.52, 0.40 }, swing = { 0.46, 0.48, 0.38 }, combo = { 0.75, 0.95, 0.70 },
      accent = { 0.70, 0.95, 0.72 }, text = { 0.92, 0.98, 0.90 }, spark = { 0.85, 1.00, 0.85 },
      barBg = { 0.06, 0.09, 0.07, 0.80 }, border = { 0.30, 0.40, 0.32, 1.00 },
      panel = { 0.05, 0.07, 0.06, 0.95 }, iconEdge = { 0.42, 0.58, 0.44, 1.00 } },
    { key = "wyrmfire", name = "Wyrmfire", style = "ember",
      bar = { 0.82, 0.24, 0.12 }, swing = { 0.74, 0.42, 0.10 }, combo = { 1.00, 0.80, 0.20 },
      accent = { 1.00, 0.72, 0.20 }, text = { 1.00, 0.95, 0.85 }, spark = { 1.00, 0.90, 0.45 },
      barBg = { 0.15, 0.04, 0.03, 0.80 }, border = { 0.52, 0.16, 0.08, 1.00 },
      panel = { 0.09, 0.04, 0.04, 0.95 }, iconEdge = { 0.70, 0.22, 0.10, 1.00 } },
    { key = "bloodmoon", name = "Bloodmoon", style = "bevel",
      bar = { 0.66, 0.10, 0.14 }, swing = { 0.52, 0.20, 0.26 }, combo = { 0.95, 0.30, 0.30 },
      accent = { 0.92, 0.26, 0.30 }, text = { 1.00, 0.92, 0.92 }, spark = { 1.00, 0.60, 0.60 },
      barBg = { 0.13, 0.02, 0.03, 0.82 }, border = { 0.42, 0.08, 0.10, 1.00 },
      panel = { 0.08, 0.03, 0.04, 0.95 }, iconEdge = { 0.60, 0.12, 0.14, 1.00 } },
    { key = "ashen_covenant", name = "Ashen Covenant", style = "flat",
      bar = { 0.44, 0.44, 0.46 }, swing = { 0.52, 0.48, 0.44 }, combo = { 0.80, 0.78, 0.74 },
      accent = { 0.82, 0.80, 0.76 }, text = { 0.96, 0.95, 0.93 }, spark = { 1.00, 1.00, 1.00 },
      barBg = { 0.08, 0.08, 0.08, 0.80 }, border = { 0.34, 0.33, 0.32, 1.00 },
      panel = { 0.07, 0.07, 0.07, 0.95 }, iconEdge = { 0.42, 0.41, 0.40, 1.00 } },
    { key = "deepstone", name = "Deepstone", style = "bevel",
      bar = { 0.36, 0.42, 0.50 }, swing = { 0.46, 0.42, 0.36 }, combo = { 0.62, 0.74, 0.86 },
      accent = { 0.58, 0.72, 0.86 }, text = { 0.93, 0.95, 0.98 }, spark = { 0.85, 0.90, 1.00 },
      barBg = { 0.06, 0.07, 0.09, 0.82 }, border = { 0.28, 0.32, 0.38, 1.00 },
      panel = { 0.05, 0.06, 0.08, 0.95 }, iconEdge = { 0.36, 0.42, 0.50, 1.00 } },
    { key = "hollow_lantern", name = "Hollow Lantern", style = "gilded",
      bar = { 0.76, 0.46, 0.10 }, swing = { 0.50, 0.40, 0.56 }, combo = { 1.00, 0.82, 0.35 },
      accent = { 1.00, 0.80, 0.32 }, text = { 1.00, 0.96, 0.86 }, spark = { 1.00, 0.92, 0.60 },
      barBg = { 0.12, 0.07, 0.03, 0.80 }, border = { 0.52, 0.36, 0.10, 1.00 },
      panel = { 0.07, 0.05, 0.07, 0.95 }, iconEdge = { 0.72, 0.50, 0.14, 1.00 } },
    { key = "gilded_reliquary", name = "Gilded Reliquary", style = "gilded",
      bar = { 0.68, 0.50, 0.12 }, swing = { 0.56, 0.24, 0.24 }, combo = { 1.00, 0.86, 0.40 },
      accent = { 1.00, 0.84, 0.38 }, text = { 1.00, 0.97, 0.88 }, spark = { 1.00, 0.95, 0.70 },
      barBg = { 0.11, 0.08, 0.03, 0.82 }, border = { 0.62, 0.48, 0.16, 1.00 },
      panel = { 0.08, 0.06, 0.04, 0.95 }, iconEdge = { 0.80, 0.62, 0.20, 1.00 } },
    { key = "plaguewick", name = "Plaguewick", style = "line",
      bar = { 0.46, 0.52, 0.12 }, swing = { 0.44, 0.36, 0.50 }, combo = { 0.82, 0.92, 0.28 },
      accent = { 0.80, 0.92, 0.30 }, text = { 0.97, 1.00, 0.88 }, spark = { 0.90, 1.00, 0.55 },
      barBg = { 0.08, 0.09, 0.03, 0.80 }, border = { 0.36, 0.42, 0.12, 1.00 },
      panel = { 0.06, 0.07, 0.04, 0.95 }, iconEdge = { 0.50, 0.58, 0.16, 1.00 } },
    { key = "stormcall", name = "Stormcall", style = "rune",
      bar = { 0.26, 0.40, 0.86 }, swing = { 0.44, 0.46, 0.66 }, combo = { 0.70, 0.80, 1.00 },
      accent = { 0.66, 0.78, 1.00 }, text = { 0.94, 0.96, 1.00 }, spark = { 0.90, 0.95, 1.00 },
      barBg = { 0.04, 0.06, 0.16, 0.80 }, border = { 0.26, 0.34, 0.66, 1.00 },
      panel = { 0.04, 0.05, 0.11, 0.95 }, iconEdge = { 0.34, 0.46, 0.90, 1.00 } },
    { key = "iron_vigil", name = "Iron Vigil", style = "bevel",
      bar = { 0.40, 0.46, 0.52 }, swing = { 0.50, 0.44, 0.40 }, combo = { 0.78, 0.84, 0.90 },
      accent = { 0.74, 0.82, 0.90 }, text = { 0.95, 0.97, 0.99 }, spark = { 1.00, 1.00, 1.00 },
      barBg = { 0.07, 0.08, 0.09, 0.82 }, border = { 0.36, 0.40, 0.44, 1.00 },
      panel = { 0.06, 0.07, 0.08, 0.95 }, iconEdge = { 0.46, 0.52, 0.58, 1.00 } },
    { key = "obsidian_oath", name = "Obsidian Oath", style = "line",
      bar = { 0.38, 0.22, 0.56 }, swing = { 0.30, 0.34, 0.44 }, combo = { 0.72, 0.50, 1.00 },
      accent = { 0.70, 0.48, 1.00 }, text = { 0.95, 0.92, 1.00 }, spark = { 0.85, 0.70, 1.00 },
      barBg = { 0.05, 0.03, 0.09, 0.85 }, border = { 0.30, 0.20, 0.46, 1.00 },
      panel = { 0.03, 0.03, 0.05, 0.96 }, iconEdge = { 0.44, 0.28, 0.66, 1.00 } },
    { key = "sunken_choir", name = "Sunken Choir", style = "frost",
      bar = { 0.12, 0.52, 0.56 }, swing = { 0.26, 0.44, 0.60 }, combo = { 0.45, 0.92, 0.88 },
      accent = { 0.42, 0.90, 0.86 }, text = { 0.90, 1.00, 0.99 }, spark = { 0.70, 1.00, 0.95 },
      barBg = { 0.03, 0.10, 0.11, 0.80 }, border = { 0.16, 0.42, 0.46, 1.00 },
      panel = { 0.03, 0.07, 0.08, 0.95 }, iconEdge = { 0.20, 0.58, 0.62, 1.00 } },
    { key = "thornmantle", name = "Thornmantle", style = "line",
      bar = { 0.24, 0.50, 0.24 }, swing = { 0.50, 0.38, 0.22 }, combo = { 0.62, 0.88, 0.40 },
      accent = { 0.60, 0.86, 0.40 }, text = { 0.94, 1.00, 0.90 }, spark = { 0.80, 1.00, 0.60 },
      barBg = { 0.04, 0.10, 0.04, 0.80 }, border = { 0.24, 0.40, 0.20, 1.00 },
      panel = { 0.05, 0.07, 0.04, 0.95 }, iconEdge = { 0.32, 0.56, 0.28, 1.00 } },
    { key = "wolfsbane", name = "Wolfsbane", style = "rune",
      bar = { 0.50, 0.30, 0.72 }, swing = { 0.40, 0.44, 0.56 }, combo = { 0.82, 0.62, 1.00 },
      accent = { 0.80, 0.60, 1.00 }, text = { 0.97, 0.93, 1.00 }, spark = { 0.90, 0.80, 1.00 },
      barBg = { 0.08, 0.05, 0.13, 0.80 }, border = { 0.40, 0.26, 0.58, 1.00 },
      panel = { 0.06, 0.04, 0.09, 0.95 }, iconEdge = { 0.56, 0.36, 0.80, 1.00 } },
    { key = "cinderhall", name = "Cinderhall", style = "ember",
      bar = { 0.70, 0.30, 0.20 }, swing = { 0.56, 0.44, 0.38 }, combo = { 1.00, 0.56, 0.32 },
      accent = { 1.00, 0.52, 0.30 }, text = { 1.00, 0.94, 0.90 }, spark = { 1.00, 0.75, 0.50 },
      barBg = { 0.13, 0.06, 0.04, 0.82 }, border = { 0.46, 0.22, 0.16, 1.00 },
      panel = { 0.08, 0.05, 0.05, 0.95 }, iconEdge = { 0.62, 0.28, 0.20, 1.00 } },
    { key = "moonwell", name = "Moonwell", style = "frost",
      bar = { 0.34, 0.44, 0.84 }, swing = { 0.46, 0.50, 0.70 }, combo = { 0.78, 0.86, 1.00 },
      accent = { 0.76, 0.84, 1.00 }, text = { 0.95, 0.97, 1.00 }, spark = { 0.92, 0.96, 1.00 },
      barBg = { 0.05, 0.07, 0.16, 0.80 }, border = { 0.34, 0.42, 0.72, 1.00 },
      panel = { 0.04, 0.05, 0.11, 0.95 }, iconEdge = { 0.44, 0.56, 0.94, 1.00 } },
    { key = "serpent_coil", name = "Serpent Coil", style = "line",
      bar = { 0.16, 0.54, 0.36 }, swing = { 0.52, 0.46, 0.18 }, combo = { 0.50, 0.95, 0.60 },
      accent = { 0.46, 0.92, 0.58 }, text = { 0.92, 1.00, 0.94 }, spark = { 0.75, 1.00, 0.80 },
      barBg = { 0.03, 0.10, 0.07, 0.80 }, border = { 0.18, 0.44, 0.30, 1.00 },
      panel = { 0.04, 0.07, 0.05, 0.95 }, iconEdge = { 0.22, 0.62, 0.42, 1.00 } },
    { key = "bonewarden", name = "Bonewarden", style = "bevel",
      bar = { 0.56, 0.50, 0.38 }, swing = { 0.46, 0.44, 0.42 }, combo = { 0.92, 0.88, 0.74 },
      accent = { 0.92, 0.87, 0.72 }, text = { 0.99, 0.97, 0.92 }, spark = { 1.00, 0.98, 0.90 },
      barBg = { 0.10, 0.09, 0.07, 0.80 }, border = { 0.48, 0.44, 0.34, 1.00 },
      panel = { 0.07, 0.07, 0.06, 0.95 }, iconEdge = { 0.64, 0.58, 0.44, 1.00 } },
    { key = "nightshade", name = "Nightshade", style = "rune",
      bar = { 0.46, 0.16, 0.52 }, swing = { 0.30, 0.30, 0.56 }, combo = { 0.88, 0.46, 0.94 },
      accent = { 0.86, 0.44, 0.92 }, text = { 0.98, 0.92, 1.00 }, spark = { 1.00, 0.70, 1.00 },
      barBg = { 0.08, 0.03, 0.10, 0.84 }, border = { 0.38, 0.16, 0.44, 1.00 },
      panel = { 0.05, 0.03, 0.07, 0.96 }, iconEdge = { 0.56, 0.22, 0.64, 1.00 } },
    { key = "dawnsteel", name = "Dawnsteel", style = "gilded",
      bar = { 0.50, 0.52, 0.60 }, swing = { 0.68, 0.46, 0.26 }, combo = { 1.00, 0.84, 0.56 },
      accent = { 1.00, 0.82, 0.54 }, text = { 1.00, 0.98, 0.94 }, spark = { 1.00, 0.95, 0.80 },
      barBg = { 0.08, 0.08, 0.10, 0.80 }, border = { 0.52, 0.52, 0.58, 1.00 },
      panel = { 0.07, 0.07, 0.09, 0.95 }, iconEdge = { 0.70, 0.66, 0.56, 1.00 } },
    { key = "grimoire", name = "Grimoire", style = "rune",
      bar = { 0.44, 0.24, 0.30 }, swing = { 0.40, 0.36, 0.56 }, combo = { 0.86, 0.66, 0.96 },
      accent = { 0.84, 0.64, 0.94 }, text = { 0.98, 0.94, 0.98 }, spark = { 0.95, 0.80, 1.00 },
      barBg = { 0.08, 0.04, 0.06, 0.84 }, border = { 0.40, 0.24, 0.34, 1.00 },
      panel = { 0.06, 0.04, 0.06, 0.96 }, iconEdge = { 0.56, 0.34, 0.50, 1.00 } },
    { key = "torchbearer", name = "Torchbearer", style = "ember",
      bar = { 0.80, 0.44, 0.08 }, swing = { 0.58, 0.36, 0.22 }, combo = { 1.00, 0.76, 0.28 },
      accent = { 1.00, 0.74, 0.26 }, text = { 1.00, 0.96, 0.86 }, spark = { 1.00, 0.90, 0.55 },
      barBg = { 0.14, 0.07, 0.02, 0.80 }, border = { 0.56, 0.32, 0.08, 1.00 },
      panel = { 0.08, 0.06, 0.03, 0.95 }, iconEdge = { 0.76, 0.44, 0.10, 1.00 } },
    { key = "verdant_ruin", name = "Verdant Ruin", style = "bevel",
      bar = { 0.30, 0.50, 0.30 }, swing = { 0.44, 0.48, 0.40 }, combo = { 0.70, 0.90, 0.56 },
      accent = { 0.68, 0.88, 0.54 }, text = { 0.95, 1.00, 0.92 }, spark = { 0.85, 1.00, 0.75 },
      barBg = { 0.05, 0.09, 0.05, 0.80 }, border = { 0.28, 0.40, 0.26, 1.00 },
      panel = { 0.05, 0.07, 0.05, 0.95 }, iconEdge = { 0.38, 0.56, 0.36, 1.00 } },
    { key = "saltbound", name = "Saltbound", style = "flat",
      bar = { 0.30, 0.48, 0.54 }, swing = { 0.52, 0.50, 0.44 }, combo = { 0.74, 0.90, 0.92 },
      accent = { 0.72, 0.88, 0.90 }, text = { 0.95, 0.99, 0.99 }, spark = { 0.90, 1.00, 1.00 },
      barBg = { 0.05, 0.08, 0.09, 0.80 }, border = { 0.30, 0.42, 0.46, 1.00 },
      panel = { 0.05, 0.07, 0.08, 0.95 }, iconEdge = { 0.38, 0.54, 0.58, 1.00 } },
    { key = "wraithglass", name = "Wraithglass", style = "frost",
      bar = { 0.30, 0.52, 0.50 }, swing = { 0.42, 0.46, 0.56 }, combo = { 0.66, 0.98, 0.92 },
      accent = { 0.64, 0.96, 0.90 }, text = { 0.93, 1.00, 0.99 }, spark = { 0.80, 1.00, 0.98 },
      barBg = { 0.04, 0.09, 0.09, 0.72 }, border = { 0.30, 0.52, 0.50, 0.90 },
      panel = { 0.04, 0.07, 0.08, 0.92 }, iconEdge = { 0.40, 0.70, 0.66, 1.00 } },
    { key = "emberwood", name = "Emberwood", style = "ember",
      bar = { 0.60, 0.34, 0.16 }, swing = { 0.40, 0.46, 0.24 }, combo = { 0.98, 0.66, 0.34 },
      accent = { 0.96, 0.64, 0.32 }, text = { 1.00, 0.95, 0.88 }, spark = { 1.00, 0.82, 0.55 },
      barBg = { 0.11, 0.06, 0.03, 0.82 }, border = { 0.44, 0.26, 0.14, 1.00 },
      panel = { 0.08, 0.06, 0.04, 0.95 }, iconEdge = { 0.60, 0.36, 0.18, 1.00 } },
    { key = "silver_chalice", name = "Silver Chalice", style = "gilded",
      bar = { 0.48, 0.50, 0.54 }, swing = { 0.56, 0.30, 0.36 }, combo = { 0.92, 0.94, 0.98 },
      accent = { 0.90, 0.92, 0.97 }, text = { 1.00, 1.00, 1.00 }, spark = { 1.00, 1.00, 1.00 },
      barBg = { 0.09, 0.09, 0.10, 0.80 }, border = { 0.60, 0.62, 0.66, 1.00 },
      panel = { 0.07, 0.07, 0.08, 0.95 }, iconEdge = { 0.78, 0.80, 0.84, 1.00 } },
    { key = "rotgarden", name = "Rotgarden", style = "line",
      bar = { 0.40, 0.44, 0.18 }, swing = { 0.48, 0.30, 0.34 }, combo = { 0.80, 0.84, 0.36 },
      accent = { 0.78, 0.82, 0.36 }, text = { 0.98, 0.99, 0.88 }, spark = { 0.95, 1.00, 0.60 },
      barBg = { 0.07, 0.08, 0.03, 0.82 }, border = { 0.34, 0.38, 0.16, 1.00 },
      panel = { 0.06, 0.07, 0.04, 0.95 }, iconEdge = { 0.48, 0.54, 0.22, 1.00 } },
    { key = "starfall", name = "Starfall", style = "rune",
      bar = { 0.30, 0.26, 0.70 }, swing = { 0.50, 0.40, 0.66 }, combo = { 1.00, 0.90, 0.56 },
      accent = { 1.00, 0.88, 0.54 }, text = { 0.97, 0.96, 1.00 }, spark = { 1.00, 0.96, 0.80 },
      barBg = { 0.05, 0.04, 0.13, 0.82 }, border = { 0.30, 0.28, 0.62, 1.00 },
      panel = { 0.04, 0.04, 0.09, 0.96 }, iconEdge = { 0.44, 0.40, 0.90, 1.00 } },
    { key = "trollhunt", name = "Trollhunt", style = "bevel",
      bar = { 0.20, 0.50, 0.44 }, swing = { 0.62, 0.36, 0.24 }, combo = { 0.98, 0.60, 0.36 },
      accent = { 0.96, 0.58, 0.34 }, text = { 0.95, 1.00, 0.97 }, spark = { 1.00, 0.85, 0.65 },
      barBg = { 0.03, 0.09, 0.08, 0.80 }, border = { 0.22, 0.42, 0.38, 1.00 },
      panel = { 0.04, 0.07, 0.06, 0.95 }, iconEdge = { 0.28, 0.60, 0.54, 1.00 } },
    { key = "brimstone", name = "Brimstone", style = "ember",
      bar = { 0.74, 0.46, 0.06 }, swing = { 0.62, 0.22, 0.14 }, combo = { 1.00, 0.84, 0.20 },
      accent = { 1.00, 0.82, 0.18 }, text = { 1.00, 0.97, 0.84 }, spark = { 1.00, 0.95, 0.50 },
      barBg = { 0.13, 0.08, 0.02, 0.82 }, border = { 0.54, 0.36, 0.06, 1.00 },
      panel = { 0.08, 0.06, 0.03, 0.95 }, iconEdge = { 0.74, 0.50, 0.08, 1.00 } },
    { key = "gloam", name = "Gloam", style = "flat",
      bar = { 0.36, 0.30, 0.48 }, swing = { 0.44, 0.38, 0.44 }, combo = { 0.76, 0.68, 0.90 },
      accent = { 0.74, 0.66, 0.88 }, text = { 0.96, 0.94, 0.99 }, spark = { 0.92, 0.88, 1.00 },
      barBg = { 0.06, 0.05, 0.08, 0.82 }, border = { 0.32, 0.28, 0.42, 1.00 },
      panel = { 0.05, 0.05, 0.07, 0.95 }, iconEdge = { 0.44, 0.38, 0.58, 1.00 } },
    { key = "frostfang", name = "Frostfang", style = "frost",
      bar = { 0.30, 0.56, 0.72 }, swing = { 0.44, 0.50, 0.58 }, combo = { 0.80, 0.95, 1.00 },
      accent = { 0.78, 0.94, 1.00 }, text = { 0.95, 0.99, 1.00 }, spark = { 0.92, 1.00, 1.00 },
      barBg = { 0.05, 0.10, 0.14, 0.80 }, border = { 0.34, 0.56, 0.70, 1.00 },
      panel = { 0.04, 0.07, 0.10, 0.95 }, iconEdge = { 0.46, 0.74, 0.92, 1.00 } },
    { key = "beastcaller", name = "Beastcaller", style = "line",
      bar = { 0.56, 0.40, 0.20 }, swing = { 0.34, 0.48, 0.26 }, combo = { 0.96, 0.74, 0.40 },
      accent = { 0.94, 0.72, 0.38 }, text = { 1.00, 0.97, 0.90 }, spark = { 1.00, 0.88, 0.60 },
      barBg = { 0.10, 0.07, 0.04, 0.82 }, border = { 0.44, 0.32, 0.18, 1.00 },
      panel = { 0.07, 0.06, 0.04, 0.95 }, iconEdge = { 0.60, 0.44, 0.22, 1.00 } },
    { key = "vaultlight", name = "Vaultlight", style = "gilded",
      bar = { 0.60, 0.52, 0.22 }, swing = { 0.38, 0.44, 0.60 }, combo = { 1.00, 0.92, 0.56 },
      accent = { 1.00, 0.90, 0.52 }, text = { 1.00, 0.98, 0.90 }, spark = { 1.00, 0.97, 0.75 },
      barBg = { 0.10, 0.09, 0.04, 0.82 }, border = { 0.58, 0.50, 0.22, 1.00 },
      panel = { 0.07, 0.07, 0.05, 0.95 }, iconEdge = { 0.78, 0.68, 0.28, 1.00 } },
}
local SKIN_BY_KEY = {}
for _, s in ipairs(SKINS) do SKIN_BY_KEY[s.key] = s end
FRHW2_SKINS = SKINS   -- read-only view for macros and the test suite

-- Edit mode: only while the config window is open may anything be moved.
local function EditMode()
    return panel ~= nil and panel:IsShown()
end

-- Whether the HUD should be on screen right now. Auto-hide out of combat is
-- the only rule that can hide everything at once; the config window being
-- open always shows it, so an element can still be found and dragged.
local function HudVisible()
    if not db or not db.shown then return false end
    if db.autoHideOOC and not EditMode() then
        if not UnitAffectingCombat("player") then return false end
    end
    return true
end

local function DeepCopy(t)
    local n = {}
    for k, v in pairs(t) do n[k] = (type(v) == "table") and DeepCopy(v) or v end
    return n
end

-- Standard Forever guard: nil is not readable, secret values are not readable,
-- and canaccessvalue confirms this code may look at it.
local function IsReadable(v)
    if v == nil then return false end
    if issecretvalue and issecretvalue(v) then return false end
    if canaccessvalue and not canaccessvalue(v) then return false end
    return true
end

-- Forward declarations
local ApplyElement, ApplySpell, ApplyAll, RefreshConfig, RefreshProfileList
local ApplySkin, PaintSwing, LayoutSwing, ReflowAll
local TXT, UF, MP = {}, {}, {}   -- text engine, unit frames, map: see their sections below.

-----------------------------------------------------------------------
-- Element frames (energy, swing, combo)
-----------------------------------------------------------------------
local function MakeStatusBar(name, r, g, b)
    local bar = CreateFrame("StatusBar", name, UIParent)
    bar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:SetStatusBarColor(r, g, b, 1)
    bar:SetFrameStrata("MEDIUM")
    bar.bg = bar:CreateTexture(nil, "BORDER")
    bar.bg:SetAllPoints(true)
    bar.bg:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    bar.bg:SetVertexColor(r * 0.25, g * 0.25, b * 0.25, 0.7)
    bar.spark = bar:CreateTexture(nil, "OVERLAY")
    bar.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    bar.spark:SetBlendMode("ADD")
    bar.spark:Hide()
    return bar
end

local energy = MakeStatusBar("ForeverWarriorHUD2_Energy", 1.0, 0.96, 0.41)
energy.value = energy:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
energy.value:SetPoint("CENTER")

local swing = MakeStatusBar("ForeverWarriorHUD2_Swing", 0.85, 0.85, 0.95)
swing.time = swing:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
swing.time:SetPoint("CENTER")

-- Energy regeneration: a second, independent bar. It is its own frame, so it
-- drags and resizes on its own exactly like the energy bar does.
local regen = MakeStatusBar("ForeverWarriorHUD2_Regen", 0.35, 0.72, 0.95)
regen.value = regen:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
regen.value:SetPoint("CENTER")

local cpHolder = CreateFrame("Frame", "ForeverWarriorHUD2_Combo", UIParent)
cpHolder:SetFrameStrata("MEDIUM")
local MAX_COMBO_POINTS = 5
local cpBars = {}
for i = 1, MAX_COMBO_POINTS do
    local b = CreateFrame("StatusBar", nil, cpHolder)
    b:SetStatusBarTexture("Interface\\BUTTONS\\WHITE8X8")
    b:SetMinMaxValues(0, 1)
    b:SetStatusBarColor(1, 0.6, 0, 1)
    b:SetAlpha(0.2)
    b.bg = b:CreateTexture(nil, "BORDER")
    b.bg:SetAllPoints(true)
    b.bg:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    b.bg:SetVertexColor(1, 0.6, 0, 0.15)
    cpBars[i] = b
end

local elems = { energy = energy, swing = swing, combo = cpHolder, regen = regen }

-----------------------------------------------------------------------
-- Spell reminder icons
-----------------------------------------------------------------------
local spellIcons = {}
for _, a in ipairs(ABILITIES) do
    local btn = CreateFrame("Frame", "ForeverWarriorHUD2_Spell_" .. a.key, UIParent, "BackdropTemplate")
    btn:SetSize(26, 26)
    btn:SetFrameStrata("MEDIUM")
    btn:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8",
                      edgeFile = "Interface\\BUTTONS\\WHITE8X8",
                      edgeSize = 1,
                      insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    btn:SetBackdropColor(0, 0, 0, 0.6)
    btn:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOPLEFT", 1, -1)
    btn.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    btn.cd:SetAllPoints(btn.icon)
    btn.cd:SetDrawEdge(false)
    -- our own countdown text replaces the template's numbers, so there is one
    -- number per icon and it has a toggle
    btn.cd:SetHideCountdownNumbers(true)
    if btn.cd.SetSwipeColor then btn.cd:SetSwipeColor(0, 0, 0, 0.75) end
    -- a font string on the icon itself would be drawn under the Cooldown child
    -- frame; this holder sits above it
    btn.over = CreateFrame("Frame", nil, btn)
    btn.over:SetAllPoints(btn)
    -- the number must never be covered: its holder is a strata above the HUD
    if btn.over.SetFrameStrata then btn.over:SetFrameStrata("HIGH") end
    if btn.over.SetFrameLevel and btn.cd.GetFrameLevel then
        btn.over:SetFrameLevel(btn.cd:GetFrameLevel() + 2)
    end
    btn.timer = btn.over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if btn.timer.SetDrawLayer then btn.timer:SetDrawLayer("OVERLAY", 7) end
    -- bottom right corner of the box
    btn.timer:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    btn.timer:SetJustifyH("RIGHT")
    btn.timer:SetShadowColor(0, 0, 0, 1)
    btn.timer:SetShadowOffset(1, -1)
    btn.timer:SetText("")
    -- lit while the ability's own effect is on the player
    btn.glow = btn.over:CreateTexture(nil, "BACKGROUND")
    btn.glow:SetTexture(WHITE)
    btn.glow:SetAllPoints(btn)
    btn.glow:SetBlendMode("ADD")
    btn.glow:SetVertexColor(1, 0.85, 0.3, 0.35)
    btn.glow:Hide()
    btn.spell = a
    btn.spellId = a.id   -- replaced by ResolveSpells() once the client answers
    spellIcons[a.key] = btn
end

-----------------------------------------------------------------------
-- Skin plumbing: decorative textures and the list of things to repaint
-----------------------------------------------------------------------
-- Every decorative texture is WHITE8X8 tinted with SetVertexColor, so there
-- is no texture path here that could be missing on this client.
local function Decor(parent, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(WHITE)
    return t
end

-- Widgets register themselves here as they are built; ApplySkin walks the
-- lists. That is what lets one skin change repaint the options window
-- without any per-widget colour code.
local skinned = {
    text = {},        -- font strings in the skin's text colour
    accentText = {},  -- font strings in the accent colour (section headers)
    dividers = {},    -- 1 px rules
    headerBars = {},  -- tinted bars behind section headers
    gutters = {},     -- scrollbar gutters
    sliders = {},     -- OptionsSliderTemplate sliders (track + thumb tint)
    tabs = {},        -- selected-tab accent bars
}

-- True while a refresh or a reflow is driving the widgets. Slider handlers
-- still update their value label but do not write to db, so neither resizing
-- the window nor repainting the panel can change the saved configuration.
local suppress = false

-----------------------------------------------------------------------
-- Swing extras (1.9.0): ready flash and tick marks
-----------------------------------------------------------------------
swing.flash = Decor(swing, "OVERLAY")
swing.flash:SetAllPoints(true)
swing.flash:SetBlendMode("ADD")
swing.flash:Hide()
swing.ticks = {}

-- Size the spark and lay the tick marks out over the bar. Called from
-- ApplyElement("swing"), so it follows width, height and orientation.
LayoutSwing = function(e)
    local size = e.sparkSize or 20
    swing.spark:SetSize(size, e.h * size / 10)   -- 20 px wide = twice the bar height, as before
    if not e.spark then swing.spark:Hide() end
    if not e.flash then swing.flash:Hide() end
    swing.time:SetShown(e.text and e.textMode ~= "none")
    local n = e.ticks and e.tickCount or 0
    for i = 1, n do
        local t = swing.ticks[i]
        if not t then
            t = Decor(swing, "OVERLAY")
            swing.ticks[i] = t
        end
        t:ClearAllPoints()
        if ME.Vertical(e) then
            -- a turned bar is e.h wide and e.w tall
            t:SetPoint("BOTTOMLEFT", swing, "BOTTOMLEFT", 0, e.w * i / (n + 1))
            t:SetSize(e.h, 1)
        else
            t:SetPoint("TOPLEFT", swing, "TOPLEFT", e.w * i / (n + 1), 0)
            t:SetSize(1, e.h)
        end
        t:Show()
    end
    for i = n + 1, #swing.ticks do swing.ticks[i]:Hide() end
    PaintSwing()
end

-----------------------------------------------------------------------
-- Edge kits: the textures a skin's style flag draws around a frame
-----------------------------------------------------------------------
-- Outlines sit 1 px OUTSIDE the frame and inlays inside it, so a style never
-- changes a frame's size or position. Spell icons already have a backdrop
-- border, so their kit is "inner": inlays and pips only.
local edgeKits = {}
local function MakeEdges(fr, inner)
    local k = {}
    local function Piece()
        local t = Decor(fr, "OVERLAY")
        t:Hide()
        return t
    end
    if not inner then
        local top, bottom, left, right = Piece(), Piece(), Piece(), Piece()
        top:SetPoint("BOTTOMLEFT", fr, "TOPLEFT", -1, 0)
        top:SetPoint("BOTTOMRIGHT", fr, "TOPRIGHT", 1, 0)
        top:SetHeight(1)
        bottom:SetPoint("TOPLEFT", fr, "BOTTOMLEFT", -1, 0)
        bottom:SetPoint("TOPRIGHT", fr, "BOTTOMRIGHT", 1, 0)
        bottom:SetHeight(1)
        left:SetPoint("TOPRIGHT", fr, "TOPLEFT", 0, 0)
        left:SetPoint("BOTTOMRIGHT", fr, "BOTTOMLEFT", 0, 0)
        left:SetWidth(1)
        right:SetPoint("TOPLEFT", fr, "TOPRIGHT", 0, 0)
        right:SetPoint("BOTTOMLEFT", fr, "BOTTOMRIGHT", 0, 0)
        right:SetWidth(1)
        k.sides = { top, bottom, left, right }
    end
    local inset = inner and 1 or 0
    k.hi = Piece()
    k.hi:SetPoint("TOPLEFT", fr, "TOPLEFT", inset, -inset)
    k.hi:SetPoint("TOPRIGHT", fr, "TOPRIGHT", -inset, -inset)
    k.hi:SetHeight(1)
    k.lo = Piece()
    k.lo:SetPoint("BOTTOMLEFT", fr, "BOTTOMLEFT", inset, inset)
    k.lo:SetPoint("BOTTOMRIGHT", fr, "BOTTOMRIGHT", -inset, inset)
    k.lo:SetHeight(1)
    -- corner pips: on the outline for bars, just inside the border for icons
    k.pips = {}
    local corners = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
    local d = inner and 1 or -1
    for i = 1, 4 do
        local sx = (i == 1 or i == 3) and 1 or -1
        local sy = (i <= 2) and -1 or 1
        local p = Piece()
        p:SetSize(3, 3)
        p:SetPoint(corners[i], fr, corners[i], sx * d, sy * d)
        k.pips[i] = p
    end
    edgeKits[#edgeKits + 1] = k
    return k
end

local function PaintEdges(k, skin)
    local st = skin.style
    local ar, ag, ab = skin.accent[1], skin.accent[2], skin.accent[3]
    if k.sides then
        for i = 1, 4 do
            k.sides[i]:SetVertexColor(skin.border[1], skin.border[2], skin.border[3], skin.border[4])
            k.sides[i]:SetShown(st ~= "flat")
        end
    end
    k.hi:Hide(); k.hi:SetHeight(1); k.hi:SetBlendMode("BLEND")
    k.lo:Hide(); k.lo:SetHeight(1); k.lo:SetBlendMode("BLEND")
    for i = 1, 4 do k.pips[i]:Hide() end
    if st == "bevel" then
        k.hi:SetVertexColor(1, 1, 1, 0.28); k.hi:Show()
        k.lo:SetVertexColor(0, 0, 0, 0.40); k.lo:Show()
    elseif st == "rune" then
        for i = 1, 4 do
            k.pips[i]:SetVertexColor(ar, ag, ab, 1)
            k.pips[i]:Show()
        end
    elseif st == "ember" then
        k.hi:SetVertexColor(0, 0, 0, 0.30); k.hi:Show()
        k.lo:SetHeight(2); k.lo:SetBlendMode("ADD")
        k.lo:SetVertexColor(ar, ag, ab, 0.60); k.lo:Show()
    elseif st == "frost" then
        k.hi:SetHeight(2)
        k.hi:SetVertexColor(1, 1, 1, 0.38); k.hi:Show()
        for i = 1, 4 do
            k.pips[i]:SetVertexColor(1, 1, 1, 0.55)
            k.pips[i]:Show()
        end
    elseif st == "gilded" then
        k.hi:SetVertexColor(ar, ag, ab, 0.75); k.hi:Show()
        k.lo:SetVertexColor(ar, ag, ab, 0.75); k.lo:Show()
    end
end

MakeEdges(energy)
MakeEdges(swing)
MakeEdges(regen)
for i = 1, MAX_COMBO_POINTS do MakeEdges(cpBars[i]) end
for _, a in ipairs(ABILITIES) do MakeEdges(spellIcons[a.key], true) end

-----------------------------------------------------------------------
-- Dragging: only while the config window is open. Hold CTRL and left-drag an
-- element or an icon to move that one item. The grid is on screen for as long
-- as the window is open, and a dropped item snaps to it and sticks to the
-- edges of the items it comes close to.
-----------------------------------------------------------------------
-- centre of a frame in UIParent units, independent of the frame's own scale
local function ScreenCenter(fr)
    local x, y = fr:GetCenter()
    if not x then return nil end
    local k = fr:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return x * k, y * k
end

-- Width and height of a frame in UIParent units.
local function ScreenSize(fr)
    local k = fr:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return (fr:GetWidth() or 0) * k, (fr:GetHeight() or 0) * k
end

-- Drop the frame where it was released and let the caller write the final
-- position, so a snapped or stuck position is what actually gets saved.
local function FinishDrag(self, reapply)
    self:StopMovingOrSizing()
    if reapply then reapply() end
end

-- Move an item so its edge abuts the nearest neighbour's edge. Everything
-- here is in offset space (the same units cfg.x / cfg.y are stored in), so a
-- stuck position can be written straight into the configuration. "Close" is
-- measured as the gap between the two edges, not the distance between
-- centres, so a bar dropped a few pixels beside another one clicks into place
-- whatever their sizes are. Nothing here runs unless the sticky option is on.
local function StickToNeighbours(self, cx, cy, ux, uy)
    -- snap off = the item stays exactly where it was released
    if not db.sticky or not db.gridSnap then return cx, cy end
    local mw, mh = ScreenSize(self)
    local best, bestScore = nil, nil
    local bestGX, bestGY = 0, 0
    for _, other in ipairs(ALL_ITEMS) do
        if other ~= self and other:IsShown() then
            local ox, oy = ScreenCenter(other)
            if ox then
                local ocx = ox - ux - db.baseX
                local ocy = oy - uy - db.baseY
                local ow, oh = ScreenSize(other)
                local gx = math.abs(cx - ocx) - (ow + mw) / 2
                local gy = math.abs(cy - ocy) - (oh + mh) / 2
                -- close on either axis is enough: two bars of different
                -- heights can still be dropped side by side
                -- close on BOTH axes: sharing a row with a far-away item is not "near"
                if gx <= STICK_DISTANCE and gy <= STICK_DISTANCE then
                    local score = math.min(gx, gy)
                    if not bestScore or score < bestScore then
                        best, bestScore, bestGX, bestGY = other, score, gx, gy
                    end
                end
            end
        end
    end
    if not best then return cx, cy end
    local ox, oy = ScreenCenter(best)
    if not ox then return cx, cy end
    local ocx = ox - ux - db.baseX
    local ocy = oy - uy - db.baseY
    local ow, oh = ScreenSize(best)
    -- abut on the axis whose gap is smaller, align on the other
    if bestGX <= bestGY then
        cy = ocy
        cx = ocx + (cx >= ocx and 1 or -1) * (ow + mw) / 2
    else
        cx = ocx
        cy = ocy + (cy >= ocy and 1 or -1) * (oh + mh) / 2
    end
    return cx, cy
end

-----------------------------------------------------------------------
-- Mouse editing. Everything here only acts while the options window is open
-- (and Lock is off). Hover an item, hold CTRL, then:
--   left button held     the item follows the cursor until release
--   mouse wheel          bigger / smaller
--   right button held    turn it by dragging; it stays where you leave it
--   right double-click   back to its original orientation (no CTRL needed)
-- Position, size and rotation are therefore NOT in the options window.
-----------------------------------------------------------------------
ME.SCALE_STEP = 0.05   -- per wheel notch
ME.DOUBLE = 0.4        -- seconds between the two clicks of a double-click

function ME.Active()
    return db ~= nil and not db.locked and EditMode()
end

-- Bars and rows turn in quarter turns (a status bar cannot be drawn at an
-- angle); icons turn freely, with a soft stop on the quarters.
function ME.Norm(rot, free)
    rot = (tonumber(rot) or 0) % 360
    if free then
        local q = math.floor(rot / 90 + 0.5) * 90
        if math.abs(rot - q) <= 4 then rot = q end
        rot = math.floor(rot + 0.5)
    else
        rot = math.floor(rot / 90 + 0.5) * 90
    end
    return rot % 360
end
function ME.Vertical(e) return (e.rot or 0) % 180 == 90 end
function ME.Reversed(e) return (e.rot or 0) >= 180 end
-- which place the i-th of n pieces takes in a row that may be reversed
function ME.Slot(e, i, n)
    if ME.Reversed(e) then return n + 1 - i end
    return i
end
-- the end of a bar its fill grows towards
function ME.SparkAnchor(e)
    if ME.Vertical(e) then return ME.Reversed(e) and "BOTTOM" or "TOP" end
    return ME.Reversed(e) and "LEFT" or "RIGHT"
end

-- angle of the cursor around an item's centre, in degrees
function ME.CursorAngle(fr)
    local fx, fy = ScreenCenter(fr)
    if not fx or not GetCursorPosition then return nil end
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    x, y = x / s, y / s
    if x == fx and y == fy then return nil end
    return math.deg((math.atan2 or math.atan)(y - fy, x - fx))
end

-- left button released: snap, stick, store
function ME.Drop(self)
    self._dragging = false
    self:StopMovingOrSizing()
    local cfg = self._cfg()
    local fx, fy = ScreenCenter(self)
    local ux, uy = UIParent:GetCenter()
    if fx and ux then
        local cx = fx - ux - db.baseX
        local cy = fy - uy - db.baseY
        -- grid first, then stick: a sticky drop wins over the grid
        cx = Snap(cx)
        cy = Snap(cy)
        cx, cy = StickToNeighbours(self, cx, cy, ux, uy)
        cfg.x = math.floor(cx + 0.5)
        cfg.y = math.floor(cy + 0.5)
    end
    FinishDrag(self, self._reapply)
end

-- while the right button is held: follow the cursor round the centre
function ME.Turn(self)
    local a = ME.CursorAngle(self)
    if not a or not ME.startAngle then return end
    local cfg = self._cfg()
    local rot = ME.Norm(ME.startRot + (a - ME.startAngle), self._freeRot)
    if rot ~= (cfg.rot or 0) then
        cfg.rot = rot
        ME.turned = true
        self._reapply()
    end
end

function ME.Watch()
    local fr = ME.held
    if fr and fr._rotating then ME.Turn(fr) return end
    if not (fr and fr._dragging) then
        ME.held = nil
        ME.watch:SetScript("OnUpdate", nil)
    end
end

function ME.Down(self, button)
    if not ME.Active() then return end
    if not (IsControlKeyDown and IsControlKeyDown()) then return end
    if button == "LeftButton" then
        self:StartMoving()
        self._dragging = true
        ME.held = self
    elseif button == "RightButton" then
        self._rotating = true
        ME.held = self
        ME.turned = false
        ME.startAngle = ME.CursorAngle(self)
        ME.startRot = self._cfg().rot or 0
        ME.watch:SetScript("OnUpdate", ME.Watch)
    end
end

function ME.Up(self, button)
    if button == "LeftButton" then
        if self._dragging then
            ME.Drop(self)
            ME.held = nil
        end
    elseif button == "RightButton" then
        local turned = false
        if self._rotating then
            ME.Turn(self)
            turned = ME.turned
            self._rotating = false
            ME.held = nil
            ME.watch:SetScript("OnUpdate", nil)
        end
        if not ME.Active() then return end
        if turned then
            self._lastRight = nil   -- the end of a turn is not a click
            return
        end
        local now = GetTime()
        if self._lastRight and now - self._lastRight <= ME.DOUBLE then
            self._lastRight = nil
            self._cfg().rot = 0
            self._reapply()
        else
            self._lastRight = now
        end
    end
end

function ME.Wheel(self, delta)
    if not ME.Active() then return end
    if not (IsControlKeyDown and IsControlKeyDown()) then return end
    local cfg = self._cfg()
    local sc = (cfg.scale or 1) + ((delta > 0) and ME.SCALE_STEP or -ME.SCALE_STEP)
    sc = math.floor(sc * 100 + 0.5) / 100
    if sc < 0.2 then sc = 0.2 elseif sc > 4 then sc = 4 end
    cfg.scale = sc
    self._reapply()
end

-- hover: light the item up and say what the mouse does to it
function ME.Enter(self)
    if not EditMode() then return end
    if self._edit then self._edit:SetVertexColor(0.2, 0.8, 1, 0.5) end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(self._label or "HUD item", 1, 1, 1)
    if db.locked then
        GameTooltip:AddLine("Locked. Untick Lock on the HUD tab to edit.", 1, 0.6, 0.6, true)
    else
        GameTooltip:AddLine("CTRL + hold left button: move", nil, nil, nil, true)
        GameTooltip:AddLine("CTRL + mouse wheel: size", nil, nil, nil, true)
        GameTooltip:AddLine(self._freeRot and "CTRL + hold right button and drag: turn"
            or "CTRL + hold right button and drag: turn (quarter turns)", nil, nil, nil, true)
        GameTooltip:AddLine("Right double-click: original orientation", nil, nil, nil, true)
    end
    GameTooltip:Show()
end
function ME.Leave(self)
    if self._edit then self._edit:SetVertexColor(0.2, 0.8, 1, 0.25) end
    GameTooltip:Hide()
end

-- the options window closed with something still in the hand
function ME.Cancel()
    local fr = ME.held
    if fr then
        if fr._dragging then ME.Drop(fr) end
        fr._rotating = false
    end
    ME.held = nil
    ME.watch:SetScript("OnUpdate", nil)
end

ME.watch = CreateFrame("Frame")

-- Places in a page remembered while it is built, so a later section can put
-- its rows next to the options they belong to instead of on a tab of its own.
ME.mark = {}
function ME.Mark(key, flow, child)
    ME.mark[key] = { flow = flow, child = child, at = #flow.rows }
end
-- fn() appends rows to the marked flow; they are moved up to the mark.
function ME.InsertRows(key, fn)
    local m = ME.mark[key]
    local flow = m.flow
    local before = #flow.rows
    fn()
    local added = #flow.rows - before
    if added == 0 then return end
    local moved = {}
    for i = 1, added do moved[i] = table.remove(flow.rows, before + 1) end
    for i = 1, added do table.insert(flow.rows, m.at + i, moved[i]) end
    for _, other in pairs(ME.mark) do
        if other.flow == flow and other.at > m.at then other.at = other.at + added end
    end
    m.at = m.at + added
end

local function MakeDraggable(fr, getCfg, reapply, label, free)
    fr:SetMovable(true)
    fr:SetClampedToScreen(true)
    fr._cfg, fr._reapply, fr._label, fr._freeRot = getCfg, reapply, label, free
    fr:SetScript("OnMouseDown", ME.Down)
    fr:SetScript("OnMouseUp", ME.Up)
    fr:SetScript("OnMouseWheel", ME.Wheel)
    fr:SetScript("OnEnter", ME.Enter)
    fr:SetScript("OnLeave", ME.Leave)
    -- no mouse at all unless the options window is open
    fr:EnableMouse(false)
    if fr.EnableMouseWheel then fr:EnableMouseWheel(false) end
end
ME.MakeDraggable = MakeDraggable   -- for the sections that add their own items

-----------------------------------------------------------------------
-- Recent actions: the last few spells you cast, newest first, fading out
-----------------------------------------------------------------------
ME.TRAIL = 4          -- icons in the row
ME.TRAIL_LIFE = 6     -- seconds an icon stays
local trail = CreateFrame("Frame", "ForeverWarriorHUD2_Trail", UIParent)
trail:SetFrameStrata("MEDIUM")
trail.icons, trail.log = {}, {}
for i = 1, ME.TRAIL do
    local t = trail:CreateTexture(nil, "ARTWORK")
    t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    trail.icons[i] = t
end

function ME.LayoutTrail(fr, e)
    local n, gap = ME.TRAIL, 2
    local vert = ME.Vertical(e)
    if vert then fr:SetSize(e.w, n * e.h + (n - 1) * gap) else fr:SetSize(n * e.w + (n - 1) * gap, e.h) end
    for i = 1, n do
        local t = fr.icons[i]
        local slot = ME.Slot(e, i, n) - 1
        t:ClearAllPoints()
        t:SetSize(e.w, e.h)
        if vert then
            t:SetPoint("BOTTOM", fr, "BOTTOM", 0, slot * (e.h + gap))
        else
            t:SetPoint("LEFT", fr, "LEFT", slot * (e.w + gap), 0)
        end
    end
    ME.PaintTrail()
end

-- alpha by age; with the options window open empty places show faintly so
-- the row can be found and grabbed
function ME.PaintTrail()
    local now = GetTime()
    for i = 1, ME.TRAIL do
        local t, entry = trail.icons[i], trail.log[i]
        local left = entry and (ME.TRAIL_LIFE - (now - entry.at)) or 0
        if left > 0 then
            t:SetTexture(entry.icon)
            t:SetVertexColor(1, 1, 1, 1)
            t:SetAlpha(math.min(1, left / 2))
            t:Show()
        elseif EditMode() then
            t:SetTexture(WHITE)
            t:SetVertexColor(1, 1, 1, 0.12)
            t:SetAlpha(1)
            t:Show()
        else
            t:Hide()
        end
    end
end

-- UNIT_SPELLCAST_SUCCEEDED for the player. A spell ID the client keeps secret
-- is simply not logged.
function ME.LogCast(spellID)
    if not IsReadable(spellID) or type(spellID) ~= "number" then return end
    local icon
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and type(info) == "table" and IsReadable(info.iconID) then icon = info.iconID end
    end
    if not icon then return end
    table.insert(trail.log, 1, { icon = icon, at = GetTime(), id = spellID })
    trail.log[ME.TRAIL + 1] = nil
    ME.PaintTrail()
end

-----------------------------------------------------------------------
-- Notifications on the ability icons. One row here = one toggle on the
-- Abilities tab, one saved field, one line in the profile clamp.
-----------------------------------------------------------------------
ME.NOTIFY = {
    { key = "sweep",      label = "Clock sweep while on cooldown" },
    { key = "cooldownDark", label = "Darken an ability while it is on cooldown" },
    { key = "readyFlash", label = "Flash when an ability comes off cooldown" },
    { key = "activeGlow", label = "Glow while the ability's effect is on you" },
    { key = "usableDim",  label = "Dim abilities you cannot use right now" },
    { key = "rangeTint",  label = "Red tint when the target is out of range" },
}
function ME.ClampNotify(src)
    if type(db.notify) ~= "table" then db.notify = {} end
    for _, n in ipairs(ME.NOTIFY) do
        db.notify[n.key] = not (type(src) == "table" and src[n.key] == false)
    end
end

-- Usable / in range / effect active, each read under pcall and only compared
-- after IsReadable. Anything the client will not tell leaves the icon plain.
function ME.IconState(btn, id)
    local n = db.notify
    local dim, red, active = false, false, false
    if n.usableDim and C_Spell and C_Spell.IsSpellUsable then
        local ok, usable = pcall(C_Spell.IsSpellUsable, id)
        if ok and IsReadable(usable) and usable == false then dim = true end
    end
    if n.rangeTint and C_Spell and C_Spell.IsSpellInRange then
        local ok, inRange = pcall(C_Spell.IsSpellInRange, id, "target")
        if ok and IsReadable(inRange) and inRange == false then red = true end
    end
    if n.activeGlow and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
        if ok and IsReadable(aura) and type(aura) == "table" then active = true end
    end
    -- on cooldown: the picture goes dark and grey, under the clock sweep
    local cooling = n.cooldownDark and btn._cdStart ~= nil
    if red then btn.icon:SetVertexColor(1, 0.3, 0.3, 1)
    elseif cooling then btn.icon:SetVertexColor(0.35, 0.35, 0.35, 1)
    elseif dim then btn.icon:SetVertexColor(0.4, 0.4, 0.4, 1)
    else btn.icon:SetVertexColor(1, 1, 1, 1) end
    if btn.icon.SetDesaturated then btn.icon:SetDesaturated(cooling and true or false) end
    btn.glow:SetShown(active)
end

-----------------------------------------------------------------------
-- A small drop-down: a button that opens a list. Built from plain frames so
-- it does not depend on any menu template of the client.
-----------------------------------------------------------------------
function ME.Dropdown(parent, name, label, options, get, set)
    local dd = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    dd:SetSize(190, 22)
    dd._kind = "button"
    dd.options = options
    dd.list = CreateFrame("Frame", name .. "List", dd, "BackdropTemplate")
    dd.list:SetFrameStrata("DIALOG")
    dd.list:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                          insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    dd.list:SetBackdropColor(0.04, 0.04, 0.06, 0.97)
    dd.list:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
    dd.list:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -2)
    dd.list:SetSize(190, #options * 22 + 4)
    dd.list:Hide()
    dd.items = {}
    function dd.Refresh()
        local cur = get()
        local text = tostring(cur)
        for _, o in ipairs(options) do
            if o.value == cur then text = o.text end
        end
        dd:SetText(label .. ": " .. text)
    end
    for i, o in ipairs(options) do
        local b = CreateFrame("Button", name .. "Item" .. i, dd.list, "UIPanelButtonTemplate")
        b:SetSize(186, 20)
        b:SetPoint("TOPLEFT", 2, -(2 + (i - 1) * 22))
        b:SetText(o.text)
        b:SetScript("OnClick", function()
            dd.list:Hide()
            set(o.value)
            dd.Refresh()
        end)
        dd.items[i] = b
    end
    dd:SetScript("OnClick", function() dd.list:SetShown(not dd.list:IsShown()) end)
    dd:SetScript("OnHide", function() dd.list:Hide() end)
    return dd
end

-----------------------------------------------------------------------
-- Menu artwork. The pictures live in the optional ForeverArt addon; without
-- it (or with "Off") the window is the plain skin colours.
-----------------------------------------------------------------------
ME.ART = "Interface\\AddOns\\ForeverArt\\warrior\\"
ME.HEADER = 80   -- height of the header band, banner included

function ME.ArtInfo()
    local a = _G.ForeverArt
    if type(a) ~= "table" or type(a.classes) ~= "table" then return nil end
    return a.classes["warrior"]
end

-- show the middle of a picture so it keeps its shape in a box of another shape
function ME.Crop(tex, boxW, boxH, picAspect)
    if not boxW or not boxH or boxW <= 0 or boxH <= 0 then return end
    local box = boxW / boxH
    if box > picAspect then
        local v = picAspect / box
        tex:SetTexCoord(0, 1, (1 - v) / 2, (1 + v) / 2)
    else
        local h = box / picAspect
        tex:SetTexCoord((1 - h) / 2, (1 + h) / 2, 0, 1)
    end
end

function ME.FitArt()
    local w, h = panel:GetWidth(), panel:GetHeight()
    ME.Crop(panel.artBack, w - 2, h - ME.HEADER - 2, 1)
    ME.Crop(panel.artBanner, w - 2, ME.HEADER - 1, 4)
end

function ME.ApplyArt()
    if not db then return end
    local info = ME.ArtInfo()
    local q = db.art
    local on = info ~= nil and q ~= "off"
    local sfx = (q == "low") and "_lo.tga" or "_hi.tga"
    -- ForeverArt says which pictures it really has for this class; a piece it
    -- does not list is never asked for, so a missing file cannot show as a
    -- blank square
    local hasBack = on and info.backdrop == true
    local hasBanner = on and (info.banner == true or info.banner2 == true)
    local hasCrest = on and info.crest == true
    panel.artBack:SetShown(hasBack)
    panel.artShade:SetShown(hasBack)
    panel.artBanner:SetShown(hasBanner)
    panel.artCrest:SetShown(hasCrest)
    if on then
        local banner = "banner"
        if info.banner2 == true and (db.artBanner == "b" or info.banner ~= true) then banner = "banner2" end
        if hasBack then panel.artBack:SetTexture(ME.ART .. "backdrop" .. sfx) end
        if hasBanner then panel.artBanner:SetTexture(ME.ART .. banner .. sfx) end
        if hasCrest then panel.artCrest:SetTexture(ME.ART .. "crest" .. sfx) end
        ME.FitArt()
    end
    panel.title:ClearAllPoints()
    panel.title:SetPoint("TOPLEFT", hasCrest and 86 or 12, -(ME.HEADER / 2 - 9))
    if ME.artDD then ME.artDD.Refresh() end
    if ME.bannerDD then
        ME.bannerDD.Refresh()
        ME.bannerDD:SetShown(on and info.banner == true and info.banner2 == true)
    end
    if ME.artNote then
        ME.artNote:SetText(info and "" or "Needs the ForeverArt addon.")
    end
end

elems.trail = trail

-----------------------------------------------------------------------
-- Custom colours. A custom scheme is a set of overrides on top of the chosen
-- skin: any part the player has not coloured keeps the skin's colour, and the
-- skin still picks the edge style. Schemes are saved by name in db.schemes,
-- apart from the live configuration (Reset to default keeps them).
-----------------------------------------------------------------------
ME.PARTS = {
    { key = "bar",      label = "Resource bar" },
    { key = "swing",    label = "Swing bar" },
    { key = "barBg",    label = "Bar background", alpha = true },
    { key = "spark",    label = "Spark and ready flash" },
    { key = "text",     label = "Text" },
    { key = "accent",   label = "Accent: headers, regen bar, glow" },
    { key = "border",   label = "Borders", alpha = true },
    { key = "panel",    label = "Window background", alpha = true },
    { key = "combo",    label = "Combo points" },
    { key = "iconEdge", label = "Icon border", alpha = true },
}
ME.PART = {}
for _, p in ipairs(ME.PARTS) do ME.PART[p.key] = p end
ME.MAX_SCHEMES = 40

-- { r, g, b [, a] } with every number in 0..1, or nil if it is not a colour
function ME.CleanColor(c, alpha)
    if type(c) ~= "table" then return nil end
    local out = {}
    for i = 1, 3 do
        local v = tonumber(c[i])
        if not v or v ~= v then return nil end
        out[i] = math.max(0, math.min(1, v))
    end
    if alpha then
        local a = tonumber(c[4])
        if not a or a ~= a then a = 1 end
        out[4] = math.max(0, math.min(1, a))
    end
    return out
end
function ME.CleanPalette(src)
    local out = {}
    if type(src) == "table" then
        for _, p in ipairs(ME.PARTS) do out[p.key] = ME.CleanColor(src[p.key], p.alpha) end
    end
    return out
end
function ME.ClampCustom(src, on)
    db.custom = ME.CleanPalette(src)
    db.customOn = on == true
end
-- the skin as painted: the chosen one, or the chosen one with the overrides
function ME.CustomSkin(base)
    if not (db and db.customOn and type(db.custom) == "table") then return base end
    local s = setmetatable({ _base = base }, { __index = base })
    for k, v in pairs(db.custom) do s[k] = v end
    return s
end
function ME.SetPart(key, r, g, b, a)
    local p = ME.PART[key]
    if not p or not db then return false end
    local c = ME.CleanColor({ r, g, b, a }, p.alpha)
    if not c then return false end
    if type(db.custom) ~= "table" then db.custom = {} end
    db.custom[key] = c
    db.customOn = true
    ApplySkin()   -- repaint with the current skin
    return true
end
function ME.SchemeName(s)
    s = tostring(s or ""):gsub("[%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if #s > 32 then s = s:sub(1, 32) end
    return s
end
function ME.SchemeNames()
    local names = {}
    if db and type(db.schemes) == "table" then
        for name in pairs(db.schemes) do
            if type(name) == "string" then names[#names + 1] = name end
        end
    end
    table.sort(names, function(x, y) return x:lower() < y:lower() end)
    return names
end
function ME.SaveScheme(name)
    name = ME.SchemeName(name)
    if name == "" then return false, "Type a name for the colours first." end
    if type(db.schemes) ~= "table" then db.schemes = {} end
    if db.schemes[name] == nil and #ME.SchemeNames() >= ME.MAX_SCHEMES then
        return false, "Colour scheme limit reached (" .. ME.MAX_SCHEMES .. "). Delete one first."
    end
    db.schemes[name] = ME.CleanPalette(db.custom)
    return true, "Saved colours '" .. name .. "'."
end
function ME.LoadScheme(name)
    name = ME.SchemeName(name)
    local s = type(db.schemes) == "table" and db.schemes[name] or nil
    if type(s) ~= "table" then return false, "No saved colours named '" .. name .. "'." end
    db.custom = ME.CleanPalette(s)
    db.customOn = true
    ApplySkin()   -- repaint with the current skin
    return true, "Loaded colours '" .. name .. "'."
end
function ME.DeleteScheme(name)
    name = ME.SchemeName(name)
    if type(db.schemes) ~= "table" or db.schemes[name] == nil then
        return false, "No saved colours named '" .. name .. "'."
    end
    db.schemes[name] = nil
    return true, "Deleted colours '" .. name .. "'."
end

-- A list that opens under a button: used for the saved colour schemes.
function ME.OpenList(owner, names, onPick)
    local l = ME.list
    if not l then
        l = CreateFrame("Frame", "ForeverWarriorHUD2List", panel, "BackdropTemplate")
        l:SetFrameStrata("DIALOG")
        l:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                        insets = { left = 1, right = 1, top = 1, bottom = 1 } })
        l:SetBackdropColor(0.04, 0.04, 0.06, 0.97)
        l:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
        l.items = {}
        ME.list = l
    end
    if l:IsShown() and l.owner == owner then l:Hide() return end
    l.owner = owner
    local n = math.max(1, #names)
    for i = 1, n do
        local b = l.items[i]
        if not b then
            b = CreateFrame("Button", "ForeverWarriorHUD2ListItem" .. i, l, "UIPanelButtonTemplate")
            b:SetSize(176, 20)
            b:SetPoint("TOPLEFT", 2, -(2 + (i - 1) * 22))
            l.items[i] = b
        end
        local name = names[i]
        b:SetText(name or "Nothing saved yet")
        b:SetScript("OnClick", function()
            l:Hide()
            if name then onPick(name) end
        end)
        b:Show()
    end
    for i = n + 1, #l.items do l.items[i]:Hide() end
    l:SetSize(180, n * 22 + 4)
    l:ClearAllPoints()
    l:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -2)
    l:Show()
end

-- The colour wheel. A ColorSelect widget draws the hue / saturation wheel and
-- the brightness bar itself; if this client will not create one, three
-- sliders stand in for it. Every change is applied live; Cancel puts the
-- starting colour back.
function ME.BuildWheel()
    local w = CreateFrame("Frame", "ForeverWarriorHUD2Wheel", panel, "BackdropTemplate")
    w:SetFrameStrata("DIALOG")
    w:SetSize(214, 286)
    w:EnableMouse(true)
    w:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                    insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    w:SetBackdropColor(0.04, 0.04, 0.06, 0.98)
    w:SetBackdropBorderColor(0.45, 0.45, 0.5, 1)
    w.title = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    w.title:SetPoint("TOPLEFT", 10, -8)
    local function Slider(name, label, y, fn)
        local s = CreateFrame("Slider", name, w, "OptionsSliderTemplate")
        s:SetPoint("TOPLEFT", 14, y)
        s:SetWidth(186)
        s:SetHeight(14)
        s:SetMinMaxValues(0, 1)
        s:SetValueStep(0.01)
        _G[name .. "Low"]:SetText("")
        _G[name .. "High"]:SetText("")
        _G[name .. "Text"]:SetText(label)
        s:SetScript("OnValueChanged", function(_, v)
            if w.setting then return end
            fn(math.floor(v * 100 + 0.5) / 100)
            w.Changed()
        end)
        return s
    end
    local ok, cs = pcall(CreateFrame, "ColorSelect", "ForeverWarriorHUD2WheelCS", w)
    if ok and cs and cs.SetColorWheelTexture and cs.SetColorRGB then
        cs:SetSize(190, 128)
        cs:SetPoint("TOPLEFT", 12, -28)
        local wt = cs:CreateTexture(nil, "ARTWORK")
        wt:SetSize(128, 128)
        wt:SetPoint("TOPLEFT", 0, 0)
        cs:SetColorWheelTexture(wt)
        local th = cs:CreateTexture(nil, "OVERLAY")
        th:SetTexture(WHITE)
        th:SetSize(6, 6)
        cs:SetColorWheelThumbTexture(th)
        local vt = cs:CreateTexture(nil, "ARTWORK")
        vt:SetSize(26, 128)
        vt:SetPoint("TOPLEFT", wt, "TOPRIGHT", 18, 0)
        cs:SetColorValueTexture(vt)
        local vth = cs:CreateTexture(nil, "OVERLAY")
        vth:SetTexture(WHITE)
        vth:SetSize(32, 4)
        cs:SetColorValueThumbTexture(vth)
        cs:SetScript("OnColorSelect", function(_, r, g, b)
            if w.setting then return end
            w.r, w.g, w.b = r, g, b
            w.Changed()
        end)
        w.cs = cs
    else
        w.rs = Slider("ForeverWarriorHUD2WheelR", "Red", -44, function(v) w.r = v end)
        w.gs = Slider("ForeverWarriorHUD2WheelG", "Green", -84, function(v) w.g = v end)
        w.bs = Slider("ForeverWarriorHUD2WheelB", "Blue", -124, function(v) w.b = v end)
    end
    w.alpha = Slider("ForeverWarriorHUD2WheelA", "Opacity", -180, function(v) w.a = v end)
    w.swatch = w:CreateTexture(nil, "ARTWORK")
    w.swatch:SetTexture(WHITE)
    w.swatch:SetSize(44, 18)
    w.swatch:SetPoint("TOPLEFT", 14, -204)
    w.info = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    w.info:SetPoint("LEFT", w.swatch, "RIGHT", 8, 0)
    function w.Paint()
        w.swatch:SetVertexColor(w.r, w.g, w.b, w.hasAlpha and w.a or 1)
        local t = string.format("%d  %d  %d", math.floor(w.r * 255 + 0.5), math.floor(w.g * 255 + 0.5), math.floor(w.b * 255 + 0.5))
        if w.hasAlpha then t = t .. string.format("   %d%%", math.floor(w.a * 100 + 0.5)) end
        w.info:SetText(t)
    end
    function w.Changed()
        w.Paint()
        if w.onChange then w.onChange(w.r, w.g, w.b, w.hasAlpha and w.a or nil) end
    end
    w.ok = CreateFrame("Button", "ForeverWarriorHUD2WheelOK", w, "UIPanelButtonTemplate")
    w.ok:SetSize(88, 22)
    w.ok:SetPoint("BOTTOMLEFT", 12, 10)
    w.ok:SetText("Done")
    w.ok:SetScript("OnClick", function() w:Hide() end)
    w.cancel = CreateFrame("Button", "ForeverWarriorHUD2WheelCancel", w, "UIPanelButtonTemplate")
    w.cancel:SetSize(88, 22)
    w.cancel:SetPoint("BOTTOMRIGHT", -12, 10)
    w.cancel:SetText("Cancel")
    w.cancel:SetScript("OnClick", function()
        local o = w.orig
        w.r, w.g, w.b, w.a = o[1], o[2], o[3], o[4]
        w.Changed()
        w:Hide()
    end)
    w:Hide()
    ME.wheel = w
    return w
end

function ME.OpenWheel(owner, title, r, g, b, a, hasAlpha, onChange)
    local w = ME.wheel or ME.BuildWheel()
    w.onChange = nil
    w.setting = true
    w.r, w.g, w.b, w.a = r, g, b, a or 1
    w.orig = { r, g, b, a or 1 }
    w.hasAlpha = hasAlpha and true or false
    w.title:SetText(title)
    if w.cs then
        w.cs:SetColorRGB(r, g, b)
    else
        w.rs:SetValue(r); w.gs:SetValue(g); w.bs:SetValue(b)
    end
    w.alpha:SetValue(w.a)
    w.alpha:SetShown(w.hasAlpha)
    w.setting = false
    w.Paint()
    w.onChange = onChange
    w:ClearAllPoints()
    w:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -4)
    w:Show()
end

MakeDraggable(energy,   function() return db.elements.energy end, function() ApplyElement("energy") end, "Rage bar")
MakeDraggable(regen,    function() return db.elements.regen end,  function() ApplyElement("regen") end, "Rage regen")
MakeDraggable(swing,    function() return db.elements.swing end,  function() ApplyElement("swing") end, "Swing timer")
MakeDraggable(cpHolder, function() return db.elements.combo end,  function() ApplyElement("combo") end, "Combo points")
MakeDraggable(trail,    function() return db.elements.trail end,  function() ApplyElement("trail") end, "Recent actions")
for key, btn in pairs(spellIcons) do
    -- icons are the items that turn to any angle
    MakeDraggable(btn, function() return db.spells[key] end, function() ApplySpell(key) end, btn.spell.name, true)
end
for _, fr in pairs(elems) do ALL_ITEMS[#ALL_ITEMS + 1] = fr end
for _, btn in pairs(spellIcons) do ALL_ITEMS[#ALL_ITEMS + 1] = btn end

-- mouse is enabled only while the config window is open; a faint outline
-- shows which items can be grabbed (hold Shift and drag)
local function SetItemsInteractive(on)
    if ME.onInteractive then ME.onInteractive(on) end
    for _, fr in ipairs(ALL_ITEMS) do
        fr:EnableMouse(on)
        if fr.EnableMouseWheel then fr:EnableMouseWheel(on) end
        if not fr._edit then
            local t = fr:CreateTexture(nil, "OVERLAY")
            t:SetAllPoints(true)
            t:SetTexture("Interface\\BUTTONS\\WHITE8X8")
            t:SetVertexColor(0.2, 0.8, 1, 0.25)
            t:Hide()
            fr._edit = t
        end
        fr._edit:SetShown(on)
        if on and not fr:IsShown() then fr._ghost = true end
    end
end

-----------------------------------------------------------------------
-- Options panel with tabs
-----------------------------------------------------------------------
panel = CreateFrame("Frame", "ForeverWarriorHUD2Panel", UIParent, "BackdropTemplate")
panel:SetSize(480, 660)
panel:SetPoint("CENTER")
panel:SetResizable(true)
if panel.SetResizeBounds then panel:SetResizeBounds(430, 360, 900, 860) end
-- A flat WHITE8X8 backdrop instead of the dialog art, so the skin's panel and
-- border colours paint the window exactly.
panel:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                    insets = { left = 1, right = 1, top = 1, bottom = 1 } })
panel:Hide()
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
panel:SetScript("OnShow", function() SetItemsInteractive(true); ShowGrid(); ApplyAll() end)
panel:SetScript("OnHide", function() ME.Cancel(); SetItemsInteractive(false); HideGrid(); ApplyAll() end)
-- every page is laid out again from the new width (see ReflowAll), and the
-- grid is redrawn for the new screen size
panel:SetScript("OnSizeChanged", function() if panel.artBack then ME.FitArt() end; if ReflowAll then ReflowAll() end; if gridFrame and gridFrame:IsShown() then gridFrame:Update() end end)
tinsert(UISpecialFrames, "ForeverWarriorHUD2Panel")

-- Header: tinted band, title, thin accent rule
panel.headerBand = Decor(panel, "BORDER")
panel.headerBand:SetPoint("TOPLEFT", 1, -1)
panel.headerBand:SetPoint("TOPRIGHT", -1, -1)
panel.headerBand:SetHeight(ME.HEADER - 1)
panel.rule = Decor(panel, "ARTWORK")
panel.rule:SetPoint("TOPLEFT", 1, -ME.HEADER)
panel.rule:SetPoint("TOPRIGHT", -1, -ME.HEADER)
panel.rule:SetHeight(1)

panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
panel.title:SetPoint("TOPLEFT", 12, -(ME.HEADER / 2 - 9))
-- Artwork (ForeverArt): a backdrop behind the pages, a banner in the header
-- and the class crest. All hidden until ME.ApplyArt finds the pictures.
panel.artBack = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
panel.artBack:SetPoint("TOPLEFT", 1, -ME.HEADER)
panel.artBack:SetPoint("BOTTOMRIGHT", -1, 1)
panel.artBack:Hide()
-- a veil over the backdrop so small text always reads
panel.artShade = panel:CreateTexture(nil, "BACKGROUND", nil, 2)
panel.artShade:SetTexture(WHITE)
panel.artShade:SetVertexColor(0, 0, 0, 0.45)
panel.artShade:SetAllPoints(panel.artBack)
panel.artShade:Hide()
panel.artBanner = panel:CreateTexture(nil, "BORDER", nil, 1)
panel.artBanner:SetPoint("TOPLEFT", 1, -1)
panel.artBanner:SetPoint("TOPRIGHT", -1, -1)
panel.artBanner:SetHeight(ME.HEADER - 1)
panel.artBanner:Hide()
panel.artCrest = panel:CreateTexture(nil, "ARTWORK")
panel.artCrest:SetSize(68, 68)
panel.artCrest:SetPoint("TOPLEFT", 10, -6)
panel.artCrest:Hide()
panel.title:SetText("ForeverWarriorHUD2")

local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", -4, -4)

-- Footer: thin rule, then version and the drag hint
panel.footRule = Decor(panel, "ARTWORK")
panel.footRule:SetPoint("BOTTOMLEFT", 1, 22)
panel.footRule:SetPoint("BOTTOMRIGHT", -1, 22)
panel.footRule:SetHeight(1)
panel.hint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
panel.hint:SetPoint("BOTTOMLEFT", 12, 7)
panel.hint:SetText("v" .. FRHW2_VERSION .. "  -  CTRL + left: move   wheel: size   right: turn.  See the Help tab.")

-- bottom-right resize grip
local grip = CreateFrame("Button", nil, panel)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", -2, 2)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
grip:SetScript("OnMouseDown", function() panel:StartSizing("BOTTOMRIGHT") end)
grip:SetScript("OnMouseUp", function() panel:StopMovingOrSizing() end)

local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
resetBtn:SetSize(100, 20)
resetBtn:SetPoint("TOPRIGHT", -34, -6)
resetBtn:SetText("Reset to default")
resetBtn:SetScript("OnClick", function() StaticPopup_Show("FRHW2_CONFIRM_RESET") end)

-- Four pages of content between the tab strip and the footer
local pageHUD    = CreateFrame("Frame", nil, panel)
pageHUD:SetPoint("TOPLEFT", 8, -(ME.HEADER + 38))
pageHUD:SetPoint("BOTTOMRIGHT", -8, 26)
local pageConfig = CreateFrame("Frame", nil, panel)
pageConfig:SetPoint("TOPLEFT", 8, -(ME.HEADER + 38))
pageConfig:SetPoint("BOTTOMRIGHT", -8, 26)
pageConfig:Hide()
local pageSkins = CreateFrame("Frame", nil, panel)
pageSkins:SetPoint("TOPLEFT", 8, -(ME.HEADER + 38))
pageSkins:SetPoint("BOTTOMRIGHT", -8, 26)
pageSkins:Hide()
local pageProfiles = CreateFrame("Frame", nil, panel)
pageProfiles:SetPoint("TOPLEFT", 8, -(ME.HEADER + 38))
pageProfiles:SetPoint("BOTTOMRIGHT", -8, 26)
pageProfiles:Hide()

-- Tabs keep PanelTabButtonTemplate; each gets a thin bar that is shown only
-- on the selected tab and tinted with the skin's accent colour.
local TABS = {}
local function SelectTab(which)
    local found = TABS[1]
    for _, t in ipairs(TABS) do
        if t.key == which then found = t end
    end
    for _, t in ipairs(TABS) do
        if t == found then
            t.page:Show()
            PanelTemplates_SelectTab(t.button)
        else
            t.page:Hide()
            PanelTemplates_DeselectTab(t.button)
        end
        t.button.accent:SetShown(t == found)
    end
    if found.key == "profiles" and RefreshProfileList then RefreshProfileList() end
end

local function AddTab(key, name, label, page)
    local tab = CreateFrame("Button", name, panel, "PanelTabButtonTemplate")
    if #TABS == 0 then
        tab:SetPoint("TOPLEFT", 12, -(ME.HEADER + 4))
    elseif #TABS == 5 then
        -- a sixth tab starts a second row; the pages move down to make room
        tab:SetPoint("TOPLEFT", 12, -(ME.HEADER + 30))
        ME.tabRows = 2
    else
        tab:SetPoint("LEFT", TABS[#TABS].button, "RIGHT", 4, 0)
    end
    tab:SetText(label)
    tab.accent = Decor(tab, "OVERLAY")
    tab.accent:SetPoint("BOTTOMLEFT", 6, 2)
    tab.accent:SetPoint("BOTTOMRIGHT", -6, 2)
    tab.accent:SetHeight(2)
    tab.accent:SetShown(#TABS == 0)   -- the HUD page is the one shown at load
    skinned.tabs[#skinned.tabs + 1] = tab.accent
    tab:SetScript("OnClick", function() SelectTab(key) end)
    TABS[#TABS + 1] = { key = key, button = tab, page = page }
    if ME.tabRows == 2 then
        for _, t in ipairs(TABS) do
            t.page:ClearAllPoints()
            t.page:SetPoint("TOPLEFT", 8, -(ME.HEADER + 64))
            t.page:SetPoint("BOTTOMRIGHT", -8, 26)
        end
    end
    return tab
end
AddTab("hud",      "FRHW2TabHUD",      "HUD",      pageHUD)
AddTab("config",   "FRHW2TabConfig",   "Abilities", pageConfig)
AddTab("skins",    "FRHW2TabSkins",    "Skins",    pageSkins)
AddTab("profiles", "FRHW2TabProfiles", "Profiles", pageProfiles)

-----------------------------------------------------------------------
-- Grid overlay (drawn only while an item is being dragged)
-----------------------------------------------------------------------
gridFrame = CreateFrame("Frame", "ForeverWarriorHUD2Grid", UIParent)
gridFrame:SetAllPoints(UIParent)
gridFrame:SetFrameStrata("BACKGROUND")
gridFrame:Hide()
gridFrame.lines = {}
gridFrame.Update = function(self)
    if not db then return end
    local g = db.gridSize or 20
    if g < 4 then g = 4 end
    local w, h = UIParent:GetSize()
    local cx, cy = w / 2, h / 2
    local needed = math.ceil(w / g) + math.ceil(h / g) + 2
    for i = #self.lines + 1, needed do
        self.lines[i] = self:CreateTexture(nil, "BACKGROUND")
        self.lines[i]:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    end
    local n = 0
    for x = cx % g, w, g do
        n = n + 1
        local l = self.lines[n]
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", self, "TOPLEFT", x, 0)
        l:SetSize(1, h)
        l:SetVertexColor(1, 1, 1, 0.08)
        l:Show()
    end
    for y = cy % g, h, g do
        n = n + 1
        local l = self.lines[n]
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
        l:SetSize(w, 1)
        l:SetVertexColor(1, 1, 1, 0.08)
        l:Show()
    end
    for i = n + 1, #self.lines do self.lines[i]:Hide() end
end

-- Shared widget factories, parented to a given page. Sliders are compact:
-- the value sits inside the track and the label above it, so rows never
-- collide with the row below. The x / y / width passed in are only a first
-- placement; the page layout (ReflowFlow) positions every control from the
-- width that is actually available.
local function MakeCheck(parent, name, x, y, label, onClick)
    local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    cb:SetSize(22, 22)
    local t = _G[name .. "Text"]
    t:SetFontObject(GameFontHighlightSmall)
    t:ClearAllPoints()
    t:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    t:SetText(label)
    cb:SetScript("OnClick", onClick)
    cb._kind = "check"
    skinned.text[#skinned.text + 1] = t
    return cb
end

local function MakeSlider(parent, name, x, y, width, minV, maxV, step, label, onChanged)
    local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", x, y)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s:SetWidth(width)
    s:SetHeight(14)
    _G[name .. "Low"]:SetFontObject(GameFontHighlightSmall)
    _G[name .. "High"]:SetFontObject(GameFontHighlightSmall)
    _G[name .. "Text"]:SetFontObject(GameFontHighlightSmall)
    _G[name .. "Low"]:SetText(tostring(minV))
    _G[name .. "High"]:SetText(tostring(maxV))
    _G[name .. "Text"]:SetText(label)
    s.val = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.val:SetPoint("RIGHT", s, "RIGHT", 0, 0)
    -- skin-tinted strip behind the template's own track art
    s.track = Decor(s, "BACKGROUND")
    s.track:SetPoint("TOPLEFT", 0, -3)
    s.track:SetPoint("BOTTOMRIGHT", 0, 3)
    s:SetScript("OnValueChanged", function(self, v)
        if step >= 1 then v = math.floor(v + 0.5)
        else v = math.floor(v * 100 + 0.5) / 100 end
        s.val:SetText(tostring(v))
        -- a refresh or a reflow is moving the slider, not the user
        if suppress then return end
        onChanged(v)
    end)
    s._kind = "slider"
    skinned.sliders[#skinned.sliders + 1] = s
    skinned.text[#skinned.text + 1] = _G[name .. "Low"]
    skinned.text[#skinned.text + 1] = _G[name .. "High"]
    skinned.text[#skinned.text + 1] = _G[name .. "Text"]
    skinned.text[#skinned.text + 1] = s.val
    return s
end

local function MakeButton(parent, text, x, by, w, h, onClick, name)
    local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h)
    b:SetPoint("TOPLEFT", x, by)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    b._kind = "button"
    return b
end

-- One divider style for the whole window: 1 px, low alpha, full content width.
local function MakeDivider(parent)
    local t = Decor(parent, "ARTWORK")
    t:SetHeight(1)
    skinned.dividers[#skinned.dividers + 1] = t
    return t
end

-- Section header: accent-coloured text on a small tinted bar.
local function MakeHeader(parent, text)
    local h = {}
    h.bar = Decor(parent, "BACKGROUND")
    h.fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h.fs:SetText(text)
    skinned.headerBars[#skinned.headerBars + 1] = h.bar
    skinned.accentText[#skinned.accentText + 1] = h.fs
    return h
end

-----------------------------------------------------------------------
-- Responsive layout
-----------------------------------------------------------------------
-- 1.8.0 placed every control at a fixed x offset inside a 430 px scroll
-- child, so widening the window left dead space and narrowing it pushed the
-- right column under the scrollbar. Now each scrolling page is a "flow": a
-- list of rows that is laid out again from the scroll frame's width whenever
-- that width changes. Two columns and a gutter are derived from the width.
local LAYOUT = {
    pad = 6,            -- left / right margin inside the scroll child
    gutter = 20,        -- space between the two columns
    minWidth = 340,     -- never lay out narrower than this (the panel stops at 430)
    scrollGutter = 26,  -- strip to the right of a scroll frame that holds its scrollbar
    pageInset = 16,     -- pages are inset 8 px from the panel on each side
    check = 24, slider = 28, header = 24, divider = 8, note = 26,   -- row heights
    headerCheck = 64,   -- room at the right of a section header for its toggle
}

local function Columns(width)
    local colW = math.floor((width - 2 * LAYOUT.pad - LAYOUT.gutter) / 2)
    return LAYOUT.pad, LAYOUT.pad + colW + LAYOUT.gutter, colW
end

-- Width available to a scroll child. The scroll frame is anchored on two
-- corners, so its width follows the panel; if the client has not resolved
-- that rectangle yet (it can report 0 before the first layout pass) fall back
-- to the panel's own explicit width.
local function ScrollWidth(scroll)
    local w = scroll:GetWidth()
    if not w or w <= 0 then
        w = panel:GetWidth() - LAYOUT.pageInset - LAYOUT.scrollGutter
    end
    if w < LAYOUT.minWidth then w = LAYOUT.minWidth end
    return math.floor(w)
end

-- A scroll frame whose scrollbar lives in its own gutter. The frame stops
-- scrollGutter px short of the page edge and the bar is pinned inside that
-- strip, so the scroll child can be exactly as wide as the scroll frame
-- without anything sitting under the bar.
local function MakeScroll(name, page, top)
    local scroll = CreateFrame("ScrollFrame", name, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, top)
    scroll:SetPoint("BOTTOMRIGHT", -LAYOUT.scrollGutter, 4)
    local child = CreateFrame("Frame", nil, scroll)
    scroll:SetScrollChild(child)
    local bar = _G[name .. "ScrollBar"] or scroll.ScrollBar
    if bar and bar.ClearAllPoints then
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, -16)
        bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 16)
    end
    local gutter = Decor(page, "BACKGROUND")
    gutter:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0)
    gutter:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 4)
    skinned.gutters[#skinned.gutters + 1] = gutter
    scroll:HookScript("OnSizeChanged", function() if ReflowAll then ReflowAll() end end)
    return scroll, child
end

local FLOWS = {}
local function NewFlow(scroll, child)
    local flow = { scroll = scroll, child = child, rows = {} }
    FLOWS[#FLOWS + 1] = flow
    return flow
end
-- Row kinds: a pair of controls (left / right column, optionally two half
-- width buttons sharing the left column), a section header with its toggle,
-- a divider, or a full-width note.
local function Row(flow, h, left, right, left2)
    flow.rows[#flow.rows + 1] = { h = h, left = left, right = right, left2 = left2 }
end
local function HeaderRow(flow, text, check)
    flow.rows[#flow.rows + 1] = { h = LAYOUT.header, header = MakeHeader(flow.child, text), check = check }
end
local function DividerRow(flow)
    flow.rows[#flow.rows + 1] = { h = LAYOUT.divider, divider = MakeDivider(flow.child) }
end
local function NoteRow(flow, text)
    local fs = flow.child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    skinned.text[#skinned.text + 1] = fs
    flow.rows[#flow.rows + 1] = { h = LAYOUT.note, note = fs }
end

local function PlaceCell(w, x, y, width, rowH)
    w:ClearAllPoints()
    if w._kind == "slider" then
        w:SetPoint("TOPLEFT", x, y - 12)   -- 12 px above the track for the label
        w:SetWidth(width)
    elseif w._kind == "button" then
        w:SetPoint("TOPLEFT", x, y - math.floor((rowH - 22) / 2))
        w:SetWidth(width)
    else
        w:SetPoint("TOPLEFT", x, y - math.floor((rowH - 22) / 2))
    end
end

local function ReflowFlow(flow, width)
    local lx, rx, colW = Columns(width)
    local full = width - 2 * LAYOUT.pad
    local y = -4
    for i = 1, #flow.rows do
        local row = flow.rows[i]
        if row.header then
            row.header.bar:ClearAllPoints()
            row.header.bar:SetPoint("TOPLEFT", lx, y - 1)
            row.header.bar:SetSize(full, 18)
            row.header.fs:ClearAllPoints()
            row.header.fs:SetPoint("TOPLEFT", lx + 6, y - 4)
            if row.check then
                row.check:ClearAllPoints()
                row.check:SetPoint("TOPLEFT", lx + full - LAYOUT.headerCheck, y + 1)
            end
        elseif row.divider then
            row.divider:ClearAllPoints()
            row.divider:SetPoint("TOPLEFT", lx, y - 4)
            row.divider:SetSize(full, 1)
        elseif row.note then
            row.note:ClearAllPoints()
            row.note:SetPoint("TOPLEFT", lx, y - 2)
            row.note:SetWidth(full)
        else
            if row.left2 then
                local half = math.floor((colW - 4) / 2)
                PlaceCell(row.left, lx, y, half, row.h)
                PlaceCell(row.left2, lx + half + 4, y, half, row.h)
            elseif row.left then
                PlaceCell(row.left, lx, y, colW, row.h)
            end
            if row.right then PlaceCell(row.right, rx, y, colW, row.h) end
        end
        y = y - row.h
    end
    flow.child:SetSize(width, -y + 8)
    flow.width = width
end

-- ============================ HUD tab ============================
-- HUD tab content sits in a scroll frame too, so a resized-small panel still
-- reaches every control.
local hudScroll, hudChild = MakeScroll("FRHW2HudScroll", pageHUD, -4)
local hudFlow = NewFlow(hudScroll, hudChild)

local showCB = MakeCheck(hudChild, "FRHW2ShowCB", 12, -6, "Show HUD", function(self)
    db.shown = self:GetChecked() and true or false
    ApplyAll()
end)
local lockCB = MakeCheck(hudChild, "FRHW2LockCB", 120, -6, "Lock", function(self)
    db.locked = self:GetChecked() and true or false
end)
local autoCB = MakeCheck(hudChild, "FRHW2AutoCB", 220, -6, "Auto-hide combo at 0", function(self)
    db.autoHide = self:GetChecked() and true or false
end)
local autoOOC = MakeCheck(hudChild, "FRHW2AutoOOCCB", 12, -6, "Auto-hide out of combat", function(self)
    db.autoHideOOC = self:GetChecked() and true or false
    ApplyAll()
end)
local snapCB = MakeCheck(hudChild, "FRHW2SnapCB", 12, -34, "Snap items to grid", function(self)
    db.gridSnap = self:GetChecked() and true or false
end)
local stickyCB = MakeCheck(hudChild, "FRHW2StickyCB", 200, -34, "Stick items together", function(self)
    db.sticky = self:GetChecked() and true or false
end)
local gridSlider = MakeSlider(hudChild, "FRHW2GridSlider", 240, -34, 190, 8, 64, 1, "Grid size", function(v)
    db.gridSize = v
end)

Row(hudFlow, LAYOUT.check, showCB, lockCB)
Row(hudFlow, LAYOUT.check, autoCB, autoOOC)
Row(hudFlow, LAYOUT.check, snapCB, stickyCB)
Row(hudFlow, LAYOUT.slider, gridSlider)
DividerRow(hudFlow)

-- Swing timer options. All of them live in db.elements.swing next to the
-- bar's position and size; the widgets are kept in one table so the refresh
-- code does not need a local per control.
local swingUI = {}
local function BuildSwingOptions(flow)
    local function cfg() return db.elements.swing end
    local function apply() ApplyElement("swing") end
    local function Check(name, label, field)
        return MakeCheck(hudChild, name, 0, 0, label, function(self)
            cfg()[field] = self:GetChecked() and true or false
            apply()
        end)
    end
    local function Slider(name, minV, maxV, step, label, field)
        return MakeSlider(hudChild, name, 0, 0, 190, minV, maxV, step, label, function(v)
            cfg()[field] = v
            apply()
        end)
    end
    -- Moving a colour slider means "I want my own colour", so it also turns
    -- the skin colour off; otherwise the sliders would appear to do nothing.
    local function Colour(name, label, field)
        return MakeSlider(hudChild, name, 0, 0, 190, 0, 1, 0.05, label, function(v)
            cfg()[field] = v
            cfg().useSkinColor = false
            swingUI.skinCB:SetChecked(false)
            apply()
        end)
    end

    swingUI.skinCB = Check("FRHW2SW_SkinColor", "Use skin colour", "useSkinColor")
    swingUI.bgAlpha = Slider("FRHW2SW_BgAlpha", 0, 1, 0.05, "Background opacity", "bgAlpha")
    swingUI.r = Colour("FRHW2SW_R", "Bar red", "r")
    swingUI.g = Colour("FRHW2SW_G", "Bar green", "g")
    swingUI.b = Colour("FRHW2SW_B", "Bar blue", "b")
    swingUI.sparkSize = Slider("FRHW2SW_SparkSize", 8, 40, 1, "Spark size", "sparkSize")
    swingUI.sparkCB = Check("FRHW2SW_Spark", "Spark", "spark")
    swingUI.flashCB = Check("FRHW2SW_Flash", "Ready flash (last 0.2 s)", "flash")
    swingUI.textCB = Check("FRHW2SW_Text", "Text", "text")
    swingUI.textBtn = MakeButton(hudChild, SWING_TEXT_LABEL.elapsed, 0, 0, 190, 22, function()
        local cur, nextMode = cfg().textMode, SWING_TEXT_ORDER[1]
        for i, mode in ipairs(SWING_TEXT_ORDER) do
            if mode == cur then nextMode = SWING_TEXT_ORDER[i % #SWING_TEXT_ORDER + 1] end
        end
        cfg().textMode = nextMode
        apply(); FRHW2_RefreshPanel()
    end, "FRHW2SW_TextMode")
    swingUI.ticksCB = Check("FRHW2SW_Ticks", "Ticks", "ticks")
    swingUI.tickCount = Slider("FRHW2SW_TickCount", 1, 10, 1, "Tick count", "tickCount")
    swingUI.sourceBtn = MakeButton(hudChild, "Source: PLAYER_SWING", 0, 0, 190, 22, function()
        cfg().source = (cfg().source == "poll") and "event" or "poll"
        apply(); FRHW2_RefreshPanel()
    end, "FRHW2SW_Source")
    swingUI.resetCB = Check("FRHW2SW_ResetOnTarget", "Reset on target change", "resetOnTarget")
    swingUI.manualCB = Check("FRHW2SW_Manual", "Manual speed override", "manual")
    swingUI.manualSpeed = Slider("FRHW2SW_ManualSpeed", 0.5, 4, 0.05, "Manual speed (s)", "manualSpeed")

    Row(flow, LAYOUT.slider, swingUI.skinCB, swingUI.bgAlpha)
    Row(flow, LAYOUT.slider, swingUI.r, swingUI.g)
    Row(flow, LAYOUT.slider, swingUI.b, swingUI.sparkSize)
    Row(flow, LAYOUT.check, swingUI.sparkCB, swingUI.flashCB)
    Row(flow, LAYOUT.slider, swingUI.textCB, swingUI.textBtn)
    Row(flow, LAYOUT.slider, swingUI.ticksCB, swingUI.tickCount)
    Row(flow, LAYOUT.slider, swingUI.sourceBtn, swingUI.resetCB)
    Row(flow, LAYOUT.slider, swingUI.manualCB, swingUI.manualSpeed)
end

-- Energy regen options. The bar is its own element (position, size, opacity,
-- scale and X/Y are in the shared element block above); these two are what the
-- bar measures and whether it prints the number.
local regenUI = {}
local function BuildRegenOptions(flow)
    local function cfg() return db.elements.regen end
    local function apply() ApplyElement("regen") end
    regenUI.rateCB = MakeCheck(hudChild, "FRHW2REG_Rate", 0, 0, "Show rage / sec", function(self)
        cfg().showRate = self:GetChecked() and true or false
        apply()
    end)
    regenUI.maxSlider = MakeSlider(hudChild, "FRHW2REG_Max", 0, 0, 190, 5, 60, 1, "Full at (rage/s)", function(v)
        cfg().regenMax = v
        apply()
    end)
    Row(flow, LAYOUT.check, regenUI.rateCB, regenUI.maxSlider)
end

local ELEMENT_INFO = {
    { key = "energy", label = "Rage bar", wmin = 60, wmax = 400, hmin = 4, hmax = 40 },
    { key = "regen",  label = "Rage regen", wmin = 60, wmax = 400, hmin = 4, hmax = 40 },
    { key = "swing",  label = "Swing timer",  wmin = 60, wmax = 400, hmin = 4, hmax = 40 },
    { key = "combo",  label = "Combo points", wmin = 4,  wmax = 60,  hmin = 4, hmax = 60 },
    { key = "trail",  label = "Recent actions", wmin = 10, wmax = 60, hmin = 10, hmax = 60 },
}
-- Width, height and opacity only: place, size and rotation are done with the
-- mouse on the item itself.
local elemCB, elemW, elemH, elemA = {}, {}, {}, {}
for _, info in ipairs(ELEMENT_INFO) do
    local key = info.key
    elemCB[key] = MakeCheck(hudChild, "FRHW2CB_" .. key, 340, 0, "Show", function(self)
        db.elements[key].enabled = self:GetChecked() and true or false
        ApplyElement(key)
    end)
    elemW[key] = MakeSlider(hudChild, "FRHW2W_" .. key, 12,  0, 190, info.wmin, info.wmax, 1, "Width", function(v)
        db.elements[key].w = v; ApplyElement(key)
    end)
    elemH[key] = MakeSlider(hudChild, "FRHW2H_" .. key, 240, 0, 190, info.hmin, info.hmax, 1, "Height", function(v)
        db.elements[key].h = v; ApplyElement(key)
    end)
    elemA[key] = MakeSlider(hudChild, "FRHW2A_" .. key, 12,  0, 190, 0.1, 1, 0.05, "Opacity", function(v)
        db.elements[key].alpha = v; ApplyElement(key)
    end)
    HeaderRow(hudFlow, info.label, elemCB[key])
    Row(hudFlow, LAYOUT.slider, elemW[key], elemH[key])
    if key == "energy" then
        -- the number on the bar has its own switch, next to the bar's options
        ME.valueCB = MakeCheck(hudChild, "FRHW2EnergyText", 0, 0, "Show the value as text", function(self)
            db.elements.energy.showText = self:GetChecked() and true or false
            ApplyElement("energy")
        end)
        Row(hudFlow, LAYOUT.slider, elemA[key], ME.valueCB)
    else
        Row(hudFlow, LAYOUT.slider, elemA[key])
    end
    if key == "swing" then BuildSwingOptions(hudFlow) end
    if key == "regen" then BuildRegenOptions(hudFlow) end
    ME.Mark(key, hudFlow, hudChild)   -- where this element's later rows go (2 build: its text options)
    DividerRow(hudFlow)
end

local function ResetToDefaults()
    -- saved profiles are deliberately kept: only the live configuration resets
    local kept = type(db.profiles) == "table" and db.profiles or {}
    local keptSchemes = type(db.schemes) == "table" and db.schemes or {}
    for k in pairs(db) do db[k] = nil end
    for k, v in pairs(DEFAULTS) do db[k] = (type(v) == "table") and DeepCopy(v) or v end
    db.profiles = kept
    db.schemes = keptSchemes
    ApplySkin(db.skin)
    UF.Apply()
    MP.Apply()
    ApplyAll(); FRHW2_RefreshPanel()
    if RefreshProfileList then RefreshProfileList() end
end
FRHW2_ResetToDefaults = ResetToDefaults
StaticPopupDialogs["FRHW2_CONFIRM_RESET"] = {
    text = "Reset ForeverWarriorHUD2 to defaults? Every position, size, scale, opacity, toggle, swing option, the countdown text and the skin go back to their original values. Saved profiles are kept.",
    button1 = YES, button2 = NO,
    OnAccept = function() ResetToDefaults() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
NoteRow(hudFlow, "Place, size and turn every item with the mouse on the item itself. The Help tab shows how.")

-- ========================== Config tab ==========================
local cfgScroll, cfgChild = MakeScroll("FRHW2ConfigScroll", pageConfig, -4)
local cfgFlow = NewFlow(cfgScroll, cfgChild)

NoteRow(cfgFlow, "Switch an ability on, then place it with the mouse: hold CTRL and the left button on its icon.")

-- One toggle for the countdown numbers on every icon. Kept in a table so the
-- main chunk does not grow another local.
local cdUI = {}
cdUI.cb = MakeCheck(cfgChild, "FRHW2CFG_CooldownText", 6, 0, "Show countdown numbers on the icons", function(self)
    db.cooldownText = self:GetChecked() and true or false
    if cdUI.refresh then cdUI.refresh() end
end)
HeaderRow(cfgFlow, "Notifications on every icon")
Row(cfgFlow, LAYOUT.check, cdUI.cb)
ME.Mark("timer", cfgFlow, cfgChild)

-- What the icons tell you, one switch each.
ME.notifyCB = {}
for _, n in ipairs(ME.NOTIFY) do
    local key = n.key
    ME.notifyCB[key] = MakeCheck(cfgChild, "FRHW2N_" .. key, 6, 0, n.label, function(self)
        db.notify[key] = self:GetChecked() and true or false
        for _, b in pairs(spellIcons) do b._cdStart = nil end   -- redraw the sweeps
        if cdUI.refresh then cdUI.refresh() end
    end)
    -- one to a row: the labels are sentences
    Row(cfgFlow, LAYOUT.check, ME.notifyCB[key])
end
DividerRow(cfgFlow)

local cfgCB, cfgA = {}, {}
for _, a in ipairs(ABILITIES) do
    local key = a.key
    cfgCB[key] = MakeCheck(cfgChild, "FRHW2CFGCB_" .. key, 340, 0, "On", function(self)
        db.spells[key].enabled = self:GetChecked() and true or false
        ApplySpell(key)
    end)
    cfgA[key] = MakeSlider(cfgChild, "FRHW2CFGA_" .. key, 6,   0, 190, 0.1, 1, 0.05, "Opacity", function(v)
        db.spells[key].alpha = v; ApplySpell(key)
    end)
    HeaderRow(cfgFlow, a.name, cfgCB[key])
    Row(cfgFlow, LAYOUT.slider, cfgA[key])
    -- typeface and number size of this ability's countdown (2 build)
    TXT.itemFont = TXT.itemFont or {}
    TXT.itemSize = TXT.itemSize or {}
    TXT.itemFont[key] = MakeButton(cfgChild, "Font", 6, 0, 190, 22, function(self)
        TXT.OpenPicker(self, db.spells[key].font, true, function(font)
            db.spells[key].font = font; TXT.Apply(); TXT.Refresh()
        end)
    end, "FRHW2CFGF_" .. key)
    TXT.itemSize[key] = MakeSlider(cfgChild, "FRHW2CFGFS_" .. key, 230, 0, 190, 0, 40, 1, "Number size (0 = Text tab)", function(v)
        db.spells[key].fontSize = (v >= 6) and v or nil; TXT.Apply()
    end)
    Row(cfgFlow, LAYOUT.slider, TXT.itemFont[key], TXT.itemSize[key])
    -- a thin divider under each spell keeps the list readable
    DividerRow(cfgFlow)
end

RefreshConfig = function()
    cdUI.cb:SetChecked(db.cooldownText)
    for _, n in ipairs(ME.NOTIFY) do ME.notifyCB[n.key]:SetChecked(db.notify[n.key]) end
    for _, a in ipairs(ABILITIES) do
        local key = a.key
        cfgCB[key]:SetChecked(db.spells[key].enabled)
        cfgA[key]:SetValue(db.spells[key].alpha or 1)
    end
end

-- =========================== Skins tab ===========================
-- A preview strip of the active palette, then a scrolling grid of 40 swatch
-- buttons. Each swatch is painted with its own skin, so the grid doubles as
-- the catalogue. Clicking one applies it.
local skinUI = { chips = {}, buttons = {} }
skinUI.title = pageSkins:CreateFontString(nil, "OVERLAY", "GameFontNormal")
skinUI.title:SetPoint("TOPLEFT", 6, -60)
-- Menu artwork, next to the skins it is drawn with
ME.artDD = ME.Dropdown(pageSkins, "FRHW2ArtDD", "Menu artwork", {
    { value = "high", text = "High resolution" },
    { value = "low",  text = "Low resolution" },
    { value = "off",  text = "Off" },
}, function() return db and db.art or "high" end, function(v) db.art = v; ME.ApplyArt() end)
ME.artDD:SetPoint("TOPLEFT", 6, -4)
ME.bannerDD = ME.Dropdown(pageSkins, "FRHW2BannerDD", "Header picture", {
    { value = "a", text = "Painted" },
    { value = "b", text = "Alternate" },
}, function() return db and db.artBanner or "a" end, function(v) db.artBanner = v; ME.ApplyArt() end)
ME.bannerDD:SetPoint("TOPLEFT", 202, -4)
ME.artNote = pageSkins:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
ME.artNote:SetPoint("TOPLEFT", 202, -9)
ME.artNote:SetText("")
-- Custom colours: tick to use them, click a colour chip below to change it,
-- and keep a set under a name.
ME.customCB = MakeCheck(pageSkins, "FRHW2CustomCB", 6, -30, "Custom colours", function(self)
    db.customOn = self:GetChecked() and true or false
    ApplySkin()
end)
ME.schemeBox = CreateFrame("EditBox", "FRHW2SchemeBox", pageSkins, "InputBoxTemplate")
ME.schemeBox:SetSize(92, 20)
ME.schemeBox:SetPoint("TOPLEFT", 126, -31)
ME.schemeBox:SetAutoFocus(false)
ME.schemeBox:SetMaxLetters(32)
ME.schemeBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
ME.schemeBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
local function SchemeSay(ok, msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD2|r " .. tostring(msg))
    return ok
end
ME.schemeSave = MakeButton(pageSkins, "Save", 224, -30, 46, 22, function()
    SchemeSay(ME.SaveScheme(ME.schemeBox:GetText()))
end, "FRHW2SchemeSave")
ME.schemeLoad = MakeButton(pageSkins, "Load", 272, -30, 46, 22, function(self)
    ME.OpenList(self, ME.SchemeNames(), function(name)
        if SchemeSay(ME.LoadScheme(name)) then ME.schemeBox:SetText(name); FRHW2_RefreshPanel() end
    end)
end, "FRHW2SchemeLoad")
ME.schemeDel = MakeButton(pageSkins, "Delete", 320, -30, 56, 22, function()
    SchemeSay(ME.DeleteScheme(ME.schemeBox:GetText()))
end, "FRHW2SchemeDelete")
skinned.accentText[#skinned.accentText + 1] = skinUI.title

do
    local parts = {
        { "bar", "bar" }, { "swing", "swing" }, { "barBg", "bg" }, { "spark", "spark" },
        { "text", "text" }, { "accent", "accent" }, { "border", "border" },
        { "panel", "panel" }, { "combo", "combo" }, { "iconEdge", "edge" },
    }
    for i, part in ipairs(parts) do
        local chip = { field = part[1] }
        -- a thin light frame keeps dark colours visible on a dark window
        chip.edge = Decor(pageSkins, "BORDER")
        chip.tex = Decor(pageSkins, "ARTWORK")
        chip.label = pageSkins:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        chip.label:SetText(part[2])
        if chip.label.SetWordWrap then chip.label:SetWordWrap(false) end
        skinned.text[#skinned.text + 1] = chip.label
        chip.btn = CreateFrame("Button", "FRHW2Chip_" .. part[1], pageSkins)
        chip.btn:SetScript("OnClick", function(self)
            local key = part[1]
            local p, c = ME.PART[key], ME.current[key]
            ME.OpenWheel(self, p.label, c[1], c[2], c[3], c[4], p.alpha, function(r, g, b, a)
                ME.SetPart(key, r, g, b, a)
                ME.customCB:SetChecked(true)
            end)
        end)
        chip.btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(ME.PART[part[1]].label, 1, 1, 1)
            GameTooltip:AddLine("Click to choose a colour" .. (ME.PART[part[1]].alpha and " and its opacity" or ""), nil, nil, nil, true)
            GameTooltip:Show()
        end)
        chip.btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        skinUI.chips[i] = chip
    end
end
skinUI.rule = MakeDivider(pageSkins)
skinUI.scroll, skinUI.child = MakeScroll("FRHW2SkinScroll", pageSkins, -114)

do
    local swatchParts = { "bar", "swing", "combo", "accent", "text", "spark" }
    for i, skin in ipairs(SKINS) do
        local b = CreateFrame("Button", "FRHW2SkinBtn_" .. skin.key, skinUI.child, "BackdropTemplate")
        b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                        insets = { left = 1, right = 1, top = 1, bottom = 1 } })
        b:SetBackdropColor(skin.panel[1], skin.panel[2], skin.panel[3], 1)
        b:SetBackdropBorderColor(skin.border[1], skin.border[2], skin.border[3], 1)
        b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.name:SetPoint("TOPLEFT", 5, -5)
        b.name:SetText(skin.name)
        b.name:SetTextColor(skin.text[1], skin.text[2], skin.text[3], 1)
        b.chips = {}
        for j, field in ipairs(swatchParts) do
            local c = Decor(b, "ARTWORK")
            c:SetVertexColor(skin[field][1], skin[field][2], skin[field][3], 1)
            b.chips[j] = c
        end
        -- shown on the active skin only
        b.sel = Decor(b, "OVERLAY")
        b.sel:SetPoint("TOPLEFT", 1, -1)
        b.sel:SetPoint("TOPRIGHT", -1, -1)
        b.sel:SetHeight(2)
        b.sel:SetVertexColor(skin.accent[1], skin.accent[2], skin.accent[3], 1)
        b.sel:Hide()
        b.skin = skin
        b:SetScript("OnClick", function(self) FRHW2_SetSkin(self.skin.key) end)
        skinUI.buttons[i] = b
    end
end

-- Preview strip from the page width, grid from the scroll frame width: as many
-- columns as fit at the minimum cell width, then the cells stretch to fill.
local function ReflowSkins(width)
    local pad = LAYOUT.pad
    local pageW = width + LAYOUT.scrollGutter
    local n, gap = #skinUI.chips, 3
    local chipW = math.floor((pageW - 2 * pad - (n - 1) * gap) / n)
    for i, chip in ipairs(skinUI.chips) do
        local x = pad + (i - 1) * (chipW + gap)
        chip.edge:ClearAllPoints()
        chip.edge:SetPoint("TOPLEFT", x - 1, -77)
        chip.edge:SetSize(chipW + 2, 16)
        chip.btn:ClearAllPoints()
        chip.btn:SetPoint("TOPLEFT", x - 1, -77)
        chip.btn:SetSize(chipW + 2, 16)
        chip.tex:ClearAllPoints()
        chip.tex:SetPoint("TOPLEFT", x, -78)
        chip.tex:SetSize(chipW, 14)
        chip.label:ClearAllPoints()
        chip.label:SetPoint("TOPLEFT", x, -95)
        chip.label:SetWidth(chipW)
    end
    skinUI.rule:ClearAllPoints()
    skinUI.rule:SetPoint("TOPLEFT", pad, -110)
    skinUI.rule:SetSize(pageW - 2 * pad, 1)

    local cellMin, cellH, cellGap = 118, 36, 6
    local cols = math.floor((width - 2 * pad + cellGap) / (cellMin + cellGap))
    if cols < 1 then cols = 1 end
    local cellW = math.floor((width - 2 * pad - (cols - 1) * cellGap) / cols)
    local rows = math.ceil(#skinUI.buttons / cols)
    for i, b in ipairs(skinUI.buttons) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", pad + col * (cellW + cellGap), -(4 + row * (cellH + cellGap)))
        b:SetSize(cellW, cellH)
        local cw = math.floor((cellW - 10 - (#b.chips - 1) * 2) / #b.chips)
        for j, c in ipairs(b.chips) do
            c:ClearAllPoints()
            c:SetPoint("BOTTOMLEFT", 5 + (j - 1) * (cw + 2), 5)
            c:SetSize(cw, 8)
        end
    end
    skinUI.child:SetSize(width, 8 + rows * (cellH + cellGap))
    skinUI.width = width
end

-- Lay every scrolling page out again. Runs once at build time, on every size
-- change of the panel or of a scroll frame, and at login. A page whose width
-- did not change is skipped, so dragging the window taller costs nothing.
ReflowAll = function(force)
    local was = suppress
    suppress = true
    for _, flow in ipairs(FLOWS) do
        local w = ScrollWidth(flow.scroll)
        if force or flow.width ~= w then ReflowFlow(flow, w) end
    end
    local sw = ScrollWidth(skinUI.scroll)
    if force or skinUI.width ~= sw then ReflowSkins(sw) end
    suppress = was
end
ReflowAll(true)

-- ========================= Profiles tab =========================
-- A profile is a plain copy of CONFIG_KEYS taken out of db. The copies live in
-- db.profiles, which ResetToDefaults and LoadProfile never write to, so a saved
-- setup survives both. Nothing here runs unless the options window is open.
local MAX_PROFILE_NAME = 32
local MAX_PROFILES = 40

local function TrimName(s)
    s = tostring(s or "")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    s = s:gsub("[%c]", "")
    if #s > MAX_PROFILE_NAME then s = s:sub(1, MAX_PROFILE_NAME) end
    return s
end

local function CaptureConfig()
    local out = {}
    for _, k in ipairs(CONFIG_KEYS) do
        local v = db[k]
        out[k] = (type(v) == "table") and DeepCopy(v) or v
    end
    return out
end

-- Numbers coming back from SavedVariables can be strings or out of range if the
-- file was hand-edited; clamp instead of trusting them.
local function Num(v, minV, maxV, fallback)
    v = tonumber(v)
    if not v then return fallback end
    if v ~= v then return fallback end          -- NaN
    if minV and v < minV then v = minV end
    if maxV and v > maxV then v = maxV end
    return v
end

-- The swing timer's own options. Used when a profile is applied and once at
-- login, so a 1.8.0 profile (which has none of these fields) or a hand-edited
-- file ends up with valid values instead of nils or strings.
local function ClampSwing(e, s, def)
    e.useSkinColor  = s.useSkinColor ~= false
    e.r             = Num(s.r, 0, 1, def.r)
    e.g             = Num(s.g, 0, 1, def.g)
    e.b             = Num(s.b, 0, 1, def.b)
    e.bgAlpha       = Num(s.bgAlpha, 0, 1, def.bgAlpha)
    e.spark         = s.spark ~= false
    e.sparkSize     = Num(s.sparkSize, 8, 40, def.sparkSize)
    e.text          = s.text ~= false
    e.textMode      = SWING_TEXT_LABEL[s.textMode] and s.textMode or def.textMode
    e.ticks         = s.ticks == true
    e.tickCount     = math.floor(Num(s.tickCount, 1, 10, def.tickCount) + 0.5)
    e.flash         = s.flash == true
    e.source        = (s.source == "poll") and "poll" or "event"
    e.manual        = s.manual == true
    e.manualSpeed   = Num(s.manualSpeed, 0.5, 4, def.manualSpeed)
    e.resetOnTarget = s.resetOnTarget == true
end

local function ApplyConfig(src)
    if type(src) ~= "table" then return false end
    db.baseX       = Num(src.baseX, -2000, 2000, DEFAULTS.baseX)
    db.baseY       = Num(src.baseY, -2000, 2000, DEFAULTS.baseY)
    db.scale       = Num(src.scale, 0.5, 2.5, DEFAULTS.scale)
    db.gridSize    = Num(src.gridSize, 8, 64, DEFAULTS.gridSize)
    db.shown       = src.shown ~= false
    db.locked      = src.locked == true
    db.autoHide    = src.autoHide ~= false
    db.autoHideOOC = src.autoHideOOC == true
    db.gridSnap    = src.gridSnap ~= false
    db.sticky      = src.sticky ~= false
    db.cooldownText = src.cooldownText ~= false
    TXT.Clamp(src.text)
    UF.Clamp(src.frames)
    MP.Clamp(src.map)
    db.orientation = "h"   -- kept for old profiles only: every item has its own rotation now
    ME.ClampNotify(src.notify)
    ME.ClampCustom(src.custom, src.customOn)
    -- an unknown skin name (older profile, renamed skin, hand edit) is the default look
    db.skin        = SKIN_BY_KEY[src.skin] and src.skin or SKIN_DEFAULT
    -- elements
    if type(db.elements) ~= "table" then db.elements = {} end
    for key, def in pairs(DEFAULTS.elements) do
        local s = type(src.elements) == "table" and src.elements[key] or nil
        if type(db.elements[key]) ~= "table" then db.elements[key] = DeepCopy(def) end
        local e = db.elements[key]
        if type(s) == "table" then
            e.enabled = s.enabled ~= false
            e.x       = Num(s.x, -2000, 2000, def.x)
            e.y       = Num(s.y, -2000, 2000, def.y)
            e.w       = Num(s.w, 4, 600, def.w)
            e.h       = Num(s.h, 4, 600, def.h)
            e.alpha   = Num(s.alpha, 0.05, 1, def.alpha)
            e.scale   = Num(s.scale, 0.2, 4, def.scale)
            -- a profile from before 2.0 has no rotation: "vertical" becomes a quarter turn
            if s.rot == nil and src.orientation == "v" then e.rot = 90 else e.rot = ME.Norm(s.rot, false) end
            if key == "energy" then e.showText = s.showText ~= false end
            if key == "swing" then ClampSwing(e, s, def) end
            if key == "regen" then
                e.regenMax = Num(s.regenMax, 5, 60, def.regenMax)
                e.showRate = s.showRate ~= false
            end
        else
            db.elements[key] = DeepCopy(def)
        end
    end
    -- spells
    if type(db.spells) ~= "table" then db.spells = {} end
    for key, def in pairs(DEFAULTS.spells) do
        local s = type(src.spells) == "table" and src.spells[key] or nil
        if type(db.spells[key]) ~= "table" then db.spells[key] = DeepCopy(def) end
        local e = db.spells[key]
        if type(s) == "table" then
            e.enabled = s.enabled == true
            e.x       = Num(s.x, -2000, 2000, def.x)
            e.y       = Num(s.y, -2000, 2000, def.y)
            e.w       = Num(s.w, 6, 200, def.w)
            e.h       = Num(s.h, 6, 200, def.h)
            e.rot     = ME.Norm(s.rot, true)
            e.alpha   = Num(s.alpha, 0.05, 1, def.alpha)
            e.scale   = Num(s.scale, 0.2, 4, def.scale)
            TXT.ClampItem(e, s)
        else
            db.spells[key] = DeepCopy(def)
        end
    end
    ApplySkin(db.skin)
    UF.Apply()
    MP.Apply()
    ApplyAll()
    FRHW2_RefreshPanel()
    return true
end

local function ProfileNames()
    local names = {}
    if type(db) == "table" and type(db.profiles) == "table" then
        for name in pairs(db.profiles) do
            if type(name) == "string" then names[#names + 1] = name end
        end
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

local function ProfileCount()
    return #ProfileNames()
end

local function SaveProfile(name)
    name = TrimName(name)
    if name == "" then return false, "Type a profile name first." end
    if type(db.profiles) ~= "table" then db.profiles = {} end
    if db.profiles[name] == nil and ProfileCount() >= MAX_PROFILES then
        return false, "Profile limit reached (" .. MAX_PROFILES .. "). Delete one first."
    end
    db.profiles[name] = { version = FRHW2_VERSION, savedAt = time and time() or nil, config = CaptureConfig() }
    return true, "Saved profile '" .. name .. "'."
end

local function LoadProfile(name)
    name = TrimName(name)
    local p = type(db.profiles) == "table" and db.profiles[name] or nil
    if type(p) ~= "table" or type(p.config) ~= "table" then
        return false, "No saved profile named '" .. name .. "'."
    end
    if not ApplyConfig(p.config) then return false, "Profile '" .. name .. "' is unreadable." end
    return true, "Loaded profile '" .. name .. "'."
end

local function DeleteProfile(name)
    name = TrimName(name)
    if type(db.profiles) ~= "table" or db.profiles[name] == nil then
        return false, "No saved profile named '" .. name .. "'."
    end
    db.profiles[name] = nil
    return true, "Deleted profile '" .. name .. "'."
end

local profileNameBox, profileStatus, profileScroll, profileChild
local profileRows = {}
local selectedProfile

local function SetStatus(msg)
    if profileStatus then profileStatus:SetText(msg or "") end
end

local function SelectProfile(name)
    selectedProfile = name
    RefreshProfileList()
end

RefreshProfileList = function()
    if not profileChild then return end
    local names = ProfileNames()
    if selectedProfile and not (type(db.profiles) == "table" and db.profiles[selectedProfile]) then
        selectedProfile = nil
    end
    local rowH = 20
    for i = 1, #names do
        local row = profileRows[i]
        if not row then
            row = CreateFrame("Button", nil, profileChild, "UIPanelButtonTemplate")
            row:SetSize(276, rowH - 2)
            row:SetScript("OnClick", function(self)
                SelectProfile(self.profileName)
            end)
            row.sel = row:CreateTexture(nil, "OVERLAY")
            row.sel:SetAllPoints(true)
            row.sel:SetTexture("Interface\\BUTTONS\\WHITE8X8")
            row.sel:SetVertexColor(0.2, 0.8, 1, 0.25)
            row.sel:Hide()
            profileRows[i] = row
        end
        row.profileName = names[i]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -((i - 1) * rowH))
        row:SetText(names[i])
        row.sel:SetShown(names[i] == selectedProfile)
        row:Show()
    end
    for i = #names + 1, #profileRows do profileRows[i]:Hide() end
    profileChild:SetSize(276, math.max(1, #names * rowH))
    if profileScroll then profileScroll:SetVerticalScroll(0) end
end

local function DoSave(name)
    local ok, msg = SaveProfile(name)
    SetStatus(msg)
    if ok then
        selectedProfile = TrimName(name)
        RefreshProfileList()
    end
end

local function RequestSave()
    if not EditMode() then return end
    local name = TrimName(profileNameBox and profileNameBox:GetText() or "")
    if name == "" then SetStatus("Type a profile name first.") return end
    if type(db.profiles) == "table" and db.profiles[name] ~= nil then
        FRHW2_PendingProfile = name
        StaticPopup_Show("FRHW2_CONFIRM_OVERWRITE", name)
    else
        DoSave(name)
    end
end

local function RequestLoad()
    if not EditMode() then return end
    if not selectedProfile then SetStatus("Select a saved profile first.") return end
    local ok, msg = LoadProfile(selectedProfile)
    SetStatus(msg)
    if ok and profileNameBox then profileNameBox:SetText(selectedProfile) end
end

local function RequestDelete()
    if not EditMode() then return end
    if not selectedProfile then SetStatus("Select a saved profile first.") return end
    FRHW2_PendingProfile = selectedProfile
    StaticPopup_Show("FRHW2_CONFIRM_DELETE", selectedProfile)
end

StaticPopupDialogs["FRHW2_CONFIRM_OVERWRITE"] = {
    text = "A profile named '%s' already exists. Overwrite it with the current setup?",
    button1 = YES, button2 = NO,
    OnAccept = function()
        local name = FRHW2_PendingProfile
        FRHW2_PendingProfile = nil
        if name then DoSave(name) end
    end,
    OnCancel = function() FRHW2_PendingProfile = nil end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
StaticPopupDialogs["FRHW2_CONFIRM_DELETE"] = {
    text = "Delete the saved profile '%s'? The HUD itself is not changed.",
    button1 = YES, button2 = NO,
    OnAccept = function()
        local name = FRHW2_PendingProfile
        FRHW2_PendingProfile = nil
        if name then
            local ok, msg = DeleteProfile(name)
            SetStatus(msg)
            if ok and selectedProfile == name then selectedProfile = nil end
            RefreshProfileList()
        end
    end,
    OnCancel = function() FRHW2_PendingProfile = nil end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local profNote = pageProfiles:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
profNote:SetPoint("TOPLEFT", 6, -4)
profNote:SetWidth(400)
profNote:SetJustifyH("LEFT")
profNote:SetText("Positions, sizes, opacity, visibility, grid, sticky, skin, countdown.")

local nameLabel = pageProfiles:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
nameLabel:SetPoint("TOPLEFT", 6, -28)
nameLabel:SetText("Name")

profileNameBox = CreateFrame("EditBox", "FRHW2ProfileNameBox", pageProfiles, "InputBoxTemplate")
profileNameBox:SetSize(212, 20)
profileNameBox:SetPoint("TOPLEFT", 40, -25)
profileNameBox:SetAutoFocus(false)
profileNameBox:SetMaxLetters(MAX_PROFILE_NAME)
profileNameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
profileNameBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    RequestSave()
end)

local saveBtn = MakeButton(pageProfiles, "Save", 254, -25, 56, 20, RequestSave)
saveBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Save profile", 1, 1, 1)
    GameTooltip:AddLine("Stores the current setup under the name on the left.", nil, nil, nil, true)
    GameTooltip:AddLine("Asks before replacing a name that already exists.", nil, nil, nil, true)
    GameTooltip:Show()
end)
saveBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

local listHeader = pageProfiles:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
listHeader:SetPoint("TOPLEFT", 6, -54)
listHeader:SetText("Saved profiles")

profileScroll = CreateFrame("ScrollFrame", "FRHW2ProfileScroll", pageProfiles, "UIPanelScrollFrameTemplate")
profileScroll:SetPoint("TOPLEFT", 6, -66)
profileScroll:SetPoint("BOTTOMRIGHT", pageProfiles, "BOTTOMLEFT", 290, 44)
profileChild = CreateFrame("Frame", nil, profileScroll)
profileChild:SetSize(276, 1)
profileScroll:SetScrollChild(profileChild)

local loadBtn = MakeButton(pageProfiles, "Load", 298, -66, 116, 22, RequestLoad)
local delBtn  = MakeButton(pageProfiles, "Delete", 298, -92, 116, 22, RequestDelete)

profileStatus = pageProfiles:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
profileStatus:SetPoint("TOPLEFT", 298, -120)
profileStatus:SetWidth(116)
profileStatus:SetJustifyH("LEFT")
profileStatus:SetText("")

local profHelp = pageProfiles:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
profHelp:SetPoint("BOTTOMLEFT", 6, 6)
profHelp:SetWidth(400)
profHelp:SetJustifyH("LEFT")
profHelp:SetText("Profiles are stored in SavedVariables and are not part of Reset to default. "
    .. "Loading a profile replaces the current setup; saved profiles themselves are never changed.")

-- the profiles page keeps its fixed layout; its labels still follow the skin
skinned.text[#skinned.text + 1] = profNote
skinned.text[#skinned.text + 1] = nameLabel
skinned.text[#skinned.text + 1] = listHeader
skinned.text[#skinned.text + 1] = profileStatus
skinned.text[#skinned.text + 1] = profHelp

-- ============================ Help tab ============================
-- How the interface works, in the window itself. Built with the same row
-- layout as the other pages, so it reflows with the window.
do
    local pageHelp = CreateFrame("Frame", nil, panel)
    pageHelp:SetPoint("TOPLEFT", 8, -(ME.HEADER + 38))
    pageHelp:SetPoint("BOTTOMRIGHT", -8, 26)
    pageHelp:Hide()
    local scroll, child = MakeScroll("FRHW2HelpScroll", pageHelp, -4)
    local flow = NewFlow(scroll, child)
    local function Para(text)
        NoteRow(flow, text)
        -- help lines are longer than option notes: three lines of room
        flow.rows[#flow.rows].h = 40
    end
    HeaderRow(flow, "Editing the HUD with the mouse")
    Para("This only works while this window is open and Lock (HUD tab) is off. Point at any bar or icon: it lights up and a tooltip names it.")
    Para("MOVE: hold CTRL, then hold the left mouse button on the item. It follows the cursor. Let go to drop it.")
    Para("SIZE: hold CTRL and roll the mouse wheel over the item. Up is bigger, down is smaller.")
    Para("TURN: hold CTRL, then hold the right mouse button on the item and drag around it. It stays as you leave it.")
    Para("STRAIGHTEN: double-click the right mouse button on the item. It goes back to its original orientation.")
    Para("Icons turn to any angle. Bars, combo points and the recent-actions row turn in quarter turns; their text stays upright.")
    DividerRow(flow)
    HeaderRow(flow, "Lining things up")
    Para("The grid is on screen while this window is open. \"Snap items to grid\" drops an item on the nearest grid line; \"Grid size\" sets the spacing.")
    Para("\"Stick items together\" makes an item dropped right next to another one click against its edge. It needs Snap to be on.")
    Para("With this window closed the HUD cannot be clicked or moved at all, so it never gets in the way of the game.")
    Para("This HUD only starts on a warrior. On any other class it stays completely off: nothing on screen, nothing saved.")
    DividerRow(flow)
    HeaderRow(flow, "What is on screen")
    Para("Rage bar and rage regen: your resource and how fast it is coming in. Swing timer: your auto-attack. Each has a Show box on the HUD tab.")
    Para("Combo points: kept for layout parity with the other class HUDs, off by default because this class has none.")
    Para("Recent actions: the last spells you cast, newest first, fading out after a few seconds.")
    Para("Ability icons: one per ability, switched on one by one on the Abilities tab. On cooldown the icon goes dark, a clock sweep runs round it, and the time left counts down to the hundredth of a second in its bottom-right corner, always on top.")
    Para("An icon also flashes when it is ready, glows while its effect is on you, and dims or turns red when you cannot use it. Each of these has its own switch.")
    DividerRow(flow)
    HeaderRow(flow, "The tabs")
    Para("HUD: show or hide each element, its width, height and opacity, plus the swing timer and regen options. Nothing here moves or scales an item; that is the mouse.")
    Para("Abilities: a switch for every notification, then every ability with its own On box and opacity.")
    Para("Skins: the menu artwork (High resolution, Low resolution or Off) and 40 colour skins. Profiles: save, load and delete named setups.")
    Para("Your own colours: on the Skins tab click any colour in the strip (bar, swing, text and so on). A colour wheel opens; the parts that can be see-through also get an Opacity slider. Changes show at once; Cancel puts the old colour back.")
    Para("Tick or untick \"Custom colours\" to switch between your colours and the plain skin. Type a name and press Save to keep a set; Load brings one back; Delete removes it. Saved colour sets survive Reset to default.")
    Para("\"Reset to default\" (top right) asks first and keeps your saved profiles.")
    DividerRow(flow)
    HeaderRow(flow, "Commands")
    Para("/fw2 opens or closes this window. /fw2 help opens this page. /fw2 abilities, /fw2 skins and /fw2 profiles open those tabs.")
    Para("/fw2 show | hide, /fw2 lock | unlock, /fw2 energy|regen|swing|combo|trail on|off, /fw2 cooldown on|off, /fw2 sticky, /fw2 grid.")
    Para("/fw2 skin <name>, /fw2 save <name>, /fw2 load <name>, /fw2 reset.")
    DividerRow(flow)
    AddTab("help", "FRHW2TabHelp", "Help", pageHelp)
    ReflowAll(true)
end

-----------------------------------------------------------------------
-- Apply positions, sizes, visibility
-----------------------------------------------------------------------
ApplyElement = function(key)
    if not db then return end
    local e = db.elements[key]
    local fr = elems[key]
    if not e or not fr then return end
    fr:ClearAllPoints()
    local sc = db.scale * (e.scale or 1)
    fr:SetPoint("CENTER", UIParent, "CENTER", (db.baseX + e.x) / sc, (db.baseY + e.y) / sc)
    fr:SetScale(sc)
    local spacing = 2
    -- dot-level fill alpha (dim vs full) is separate; it is re-scaled by the
    -- element's own opacity so both controls work together.
    local baseAlpha = e.alpha or 1
    if key == "combo" then
        if ME.Vertical(e) then
            fr:SetSize(e.w, MAX_COMBO_POINTS * e.h + (MAX_COMBO_POINTS - 1) * spacing)
            for i = 1, MAX_COMBO_POINTS do
                local b = cpBars[i]
                b:SetOrientation("VERTICAL")
                b:SetSize(e.w, e.h)
                b:ClearAllPoints()
                b:SetPoint("BOTTOM", fr, "BOTTOM", 0, (ME.Slot(e, i, MAX_COMBO_POINTS) - 1) * (e.h + spacing))
            end
        else
            fr:SetSize(MAX_COMBO_POINTS * e.w + (MAX_COMBO_POINTS - 1) * spacing, e.h)
            for i = 1, MAX_COMBO_POINTS do
                local b = cpBars[i]
                b:SetOrientation("HORIZONTAL")
                b:SetSize(e.w, e.h)
                b:ClearAllPoints()
                b:SetPoint("LEFT", fr, "LEFT", (ME.Slot(e, i, MAX_COMBO_POINTS) - 1) * (e.w + spacing), 0)
            end
        end
    elseif key == "trail" then
        ME.LayoutTrail(fr, e)
    else
        -- a quarter turn swaps width and height; a half turn fills the other way
        local vert = ME.Vertical(e)
        if vert then fr:SetSize(e.h, e.w) else fr:SetSize(e.w, e.h) end
        fr:SetOrientation(vert and "VERTICAL" or "HORIZONTAL")
        if fr.SetReverseFill then fr:SetReverseFill(ME.Reversed(e)) end
        if key == "energy" then fr.value:SetShown(e.showText ~= false) end
        if key == "swing" then
            LayoutSwing(e)   -- spark size, tick marks, colours
        elseif key == "regen" then
            fr.spark:Hide()  -- the regen bar has no spark of its own
        else
            fr.spark:SetSize(20, e.h * 2)
        end
    end
    fr:SetAlpha(baseAlpha)
    if db.shown and e.enabled and HudVisible() then fr:Show() else fr:Hide() end
end

ApplySpell = function(key)
    if not db then return end
    local cfg = db.spells[key]
    local btn = spellIcons[key]
    if not cfg or not btn then return end
    btn:ClearAllPoints()
    local sc = db.scale * (cfg.scale or 1)
    btn:SetPoint("CENTER", UIParent, "CENTER", (db.baseX + cfg.x) / sc, (db.baseY + cfg.y) / sc)
    btn:SetScale(sc)
    btn:SetSize(cfg.w, cfg.h)
    btn:SetAlpha(cfg.alpha or 1)
    -- the picture turns; the border, the sweep and the number stay upright
    if btn.icon.SetRotation then btn.icon:SetRotation(math.rad(cfg.rot or 0)) end
    if db.shown and cfg.enabled and HudVisible() then btn:Show() else btn:Hide() end
end

ApplyAll = function()
    ApplyElement("energy")
    ApplyElement("regen")
    ApplyElement("swing")
    ApplyElement("combo")
    ApplyElement("trail")
    for key in pairs(spellIcons) do ApplySpell(key) end
    TXT.Apply()
end
-- exposed so a macro or a test can re-apply the live configuration on demand
FRHW2_ApplyAll = function() if db then ApplyAll() end end
FRHW2_ApplyElement = function(key) if db then ApplyElement(key) end end

-----------------------------------------------------------------------
-- Skins: repaint the HUD and the options window
-----------------------------------------------------------------------
local currentSkin = SKIN_BY_KEY[SKIN_DEFAULT]

-- r, g, b, a of a palette entry, with an optional alpha override
local function Col(c, a)
    return c[1], c[2], c[3], a or c[4] or 1
end

-----------------------------------------------------------------------
-- Text engine (the "2" build): font, size, outline, shadow, colour,
-- placement and number format of every text on the HUD.
--
-- Shape borrowed from ElvUI's FontTemplate / UpdateFontTemplates: one table
-- of settings (db.text), one Apply that pushes it to every font string, and
-- format strings that are built once in Apply and only *used* per frame.
-- Nothing here runs on its own timer; the per-frame cost is one table read.
--
-- To add an option:  1. default in DEFAULTS.text   2. validate in TXT.Clamp
--                    3. use it in TXT.Apply (or a formatter)
--                    4. widget in the "Text tab" block + a line in TXT.Refresh
-- Everything lives in the TXT table so the main chunk gains no locals.
-----------------------------------------------------------------------
TXT.FONTS = {
    { key = "default",  name = "Game default" },
    { key = "friz",     name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { key = "arial",    name = "Arial Narrow",  path = "Fonts\\ARIALN.TTF" },
    { key = "morpheus", name = "Morpheus",      path = "Fonts\\MORPHEUS.TTF" },
    { key = "skurri",   name = "Skurri",        path = "Fonts\\SKURRI.TTF" },
}
TXT.OUTLINES = {
    { key = "",                   name = "None" },
    { key = "OUTLINE",            name = "Outline" },
    { key = "THICKOUTLINE",       name = "Thick outline" },
    { key = "MONOCHROME,OUTLINE", name = "Pixel outline" },
}
TXT.ANCHORS = {
    { key = "CENTER", name = "Centre" },
    { key = "LEFT",   name = "Left" },
    { key = "RIGHT",  name = "Right" },
    { key = "TOP",    name = "Top" },
    { key = "BOTTOM", name = "Bottom" },
    { key = "BOTTOMRIGHT", name = "Bottom right" },
    { key = "BOTTOMLEFT",  name = "Bottom left" },
    { key = "TOPRIGHT",    name = "Top right" },
    { key = "TOPLEFT",     name = "Top left" },
}
-- One entry per text on the HUD. formats / decimals are optional; a target
-- without them simply gets no such control on the Text tab.
TXT.TARGETS = {
    { key = "energy", label = "Resource bar text", formats = {
        { key = "cur_max", name = "Current / max" },
        { key = "cur",     name = "Current" },
        { key = "percent", name = "Percent" },
        { key = "deficit", name = "Deficit" },
        { key = "none",    name = "Hidden" } } },
    { key = "regen", label = "Regen bar text", decimals = true, formats = {
        { key = "rate",       name = "Rate with /s" },
        { key = "rate_plain", name = "Rate only" },
        { key = "none",       name = "Hidden" } } },
    { key = "swing", label = "Swing timer text", decimals = true },
    { key = "timer", label = "Cooldown numbers on icons", formats = {
        { key = "auto",    name = "7 then 2:05" },
        { key = "seconds", name = "Seconds only" },
        { key = "tenths",  name = "Tenths under 10 s" },
        { key = "mmss",    name = "Always m:ss" } } },
}

-- Entry of a { key =, name = } list by key, or nil.
TXT.Find = function(list, key)
    for i = 1, #list do
        if list[i].key == key then return list[i], i end
    end
    return nil
end

-- Key of the entry after `key`, wrapping round. Drives every cycle button.
TXT.Next = function(list, key)
    local _, i = TXT.Find(list, key)
    return list[(i or 0) % #list + 1].key
end

-- Build the full typeface list, once, at login:
--   1. the four fonts above,
--   2. every font file the client itself uses (walks GetFonts(), so the list
--      is whatever this build of the game really ships),
--   3. every font another addon registered with LibSharedMedia.
-- A file is listed once however many font objects or addons point at it.
TXT.LoadSharedFonts = function()
    if TXT.sharedLoaded then return end
    TXT.sharedLoaded = true
    local seen, extra = {}, {}
    local function norm(p) return (p:lower():gsub("/", "\\")) end
    for i = 1, #TXT.FONTS do
        if TXT.FONTS[i].path then seen[norm(TXT.FONTS[i].path)] = true end
    end
    local function add(key, name, path)
        if type(name) ~= "string" or type(path) ~= "string" or path == "" then return end
        local n = norm(path)
        if seen[n] or TXT.Find(TXT.FONTS, key) then return end
        seen[n] = true
        extra[#extra + 1] = { key = key, name = name, path = path }
    end
    if type(GetFonts) == "function" then
        local ok, names = pcall(GetFonts)
        if ok and type(names) == "table" then
            for i = 1, #names do
                local obj = _G[names[i]]
                if type(obj) == "table" and obj.GetFont then
                    local ok2, path = pcall(obj.GetFont, obj)
                    if ok2 and type(path) == "string" then
                        -- "Fonts\\NIM_____.ttf" -> "NIM", "Fonts\\2002B.TTF" -> "2002B"
                        local base = path:match("([^\\/]+)%.[%a%d]+$") or path
                        base = base:gsub("_+$", ""):gsub("_+", " ")
                        add("file:" .. norm(path), base, path)
                    end
                end
            end
        end
    end
    -- a font pack addon (ForeverFonts) lists its files in a global table:
    -- ForeverFonts = { { name = "Roboto", path = "Interface\\AddOns\\ForeverFonts\\Roboto.ttf" }, ... }
    if type(_G.ForeverFonts) == "table" then
        for i = 1, #_G.ForeverFonts do
            local e = _G.ForeverFonts[i]
            if type(e) == "table" then add("pack:" .. tostring(e.name), e.name, e.path) end
        end
    end
    if LibStub then
        local ok, lsm = pcall(LibStub, "LibSharedMedia-3.0", true)
        if ok and type(lsm) == "table" and lsm.HashTable then
            for name, path in pairs(lsm:HashTable("font")) do add("lsm:" .. tostring(name), name, path) end
        end
    end
    table.sort(extra, function(a, b) return a.name:lower() < b.name:lower() end)
    for i = 1, #extra do TXT.FONTS[#TXT.FONTS + 1] = extra[i] end
end

-- File path for a font key. An unknown key (a shared font whose addon is
-- gone) is the game's own font.
TXT.FontPath = function(key)
    local f = TXT.Find(TXT.FONTS, key)
    return (f and f.path) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

-- Fill and validate a text table from SavedVariables or a profile, then make
-- it the live one. Same rule as ClampSwing: never trust a stored value.
TXT.Clamp = function(src)
    local def = DEFAULTS.text
    if type(src) ~= "table" then src = def end
    local t = {}
    t.font         = type(src.font) == "string" and src.font or def.font
    t.outline      = TXT.Find(TXT.OUTLINES, src.outline) and src.outline or def.outline
    t.shadow       = src.shadow ~= false
    t.useSkinColor = src.useSkinColor ~= false
    t.r            = Num(src.r, 0, 1, def.r)
    t.g            = Num(src.g, 0, 1, def.g)
    t.b            = Num(src.b, 0, 1, def.b)
    for i = 1, #TXT.TARGETS do
        local info = TXT.TARGETS[i]
        local d, s = def[info.key], src[info.key]
        if type(s) ~= "table" then s = d end
        local o = {}
        o.font   = type(s.font) == "string" and s.font or nil   -- nil = the global font
        o.size   = math.floor(Num(s.size, 6, 40, d.size) + 0.5)
        o.anchor = TXT.Find(TXT.ANCHORS, s.anchor) and s.anchor or d.anchor
        o.x      = Num(s.x, -200, 200, d.x)
        o.y      = Num(s.y, -200, 200, d.y)
        if info.formats then
            o.format = TXT.Find(info.formats, s.format) and s.format or d.format
        end
        if info.decimals then
            o.decimals = math.floor(Num(s.decimals, 0, 2, d.decimals) + 0.5)
        end
        t[info.key] = o
    end
    db.text = t
end

-- One tracked ability's own typeface and number size (db.spells[key].font /
-- .fontSize). nil means "same as the Text tab", so an untouched ability
-- stores nothing extra.
TXT.ClampItem = function(e, s)
    e.font = type(s.font) == "string" and s.font or nil
    local size = Num(s.fontSize, 0, 40, 0)
    e.fontSize = size >= 6 and math.floor(size + 0.5) or nil
end

-- r, g, b, a for HUD text: the skin's text colour, or the user's own.
TXT.Color = function()
    local t = db and db.text
    if type(t) == "table" and not t.useSkinColor then return t.r, t.g, t.b, 1 end
    return Col(currentSkin.text, 1)
end

-- Colour only. Called from ApplySkin, so a skin change keeps a custom colour.
TXT.Paint = function()
    local r, g, b, a = TXT.Color()
    energy.value:SetTextColor(r, g, b, a)
    regen.value:SetTextColor(r, g, b, a)
    swing.time:SetTextColor(r, g, b, a)
    for _, btn in pairs(spellIcons) do btn.timer:SetTextColor(r, g, b, a) end
    UF.TextColor()
    MP.Paint()
end

-- Set a typeface; a file the client cannot load becomes the game's own font.
TXT.Font = function(fs, path, size, flags)
    local ok = pcall(fs.SetFont, fs, path, size, flags)
    if not ok or not fs:GetFont() then
        fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, flags)
    end
end

-- Font, size, flags, shadow and placement of one font string.
-- size overrides o.size (a tracked ability with its own number size).
TXT.Place = function(fs, parent, o, path, flags, shadow, size)
    TXT.Font(fs, path, size or o.size, flags)
    fs:ClearAllPoints()
    fs:SetPoint(o.anchor, parent, o.anchor, o.x, o.y)
    fs:SetJustifyH(o.anchor:find("LEFT") and "LEFT" or o.anchor:find("RIGHT") and "RIGHT" or "CENTER")
    if shadow then
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

-- Push db.text to every font string and rebuild the cached format strings.
-- Runs on a settings change only (ApplyAll, a Text tab control, a profile).
TXT.Apply = function()
    if not db or type(db.text) ~= "table" then return end
    local t = db.text
    local flags = t.outline
    -- most specific wins: the item's own font, then its group's, then the global one
    TXT.Place(energy.value, energy, t.energy, TXT.FontPath(t.energy.font or t.font), flags, t.shadow)
    TXT.Place(regen.value, regen, t.regen, TXT.FontPath(t.regen.font or t.font), flags, t.shadow)
    TXT.Place(swing.time, swing, t.swing, TXT.FontPath(t.swing.font or t.font), flags, t.shadow)
    for key, btn in pairs(spellIcons) do
        local cfg = db.spells and db.spells[key] or nil
        TXT.Place(btn.timer, btn, t.timer,
            TXT.FontPath((cfg and cfg.font) or t.timer.font or t.font), flags, t.shadow,
            cfg and cfg.fontSize or nil)
    end
    TXT.regenFmt    = "%." .. t.regen.decimals .. "f" .. (t.regen.format == "rate" and " /s" or "")
    TXT.swingRemain = "%." .. t.swing.decimals .. "f s"
    TXT.swingBoth   = "%." .. t.swing.decimals .. "f / %." .. t.swing.decimals .. "f s"
    UF.Fonts()   -- the unit frames follow the global font, outline and shadow
    TXT.Paint()
end

-- Resource bar text.
TXT.Energy = function(fs, cur, max)
    local t = db and db.text
    TXT.Value(fs, t and t.energy.format, cur, max)   -- nil before login: the original format
end

-- A current / maximum pair as text, in format f (cur_max, cur, percent,
-- deficit, none). cur / max may be secret: they are only ever handed to the
-- widget unless IsReadable says our own arithmetic may look at them.
TXT.Value = function(fs, f, cur, max)
    if f == "none" then
        fs:SetText("")
    elseif f == "cur" then
        fs:SetFormattedText("%d", cur)
    elseif (f == "percent" or f == "deficit") and IsReadable(cur) and IsReadable(max)
        and type(cur) == "number" and type(max) == "number" then
        if f == "percent" then
            fs:SetFormattedText("%d%%", max > 0 and math.floor(cur / max * 100 + 0.5) or 0)
        else
            fs:SetFormattedText("%d", cur - max)
        end
    else
        fs:SetFormattedText("%d / %d", cur, max)
    end
end

-- Regen bar text. rate is our own measured number.
TXT.Regen = function(fs, rate)
    local t = db and db.text
    if t and t.regen.format == "none" then
        fs:SetText("")
    else
        fs:SetFormattedText(TXT.regenFmt or "%.1f /s", rate)
    end
end

-- Cooldown number for the formats other than "auto" (FormatRemaining keeps
-- the original auto behaviour). rem is a plain readable number.
TXT.Timer = function(rem, f)
    if f == "tenths" and rem < 10 then return string.format("%.1f", rem) end
    local sec = math.ceil(rem)
    if f == "seconds" then return tostring(sec) end
    if f == "mmss" or sec >= 60 then
        return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
    end
    return tostring(sec)
end

-- Show db.text on the Text tab. Sliders only repaint their labels here.
TXT.Refresh = function()
    local ui, t = TXT.ui, db and db.text
    if not ui or type(t) ~= "table" then return end
    local was = suppress
    suppress = true
    TXT.Label(ui.font, t.font, "Font: ", t.font)
    ui.outline:SetText("Outline: " .. TXT.Find(TXT.OUTLINES, t.outline).name)
    ui.shadow:SetChecked(t.shadow)
    ui.skinColor:SetChecked(t.useSkinColor)
    ui.r:SetValue(t.r)
    ui.g:SetValue(t.g)
    ui.b:SetValue(t.b)
    for i = 1, #TXT.TARGETS do
        local info = TXT.TARGETS[i]
        local o = t[info.key]
        TXT.Label(ui.tfont[info.key], o.font, "Font: ", t.font)
        ui.size[info.key]:SetValue(o.size)
        ui.x[info.key]:SetValue(o.x)
        ui.y[info.key]:SetValue(o.y)
        ui.anchor[info.key]:SetText("Anchor: " .. TXT.Find(TXT.ANCHORS, o.anchor).name)
        if ui.format[info.key] then
            ui.format[info.key]:SetText("Format: " .. TXT.Find(info.formats, o.format).name)
        end
        if ui.decimals[info.key] then ui.decimals[info.key]:SetValue(o.decimals) end
    end
    -- Config tab: each tracked ability's own font button and number size
    if TXT.itemFont and db.spells then
        for key, b in pairs(TXT.itemFont) do
            local cfg = db.spells[key]
            if cfg then
                TXT.Label(b, cfg.font, "Font: ", t.timer.font or t.font)
                TXT.itemSize[key]:SetValue(cfg.fontSize or 0)
            end
        end
    end
    suppress = was
end

-- Caption of a font button, drawn in the typeface it stands for. key nil
-- means the button inherits; inherited is the font it falls back to.
TXT.Label = function(b, key, prefix, inherited)
    local f = TXT.Find(TXT.FONTS, key)
    if key and f then
        b:SetText(prefix .. f.name)
    elseif key then
        b:SetText(prefix .. "(missing, using default)")
    else
        b:SetText(prefix .. "same as Text tab")
    end
    local fs = b.GetFontString and b:GetFontString()
    if fs and fs.SetFont then
        pcall(fs.SetFont, fs, TXT.FontPath(key or inherited), 11, "")
        if fs.GetFont and not fs:GetFont() then fs:SetFont(STANDARD_TEXT_FONT, 11, "") end
    end
end

-- The typeface list: one shared popup for every font button, so forty
-- buttons cost one frame. Each row is drawn in its own typeface; the mouse
-- wheel scrolls; a click picks and closes; clicking the button again closes.
-- allowInherit adds a first row that clears the override (onPick(nil)).
TXT.PICK_ROWS = 12
TXT.OpenPicker = function(owner, current, allowInherit, onPick)
    local p = TXT.picker
    if not p then
        p = CreateFrame("Frame", "FRHW2FontPicker", panel, "BackdropTemplate")
        TXT.picker = p
        p:SetSize(230, TXT.PICK_ROWS * 18 + 24)
        p:SetFrameStrata("DIALOG")
        p:SetClampedToScreen(true)
        p:EnableMouse(true)
        p:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                        insets = { left = 1, right = 1, top = 1, bottom = 1 } })
        p.foot = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        p.foot:SetPoint("BOTTOMLEFT", 6, 5)
        p.rows = {}
        for i = 1, TXT.PICK_ROWS do
            local r = CreateFrame("Button", nil, p)
            r:SetSize(222, 18)
            r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 18)
            r.sel = Decor(r, "BACKGROUND")
            r.sel:SetAllPoints(true)
            r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.text:SetPoint("LEFT", 6, 0)
            r.text:SetJustifyH("LEFT")
            r:SetScript("OnEnter", function(self) self.sel:SetVertexColor(Col(currentSkin.accent, 0.30)); self.sel:Show() end)
            r:SetScript("OnLeave", function(self) p.Paint(self) end)
            r:SetScript("OnClick", function(self)
                if not self.entry then return end
                p:Hide()
                p.onPick(self.entry.key)
            end)
            p.rows[i] = r
        end
        -- selected row keeps a tint; the others are clear
        p.Paint = function(r)
            if r.entry and r.entry.key == p.current then
                r.sel:SetVertexColor(Col(currentSkin.accent, 0.45)); r.sel:Show()
            else
                r.sel:Hide()
            end
        end
        p.Update = function()
            local n = #p.list
            local maxOff = math.max(0, n - TXT.PICK_ROWS)
            if p.offset > maxOff then p.offset = maxOff end
            if p.offset < 0 then p.offset = 0 end
            for i = 1, TXT.PICK_ROWS do
                local r, e = p.rows[i], p.list[p.offset + i]
                r.entry = e
                if e then
                    r.text:SetText(e.name)
                    if r.text.SetFont then
                        pcall(r.text.SetFont, r.text, TXT.FontPath(e.key or p.inherited), 12, "")
                        if r.text.GetFont and not r.text:GetFont() then r.text:SetFont(STANDARD_TEXT_FONT, 12, "") end
                    end
                    r.text:SetTextColor(Col(currentSkin.text, 1))
                    p.Paint(r)
                    r:Show()
                else
                    r:Hide()
                end
            end
            p.foot:SetText(string.format("%d-%d of %d typefaces   (mouse wheel scrolls)",
                math.min(n, p.offset + 1), math.min(n, p.offset + TXT.PICK_ROWS), n))
        end
        if p.EnableMouseWheel then
            p:EnableMouseWheel(true)
            p:SetScript("OnMouseWheel", function(_, delta)
                p.offset = p.offset - delta * 3
                p.Update()
            end)
        end
        p:Hide()
    end
    if p:IsShown() and p.owner == owner then p:Hide(); return end
    p.list = {}
    if allowInherit then p.list[1] = { name = "Same as Text tab" } end   -- key nil clears the override
    for i = 1, #TXT.FONTS do p.list[#p.list + 1] = TXT.FONTS[i] end
    p.owner, p.current, p.onPick = owner, current, onPick
    p.inherited = db and db.text and db.text.font or nil
    p.offset = 0
    for i = 1, #p.list do
        if p.list[i].key == current then p.offset = i - math.floor(TXT.PICK_ROWS / 2) end
    end
    p:SetBackdropColor(Col(currentSkin.panel, 0.98))
    p:SetBackdropBorderColor(Col(currentSkin.accent, 0.9))
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    p:Show()
    p.Update()
end

-- The colour palette: one shared popup for every colour button. A grid of
-- swatches (greys, then twelve hues at four strengths, then the class
-- colours), and "More..." for the game's own colour wheel. onPick(r, g, b).
TXT.OpenPalette = function(owner, r, g, b, onPick)
    local p = TXT.palette
    if not p then
        p = CreateFrame("Frame", "FRHW2Palette", panel, "BackdropTemplate")
        TXT.palette = p
        p:SetFrameStrata("DIALOG")
        p:SetClampedToScreen(true)
        p:EnableMouse(true)
        p:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                        insets = { left = 1, right = 1, top = 1, bottom = 1 } })
        local colours = {}
        for i = 0, 11 do colours[#colours + 1] = { i / 11, i / 11, i / 11 } end
        -- hue to r, g, b at full saturation, then lighter / darker rows
        local function Hue(h)
            local x = 1 - math.abs((h * 6) % 2 - 1)
            local s = math.floor(h * 6) % 6
            if s == 0 then return 1, x, 0 elseif s == 1 then return x, 1, 0
            elseif s == 2 then return 0, 1, x elseif s == 3 then return 0, x, 1
            elseif s == 4 then return x, 0, 1 end
            return 1, 0, x
        end
        for _, row in ipairs({ { 0.55, 1 }, { 0, 1 }, { 0, 0.7 }, { 0, 0.4 } }) do
            for i = 0, 11 do
                local hr, hg, hb = Hue(i / 12)
                local w, v = row[1], row[2]
                colours[#colours + 1] = { (hr + (1 - hr) * w) * v, (hg + (1 - hg) * w) * v, (hb + (1 - hb) * w) * v }
            end
        end
        if type(RAID_CLASS_COLORS) == "table" then
            local n = 0
            for _, c in pairs(RAID_CLASS_COLORS) do
                if type(c) == "table" and c.r and n < 12 then n = n + 1; colours[#colours + 1] = { c.r, c.g, c.b } end
            end
        end
        p.swatches = {}
        for i = 1, #colours do
            local c = colours[i]
            local s = CreateFrame("Button", nil, p)
            s:SetSize(16, 16)
            s:SetPoint("TOPLEFT", 6 + ((i - 1) % 12) * 18, -6 - math.floor((i - 1) / 12) * 18)
            s.tex = Decor(s, "ARTWORK")
            s.tex:SetAllPoints(true)
            s.tex:SetVertexColor(c[1], c[2], c[3], 1)
            s.color = c
            s:SetScript("OnClick", function(self)
                p:Hide()
                p.onPick(self.color[1], self.color[2], self.color[3])
            end)
            p.swatches[i] = s
        end
        local rows = math.ceil(#colours / 12)
        p.more = MakeButton(p, "More...", 6, -(10 + rows * 18), 90, 20, function()
            p:Hide()
            local cp = ColorPickerFrame
            if not cp or not cp.SetupColorPickerAndShow then return end
            local r0, g0, b0, pick = p.r, p.g, p.b, p.onPick
            cp:SetupColorPickerAndShow({
                r = r0, g = g0, b = b0, hasOpacity = false,
                swatchFunc = function() pick(cp:GetColorRGB()) end,
                cancelFunc = function() pick(r0, g0, b0) end,
            })
        end)
        p.now = Decor(p, "ARTWORK")   -- the colour being replaced
        p.now:SetSize(40, 16)
        p.now:SetPoint("TOPLEFT", 104, -(12 + rows * 18))
        p:SetSize(12 * 18 + 10, rows * 18 + 40)
        p:Hide()
    end
    if p:IsShown() and p.owner == owner then p:Hide(); return end
    p.owner, p.onPick, p.r, p.g, p.b = owner, onPick, r or 1, g or 1, b or 1
    p.now:SetVertexColor(p.r, p.g, p.b, 1)
    p:SetBackdropColor(Col(currentSkin.panel, 0.98))
    p:SetBackdropBorderColor(Col(currentSkin.accent, 0.9))
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    p:Show()
end

-- Public entry points, for macros and for the test suite.
FRHW2_TEXT = TXT
FRHW2_ApplyText = function() if db then TXT.Apply() end end
-- Set the font by key ("friz", "arial", "lsm:<name>" ...). False if unknown.
function FRHW2_SetFont(key)
    if not db or not TXT.Find(TXT.FONTS, key) then return false end
    db.text.font = key
    TXT.Apply()
    TXT.Refresh()
    return true
end

-- ============================ Text tab ============================
do
    local page = CreateFrame("Frame", nil, panel)
    page:SetPoint("TOPLEFT", 8, -70)
    page:SetPoint("BOTTOMRIGHT", -8, 26)
    page:Hide()
    AddTab("text", "FRHW2TabText", "Text", page)
    local scroll, child = MakeScroll("FRHW2TextScroll", page, -4)
    local flow = NewFlow(scroll, child)
    local ui = { tfont = {}, size = {}, x = {}, y = {}, anchor = {}, format = {}, decimals = {} }
    TXT.ui = ui

    -- a button changed something: apply it and repaint the button labels
    local function Changed()
        TXT.Apply()
        TXT.Refresh()
    end

    NoteRow(flow, "The default look of every text. Each text's own font and format are beside its bar on the HUD tab, or on the Abilities tab.")
    ui.font = MakeButton(child, "Font", 0, 0, 190, 22, function(self)
        TXT.OpenPicker(self, db.text.font, false, function(font) db.text.font = font; Changed() end)
    end, "FRHW2TXT_Font")
    ui.outline = MakeButton(child, "Outline", 0, 0, 190, 22, function()
        db.text.outline = TXT.Next(TXT.OUTLINES, db.text.outline); Changed()
    end, "FRHW2TXT_Outline")
    ui.shadow = MakeCheck(child, "FRHW2TXT_Shadow", 0, 0, "Shadow", function(self)
        db.text.shadow = self:GetChecked() and true or false; TXT.Apply()
    end)
    ui.skinColor = MakeCheck(child, "FRHW2TXT_SkinColor", 0, 0, "Use skin text colour", function(self)
        db.text.useSkinColor = self:GetChecked() and true or false; TXT.Paint()
    end)
    ui.r = MakeSlider(child, "FRHW2TXT_R", 0, 0, 190, 0, 1, 0.05, "Text red", function(v)
        db.text.r = v; TXT.Paint()
    end)
    ui.g = MakeSlider(child, "FRHW2TXT_G", 0, 0, 190, 0, 1, 0.05, "Text green", function(v)
        db.text.g = v; TXT.Paint()
    end)
    ui.b = MakeSlider(child, "FRHW2TXT_B", 0, 0, 190, 0, 1, 0.05, "Text blue", function(v)
        db.text.b = v; TXT.Paint()
    end)
    Row(flow, LAYOUT.slider, ui.font, ui.outline)
    Row(flow, LAYOUT.check, ui.shadow, ui.skinColor)
    Row(flow, LAYOUT.slider, ui.r, ui.g)
    -- the same colour from the palette instead of three sliders
    ui.pal = MakeButton(child, "Pick text colour...", 0, 0, 190, 22, function(self)
        TXT.OpenPalette(self, db.text.r, db.text.g, db.text.b, function(r, g, b)
            db.text.r, db.text.g, db.text.b = r, g, b
            db.text.useSkinColor = false
            TXT.Paint(); TXT.Refresh()
        end)
    end, "FRHW2TXT_Palette")
    Row(flow, LAYOUT.slider, ui.b, ui.pal)
    DividerRow(flow)

    for i = 1, #TXT.TARGETS do
        local info = TXT.TARGETS[i]
        local key = info.key
        -- the bar texts live in their bar's block on the HUD tab and the icon
        -- countdown with the notifications on the Abilities tab
        local m = ME.mark[key]
        local flow, child = flow, child
        if m then flow, child = m.flow, m.child end
        ui.tfont[key] = MakeButton(child, "Font", 0, 0, 190, 22, function(self)
            TXT.OpenPicker(self, db.text[key].font, true, function(font) db.text[key].font = font; Changed() end)
        end, "FRHW2TXT_Font_" .. key)
        ui.size[key] = MakeSlider(child, "FRHW2TXT_Size_" .. key, 0, 0, 190, 6, 40, 1, "Font size", function(v)
            db.text[key].size = v; TXT.Apply()
        end)
        ui.anchor[key] = MakeButton(child, "Anchor", 0, 0, 190, 22, function()
            db.text[key].anchor = TXT.Next(TXT.ANCHORS, db.text[key].anchor); Changed()
        end, "FRHW2TXT_Anchor_" .. key)
        ui.x[key] = MakeSlider(child, "FRHW2TXT_X_" .. key, 0, 0, 190, -200, 200, 1, "Offset X", function(v)
            db.text[key].x = v; TXT.Apply()
        end)
        ui.y[key] = MakeSlider(child, "FRHW2TXT_Y_" .. key, 0, 0, 190, -200, 200, 1, "Offset Y", function(v)
            db.text[key].y = v; TXT.Apply()
        end)
        if info.formats then
            ui.format[key] = MakeButton(child, "Format", 0, 0, 190, 22, function()
                db.text[key].format = TXT.Next(info.formats, db.text[key].format); Changed()
            end, "FRHW2TXT_Format_" .. key)
        end
        if info.decimals then
            ui.decimals[key] = MakeSlider(child, "FRHW2TXT_Dec_" .. key, 0, 0, 190, 0, 2, 1, "Decimals", function(v)
                db.text[key].decimals = v; TXT.Apply()
            end)
        end
        local function Rows()
            if not m then HeaderRow(flow, info.label) end
            -- look first (typeface, size), then where it sits, then what it says
            Row(flow, LAYOUT.slider, ui.tfont[key], ui.size[key])
            Row(flow, LAYOUT.slider, ui.x[key], ui.y[key])
            Row(flow, LAYOUT.slider, ui.anchor[key], ui.format[key] or ui.decimals[key])
            if ui.format[key] and ui.decimals[key] then
                Row(flow, LAYOUT.slider, ui.decimals[key])
            end
            if not m then DividerRow(flow) end
        end
        if m then ME.InsertRows(key, Rows) else Rows() end
    end
    ReflowAll(true)
end

-----------------------------------------------------------------------
-- Option schemas (shared by the Frames and Map tabs)
--
-- A tab's options are one list of rows. Each row is
--   { t = "header", l = "Title" }                               a section
--   { k = key, t = "check",  l = label, d = default }
--   { k = key, t = "slider", l = label, d = default, min =, max =, step = }
--   { k = key, t = "cycle",  l = label, d = default, list = { {key=,name=} } }
--   { k = key, t = "font",   l = label }                        nil = inherit
--   { k = key, t = "color",  l = label, keys = {kr,kg,kb}, d = {r,g,b} }
--     (k is the first of the three keys; the button opens the palette)
-- du = { unitKey = value } overrides d for one unit; only = { unitKey = true }
-- greys the control out for the others. From that one list come the
-- defaults, the validation, the widgets and the refresh, so a new option is
-- one row here plus the line of code that uses it.
-----------------------------------------------------------------------
-- A validated settings table for one schema. s may be nil (gives defaults).
TXT.ClampOptions = function(opts, s, unitKey)
    local out = {}
    if type(s) ~= "table" then s = {} end
    for i = 1, #opts do
        local o = opts[i]
        if o.k then
            local d = o.d
            if o.du and o.du[unitKey] ~= nil then d = o.du[unitKey] end
            local v = s[o.k]
            if o.t == "check" then
                if type(v) ~= "boolean" then v = d end
                out[o.k] = v == true
            elseif o.t == "slider" then
                v = Num(v, o.min, o.max, d)
                if o.step >= 1 then v = math.floor(v + 0.5) end
                out[o.k] = v
            elseif o.t == "cycle" then
                out[o.k] = TXT.Find(o.list, v) and v or d
            elseif o.t == "color" then
                -- three numbers under three keys (o.keys), so old saved values still load
                for c = 1, 3 do out[o.keys[c]] = Num(s[o.keys[c]], 0, 1, o.d[c]) end
            else
                out[o.k] = type(v) == "string" and v or nil
            end
        end
    end
    return out
end

-- Build the widgets for a schema, two to a row under their section headers.
-- cur() returns the table being edited; changed(o, isSlider) applies it.
TXT.BuildOptions = function(flow, child, prefix, opts, cur, changed)
    local ws, pending = {}, nil
    for i = 1, #opts do
        local o = opts[i]
        if o.t == "header" then
            if pending then Row(flow, LAYOUT.slider, pending); pending = nil end
            HeaderRow(flow, o.l)
        elseif o.mouse then
            -- set with the mouse on the frame itself: saved and validated, no control
        else
            local w
            if o.t == "check" then
                w = MakeCheck(child, prefix .. o.k, 0, 0, o.l, function(self)
                    cur()[o.k] = self:GetChecked() and true or false; changed(o)
                end)
            elseif o.t == "slider" then
                w = MakeSlider(child, prefix .. o.k, 0, 0, 190, o.min, o.max, o.step, o.l, function(v)
                    cur()[o.k] = v; changed(o, true)
                end)
            elseif o.t == "cycle" then
                w = MakeButton(child, o.l, 0, 0, 190, 22, function()
                    cur()[o.k] = TXT.Next(o.list, cur()[o.k]); changed(o)
                end, prefix .. o.k)
            elseif o.t == "color" then
                -- a button with a swatch of the current colour; opens the palette
                w = MakeButton(child, o.l, 0, 0, 190, 22, function(self)
                    local t = cur()
                    TXT.OpenPalette(self, t[o.keys[1]], t[o.keys[2]], t[o.keys[3]], function(r, g, b)
                        local now = cur()
                        now[o.keys[1]], now[o.keys[2]], now[o.keys[3]] = r, g, b
                        changed(o)
                    end)
                end, prefix .. o.k)
                w.swatch = Decor(w, "OVERLAY")
                w.swatch:SetSize(14, 14)
                w.swatch:SetPoint("RIGHT", -6, 0)
            else
                w = MakeButton(child, o.l, 0, 0, 190, 22, function(self)
                    TXT.OpenPicker(self, cur()[o.k], true, function(font)
                        cur()[o.k] = font; changed(o)
                    end)
                end, prefix .. o.k)
            end
            ws[o.k] = w
            if pending then
                Row(flow, LAYOUT.slider, pending, w); pending = nil
            else
                pending = w
            end
        end
    end
    if pending then Row(flow, LAYOUT.slider, pending) end
    return ws
end

-- Show a settings table on its widgets. Call with suppress set.
TXT.ShowOptions = function(ws, opts, t, unitKey, inheritedFont)
    for i = 1, #opts do
        local o = opts[i]
        local w = o.k and ws[o.k]
        if w then
            local v = t[o.k]
            if o.t == "check" then
                w:SetChecked(v)
            elseif o.t == "slider" then
                w:SetValue(v)
            elseif o.t == "cycle" then
                w:SetText(o.l .. ": " .. TXT.Find(o.list, v).name)
            elseif o.t == "color" then
                w.swatch:SetVertexColor(t[o.keys[1]], t[o.keys[2]], t[o.keys[3]], 1)
            else
                TXT.Label(w, v, o.l .. ": ", inheritedFont)
            end
            local on = not o.only or o.only[unitKey] == true
            w:SetAlpha(on and 1 or 0.35)
            if w.EnableMouse then w:EnableMouse(on) end
        end
    end
end

-- Run fn once combat has ended (now, if not in combat). key keeps one
-- pending call per job however often it is asked for.
TXT.AfterCombat = function(key, fn)
    if not (InCombatLockdown and InCombatLockdown()) then fn(); return end
    if not TXT.waiter then
        TXT.waiting = {}
        TXT.waiter = CreateFrame("Frame")
        TXT.waiter:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            local jobs = TXT.waiting
            TXT.waiting = {}
            for _, job in pairs(jobs) do job() end
        end)
    end
    TXT.waiting[key] = fn
    TXT.waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- Move a game frame under a hidden parent, or give it back. Reversible, so
-- an option can be switched off again without a reload (ElvUI's hide, minus
-- the part that cannot be undone).
TXT.Stash = function(frame, hide)
    if type(frame) ~= "table" or not frame.SetParent or not frame.GetParent then return end
    TXT.stashed = TXT.stashed or {}
    if hide and not TXT.stashed[frame] then
        if not TXT.hidden then
            TXT.hidden = CreateFrame("Frame")
            TXT.hidden:Hide()
        end
        TXT.stashed[frame] = frame:GetParent() or UIParent
        frame:SetParent(TXT.hidden)
        TXT.hooked = TXT.hooked or {}
        if hooksecurefunc and not TXT.hooked[frame] then
            TXT.hooked[frame] = true
            -- the game can re-parent its own frame; put it back under ours
            hooksecurefunc(frame, "SetParent", function(self, parent)
                if TXT.stashed[self] and parent ~= TXT.hidden and not (InCombatLockdown and InCombatLockdown()) then
                    self:SetParent(TXT.hidden)
                end
            end)
        end
    elseif not hide and TXT.stashed[frame] then
        local parent = TXT.stashed[frame]
        TXT.stashed[frame] = nil
        frame:SetParent(parent)
    end
end

-----------------------------------------------------------------------
-- Unit frames (the "2" build): player, target, target of target
--
-- The ElvUI look -- flat bars in a 1 px border, class / reaction colours,
-- portrait, name and health texts -- painted with this HUD's own skins,
-- without ElvUI's machinery. What keeps it cheap:
--   * a frame is only built the first time it is switched on; a frame that
--     is off has no frame, no events and no code running;
--   * updates are event driven. Only target of target is polled (5 times a
--     second, and only while it is on screen) because the client sends no
--     events for that unit;
--   * settings work happens in UF.Apply, never in an update.
-- The frames are secure unit buttons (left click targets, right click opens
-- the unit menu), so the client forbids moving, sizing, showing or hiding
-- them in combat: UF.Apply waits for combat to end. Colours, texts, bar
-- values, icons and opacity are not restricted and update in combat.
--
-- To add an option: one row in UF.OPTS, then use db.frames[key].<k> in
-- UF.Apply / UF.Layout / UF.Fonts or in the update that needs it.
-----------------------------------------------------------------------
UF.UNITS = {
    { key = "player",       unit = "player",       label = "Player",           blizz = "PlayerFrame" },
    { key = "target",       unit = "target",       label = "Target",           blizz = "TargetFrame" },
    { key = "targettarget", unit = "targettarget", label = "Target of target", blizz = "TargetFrameToT" },
}
UF.COLORS = {
    { key = "class",  name = "Class / reaction" },
    { key = "skin",   name = "Skin bar colour" },
    { key = "custom", name = "Custom (sliders)" },
}
UF.HEALTH = {
    { key = "cur_max", name = "Current / max" },
    { key = "percent", name = "Percent" },
    { key = "cur",     name = "Current" },
    { key = "deficit", name = "Deficit" },
    { key = "none",    name = "Hidden" },
}
UF.STRATA = {
    { key = "BACKGROUND", name = "Background" },
    { key = "LOW",        name = "Low" },
    { key = "MEDIUM",     name = "Medium" },
    { key = "HIGH",       name = "High" },
}
UF.TEX = {
    { key = "flat",     name = "Flat",     path = WHITE },
    { key = "blizzard", name = "Blizzard", path = "Interface\\TARGETINGFRAME\\UI-StatusBar" },
    { key = "raid",     name = "Raid",     path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
}
UF.NAMEFMT = {
    { key = "name",       name = "Name" },
    { key = "level_name", name = "Level Name" },
    { key = "name_level", name = "Name (Level)" },
}
UF.NAMECOL = {
    { key = "text",  name = "Text colour" },
    { key = "class", name = "Class / reaction" },
}
UF.PORT = {
    { key = "2d", name = "2D picture" },
    { key = "3d", name = "3D model" },
}
UF.SIDE = {
    { key = "left",  name = "Left" },
    { key = "right", name = "Right" },
}
UF.VPOS = {
    { key = "above", name = "Above the frame" },
    { key = "below", name = "Below the frame" },
}
UF.ABTYPE = {
    { key = "buffs",   name = "Buffs" },
    { key = "debuffs", name = "Debuffs" },
}
UF.CUSTOM = {
    { key = "none",  name = "None" },
    { key = "level", name = "Level" },
    { key = "class", name = "Class / creature type" },
    { key = "hcur",  name = "Health" },
    { key = "hpp",   name = "Health %" },
    { key = "pow",   name = "Power" },
    { key = "powp",  name = "Power %" },
}
UF.PLAYER = { player = true }
UF.NOTTOT = { player = true, target = true }

-- Every per-frame option, in the order and groups ElvUI lists them.
UF.OPTS = {
    { t = "header", l = "General" },
    { k = "enabled",      t = "check",  l = "Enable this frame", d = false },
    { k = "hideBlizzard", t = "check",  l = "Hide the game's own frame", d = true },
    { k = "x",     t = "slider", mouse = true, l = "X (from screen centre)", d = 0, du = { player = -290, target = 290 }, min = -1200, max = 1200, step = 1 },
    { k = "y",     t = "slider", mouse = true, l = "Y (from screen centre)", d = -190, du = { targettarget = -240 }, min = -700, max = 700, step = 1 },
    { k = "w",     t = "slider", l = "Width",  d = 230, du = { targettarget = 130 }, min = 40, max = 600, step = 1 },
    { k = "h",     t = "slider", l = "Height", d = 34,  du = { targettarget = 24 },  min = 10, max = 200, step = 1 },
    { k = "scale", t = "slider", mouse = true, l = "Scale",   d = 1, min = 0.5, max = 3, step = 0.05 },
    { k = "alpha", t = "slider", l = "Opacity", d = 1, min = 0.1, max = 1, step = 0.05 },
    { k = "strata",  t = "cycle",  l = "Strata", d = "LOW", list = UF.STRATA },
    { k = "level",   t = "slider", l = "Frame level", d = 5, min = 1, max = 50, step = 1 },
    { k = "texture", t = "cycle",  l = "Bar texture", d = "flat", list = UF.TEX },
    { k = "smooth",  t = "check",  l = "Smooth bars", d = true },
    { k = "hover",   t = "check",  l = "Mouseover highlight", d = true },
    { k = "threat",  t = "check",  l = "Threat border", d = true, du = { targettarget = false }, only = UF.NOTTOT },

    { t = "header", l = "Fader" },
    { k = "fade",       t = "check",  l = "Fade when idle", d = false },
    { k = "fadeAlpha",  t = "slider", l = "Idle opacity", d = 0.35, min = 0, max = 1, step = 0.05 },
    { k = "fadeCombat", t = "check",  l = "Full in combat", d = true },
    { k = "fadeTarget", t = "check",  l = "Full with a target", d = true },
    { k = "fadeHover",  t = "check",  l = "Full on mouseover", d = true },

    { t = "header", l = "Health" },
    { k = "color",    t = "cycle",  l = "Colour", d = "class", list = UF.COLORS },
    { k = "bgAlpha",  t = "slider", l = "Background opacity", d = 0.9, min = 0, max = 1, step = 0.05 },
    { k = "hr",       t = "color",  l = "Custom colour", keys = { "hr", "hg", "hb" }, d = { 0.2, 0.6, 0.2 } },
    { k = "hReverse", t = "check",  l = "Reverse fill", d = false },
    { k = "hpred",    t = "check",  l = "Show incoming heals", d = true },
    { k = "cutaway",  t = "check",  l = "Cutaway (health just lost)", d = false },
    { k = "health",   t = "cycle",  l = "Text", d = "cur_max", du = { targettarget = "percent" }, list = UF.HEALTH },
    { k = "hAnchor",  t = "cycle",  l = "Text position", d = "RIGHT", list = TXT.ANCHORS },
    { k = "hX",       t = "slider", l = "Text offset X", d = 0, min = -200, max = 200, step = 1 },
    { k = "hY",       t = "slider", l = "Text offset Y", d = 0, min = -100, max = 100, step = 1 },

    { t = "header", l = "Power" },
    { k = "powerH",    t = "slider", l = "Bar height (0 = none)", d = 8, du = { targettarget = 4 }, min = 0, max = 40, step = 1 },
    { k = "pReverse",  t = "check",  l = "Reverse fill", d = false },
    { k = "pAuto",     t = "check",  l = "Hide when the unit has none", d = true },
    { k = "pHideNPC",  t = "check",  l = "Hide on NPCs", d = false },
    { k = "powerText", t = "check",  l = "Show number", d = false },
    { k = "pAnchor",   t = "cycle",  l = "Number position", d = "CENTER", list = TXT.ANCHORS },
    { k = "pX",        t = "slider", l = "Number offset X", d = 0, min = -200, max = 200, step = 1 },
    { k = "pY",        t = "slider", l = "Number offset Y", d = 0, min = -100, max = 100, step = 1 },

    { t = "header", l = "Name" },
    { k = "name",       t = "check",  l = "Show name", d = true },
    { k = "nameFormat", t = "cycle",  l = "Format", d = "name", list = UF.NAMEFMT },
    { k = "nameColor",  t = "cycle",  l = "Colour", d = "text", list = UF.NAMECOL },
    { k = "nAnchor",    t = "cycle",  l = "Position", d = "LEFT", list = TXT.ANCHORS },
    { k = "nX",         t = "slider", l = "Offset X", d = 0, min = -200, max = 200, step = 1 },
    { k = "nY",         t = "slider", l = "Offset Y", d = 0, min = -100, max = 100, step = 1 },

    { t = "header", l = "Text font" },
    { k = "font",     t = "font",   l = "Font" },
    { k = "fontSize", t = "slider", l = "Font size", d = 11, du = { targettarget = 10 }, min = 6, max = 40, step = 1 },

    { t = "header", l = "Portrait" },
    { k = "portrait",  t = "check",  l = "Show portrait", d = false },
    { k = "portStyle", t = "cycle",  l = "Style", d = "2d", list = UF.PORT },
    { k = "portSide",  t = "cycle",  l = "Side", d = "left", du = { target = "right" }, list = UF.SIDE },
    { k = "portW",     t = "slider", l = "Width (0 = square)", d = 0, min = 0, max = 200, step = 1 },

    { t = "header", l = "Cast bar" },
    { k = "cb",          t = "check",  l = "Show cast bar", d = true, du = { targettarget = false }, only = UF.NOTTOT },
    { k = "cbHideBlizz", t = "check",  l = "Hide the game's cast bar", d = true, only = UF.PLAYER },
    { k = "cbW",    t = "slider", l = "Width (0 = frame width)", d = 0, min = 0, max = 600, step = 1, only = UF.NOTTOT },
    { k = "cbH",    t = "slider", l = "Height", d = 14, min = 6, max = 40, step = 1, only = UF.NOTTOT },
    { k = "cbPos",  t = "cycle",  l = "Position", d = "below", list = UF.VPOS, only = UF.NOTTOT },
    { k = "cbr",    t = "color",  l = "Bar colour", keys = { "cbr", "cbg", "cbb" }, d = { 1, 0.7, 0 }, only = UF.NOTTOT },
    { k = "cbIcon", t = "check",  l = "Spell icon", d = true, only = UF.NOTTOT },
    { k = "cbTime", t = "check",  l = "Time left", d = true, only = UF.NOTTOT },

    { t = "header", l = "Buffs" },
    { k = "bOn",   t = "check",  l = "Show buffs", d = false, du = { target = true } },
    { k = "bMine", t = "check",  l = "Only mine", d = false },
    { k = "bMax",  t = "slider", l = "How many", d = 8, min = 1, max = 24, step = 1 },
    { k = "bSize", t = "slider", l = "Icon size", d = 20, min = 12, max = 48, step = 1 },
    { k = "bPos",  t = "cycle",  l = "Position", d = "above", list = UF.VPOS },

    { t = "header", l = "Debuffs" },
    { k = "dOn",   t = "check",  l = "Show debuffs", d = true, du = { targettarget = false } },
    { k = "dMine", t = "check",  l = "Only mine", d = false },
    { k = "dMax",  t = "slider", l = "How many", d = 8, min = 1, max = 24, step = 1 },
    { k = "dSize", t = "slider", l = "Icon size", d = 20, min = 12, max = 48, step = 1 },
    { k = "dPos",  t = "cycle",  l = "Position", d = "above", list = UF.VPOS },

    { t = "header", l = "Aura bars" },
    { k = "abOn",   t = "check",  l = "Show aura bars", d = false },
    { k = "abMine", t = "check",  l = "Only mine", d = true },
    { k = "abType", t = "cycle",  l = "Show", d = "buffs", du = { target = "debuffs" }, list = UF.ABTYPE },
    { k = "abMax",  t = "slider", l = "How many", d = 5, min = 1, max = 10, step = 1 },
    { k = "abH",    t = "slider", l = "Bar height", d = 14, min = 8, max = 30, step = 1 },

    { t = "header", l = "Info panel" },
    { k = "info",  t = "check",  l = "Name and health on a strip below", d = false },
    { k = "infoH", t = "slider", l = "Strip height", d = 14, min = 10, max = 40, step = 1 },

    { t = "header", l = "Custom texts" },
    { k = "c1",       t = "cycle",  l = "Text 1", d = "none", list = UF.CUSTOM },
    { k = "c1Anchor", t = "cycle",  l = "Text 1 position", d = "CENTER", list = TXT.ANCHORS },
    { k = "c1X",      t = "slider", l = "Text 1 offset X", d = 0, min = -200, max = 200, step = 1 },
    { k = "c1Y",      t = "slider", l = "Text 1 offset Y", d = 0, min = -100, max = 100, step = 1 },
    { k = "c2",       t = "cycle",  l = "Text 2", d = "none", list = UF.CUSTOM },
    { k = "c2Anchor", t = "cycle",  l = "Text 2 position", d = "BOTTOM", list = TXT.ANCHORS },
    { k = "c2X",      t = "slider", l = "Text 2 offset X", d = 0, min = -200, max = 200, step = 1 },
    { k = "c2Y",      t = "slider", l = "Text 2 offset Y", d = 0, min = -100, max = 100, step = 1 },

    { t = "header", l = "Class bar" },
    { k = "classbar", t = "check",  l = "Combo points on the frame", d = false, only = UF.PLAYER },
    { k = "cpH",      t = "slider", l = "Height", d = 6, min = 3, max = 20, step = 1, only = UF.PLAYER },

    { t = "header", l = "Colours" },
    { k = "bgr", t = "color", l = "Frame background", keys = { "bgr", "bgg", "bgb" }, d = { 0, 0, 0 } },

    { t = "header", l = "Icons" },
    { k = "leaderIcon", t = "check", l = "Group leader icon", d = true },
    { k = "pvpIcon",    t = "check", l = "PvP icon", d = false },
    { k = "rezIcon",    t = "check", l = "Incoming resurrection icon", d = true },
    { k = "phaseIcon",  t = "check", l = "Out-of-phase icon", d = true, only = { target = true, targettarget = true } },
    { k = "raidIcon",   t = "check",  l = "Raid target icon", d = true },
    { k = "iconSize",   t = "slider", l = "Icon size", d = 18, min = 8, max = 48, step = 1 },
    { k = "restIcon",   t = "check",  l = "Resting icon", d = true, only = UF.PLAYER },
    { k = "combatIcon", t = "check",  l = "Combat icon", d = true, only = UF.PLAYER },
}

UF.EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER",
              "UNIT_DISPLAYPOWER", "UNIT_NAME_UPDATE", "UNIT_FACTION", "UNIT_LEVEL",
              "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_THREAT_SITUATION_UPDATE",
              "UNIT_AURA", "UNIT_HEAL_PREDICTION", "UNIT_PHASE",
              "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_STOP",
              "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_UPDATE",
              "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_INTERRUPTIBLE",
              "UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "UNIT_SPELLCAST_SUCCEEDED" }
UF.PLAIN = { "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
             "RAID_TARGET_UPDATE", "PLAYER_UPDATE_RESTING",
             "PARTY_LEADER_CHANGED", "GROUP_ROSTER_UPDATE", "INCOMING_RESURRECT_CHANGED" }
UF.frames = {}        -- key -> frame, filled as frames are switched on
UF.sel = "player"     -- the unit the Frames tab is editing

-- Defaults come from the schema, so Reset to default and a fresh install
-- need no second list.
DEFAULTS.frames = {}
for i = 1, #UF.UNITS do
    DEFAULTS.frames[UF.UNITS[i].key] = TXT.ClampOptions(UF.OPTS, nil, UF.UNITS[i].key)
end

-- Fill and validate db.frames from SavedVariables or a profile.
UF.Clamp = function(src)
    local out = {}
    for i = 1, #UF.UNITS do
        local key = UF.UNITS[i].key
        out[key] = TXT.ClampOptions(UF.OPTS, type(src) == "table" and src[key] or nil, key)
    end
    db.frames = out
end

-- True while the client forbids changing a secure frame.
UF.Locked = function()
    return InCombatLockdown ~= nil and InCombatLockdown() and true or false
end

-- Class colour for a player, reaction colour for anything else, or nil when
-- the client will not let us read which it is.
UF.UnitColor = function(u)
    if not UnitIsPlayer then return nil end
    local ok, isPlayer = pcall(UnitIsPlayer, u)
    if not ok or not IsReadable(isPlayer) then return nil end
    local c
    if isPlayer then
        local ok2, _, class = pcall(UnitClass, u)
        c = ok2 and IsReadable(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    elseif UnitReaction then
        local ok2, reaction = pcall(UnitReaction, u, "player")
        c = ok2 and IsReadable(reaction) and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
    end
    if c then return c.r, c.g, c.b end
    return nil
end

-- Health bar and health text. Secret values only ever reach the widgets.
UF.Health = function(f)
    local cfg = db.frames[f.info.key]
    local cur, max = UnitHealth(f.unit), UnitHealthMax(f.unit)
    f.health:SetMinMaxValues(0, max)
    if cfg.smooth and UF.interp then f.health:SetValue(cur, UF.interp) else f.health:SetValue(cur) end
    TXT.Value(f.hp, cfg.health, cur, max)
    -- cutaway: the layer behind the bar keeps the previous value for a moment,
    -- so the health just lost stays visible. The values are only stored and
    -- handed back to a widget, never compared, so secret ones are fine.
    f.back:SetMinMaxValues(0, max)
    if cfg.cutaway and C_Timer and C_Timer.After then
        if f.hasHp and not f.cutBusy then
            f.cutBusy = true
            f.back:SetValue(f.lastHp)
            C_Timer.After(0.4, function()
                f.cutBusy = false
                f.back:SetValue(f.lastHp)
            end)
        end
    else
        f.back:SetValue(0)
    end
    f.lastHp, f.hasHp = cur, true
    UF.Custom(f)
end

-- Power bar and, if wanted, the power number. The bar folds away when the
-- unit has no power or is an NPC (if those options are on).
UF.Power = function(f)
    local cfg = db.frames[f.info.key]
    local show = cfg.powerH > 0
    local cur, max = UnitPower(f.unit), UnitPowerMax(f.unit)
    if show and cfg.pAuto and IsReadable(max) and type(max) == "number" and max <= 0 then show = false end
    if show and cfg.pHideNPC and UnitIsPlayer then
        local ok, isPlayer = pcall(UnitIsPlayer, f.unit)
        if ok and IsReadable(isPlayer) and not isPlayer then show = false end
    end
    if (not show) ~= (f.noPower == true) then
        f.noPower = not show
        UF.Layout(f, cfg)
    end
    if not show then return end
    f.power:SetMinMaxValues(0, max)
    if cfg.smooth and UF.interp then f.power:SetValue(cur, UF.interp) else f.power:SetValue(cur) end
    if cfg.powerText then f.pp:SetFormattedText("%d", cur) else f.pp:SetText("") end
    UF.Custom(f)
    if f.cp then UF.Combo(f) end
end

-- Bar colours. Anything the client will not let us read falls back to the
-- skin, so this cannot error on a secret value.
UF.Tint = function(f)
    local cfg = db.frames[f.info.key]
    local r, g, b = Col(currentSkin.bar)
    if cfg.color == "custom" then
        r, g, b = cfg.hr, cfg.hg, cfg.hb
    elseif cfg.color == "class" then
        local cr, cg, cb = UF.UnitColor(f.unit)
        if cr then r, g, b = cr, cg, cb end
    end
    f.health:SetStatusBarColor(r, g, b, 1)
    f.health.bg:SetVertexColor(r * 0.25, g * 0.25, b * 0.25, cfg.bgAlpha)
    r, g, b = Col(currentSkin.accent)
    if UnitPowerType and PowerBarColor then
        local ok, ptype, token = pcall(UnitPowerType, f.unit)
        local c = ok and ((IsReadable(token) and PowerBarColor[token]) or (IsReadable(ptype) and PowerBarColor[ptype]))
        if c and c.r then r, g, b = c.r, c.g, c.b end
    end
    f.power:SetStatusBarColor(r, g, b, 1)
    f.power.bg:SetVertexColor(r * 0.25, g * 0.25, b * 0.25, cfg.bgAlpha)
end

-- Name text: with or without the level, in the text colour or the unit's.
UF.Name = function(f)
    local cfg = db.frames[f.info.key]
    if not cfg.name then f.name:SetText(""); return end
    local n = UnitName(f.unit)
    local done = false
    if cfg.nameFormat ~= "name" and UnitLevel then
        local ok, lvl = pcall(UnitLevel, f.unit)
        if ok and IsReadable(lvl) and type(lvl) == "number" then
            local ls = lvl > 0 and tostring(lvl) or "??"
            if cfg.nameFormat == "level_name" then
                done = pcall(f.name.SetFormattedText, f.name, "%s %s", ls, n)
            else
                done = pcall(f.name.SetFormattedText, f.name, "%s (%s)", n, ls)
            end
        end
    end
    if not done then f.name:SetText(n) end
    local r, g, b
    if cfg.nameColor == "class" then r, g, b = UF.UnitColor(f.unit) end
    if r then f.name:SetTextColor(r, g, b, 1) else f.name:SetTextColor(TXT.Color()) end
end

-- Portrait: the unit's 2D picture or its 3D model.
UF.Portrait = function(f)
    local cfg = db.frames[f.info.key]
    local exists = UnitExists(f.unit)
    if not cfg.portrait then
        f.port:Hide()
        if f.model then f.model:Hide() end
        return
    end
    if cfg.portStyle == "3d" then
        if not f.model then
            f.model = CreateFrame("PlayerModel", nil, f)
            f.model:SetAllPoints(f.portBg)
        end
        f.port:Hide()
        f.model:SetShown(exists and true or false)
        if exists then
            pcall(f.model.SetUnit, f.model, f.unit)
            if f.model.SetPortraitZoom then f.model:SetPortraitZoom(1) end
        end
    else
        if f.model then f.model:Hide() end
        f.port:SetShown(exists and true or false)
        if exists and SetPortraitTexture then pcall(SetPortraitTexture, f.port, f.unit) end
    end
end

-- Raid target icon on any frame; resting and combat icons on the player's.
UF.Icons = function(f)
    local cfg = db.frames[f.info.key]
    local shown = false
    if cfg.raidIcon and GetRaidTargetIndex and SetRaidTargetIconTexture then
        local ok, idx = pcall(GetRaidTargetIndex, f.unit)
        if ok and IsReadable(idx) and type(idx) == "number" then
            SetRaidTargetIconTexture(f.raid, idx)
            shown = true
        end
    end
    f.raid:SetShown(shown)
    if f.info.key == "player" then
        f.rest:SetShown(cfg.restIcon and IsResting ~= nil and IsResting() and true or false)
        f.combat:SetShown(cfg.combatIcon and UnitAffectingCombat("player") and true or false)
    end
end

-- Border colour from threat: yellow, orange, red; the skin's border otherwise.
UF.Threat = function(f)
    local cfg = db.frames[f.info.key]
    local r, g, b, a = Col(currentSkin.border)
    if cfg.threat and UnitThreatSituation and f.info.key ~= "targettarget" then
        local ok, st
        if f.info.key == "target" then
            ok, st = pcall(UnitThreatSituation, "player", "target")
        else
            ok, st = pcall(UnitThreatSituation, "player")
        end
        if ok and IsReadable(st) and type(st) == "number" and st > 0 then
            if st >= 3 then r, g, b, a = 1, 0, 0, 1
            elseif st == 2 then r, g, b, a = 1, 0.6, 0, 1
            else r, g, b, a = 1, 1, 0.47, 1 end
        end
    end
    f:SetBackdropBorderColor(r, g, b, a)
end

-- Opacity: the frame's own, or the idle value while nothing keeps it awake.
-- SetAlpha is not a protected call, so this runs in combat.
UF.Fade = function(f)
    local cfg = db.frames[f.info.key]
    local a = cfg.alpha
    if cfg.fade and not EditMode() then
        local awake = (cfg.fadeCombat and UnitAffectingCombat("player"))
            or (cfg.fadeTarget and UnitExists("target"))
            or (cfg.fadeHover and f.hovering)
        if not awake then a = cfg.alpha * cfg.fadeAlpha end
    end
    f:SetAlpha(a)
end

-- What a poll or a plain refresh needs: no portrait work.
UF.Light = function(f)
    UF.Name(f)
    UF.Tint(f)
    UF.Health(f)
    UF.Power(f)
    UF.Icons(f)
end

-- Everything about the unit. With no such unit (the options window is open
-- and nothing is targeted) the frame shows its own label so it can still be
-- seen, sized and dragged.
UF.Update = function(f)
    if not db or not db.frames then return end
    local cfg = db.frames[f.info.key]
    local exists = UnitExists(f.unit)
    if not f.secure and f.info.key ~= "player" and not EditMode() then
        f:SetShown(exists and true or false)   -- no unit watch without the secure template
    end
    UF.Fade(f)
    if not exists then
        if f.noPower then f.noPower = false; UF.Layout(f, cfg) end
        f.name:SetText(cfg.name and f.info.label or "")
        f.name:SetTextColor(TXT.Color())
        f.hp:SetText("")
        f.pp:SetText("")
        f.health:SetMinMaxValues(0, 1); f.health:SetValue(1)
        f.power:SetMinMaxValues(0, 1); f.power:SetValue(1)
        f.health:SetStatusBarColor(Col(currentSkin.bar, 1))
        f.power:SetStatusBarColor(Col(currentSkin.accent, 1))
        f.raid:Hide()
        UF.Portrait(f)
        UF.Clear(f)
        return
    end
    UF.Light(f)
    UF.Portrait(f)
    UF.Threat(f)
    UF.More(f)
end

-- Start or stop listening for one frame's unit. A frame that is off listens
-- to nothing.
UF.Listen = function(f, on)
    if on == (f.listening == true) then return end
    f.listening = on
    local ev = f.ev
    for i = 1, #UF.EVENTS do
        if on then
            pcall(ev.RegisterUnitEvent, ev, UF.EVENTS[i], f.unit)
        else
            pcall(ev.UnregisterEvent, ev, UF.EVENTS[i])
        end
    end
    for i = 1, #UF.PLAIN do
        if on then
            pcall(ev.RegisterEvent, ev, UF.PLAIN[i])
        else
            pcall(ev.UnregisterEvent, ev, UF.PLAIN[i])
        end
    end
    if f.info.key == "targettarget" then
        -- no events exist for this unit: poll, and only while it is shown
        -- (f.ev is a child, so a hidden frame's OnUpdate does not run)
        if on then
            pcall(ev.RegisterUnitEvent, ev, "UNIT_TARGET", "target")
            ev:SetScript("OnUpdate", function(self, elapsed)
                self.t = (self.t or 0) + elapsed
                if self.t >= 0.2 then
                    self.t = 0
                    if UnitExists(f.unit) then UF.Light(f); UF.AurasAll(f) end
                end
            end)
        else
            pcall(ev.UnregisterEvent, ev, "UNIT_TARGET")
            ev:SetScript("OnUpdate", nil)
        end
    end
end

-- Build one frame. Runs once per unit, the first time it is switched on, and
-- never in combat (UF.Apply sees to that).
UF.Create = function(info)
    local name = "FRHW2UF_" .. info.key
    local ok, f = pcall(CreateFrame, "Button", name, UIParent, "SecureUnitButtonTemplate,BackdropTemplate")
    local secure = ok and f ~= nil
    if not secure then f = CreateFrame("Button", name, UIParent, "BackdropTemplate") end
    f.info, f.unit, f.secure = info, info.unit, secure
    if secure and f.SetAttribute then
        f:SetAttribute("unit", info.unit)
        f:SetAttribute("type1", "target")       -- left click: target the unit
        f:SetAttribute("type2", "togglemenu")   -- right click: the unit's menu
    end
    if f.RegisterForClicks then f:RegisterForClicks("AnyUp") end
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                    insets = { left = 1, right = 1, top = 1, bottom = 1 } })

    -- behind the health bar: its background, and the cutaway layer
    f.back = CreateFrame("StatusBar", nil, f)
    f.back:SetStatusBarTexture(WHITE)
    f.back:SetStatusBarColor(1, 1, 1, 0.35)
    f.health = CreateFrame("StatusBar", nil, f)
    f.back:SetAllPoints(f.health)
    f.health.bg = Decor(f.back, "BORDER")
    f.health.bg:SetAllPoints(true)
    f.hl = Decor(f.health, "OVERLAY")
    f.hl:SetAllPoints(true)
    f.hl:SetBlendMode("ADD")
    f.hl:SetVertexColor(1, 1, 1, 0.10)
    f.hl:Hide()
    f.power = CreateFrame("StatusBar", nil, f)
    f.power.bg = Decor(f.power, "BORDER")
    f.power.bg:SetAllPoints(true)
    f.portBg = Decor(f, "BORDER")
    f.portBg:SetVertexColor(0, 0, 0, 0.6)
    f.port = f:CreateTexture(nil, "ARTWORK")
    f.port:SetAllPoints(f.portBg)
    f.port:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    -- texts and icons sit on their own layer above both bars
    f.top = CreateFrame("Frame", nil, f)
    f.top:SetAllPoints(f)
    f.name = f.top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.name:SetWordWrap(false)
    f.hp = f.top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.pp = f.top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.raid = f.top:CreateTexture(nil, "OVERLAY")
    f.raid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    f.raid:SetPoint("CENTER", f, "TOP", 0, 0)
    f.raid:Hide()
    f.rest = f.top:CreateTexture(nil, "OVERLAY")
    f.rest:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
    f.rest:SetTexCoord(0, 0.5, 0, 0.421875)
    f.rest:SetPoint("CENTER", f, "TOPLEFT", 0, 0)
    f.rest:Hide()
    f.combat = f.top:CreateTexture(nil, "OVERLAY")
    f.combat:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
    f.combat:SetTexCoord(0.5, 1, 0, 0.484375)
    f.combat:SetPoint("CENTER", f, "TOPRIGHT", 0, 0)
    f.combat:Hide()
    f.kit = MakeEdges(f)   -- the skin's edge style, same as the HUD bars
    UF.Extras(f)

    f:SetScript("OnEnter", function(self)
        self.hovering = true
        if db and db.frames then
            if db.frames[info.key].hover then self.hl:Show() end
            UF.Fade(self)
        end
        if GameTooltip and GameTooltip.SetUnit and UnitExists(self.unit) then
            if GameTooltip_SetDefaultAnchor then GameTooltip_SetDefaultAnchor(GameTooltip, UIParent) end
            GameTooltip:SetUnit(self.unit)
            GameTooltip:Show()
        end
    end)
    f:SetScript("OnLeave", function(self)
        self.hovering = false
        self.hl:Hide()
        if db and db.frames then UF.Fade(self) end
        if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
    end)

    -- Mouse editing while the options window is open, as for every HUD item:
    -- CTRL + left hold moves, CTRL + wheel sizes. A unit frame is a stack of
    -- bars and text and does not turn. Placed from the screen centre.
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetScript("OnMouseWheel", function(self, delta)
        if not ME.Active() or UF.Locked() then return end
        if not (IsControlKeyDown and IsControlKeyDown()) then return end
        local cfg = db.frames[info.key]
        local sc = math.floor(((cfg.scale or 1) + ((delta > 0) and ME.SCALE_STEP or -ME.SCALE_STEP)) * 100 + 0.5) / 100
        if sc < 0.5 then sc = 0.5 elseif sc > 3 then sc = 3 end
        cfg.scale = sc
        UF.Apply()
        UF.Refresh()
    end)
    if f.EnableMouseWheel then f:EnableMouseWheel(EditMode()) end
    f:HookScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or not ME.Active() or UF.Locked() then return end
        if not (IsControlKeyDown and IsControlKeyDown()) then return end
        self:StartMoving()
        self._dragging = true
    end)
    f:HookScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" or not self._dragging then return end
        self._dragging = false
        self:StopMovingOrSizing()
        local fx, fy = ScreenCenter(self)
        local ux, uy = UIParent:GetCenter()
        if fx and ux then
            local cfg = db.frames[info.key]
            cfg.x = math.floor(Snap(fx - ux) + 0.5)
            cfg.y = math.floor(Snap(fy - uy) + 0.5)
        end
        UF.Apply()
        UF.Refresh()
    end)

    f.ev = CreateFrame("Frame", nil, f)
    f.ev:SetScript("OnEvent", function(_, event)
        if not db or not db.frames then return end
        local route = UF.ROUTE[event]   -- cast bar, auras, heals, status icons
        if route then
            route(f)
        elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            UF.Health(f)
        elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then
            UF.Power(f)
        elseif event == "UNIT_PORTRAIT_UPDATE" or event == "UNIT_MODEL_CHANGED" then
            UF.Portrait(f)
        elseif event == "UNIT_THREAT_SITUATION_UPDATE" then
            UF.Threat(f)
        elseif event == "RAID_TARGET_UPDATE" or event == "PLAYER_UPDATE_RESTING" then
            UF.Icons(f)
        elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
            UF.Icons(f); UF.Fade(f); UF.Threat(f)
        elseif event == "PLAYER_TARGET_CHANGED" and info.key == "player" then
            UF.Fade(f)
            if f.cp then UF.Combo(f) end
        else
            UF.Update(f)
        end
    end)
    return f
end

-- Bars, portrait, texts and icons inside the frame. None of this is
-- protected, so it may run in combat (the power bar folding away does).
UF.Layout = function(f, cfg)
    local ph = 0
    if cfg.powerH > 0 and not f.noPower then ph = math.min(cfg.powerH, math.max(0, cfg.h - 8)) end
    local lx, rx = 1, 1   -- inner left / right edge of the bars
    if cfg.portrait then
        local pw = cfg.portW > 0 and cfg.portW or (cfg.h - 2)
        pw = math.min(pw, math.max(4, cfg.w - 30))
        f.portBg:ClearAllPoints()
        if cfg.portSide == "right" then
            f.portBg:SetPoint("TOPRIGHT", -1, -1)
            f.portBg:SetPoint("BOTTOMRIGHT", -1, 1)
            rx = pw + 2
        else
            f.portBg:SetPoint("TOPLEFT", 1, -1)
            f.portBg:SetPoint("BOTTOMLEFT", 1, 1)
            lx = pw + 2
        end
        f.portBg:SetWidth(pw)
        f.portBg:Show()
    else
        f.portBg:Hide()
    end
    -- info panel: a strip along the bottom that carries the name and health texts
    local ip = cfg.info and math.min(cfg.infoH, math.max(0, cfg.h - 12)) or 0
    local base = ip > 0 and (ip + 2) or 1
    f.infoBg:ClearAllPoints()
    f.infoBg:SetPoint("BOTTOMLEFT", lx, 1)
    f.infoBg:SetPoint("BOTTOMRIGHT", -rx, 1)
    f.infoBg:SetHeight(math.max(1, ip))
    f.infoBg:SetShown(ip > 0)
    f.health:ClearAllPoints()
    f.health:SetPoint("TOPLEFT", lx, -1)
    f.health:SetPoint("BOTTOMRIGHT", -rx, base + (ph > 0 and (ph + 1) or 0))
    f.power:ClearAllPoints()
    f.power:SetPoint("BOTTOMLEFT", lx, base)
    f.power:SetPoint("BOTTOMRIGHT", -rx, base)
    f.power:SetHeight(math.max(1, ph))
    f.power:SetShown(ph > 0)
    f.pp:SetShown(ph > 0)

    -- a text anchored to a side keeps 4 px off that edge
    local function Put(fs, bar, anchor, x, y)
        fs:ClearAllPoints()
        fs:SetPoint(anchor, bar, anchor, x + (anchor == "LEFT" and 4 or anchor == "RIGHT" and -4 or 0), y)
        fs:SetJustifyH((anchor == "LEFT" or anchor == "RIGHT") and anchor or "CENTER")
    end
    local textHome = ip > 0 and f.infoBg or f.health
    Put(f.name, textHome, cfg.nAnchor, cfg.nX, cfg.nY)
    Put(f.hp, textHome, cfg.hAnchor, cfg.hX, cfg.hY)
    Put(f.pp, f.power, cfg.pAnchor, cfg.pX, cfg.pY)
    Put(f.c1, f.health, cfg.c1Anchor, cfg.c1X, cfg.c1Y)
    Put(f.c2, f.health, cfg.c2Anchor, cfg.c2X, cfg.c2Y)
    -- a long name is cut short rather than run under the health text
    local barW = cfg.w - lx - rx
    local share = (cfg.health ~= "none" and cfg.nAnchor ~= cfg.hAnchor) and 0.62 or 1
    f.name:SetWidth(math.max(20, barW * share - 8))

    f.raid:SetSize(cfg.iconSize, cfg.iconSize)
    f.rest:SetSize(cfg.iconSize, cfg.iconSize)
    f.combat:SetSize(cfg.iconSize, cfg.iconSize)
    UF.LayoutMore(f, cfg, barW)
end

-- Typeface, size, outline and shadow of every unit frame text. Called from
-- TXT.Apply as well, so the frames follow the Text tab.
UF.Fonts = function()
    if not db or not db.frames or not db.text then return end
    local t = db.text
    for key, f in pairs(UF.frames) do
        local cfg = db.frames[key]
        local path = TXT.FontPath(cfg.font or t.font)
        TXT.Font(f.name, path, cfg.fontSize, t.outline)
        TXT.Font(f.hp, path, cfg.fontSize, t.outline)
        TXT.Font(f.pp, path, math.max(6, math.min(cfg.fontSize, cfg.powerH)), t.outline)
        UF.FontMore(f, path, cfg, t)
        for _, fs in ipairs({ f.name, f.hp, f.pp, f.c1, f.c2 }) do
            if t.shadow then
                fs:SetShadowColor(0, 0, 0, 1); fs:SetShadowOffset(1, -1)
            else
                fs:SetShadowOffset(0, 0)
            end
        end
    end
end

-- Text colour: the skin's, or the custom one from the Text tab.
UF.TextColor = function()
    local r, g, b, a = TXT.Color()
    for key, f in pairs(UF.frames) do
        f.hp:SetTextColor(r, g, b, a)
        f.pp:SetTextColor(r, g, b, a)
        f.c1:SetTextColor(r, g, b, a)
        f.c2:SetTextColor(r, g, b, a)
        if f.cast then
            f.cast.text:SetTextColor(r, g, b, a)
            f.cast.time:SetTextColor(r, g, b, a)
        end
        if db and db.frames and db.frames[key].enabled and UnitExists(f.unit) then
            UF.Name(f)   -- the name may be class coloured
        else
            f.name:SetTextColor(r, g, b, a)
        end
    end
end

-- Skin colours. Called from ApplySkin; nothing here is protected.
UF.Paint = function()
    for key, f in pairs(UF.frames) do
        local cfg = db and db.frames and db.frames[key]
        if cfg then f:SetBackdropColor(cfg.bgr, cfg.bgg, cfg.bgb, 0.85) else f:SetBackdropColor(0, 0, 0, 0.85) end
        f:SetBackdropBorderColor(Col(currentSkin.border))
        PaintEdges(f.kit, currentSkin)
        if db and db.frames and db.frames[key].enabled then UF.Update(f) end
    end
    UF.TextColor()
end

-- Push db.frames to the frames: build, place, size, show or hide, and hide
-- or restore the game's own. In combat it does nothing but remember that it
-- was asked, and runs when combat ends.
UF.Apply = function()
    if not db or type(db.frames) ~= "table" then return end
    if UF.Locked() then
        TXT.AfterCombat("frames", UF.Apply)
        return
    end
    UF.interp = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut or nil
    local edit = EditMode()
    for i = 1, #UF.UNITS do
        local info = UF.UNITS[i]
        local cfg = db.frames[info.key]
        local f = UF.frames[info.key]
        -- While the options window is open every unit frame is on screen, the
        -- switched-off ones too (dimmed, tagged OFF), so each can be placed
        -- and sized with the mouse before or after it is switched on.
        local want = cfg.enabled or edit
        if want and not f then
            f = UF.Create(info)
            UF.frames[info.key] = f
        end
        if f then
            if f.secure and UnregisterUnitWatch then UnregisterUnitWatch(f) end
            if want then
                f:ClearAllPoints()
                f:SetScale(cfg.scale)
                f:SetPoint("CENTER", UIParent, "CENTER", cfg.x / cfg.scale, cfg.y / cfg.scale)
                f:SetSize(cfg.w, cfg.h)
                f:SetFrameStrata(cfg.strata)
                f:SetFrameLevel(cfg.level)
                f.back:SetFrameLevel(cfg.level + 1)
                f.health:SetFrameLevel(cfg.level + 2)
                f.power:SetFrameLevel(cfg.level + 2)
                f.top:SetFrameLevel(cfg.level + 6)
                local tex = TXT.Find(UF.TEX, cfg.texture).path
                f.health:SetStatusBarTexture(tex)
                f.power:SetStatusBarTexture(tex)
                if f.health.SetReverseFill then
                    f.health:SetReverseFill(cfg.hReverse)
                    f.power:SetReverseFill(cfg.pReverse)
                end
                UF.Layout(f, cfg)
                UF.Listen(f, true)
                if not f.offTag then
                    f.offTag = f.top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    f.offTag:SetPoint("CENTER", f, "CENTER", 0, 0)
                    f.offTag:SetText("OFF  -  tick Enable on the Frames tab")
                end
                f.offTag:SetShown(not cfg.enabled)
                if cfg.enabled then
                    f:SetAlpha(1)
                    UF.Fade(f)
                else
                    f:SetAlpha(0.45)
                end
                if info.key == "player" or edit then
                    f:Show()                    -- the options window shows every frame
                elseif f.secure and RegisterUnitWatch then
                    RegisterUnitWatch(f)        -- the client shows it while the unit exists
                else
                    f:SetShown(UnitExists(info.unit) and true or false)
                end
            else
                UF.Listen(f, false)
                f:Hide()
            end
        end
        TXT.Stash(_G[info.blizz], cfg.enabled and cfg.hideBlizzard)
    end
    local pc = db.frames.player
    TXT.Stash(_G.PlayerCastingBarFrame or _G.CastingBarFrame, pc.enabled and pc.cb and pc.cbHideBlizz)
    UF.Fonts()
    UF.Paint()
end

-- Show the selected unit's settings on the Frames tab.
UF.Refresh = function()
    local ui = UF.ui
    if not ui or not db or type(db.frames) ~= "table" then return end
    local was = suppress
    suppress = true
    local cfg = db.frames[UF.sel]
    local label = ""
    for i = 1, #UF.UNITS do
        local info = UF.UNITS[i]
        local b = ui.pick[info.key]
        b:SetText(info.label .. (db.frames[info.key].enabled and "  (on)" or "  (off)"))
        if info.key == UF.sel then b:Disable(); label = info.label else b:Enable() end
    end
    if cfg.enabled then
        ui.status:SetText(label .. " frame is ON. Hold CTRL and drag it, or use the sliders. Changes made in combat apply when it ends.")
    else
        ui.status:SetText(label .. " frame is OFF: nothing below shows until you tick \"Enable this frame\".")
    end
    TXT.ShowOptions(ui.ws, UF.OPTS, cfg, UF.sel, db.text and db.text.font)
    suppress = was
end

FRHW2_FRAMES = UF
FRHW2_ApplyFrames = function() if db then UF.Apply() end end
-- Open the Frames tab on one unit ("player", "target", "targettarget").
function FRHW2_SelectFrame(key)
    if not DEFAULTS.frames[key] then return false end
    UF.sel = key
    UF.Refresh()
    return true
end

-- ============================ Frames tab ============================
do
    local page = CreateFrame("Frame", nil, panel)
    page:SetPoint("TOPLEFT", 8, -70)
    page:SetPoint("BOTTOMRIGHT", -8, 26)
    page:Hide()
    AddTab("frames", "FRHW2TabFrames", "Frames", page)
    local scroll, child = MakeScroll("FRHW2FramesScroll", page, -4)
    local flow = NewFlow(scroll, child)
    local ui = { pick = {} }
    UF.ui = ui

    -- which frame this page is editing: one button each, the current one greyed
    for i = 1, #UF.UNITS do
        local info = UF.UNITS[i]
        ui.pick[info.key] = MakeButton(child, info.label, 0, 0, 120, 22, function()
            UF.sel = info.key
            UF.Refresh()
        end, "FRHW2UFSel_" .. info.key)
    end
    Row(flow, LAYOUT.slider, ui.pick.player, ui.pick.targettarget, ui.pick.target)
    NoteRow(flow, "")
    ui.status = flow.rows[#flow.rows].note
    flow.rows[#flow.rows].h = 34   -- room for two lines

    ui.ws = TXT.BuildOptions(flow, child, "FRHW2UFO_", UF.OPTS,
        function() return db.frames[UF.sel] end,
        function(o, isSlider)
            UF.Apply()
            if not isSlider then UF.Refresh() end
        end)

    -- opening the window shows every frame that is on (so it can be placed
    -- with nothing targeted); closing it hands them back to the client
    panel:HookScript("OnShow", function() UF.Apply() end)
    panel:HookScript("OnHide", function() UF.Apply() end)
end

-- the wheel only belongs to a unit frame while the options window is open
ME.onInteractive = function(on)
    -- opening or closing the window changes which frames are on screen
    -- (all three while it is open), so apply before handing out the wheel
    if db and db.frames then UF.Apply() end
    for _, f in pairs(UF.frames) do
        if f.EnableMouseWheel then f:EnableMouseWheel(on) end
    end
end

-----------------------------------------------------------------------
-- Unit frame extras: cast bar, buffs / debuffs, aura bars, incoming heals,
-- custom texts, combo points, status icons
--
-- Same rules as the frames themselves: each piece is built the first time
-- its option is on, driven by events, and hands whatever the client marks
-- secret straight to a widget. On this client cast and aura times arrive as
-- "duration objects"; a bar or a cooldown takes one whole (SetTimerDuration,
-- SetCooldownFromDurationObject), so no arithmetic is ever done on them.
-- Where a client has no such object the plain numbers are used instead.
-----------------------------------------------------------------------

-- True only for a value we are allowed to read that is also truthy.
UF.Flag = function(fn, ...)
    if not fn then return false end
    local ok, v = pcall(fn, ...)
    return ok and IsReadable(v) and v and true or false
end

-- The pieces every frame has from the start (cheap: textures and strings).
UF.Extras = function(f)
    f.heal = CreateFrame("StatusBar", nil, f.health)
    f.heal:SetStatusBarTexture(WHITE)
    f.heal:SetStatusBarColor(0.2, 1, 0.4, 0.45)
    f.heal:Hide()
    if f.health.SetClipsChildren then f.health:SetClipsChildren(true) end
    f.infoBg = Decor(f, "BORDER")
    f.infoBg:SetVertexColor(0, 0, 0, 0.5)
    f.infoBg:Hide()
    f.c1 = f.top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.c2 = f.top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.stat = {}
    local function Icon(key, tex, point, shift)
        local t = f.top:CreateTexture(nil, "OVERLAY")
        if tex then t:SetTexture(tex) end
        t.point, t.shift = point, shift
        t:Hide()
        f.stat[key] = t
    end
    Icon("leader", "Interface\\GroupFrame\\UI-Group-LeaderIcon", "TOPLEFT", 1)
    Icon("phase", "Interface\\TargetingFrame\\UI-PhasingIcon", "TOP", 1)
    Icon("rez", "Interface\\RaidFrame\\Raid-Icon-Rez", "CENTER", 0)
    Icon("pvp", nil, "BOTTOMRIGHT", 0)
    f.buffs, f.debuffs, f.abars = {}, {}, {}
end

-- ---------------------------------------------------------------- cast bar
UF.CastBar = function(f)
    if f.cast then return f.cast end
    local cb = CreateFrame("StatusBar", nil, f)
    f.cast = cb
    cb:SetStatusBarTexture(WHITE)
    cb.bg = Decor(cb, "BACKGROUND")
    cb.bg:SetPoint("TOPLEFT", -1, 1)
    cb.bg:SetPoint("BOTTOMRIGHT", 1, -1)
    cb.bg:SetVertexColor(0, 0, 0, 0.85)
    cb.icon = cb:CreateTexture(nil, "ARTWORK")
    cb.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    cb.shield = Decor(cb, "OVERLAY")   -- grey wash over a cast that cannot be interrupted
    cb.shield:SetAllPoints(true)
    cb.shield:SetVertexColor(0.6, 0.6, 0.6, 0.5)
    cb.shield:Hide()
    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cb.text:SetPoint("LEFT", 4, 0)
    cb.text:SetJustifyH("LEFT")
    cb.text:SetWordWrap(false)
    cb.time = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cb.time:SetPoint("RIGHT", -4, 0)
    cb:Hide()
    -- runs only while a cast is on screen
    cb:SetScript("OnUpdate", function(self, elapsed)
        self.t = (self.t or 0) + elapsed
        if self.s then
            -- plain-number timing (a client without duration objects)
            local now = GetTime()
            if now >= self.e then self:Hide(); return end
            self:SetValue(self.chan and (self.e - now) or (now - self.s))
            if self.t >= 0.05 then
                self.t = 0
                if self.showTime then self.time:SetFormattedText("%.1f", self.e - now) end
            end
        elseif self.t >= 0.05 then
            self.t = 0
            if self.showTime and self.GetTimerDuration then
                local d = self:GetTimerDuration()
                if d then self.time:SetFormattedText("%.1f", d:GetRemainingDuration()) end
            end
        end
    end)
    UF.Layout(f, db.frames[f.info.key])   -- size and place it now that it exists
    UF.Fonts()
    UF.TextColor()
    return cb
end

-- Start, refresh or end the cast bar from what the unit is doing right now.
-- Every cast event lands here; asking the client again is simpler and safer
-- than tracking each event's meaning.
UF.Cast = function(f)
    local cfg = db.frames[f.info.key]
    if not cfg.cb or f.info.key == "targettarget" then
        if f.cast then f.cast:Hide() end
        return
    end
    local u = f.unit
    local chan = false
    local name, _, texture, s, e, _, _, notInt = UnitCastingInfo(u)
    local cb
    if UnitCastingDuration then
        local dur = UnitCastingDuration(u)
        if not dur and UnitChannelDuration then
            dur = UnitChannelDuration(u)
            if dur then
                chan = true
                name, _, texture, s, e, _, notInt = UnitChannelInfo(u)
            end
        end
        if not dur then
            if f.cast then f.cast:Hide() end
            return
        end
        cb = UF.CastBar(f)
        cb.s = nil
        local dir = Enum and Enum.StatusBarTimerDirection
        cb:SetTimerDuration(dur, Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or nil,
            dir and (chan and dir.RemainingTime or dir.ElapsedTime) or nil)
    else
        if not IsReadable(name) then
            chan = true
            name, _, texture, s, e, _, notInt = UnitChannelInfo(u)
        end
        if not IsReadable(name) or not IsReadable(s) or not IsReadable(e) or type(s) ~= "number" or type(e) ~= "number" then
            if f.cast then f.cast:Hide() end
            return
        end
        cb = UF.CastBar(f)
        cb.s, cb.e = s / 1000, e / 1000
        cb:SetMinMaxValues(0, cb.e - cb.s)
    end
    cb.chan, cb.showTime = chan, cfg.cbTime
    cb.text:SetText(name)
    cb.icon:SetTexture(texture)
    if not cfg.cbTime then cb.time:SetText("") end
    if IsReadable(notInt) then
        cb.shield:SetAlpha(1)
        cb.shield:SetShown(notInt and true or false)
    elseif cb.shield.SetAlphaFromBoolean then
        cb.shield:Show()
        cb.shield:SetAlphaFromBoolean(notInt, 1, 0)
    else
        cb.shield:Hide()
    end
    cb:Show()
end

-- ------------------------------------------------------- buffs and debuffs
UF.AuraButton = function(f, list, i)
    local b = CreateFrame("Frame", nil, f)
    b.bg = Decor(b, "BACKGROUND")
    b.bg:SetAllPoints(true)
    b.bg:SetVertexColor(0, 0, 0, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.icon)
    b.cd:SetDrawEdge(false)
    b.over = CreateFrame("Frame", nil, b)
    b.over:SetAllPoints(b)
    if b.over.SetFrameLevel and b.cd.GetFrameLevel then b.over:SetFrameLevel(b.cd:GetFrameLevel() + 2) end
    b.count = b.over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.count:SetPoint("BOTTOMRIGHT", 1, 0)
    b:EnableMouse(true)
    b:SetScript("OnEnter", function(self)
        if not GameTooltip or not GameTooltip.SetUnitAura then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        pcall(GameTooltip.SetUnitAura, GameTooltip, f.unit, self.index, self.filter)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end end)
    list[i] = b
    UF.PlaceAura(f, list, i)
    return b
end

-- Put button i of a row set where the layout says (list.size / perRow / dir / base).
UF.PlaceAura = function(f, list, i)
    local b = list[i]
    local size, per = list.size or 20, list.perRow or 8
    local col, row = (i - 1) % per, math.floor((i - 1) / per)
    b:SetSize(size, size)
    b:ClearAllPoints()
    if list.dir == -1 then
        b:SetPoint("TOPLEFT", f, "BOTTOMLEFT", col * (size + 2), -((list.base or 3) + row * (size + 2)))
    else
        b:SetPoint("BOTTOMLEFT", f, "TOPLEFT", col * (size + 2), (list.base or 3) + row * (size + 2))
    end
end

-- Fill one set of aura icons from the client. The filter does the choosing
-- ("only mine" is the client's PLAYER filter), so nothing secret is compared.
UF.FillAuras = function(f, list, on, max, filter)
    local shown = 0
    local A = C_UnitAuras
    if on and A and A.GetAuraDataByIndex then
        for i = 1, max do
            local ok, a = pcall(A.GetAuraDataByIndex, f.unit, i, filter)
            if not ok or type(a) ~= "table" then break end
            local b = list[i] or UF.AuraButton(f, list, i)
            b.index, b.filter = i, filter
            b.icon:SetTexture(a.icon)
            local okd, d = false, nil
            if A.GetAuraDuration then okd, d = pcall(A.GetAuraDuration, f.unit, a.auraInstanceID) end
            if okd and d and b.cd.SetCooldownFromDurationObject then
                pcall(b.cd.SetCooldownFromDurationObject, b.cd, d)
            elseif IsReadable(a.expirationTime) and IsReadable(a.duration)
                and type(a.duration) == "number" and type(a.expirationTime) == "number" and a.duration > 0 then
                b.cd:SetCooldown(a.expirationTime - a.duration, a.duration)
            else
                b.cd:Clear()
            end
            local n = a.applications
            if IsReadable(n) and type(n) == "number" then
                b.count:SetText(n > 1 and tostring(n) or "")
            elseif A.GetAuraApplicationDisplayCount then
                local okc, txt = pcall(A.GetAuraApplicationDisplayCount, f.unit, a.auraInstanceID, 2, 99)
                if okc then b.count:SetText(txt) else b.count:SetText("") end
            else
                b.count:SetText("")
            end
            b:Show()
            shown = i
        end
    end
    for i = shown + 1, #list do list[i]:Hide() end
end

-- --------------------------------------------------------------- aura bars
UF.AuraBar = function(f, i)
    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetStatusBarTexture(WHITE)
    bar.bg = Decor(bar, "BACKGROUND")
    bar.bg:SetPoint("TOPLEFT", -1, 1)
    bar.bg:SetPoint("BOTTOMRIGHT", 1, -1)
    bar.bg:SetVertexColor(0, 0, 0, 0.85)
    bar.icon = bar:CreateTexture(nil, "ARTWORK")
    bar.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    bar.icon:SetPoint("RIGHT", bar, "LEFT", -2, 0)
    bar.name = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.name:SetPoint("LEFT", 4, 0)
    bar.name:SetJustifyH("LEFT")
    bar.name:SetWordWrap(false)
    f.abars[i] = bar
    return bar
end

UF.AuraBars = function(f)
    local cfg = db.frames[f.info.key]
    local list, shown = f.abars, 0
    local A = C_UnitAuras
    if cfg.abOn and A and A.GetAuraDataByIndex then
        local debuff = cfg.abType == "debuffs"
        local filter = (debuff and "HARMFUL" or "HELPFUL") .. (cfg.abMine and "|PLAYER" or "")
        local w = math.max(20, cfg.w - cfg.abH - 2)
        for i = 1, cfg.abMax do
            local ok, a = pcall(A.GetAuraDataByIndex, f.unit, i, filter)
            if not ok or type(a) ~= "table" then break end
            local bar = list[i]
            if not bar then
                bar = UF.AuraBar(f, i)
                UF.Fonts()
                UF.TextColor()
            end
            bar:SetSize(w, cfg.abH)
            bar.icon:SetSize(cfg.abH, cfg.abH)
            bar:ClearAllPoints()
            bar:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, (f.abBase or 3) + (i - 1) * (cfg.abH + 3))
            bar.name:SetWidth(w - 8)
            bar.name:SetText(a.name)
            bar.icon:SetTexture(a.icon)
            if debuff then bar:SetStatusBarColor(0.8, 0.2, 0.2, 1) else bar:SetStatusBarColor(Col(currentSkin.accent, 1)) end
            local okd, d = false, nil
            if A.GetAuraDuration then okd, d = pcall(A.GetAuraDuration, f.unit, a.auraInstanceID) end
            local dir = Enum and Enum.StatusBarTimerDirection
            if okd and d and bar.SetTimerDuration and dir then
                bar:SetTimerDuration(d, Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or nil, dir.RemainingTime)
            else
                bar:SetMinMaxValues(0, 1)   -- no timer available: a full bar
                bar:SetValue(1)
            end
            bar:Show()
            shown = i
        end
    end
    for i = shown + 1, #list do list[i]:Hide() end
end

-- Buffs, debuffs and aura bars together: one UNIT_AURA, one pass.
UF.AurasAll = function(f)
    local cfg = db.frames[f.info.key]
    UF.FillAuras(f, f.buffs, cfg.bOn, cfg.bMax, cfg.bMine and "HELPFUL|PLAYER" or "HELPFUL")
    UF.FillAuras(f, f.debuffs, cfg.dOn, cfg.dMax, cfg.dMine and "HARMFUL|PLAYER" or "HARMFUL")
    UF.AuraBars(f)
end

-- ----------------------------------------------------------- incoming heals
-- A bar that starts where the health fill ends and is as wide as the whole
-- health bar, clipped by it: the heal amount needs no arithmetic at all.
UF.Heal = function(f)
    local cfg = db.frames[f.info.key]
    if not cfg.hpred or not UnitGetIncomingHeals then f.heal:Hide(); return end
    local ok, inc = pcall(UnitGetIncomingHeals, f.unit)
    if not ok or inc == nil then f.heal:Hide(); return end   -- nil: no heal data for this unit
    f.heal:SetMinMaxValues(0, UnitHealthMax(f.unit))
    f.heal:SetShown(pcall(f.heal.SetValue, f.heal, inc))   -- nil (no heal data) just hides it
end

-- ------------------------------------------------------------- custom texts
UF.Custom = function(f)
    local cfg = db.frames[f.info.key]
    for slot = 1, 2 do
        local kind = cfg[slot == 1 and "c1" or "c2"]
        local fs = slot == 1 and f.c1 or f.c2
        if kind == "none" or not UnitExists(f.unit) then
            fs:SetText("")
        elseif kind == "level" then
            local ok, lvl = pcall(UnitLevel, f.unit)
            if ok and IsReadable(lvl) and type(lvl) == "number" then
                fs:SetText(lvl > 0 and tostring(lvl) or "??")
            else
                fs:SetText("")
            end
        elseif kind == "class" then
            local ok, a = false, nil
            if UF.Flag(UnitIsPlayer, f.unit) then
                ok, a = pcall(UnitClass, f.unit)
            elseif UnitCreatureType then
                ok, a = pcall(UnitCreatureType, f.unit)
            end
            if ok then fs:SetText(a) else fs:SetText("") end
        elseif kind == "hcur" then
            TXT.Value(fs, "cur", UnitHealth(f.unit), UnitHealthMax(f.unit))
        elseif kind == "hpp" then
            TXT.Value(fs, "percent", UnitHealth(f.unit), UnitHealthMax(f.unit))
        elseif kind == "pow" then
            TXT.Value(fs, "cur", UnitPower(f.unit), UnitPowerMax(f.unit))
        else
            TXT.Value(fs, "percent", UnitPower(f.unit), UnitPowerMax(f.unit))
        end
    end
end

-- ------------------------------------------------------------- combo points
-- Same reading as the HUD's own combo element, including its secret path.
UF.Combo = function(f)
    local cp = GetComboPoints("player", "target")
    if not IsReadable(cp) then cp = UnitPower("player", 14) end
    for i = 1, #f.cp do
        local b = f.cp[i]
        if IsReadable(cp) then
            b:SetMinMaxValues(0, 1)
            b:SetValue(1)
            b:SetAlpha(type(cp) == "number" and i <= cp and 1 or 0.2)
        else
            b:SetAlpha(1)
            b:SetMinMaxValues(i - 1, i)
            b:SetValue(cp)
        end
    end
end

-- ------------------------------------------------------------- status icons
UF.Status = function(f)
    local cfg = db.frames[f.info.key]
    local u = f.unit
    f.stat.leader:SetShown(cfg.leaderIcon and UF.Flag(UnitIsGroupLeader, u))
    f.stat.rez:SetShown(cfg.rezIcon and UF.Flag(UnitHasIncomingResurrection, u))
    f.stat.phase:SetShown(cfg.phaseIcon and f.info.key ~= "player" and UF.Flag(UnitPhaseReason, u))
    local pvp = false
    if cfg.pvpIcon and UF.Flag(UnitIsPVP, u) and UnitFactionGroup then
        local ok, faction = pcall(UnitFactionGroup, u)
        if ok and IsReadable(faction) and (faction == "Alliance" or faction == "Horde") then
            f.stat.pvp:SetTexture("Interface\\TargetingFrame\\UI-PVP-" .. faction)
            pvp = true
        end
    end
    f.stat.pvp:SetShown(pvp)
end

-- Everything above for a unit that exists; called from UF.Update.
UF.More = function(f)
    UF.Cast(f)
    UF.AurasAll(f)
    UF.Heal(f)
    UF.Status(f)
    UF.Custom(f)
    if f.cp then UF.Combo(f) end
end

-- And for a unit that does not (the placeholder shown while placing a frame).
UF.Clear = function(f)
    if f.cast then f.cast:Hide() end
    for _, list in ipairs({ f.buffs, f.debuffs, f.abars }) do
        for i = 1, #list do list[i]:Hide() end
    end
    f.heal:Hide()
    for _, t in pairs(f.stat) do t:Hide() end
    f.c1:SetText("")
    f.c2:SetText("")
end

-- Which function an event goes to (looked up in the frame's OnEvent).
UF.ROUTE = {
    UNIT_AURA = UF.AurasAll,
    UNIT_HEAL_PREDICTION = UF.Heal,
    UNIT_PHASE = UF.Status,
    PARTY_LEADER_CHANGED = UF.Status,
    GROUP_ROSTER_UPDATE = UF.Status,
    INCOMING_RESURRECT_CHANGED = UF.Status,
}
for _, ev in ipairs({ "START", "CHANNEL_START", "STOP", "CHANNEL_STOP", "DELAYED", "CHANNEL_UPDATE",
                      "FAILED", "INTERRUPTED", "INTERRUPTIBLE", "NOT_INTERRUPTIBLE", "SUCCEEDED" }) do
    UF.ROUTE["UNIT_SPELLCAST_" .. ev] = UF.Cast
end

-- Size and place the extras. Things attached above and below the frame are
-- stacked outwards in a fixed order, so they never overlap each other:
-- cast bar, combo points, buffs, debuffs, aura bars.
UF.LayoutMore = function(f, cfg, barW)
    local above, below = 3, 3

    -- incoming heals: from the end of the health fill, clipped by the bar
    local tex = f.health:GetStatusBarTexture()
    f.heal:ClearAllPoints()
    if tex then
        if cfg.hReverse then
            f.heal:SetPoint("TOPRIGHT", tex, "TOPLEFT")
            f.heal:SetPoint("BOTTOMRIGHT", tex, "BOTTOMLEFT")
        else
            f.heal:SetPoint("TOPLEFT", tex, "TOPRIGHT")
            f.heal:SetPoint("BOTTOMLEFT", tex, "BOTTOMRIGHT")
        end
        if f.heal.SetReverseFill then f.heal:SetReverseFill(cfg.hReverse) end
    end
    f.heal:SetWidth(math.max(1, barW))

    -- cast bar
    if f.cast then
        local cb = f.cast
        local icon = cfg.cbIcon and (cfg.cbH + 2) or 0
        cb:SetSize(math.max(20, (cfg.cbW > 0 and cfg.cbW or cfg.w) - icon), cfg.cbH)
        cb:ClearAllPoints()
        if cfg.cbPos == "above" then
            cb:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, above)
        else
            cb:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -below)
        end
        cb.icon:ClearAllPoints()
        cb.icon:SetPoint("RIGHT", cb, "LEFT", -2, 0)
        cb.icon:SetSize(cfg.cbH, cfg.cbH)
        cb.icon:SetShown(cfg.cbIcon)
        cb.text:SetWidth(math.max(10, cb:GetWidth() - 44))
        cb:SetStatusBarColor(cfg.cbr, cfg.cbg, cfg.cbb, 1)
        cb.showTime = cfg.cbTime
    end
    if cfg.cb and f.info.key ~= "targettarget" then
        if cfg.cbPos == "above" then above = above + cfg.cbH + 4 else below = below + cfg.cbH + 4 end
    end

    -- combo points (player): five pips across the top
    if f.info.key == "player" and cfg.classbar then
        if not f.cp then
            f.cp = {}
            for i = 1, 5 do
                local b = CreateFrame("StatusBar", nil, f)
                b:SetStatusBarTexture(WHITE)
                b.bg = Decor(b, "BACKGROUND")
                b.bg:SetPoint("TOPLEFT", -1, 1)
                b.bg:SetPoint("BOTTOMRIGHT", 1, -1)
                b.bg:SetVertexColor(0, 0, 0, 0.85)
                f.cp[i] = b
            end
        end
        local w = (cfg.w - 4 * 3) / 5
        for i = 1, 5 do
            local b = f.cp[i]
            b:SetSize(w, cfg.cpH)
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", f, "TOPLEFT", (i - 1) * (w + 3), above)
            b:SetStatusBarColor(Col(currentSkin.combo, 1))
            b:Show()
        end
        above = above + cfg.cpH + 4
    elseif f.cp then
        for i = 1, 5 do f.cp[i]:Hide() end
    end

    -- buffs, then debuffs, each on its side of the frame
    local function Stack(list, on, size, max, pos)
        local per = math.max(1, math.floor((cfg.w + 2) / (size + 2)))
        list.size, list.perRow = size, per
        list.dir = pos == "below" and -1 or 1
        list.base = pos == "below" and below or above
        for i = 1, #list do UF.PlaceAura(f, list, i) end
        if on then
            local used = math.ceil(max / per) * (size + 2) + 2
            if pos == "below" then below = below + used else above = above + used end
        end
    end
    Stack(f.buffs, cfg.bOn, cfg.bSize, cfg.bMax, cfg.bPos)
    Stack(f.debuffs, cfg.dOn, cfg.dSize, cfg.dMax, cfg.dPos)
    f.abBase = above   -- aura bars sit above everything else

    -- status icons along the frame's edge
    for _, t in pairs(f.stat) do
        t:SetSize(cfg.iconSize, cfg.iconSize)
        t:ClearAllPoints()
        t:SetPoint("CENTER", f, t.point, t.shift * cfg.iconSize, 0)
    end
end

-- Fonts of the extras; called from UF.Fonts for each frame.
UF.FontMore = function(f, path, cfg, t)
    TXT.Font(f.c1, path, cfg.fontSize, t.outline)
    TXT.Font(f.c2, path, cfg.fontSize, t.outline)
    if f.cast then
        local size = math.max(6, math.min(cfg.fontSize, cfg.cbH - 2))
        TXT.Font(f.cast.text, path, size, t.outline)
        TXT.Font(f.cast.time, path, size, t.outline)
    end
    for i = 1, #f.abars do
        TXT.Font(f.abars[i].name, path, math.max(6, math.min(cfg.fontSize, cfg.abH - 2)), t.outline)
    end
    for _, list in ipairs({ f.buffs, f.debuffs }) do
        for i = 1, #list do TXT.Font(list[i].count, path, 10, "OUTLINE") end
    end
end

-----------------------------------------------------------------------
-- Map (the "2" build): minimap and world map options
--
-- ElvUI's map options, each one off until ticked. An option that is off
-- touches nothing: no hook, no script, no frame. Every change to a game
-- frame is remembered in MP.state and undone when the option is switched
-- off again, so nothing here needs a reload.
--
-- To add an option: one row in MP.OPTS, then use db.map.<k> in MP.Apply.
-----------------------------------------------------------------------
MP.OPTS = {
    { t = "header", l = "Minimap" },
    { k = "skin",      t = "check",  l = "Square minimap, flat border", d = false },
    { k = "size",      t = "slider", l = "Size (when square)", d = 175, min = 100, max = 320, step = 1 },
    { k = "scale",     t = "slider", l = "Scale", d = 1, min = 0.5, max = 2, step = 0.05 },
    { k = "coords",    t = "check",  l = "Coordinates under the minimap", d = false },
    { k = "wheel",     t = "check",  l = "Mouse wheel zooms", d = false },
    { k = "hideZoom",  t = "check",  l = "Hide zoom buttons", d = false },
    { k = "reset",     t = "check",  l = "Reset zoom after a delay", d = false },
    { k = "resetTime", t = "slider", l = "Delay (seconds)", d = 3, min = 1, max = 15, step = 1 },
    { k = "hideZone",  t = "check",  l = "Hide zone name bar", d = false },
    { k = "hideCal",   t = "check",  l = "Hide calendar button", d = false },
    { k = "hideTrack", t = "check",  l = "Hide tracking button", d = false },
    { k = "hideClock", t = "check",  l = "Hide clock", d = false },

    { t = "header", l = "World map" },
    { k = "wmScale",  t = "slider", l = "Scale (windowed map)", d = 1, min = 0.5, max = 1.5, step = 0.05 },
    { k = "wmCoords", t = "check",  l = "Player and cursor coordinates", d = false },
    { k = "wmFade",   t = "check",  l = "Fade while moving", d = false },
    { k = "wmAlpha",  t = "slider", l = "Opacity while moving", d = 0.4, min = 0.1, max = 1, step = 0.05 },
}
MP.state = {}   -- what has been changed on the game's frames, so it can be undone
DEFAULTS.map = TXT.ClampOptions(MP.OPTS, nil)

MP.Clamp = function(src)
    db.map = TXT.ClampOptions(MP.OPTS, src)
end

-- Player position on a map as 0-100, 0-100, or nil where the client gives
-- none (instances). map nil = the map the player is on.
MP.Pos = function(map)
    if not C_Map or not C_Map.GetPlayerMapPosition then return nil end
    if not map then
        local ok, m = pcall(C_Map.GetBestMapForUnit, "player")
        if not ok or not IsReadable(m) or not m then return nil end
        map = m
    end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not ok or type(pos) ~= "table" or not pos.GetXY then return nil end
    local x, y = pos:GetXY()
    if not IsReadable(x) or not IsReadable(y) or type(x) ~= "number" or type(y) ~= "number" then return nil end
    return x * 100, y * 100
end

-- Coordinates text under the minimap. Its frame only exists, and only
-- updates (4 times a second), while the option is on.
MP.Coords = function(on)
    if on and not MP.coord then
        MP.coord = CreateFrame("Frame", nil, _G.Minimap)
        MP.coord:SetSize(120, 14)
        MP.coord:SetPoint("TOP", _G.Minimap, "BOTTOM", 0, -4)
        MP.coord.text = MP.coord:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        MP.coord.text:SetPoint("CENTER")
        MP.coord:SetScript("OnUpdate", function(self, elapsed)
            self.t = (self.t or 0) + elapsed
            if self.t < 0.25 then return end
            self.t = 0
            local x, y = MP.Pos()
            if x then self.text:SetFormattedText("%.1f, %.1f", x, y) else self.text:SetText("") end
        end)
    end
    if MP.coord then MP.coord:SetShown(on) end
end

-- World map: applied each time it opens.
MP.WorldShow = function()
    local wm, c = _G.WorldMapFrame, db and db.map
    if not wm or not c then return end
    if (c.wmScale ~= 1 or MP.state.wmScaled) and not UF.Locked()
        and not (wm.IsMaximized and wm:IsMaximized()) then
        MP.state.wmScaled = true
        wm:SetScale(c.wmScale)
    end
    if not c.wmFade then wm:SetAlpha(1) end
end

-- World map coordinates, 10 times a second while the map is open.
MP.WorldTick = function(self, elapsed)
    self.t = (self.t or 0) + elapsed
    if self.t < 0.1 then return end
    self.t = 0
    local wm = _G.WorldMapFrame
    local px, py = MP.Pos(wm.GetMapID and wm:GetMapID() or nil)
    local cx, cy
    local sc = wm.ScrollContainer
    if sc and sc.GetNormalizedCursorPosition then
        local ok, x, y = pcall(sc.GetNormalizedCursorPosition, sc)
        if ok and type(x) == "number" and type(y) == "number" and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
            cx, cy = x * 100, y * 100
        end
    end
    MP.wmText:SetText((px and string.format("Player %.1f, %.1f", px, py) or "Player --")
        .. "     " .. (cx and string.format("Cursor %.1f, %.1f", cx, cy) or "Cursor --"))
end

-- World map options. Nothing is hooked until one of them is first used.
MP.World = function()
    local wm, c = _G.WorldMapFrame, db.map
    if type(wm) ~= "table" or not wm.HookScript then return end
    if (c.wmScale ~= 1 or c.wmFade or c.wmCoords) and not MP.wmEv then
        wm:HookScript("OnShow", MP.WorldShow)
        MP.wmEv = CreateFrame("Frame", nil, wm)   -- a child: it only ticks while the map is open
        MP.wmEv:SetAllPoints(wm)
        if wm.GetFrameLevel then MP.wmEv:SetFrameLevel(wm:GetFrameLevel() + 50) end
        MP.wmText = MP.wmEv:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        MP.wmText:SetPoint("BOTTOMLEFT", wm, "BOTTOMLEFT", 14, 8)
        MP.wmEv:SetScript("OnEvent", function(_, event)
            if db and db.map and db.map.wmFade and wm:IsShown() then
                wm:SetAlpha(event == "PLAYER_STARTED_MOVING" and db.map.wmAlpha or 1)
            end
        end)
    end
    if not MP.wmEv then return end
    if c.wmFade then
        pcall(MP.wmEv.RegisterEvent, MP.wmEv, "PLAYER_STARTED_MOVING")
        pcall(MP.wmEv.RegisterEvent, MP.wmEv, "PLAYER_STOPPED_MOVING")
    else
        pcall(MP.wmEv.UnregisterEvent, MP.wmEv, "PLAYER_STARTED_MOVING")
        pcall(MP.wmEv.UnregisterEvent, MP.wmEv, "PLAYER_STOPPED_MOVING")
    end
    MP.wmText:SetShown(c.wmCoords)
    MP.wmEv:SetScript("OnUpdate", c.wmCoords and MP.WorldTick or nil)
    if wm:IsShown() then MP.WorldShow() end
end

-- Fonts and colours of the two coordinate texts; the minimap border.
MP.Paint = function()
    if not db or not db.text then return end
    local path = TXT.FontPath(db.text.font)
    local r, g, b, a = TXT.Color()
    if MP.coord then
        TXT.Font(MP.coord.text, path, 11, db.text.outline)
        MP.coord.text:SetTextColor(r, g, b, a)
    end
    if MP.wmText then
        TXT.Font(MP.wmText, path, 12, db.text.outline)
        MP.wmText:SetTextColor(r, g, b, a)
    end
    if MP.border then MP.border:SetBackdropBorderColor(Col(currentSkin.border)) end
end

-- Push db.map to the game's map frames. Waits for combat to end.
MP.Apply = function()
    if not db or type(db.map) ~= "table" then return end
    if UF.Locked() then
        TXT.AfterCombat("map", MP.Apply)
        return
    end
    local c, st = db.map, MP.state
    local mm, cluster = _G.Minimap, _G.MinimapCluster
    if type(mm) == "table" then
        -- square skin: mask, flat border, compass art out of the way
        if c.skin ~= (st.skin == true) then
            st.skin = c.skin
            if c.skin then
                st.w, st.h = mm:GetSize()
                st.shape = _G.GetMinimapShape
                _G.GetMinimapShape = function() return "SQUARE" end   -- what other addons ask
                if mm.SetMaskTexture then pcall(mm.SetMaskTexture, mm, 130937) end
                if not MP.border then
                    MP.border = CreateFrame("Frame", nil, mm, "BackdropTemplate")
                    MP.border:SetPoint("TOPLEFT", -1, 1)
                    MP.border:SetPoint("BOTTOMRIGHT", 1, -1)
                    MP.border:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
                end
                MP.border:Show()
            else
                _G.GetMinimapShape = st.shape
                if mm.SetMaskTexture then pcall(mm.SetMaskTexture, mm, 186178) end
                if st.w and st.w > 0 then mm:SetSize(st.w, st.h) end
                if MP.border then MP.border:Hide() end
            end
            TXT.Stash(_G.MinimapCompassTexture, c.skin)
            TXT.Stash(_G.MinimapCompassTextureUnderlay, c.skin)
        end
        if c.skin and st.size ~= c.size then
            st.size = c.size
            mm:SetSize(c.size, c.size)
            -- the map only redraws at its new size after a zoom change
            if mm.GetZoom and mm.SetZoom then
                local zoom = mm:GetZoom()
                if type(zoom) == "number" then
                    mm:SetZoom(zoom > 0 and 0 or 1)
                    mm:SetZoom(zoom)
                end
            end
        elseif not c.skin then
            st.size = nil
        end
        if type(cluster) == "table" and (c.scale ~= 1 or st.scaled) then
            st.scaled = true
            cluster:SetScale(c.scale)
        end
        -- mouse wheel zoom: our script while on, the game's own back when off
        if c.wheel ~= (st.wheel == true) then
            st.wheel = c.wheel
            if c.wheel then
                st.wheelScript = mm:GetScript("OnMouseWheel")
                if mm.EnableMouseWheel then mm:EnableMouseWheel(true) end
                mm:SetScript("OnMouseWheel", function(self, delta)
                    local z = self:GetZoom() + (delta > 0 and 1 or -1)
                    local top = self:GetZoomLevels() - 1
                    if z < 0 then z = 0 elseif z > top then z = top end
                    self:SetZoom(z)
                end)
            else
                mm:SetScript("OnMouseWheel", st.wheelScript)
            end
        end
        -- zoom reset: hooked once, the first time the option is used
        if c.reset and not st.zoomHook and hooksecurefunc and C_Timer and C_Timer.After then
            st.zoomHook = true
            hooksecurefunc(mm, "SetZoom", function(self, z)
                if not db or not db.map or not db.map.reset then return end
                st.zoomToken = (st.zoomToken or 0) + 1
                local token = st.zoomToken
                if type(z) == "number" and z > 0 then
                    C_Timer.After(db.map.resetTime, function()
                        if st.zoomToken == token and db.map.reset then self:SetZoom(0) end
                    end)
                end
            end)
        end
        TXT.Stash(mm.ZoomIn or _G.MinimapZoomIn, c.hideZoom)
        TXT.Stash(mm.ZoomOut or _G.MinimapZoomOut, c.hideZoom)
        if type(cluster) == "table" then
            TXT.Stash(cluster.ZoneTextButton or _G.MinimapZoneTextButton, c.hideZone)
            TXT.Stash(cluster.BorderTop, c.hideZone)
            TXT.Stash(cluster.Tracking or cluster.TrackingFrame or _G.MiniMapTracking, c.hideTrack)
        end
        TXT.Stash(_G.GameTimeFrame, c.hideCal)
        TXT.Stash(_G.TimeManagerClockButton, c.hideClock)
        MP.Coords(c.coords)
    end
    MP.World()
    MP.Paint()
end

-- Show db.map on the Map tab.
MP.Refresh = function()
    if not MP.ws or not db or type(db.map) ~= "table" then return end
    local was = suppress
    suppress = true
    TXT.ShowOptions(MP.ws, MP.OPTS, db.map, nil, nil)
    suppress = was
end

-- Push the whole saved configuration to the screen again: skin, HUD, texts,
-- unit frames, map. Returns false if the frame and map part had to wait for
-- combat to end.
function FRHW2_ApplyNow()
    if not db then return false end
    ApplySkin(db.skin); ApplyAll()   -- skin, HUD elements, icons, texts
    UF.Apply(); MP.Apply()           -- unit frames, map (these wait for combat to end)
    FRHW2_RefreshPanel()
    local waiting = UF.Locked()
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD2|r " .. (waiting
        and "settings applied; frame and map changes will finish when combat ends."
        or "settings applied."))
    return not waiting
end

FRHW2_MAP = MP
FRHW2_ApplyMap = function() if db then MP.Apply() end end

-- ============================== Map tab ==============================
do
    local page = CreateFrame("Frame", nil, panel)
    page:SetPoint("TOPLEFT", 8, -70)
    page:SetPoint("BOTTOMRIGHT", -8, 26)
    page:Hide()
    AddTab("map", "FRHW2TabMap", "Map", page)
    local scroll, child = MakeScroll("FRHW2MapScroll", page, -4)
    local flow = NewFlow(scroll, child)
    NoteRow(flow, "Each option changes the game's own map only while it is ticked; untick it to put things back.")
    MP.ws = TXT.BuildOptions(flow, child, "FRHW2MPO_", MP.OPTS,
        function() return db.map end,
        function(o, isSlider)
            MP.Apply()
            if not isSlider then MP.Refresh() end
        end)

    -- Apply: every change already takes effect as it is made; this pushes the
    -- whole configuration again in one go and says so, for peace of mind and
    -- for changes that were waiting on combat.
    local apply = MakeButton(panel, "Apply", 0, 0, 70, 20, function() FRHW2_ApplyNow() end, "FRHW2ApplyButton")
    apply:ClearAllPoints()
    apply:SetPoint("TOPRIGHT", -140, -6)

    -- seven tabs need a wider window than the original four
    if panel.SetResizeBounds then panel:SetResizeBounds(600, 360, 1000, 860) end
    if panel:GetWidth() < 620 then panel:SetWidth(620) end
end

-- The swing bar's colours depend on both the skin and the user's own swing
-- options, so they are painted here and called from ApplySkin and from
-- ApplyElement("swing") alike.
PaintSwing = function()
    if not db then return end
    local e = db.elements.swing
    local r, g, b = currentSkin.swing[1], currentSkin.swing[2], currentSkin.swing[3]
    if not e.useSkinColor then r, g, b = e.r, e.g, e.b end
    swing:SetStatusBarColor(r, g, b, 1)
    -- same rule as 1.8.0: the background is the bar colour at a quarter strength
    swing.bg:SetVertexColor(r * 0.25, g * 0.25, b * 0.25, e.bgAlpha)
    swing.time:SetTextColor(TXT.Color())
    swing.spark:SetVertexColor(Col(currentSkin.spark, 1))
    swing.flash:SetVertexColor(Col(currentSkin.spark, 0.45))
    for i = 1, #swing.ticks do
        swing.ticks[i]:SetVertexColor(Col(currentSkin.text, 0.5))
    end
end

-- Palette and edge style only: nothing here sets a point, a size or a scale,
-- so switching skins cannot move or resize anything.
ApplySkin = function(key)
    local skin = SKIN_BY_KEY[key or (db and db.skin)] or SKIN_BY_KEY[SKIN_DEFAULT]
    skin = ME.CustomSkin(skin)
    currentSkin = skin
    ME.current = skin

    -- HUD
    energy:SetStatusBarColor(Col(skin.bar, 1))
    energy.bg:SetVertexColor(Col(skin.barBg))
    energy.value:SetTextColor(TXT.Color())
    -- the regen bar reads as a cooler sibling of the energy bar: the same
    -- accent, dimmed, so the two are distinguishable without a new palette entry
    regen:SetStatusBarColor(Col(skin.accent, 1))
    regen.bg:SetVertexColor(Col(skin.barBg))
    regen.value:SetTextColor(TXT.Color())
    PaintSwing()
    for i = 1, MAX_COMBO_POINTS do
        cpBars[i]:SetStatusBarColor(Col(skin.combo, 1))
        cpBars[i].bg:SetVertexColor(Col(skin.combo, 0.15))
    end
    for _, btn in pairs(spellIcons) do
        btn:SetBackdropBorderColor(Col(skin.iconEdge))
        btn.timer:SetTextColor(TXT.Color())
        btn._flashUntil = nil   -- a running ready flash would keep the old colour
        btn.glow:SetVertexColor(Col(skin.accent, 0.35))
    end
    for i = 1, #edgeKits do PaintEdges(edgeKits[i], skin) end
    UF.Paint()
    MP.Paint()

    -- options window
    panel:SetBackdropColor(Col(skin.panel))
    panel:SetBackdropBorderColor(Col(skin.border))
    panel.headerBand:SetVertexColor(Col(skin.accent, 0.10))
    panel.rule:SetVertexColor(Col(skin.accent, 0.85))
    panel.footRule:SetVertexColor(Col(skin.accent, 0.30))
    panel.title:SetTextColor(Col(skin.accent, 1))
    panel.hint:SetTextColor(Col(skin.text, 0.75))
    for i = 1, #skinned.text do skinned.text[i]:SetTextColor(Col(skin.text, 1)) end
    for i = 1, #skinned.accentText do skinned.accentText[i]:SetTextColor(Col(skin.accent, 1)) end
    for i = 1, #skinned.dividers do skinned.dividers[i]:SetVertexColor(Col(skin.accent, 0.18)) end
    for i = 1, #skinned.headerBars do skinned.headerBars[i]:SetVertexColor(Col(skin.accent, 0.16)) end
    for i = 1, #skinned.gutters do skinned.gutters[i]:SetVertexColor(Col(skin.border, 0.15)) end
    for i = 1, #skinned.tabs do skinned.tabs[i]:SetVertexColor(Col(skin.accent, 1)) end
    for i = 1, #skinned.sliders do
        local s = skinned.sliders[i]
        s.track:SetVertexColor(Col(skin.accent, 0.14))
        -- the thumb is template art: tint it where the template exposes it,
        -- halfway to white so a dark accent does not turn it black
        local thumb = s.GetThumbTexture and s:GetThumbTexture()
        if thumb and thumb.SetVertexColor then
            thumb:SetVertexColor((skin.accent[1] + 1) / 2, (skin.accent[2] + 1) / 2, (skin.accent[3] + 1) / 2, 1)
        end
    end

    -- Skins tab: preview strip and the marker on the active swatch
    skinUI.title:SetText("Skin: " .. skin.name .. "   (" .. skin.style .. " edges)" .. (skin._base and "  + custom colours" or "") .. "   click a colour to change it")
    for i = 1, #skinUI.chips do
        local chip = skinUI.chips[i]
        chip.tex:SetVertexColor(Col(skin[chip.field], 1))
        chip.edge:SetVertexColor(Col(skin.text, 0.35))
    end
    for i = 1, #skinUI.buttons do
        local b = skinUI.buttons[i]
        b.sel:SetShown(b.skin == (skin._base or skin))
    end
    ME.ApplyArt()
end

-- Choose a skin: stores it and repaints. Returns false for an unknown key.
function FRHW2_SetSkin(key)
    if not db or not SKIN_BY_KEY[key] then return false end
    db.skin = key
    ApplySkin(key)
    return true
end

function FRHW2_RefreshPanel()
    if not db then return end
    -- SetValue fires OnValueChanged; with suppress set the sliders only update
    -- their labels, so showing the configuration can never rewrite it (a value
    -- outside a slider's range used to be clamped back into db here).
    local was = suppress
    suppress = true
    showCB:SetChecked(db.shown)
    lockCB:SetChecked(db.locked)
    autoCB:SetChecked(db.autoHide)
    autoOOC:SetChecked(db.autoHideOOC)
    snapCB:SetChecked(db.gridSnap)
    stickyCB:SetChecked(db.sticky)
    gridSlider:SetValue(db.gridSize or 20)
    for _, info in ipairs(ELEMENT_INFO) do
        local key = info.key
        elemCB[key]:SetChecked(db.elements[key].enabled)
        elemW[key]:SetValue(db.elements[key].w)
        elemH[key]:SetValue(db.elements[key].h)
        elemA[key]:SetValue(db.elements[key].alpha or 1)
    end
    local sw = db.elements.swing
    swingUI.skinCB:SetChecked(sw.useSkinColor)
    swingUI.bgAlpha:SetValue(sw.bgAlpha)
    swingUI.r:SetValue(sw.r)
    swingUI.g:SetValue(sw.g)
    swingUI.b:SetValue(sw.b)
    swingUI.sparkSize:SetValue(sw.sparkSize)
    swingUI.sparkCB:SetChecked(sw.spark)
    swingUI.flashCB:SetChecked(sw.flash)
    swingUI.textCB:SetChecked(sw.text)
    swingUI.textBtn:SetText(SWING_TEXT_LABEL[sw.textMode] or SWING_TEXT_LABEL.elapsed)
    swingUI.ticksCB:SetChecked(sw.ticks)
    swingUI.tickCount:SetValue(sw.tickCount)
    swingUI.sourceBtn:SetText(sw.source == "poll" and "Source: UnitAttackSpeed" or "Source: PLAYER_SWING")
    swingUI.resetCB:SetChecked(sw.resetOnTarget)
    swingUI.manualCB:SetChecked(sw.manual)
    swingUI.manualSpeed:SetValue(sw.manualSpeed)
    regenUI.rateCB:SetChecked(db.elements.regen.showRate)
    regenUI.maxSlider:SetValue(db.elements.regen.regenMax or 25)
    ME.valueCB:SetChecked(db.elements.energy.showText ~= false)
    ME.customCB:SetChecked(db.customOn)
    ME.artDD.Refresh()
    ME.bannerDD.Refresh()
    RefreshConfig()
    TXT.Refresh()
    UF.Refresh()
    MP.Refresh()
    suppress = was
    if RefreshProfileList and pageProfiles:IsShown() then RefreshProfileList() end
end

-----------------------------------------------------------------------
-- Data updates — reads go to widgets, never into our own compare
-----------------------------------------------------------------------
local swingDuration = 0
local swingElapsed  = 0

-- Rage: power type 1 on this client, the same in every stance.
local function PowerIndex()
    return 1
end

local function UpdateEnergy()
    local idx = PowerIndex()
    local cur = UnitPower("player", idx)
    local max = UnitPowerMax("player", idx)
    energy:SetMinMaxValues(0, max)
    energy:SetValue(cur)
    TXT.Energy(energy.value, cur, max)
end

-- Energy regeneration, measured rather than guessed: the difference in energy
-- across a short window, divided by the window's length. Both readings went
-- through IsReadable first, so nothing secret is ever subtracted here.
local regenLast, regenAccum, regenRate, regenIndex = nil, 0, 0, nil
local REGEN_WINDOW = 1.0
local regenGain = 0

local function UpdateRegen(elapsed)
    local e = db.elements.regen
    local idx = PowerIndex()
    if idx ~= regenIndex then
        -- a different resource (a form change): the old sample means nothing
        regenIndex = idx
        regenLast, regenAccum, regenRate = nil, 0, 0
        regenGain = 0
        regen:SetValue(0)
        regen.value:SetText(e.showRate and "0.0 /s" or "")
    end
    local cur = UnitPower("player", idx)
    if not IsReadable(cur) then return end
    if regenLast == nil then
        regenLast = cur
        return
    end
    regenAccum = regenAccum + (elapsed or 0)
    local delta = cur - regenLast
    regenLast = cur
    if delta < 0 then
        -- a spend, not a tick: restart the window so the drop does not read as
        -- negative regeneration
        regenAccum = 0
        regenRate = 0
        regenGain = 0
    else
        -- everything gained since the window opened counts, not just the
        -- change seen by the sample that happens to close it
        regenGain = regenGain + delta
        if regenAccum >= REGEN_WINDOW then
            regenRate = regenGain / regenAccum
            regenAccum = 0
            regenGain = 0
        end
    end
    local full = e.regenMax or 25
    regen:SetMinMaxValues(0, full)
    regen:SetValue(math.min(regenRate, full))
    if e.showRate then
        TXT.Regen(regen.value, regenRate)
    else
        regen.value:SetText("")
    end
end

-- Where the swing duration comes from. Whatever this returns is a plain,
-- readable number: the manual override is our own value, the event duration
-- was checked with IsReadable when it arrived, and UnitAttackSpeed is only
-- used after IsReadable says so. Nothing unreadable ever reaches arithmetic.
local function SwingDuration(e)
    if e.manual then return e.manualSpeed end
    if e.source == "poll" then
        -- polling fallback: ask for the attack speed every frame
        local spd = UnitAttackSpeed("player")
        if IsReadable(spd) and spd > 0 then return spd end
    end
    if IsReadable(swingDuration) and swingDuration > 0 then return swingDuration end
    local spd = UnitAttackSpeed("player")
    if IsReadable(spd) and spd > 0 then
        swingDuration = spd
        return spd
    end
    return nil
end

local function UpdateSwingBar(elapsed)
    local e = db.elements.swing
    local dur = SwingDuration(e)
    if not dur then return end
    swingElapsed = swingElapsed + elapsed
    if swingElapsed > dur then swingElapsed = swingElapsed % dur end
    swing:SetMinMaxValues(0, dur)
    swing:SetValue(swingElapsed)
    local remaining = dur - swingElapsed
    if e.text and e.textMode ~= "none" then
        if e.textMode == "remaining" then
            swing.time:SetFormattedText(TXT.swingRemain or "%.2f s", remaining)
        elseif e.textMode == "percent" then
            swing.time:SetFormattedText("%d%%", math.floor(swingElapsed / dur * 100 + 0.5))
        else
            swing.time:SetFormattedText(TXT.swingBoth or "%.2f / %.2f s", swingElapsed, dur)
        end
        swing.time:Show()
    else
        swing.time:Hide()
    end
    local anchor = ME.SparkAnchor(e)
    if e.spark and swingElapsed / dur >= 0.01 then
        swing.spark:ClearAllPoints()
        swing.spark:SetPoint("CENTER", swing:GetStatusBarTexture(), anchor)
        swing.spark:Show()
    else
        swing.spark:Hide()
    end
    -- ready flash: the swing lands within the next 0.2 s
    swing.flash:SetShown(e.flash and remaining <= 0.2)
end

function FRHW2_UpdateCombo()
    local cp = GetComboPoints("player", "target")
    if not IsReadable(cp) then
        cp = UnitPower("player", 14)   -- Enum.PowerType.ComboPoints on Mainline
    end
    if IsReadable(cp) then
        if db.autoHide and cp == 0 and not UnitAffectingCombat("player") then
            for i = 1, MAX_COMBO_POINTS do cpBars[i]:Hide() end
            return
        end
        for i = 1, MAX_COMBO_POINTS do
            cpBars[i]:Show()
            cpBars[i]:SetAlpha(i <= cp and 1 or 0.2)
            cpBars[i]:SetValue(1)
        end
    else
        -- secret path: no arithmetic on cp at all (that would throw).
        -- Each dot is a 1-unit window of the total; the widget clamps the
        -- secret value internally, so dot i fills exactly when cp >= i.
        for i = 1, MAX_COMBO_POINTS do
            cpBars[i]:Show()
            cpBars[i]:SetAlpha(1)
            cpBars[i]:SetMinMaxValues(i - 1, i)
            cpBars[i]:SetValue(cp)
        end
    end
end

-- Ask the client which spell ID is behind each spellbook name. Rank 1 IDs are
-- what the table holds; a character who knows rank 5 gets rank 5's icon and
-- cooldown. Anything the client cannot name keeps the table ID.
local function ResolveSpells()
    for _, btn in pairs(spellIcons) do
        local a = btn.spell
        local id = a.id
        if C_Spell and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, a.name)
            if ok and type(info) == "table" and IsReadable(info.spellID) and IsReadable(info.name)
                and type(info.spellID) == "number" and info.name == a.name then
                id = info.spellID
            end
        end
        if id ~= btn.spellId then
            btn.spellId = id
            btn.iconReady = false
            btn._cdStart, btn._cdDur = nil, nil
        end
    end
end

-- "7" under a minute, "2:05" under an hour. Only ever called with a plain
-- number that passed IsReadable.
local function FormatRemaining(rem)
    local f = db and db.text and db.text.timer.format
    if f and f ~= "auto" then return TXT.Timer(rem, f) end
    -- under a minute: seconds and hundredths ("7.43"); above it, minutes and seconds
    if rem < 60 then return string.format("%.2f", rem) end
    local sec = math.ceil(rem)
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

-- Cooldown reading: the same shape GlowingBars uses on this client. One pass
-- per icon does the sweep, the countdown text and the ready flash; there is no
-- per-icon OnUpdate, so a hidden icon costs nothing.
local function UpdateSpellIcon(btn)
    local id = btn.spellId
    -- Icon texture: set once it resolves (nil until the client caches the spell)
    if not btn.iconReady and C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        if ok and type(info) == "table" and info.iconID then
            btn.icon:SetTexture(info.iconID)
            btn.iconReady = true
        elseif C_Spell.RequestLoadSpellData then
            pcall(C_Spell.RequestLoadSpellData, id)
        end
    end
    local now = GetTime()
    ME.IconState(btn, id)
    -- Ready flash: the border sits at the skin's spark colour for 0.25 s
    if btn._flashUntil and now >= btn._flashUntil then
        btn._flashUntil = nil
        btn:SetBackdropBorderColor(Col(currentSkin.iconEdge))
    end
    local ok, info
    if C_Spell and C_Spell.GetSpellCooldown then ok, info = pcall(C_Spell.GetSpellCooldown, id) end
    if not ok or type(info) ~= "table" then
        btn.timer:SetText("")
        return
    end
    local start = info.startTime
    local dur = info.duration
    -- nil or secret: no number, no arithmetic, no error. The sweep is left as
    -- it was; it runs out on its own.
    if not IsReadable(start) or not IsReadable(dur) or type(start) ~= "number" or type(dur) ~= "number" then
        btn.timer:SetText("")
        btn._wasOnCd = false
        return
    end
    local remaining = 0
    if dur > GLOBAL_COOLDOWN then remaining = start + dur - now end
    if remaining > 0 then
        if btn._cdStart ~= start or btn._cdDur ~= dur then
            if db.notify.sweep then btn.cd:SetCooldown(start, dur) else btn.cd:Clear() end
            btn._cdStart, btn._cdDur = start, dur
        end
        btn._wasOnCd = true
        if db.cooldownText and remaining < 3600 then
            btn.timer:SetText(FormatRemaining(remaining))
        else
            btn.timer:SetText("")
        end
    else
        if btn._cdStart then
            btn.cd:Clear()
            btn._cdStart, btn._cdDur = nil, nil
        end
        btn.timer:SetText("")
        if btn._wasOnCd then
            -- on cooldown -> ready: flash once
            btn._wasOnCd = false
            if db.notify.readyFlash then
                btn._flashUntil = now + 0.25
                btn:SetBackdropBorderColor(Col(currentSkin.spark, 1))
            end
        end
    end
end

local spellTick = 0
local function UpdateAllSpells()
    spellTick = 0
    for key, btn in pairs(spellIcons) do
        if btn:IsShown() then UpdateSpellIcon(btn) end
    end
end

cdUI.refresh = UpdateAllSpells   -- the Config toggle repaints the icons at once

-- Hundredths need every frame. This touches only icons that are on a cooldown
-- already read by the pass above (plain numbers), and asks the client nothing.
function ME.TickTimers()
    if not db.cooldownText then return end
    local now = GetTime()
    for _, btn in pairs(spellIcons) do
        if btn._cdStart and btn:IsShown() then
            local rem = btn._cdStart + btn._cdDur - now
            if rem > 0 and rem < 60 then btn.timer:SetText(FormatRemaining(rem)) end
        end
    end
end

-----------------------------------------------------------------------
-- Events
-----------------------------------------------------------------------
local driver = CreateFrame("Frame")
driver:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
    if event == "UNIT_POWER_UPDATE" then
        if elems.energy:IsShown() then UpdateEnergy() end
        if elems.regen:IsShown() then UpdateRegen(0) end
        if elems.combo:IsShown() then FRHW2_UpdateCombo() end
    elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        -- combat state drives auto-hide out of combat, so re-apply on the way
        -- in and out of combat as well as on a target change
        if event ~= "PLAYER_TARGET_CHANGED" and db and db.autoHideOOC then ApplyAll() end
        if elems.combo:IsShown() then FRHW2_UpdateCombo() end
        -- optional: a new target restarts the swing bar
        if event == "PLAYER_TARGET_CHANGED" and db and db.elements.swing.resetOnTarget then
            swingElapsed = 0
        end
    elseif event == "PLAYER_SWING" then
        -- arg1 = duration of the swing just started; units are unverified, so
        -- accept seconds directly and only divide when it clearly came in ms.
        if IsReadable(arg1) and arg1 > 0 then
            if arg1 >= 300 then swingDuration = arg1 / 1000
            elseif arg1 >= 0.3 and arg1 < 30 then swingDuration = arg1 end
        end
        swingElapsed = 0
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_DATA_LOAD_RESULT" then
        UpdateAllSpells()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- unit, cast GUID, spell ID
        if elems.trail:IsShown() then ME.LogCast(arg3) end
    elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_SKILL_LINE" then
        -- a new rank or a new spell: ask the client for the IDs again
        ResolveSpells()
        UpdateAllSpells()
    elseif event == "UPDATE_SHAPESHIFT_FORM" or event == "UNIT_DISPLAYPOWER" then
        -- the resource may have changed with the form
        if elems.energy:IsShown() then UpdateEnergy() end
        if elems.regen:IsShown() then UpdateRegen(0) end
        if elems.combo:IsShown() then FRHW2_UpdateCombo() end
    end
end)
-- Register one at a time under pcall: an unknown event throws and would abort load.
local wantedEvents = {
    "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
    "PLAYER_SWING", "SPELL_UPDATE_COOLDOWN", "SPELL_DATA_LOAD_RESULT",
    "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "UPDATE_SHAPESHIFT_FORM",
}
for i = 1, #wantedEvents do
    local ev = wantedEvents[i]
    pcall(function() driver:RegisterEvent(ev) end)
end
pcall(function() driver:RegisterUnitEvent("UNIT_POWER_UPDATE", "player") end)
pcall(function() driver:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player") end)
pcall(function() driver:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player") end)
driver:SetScript("OnUpdate", function(_, elapsed)
    if not db then return end
    if elems.swing:IsShown() then UpdateSwingBar(elapsed) end
    if elems.energy:IsShown() then UpdateEnergy() end
    if elems.regen:IsShown() then UpdateRegen(elapsed) end
    if elems.combo:IsShown() then FRHW2_UpdateCombo() end
    if elems.trail:IsShown() then ME.PaintTrail() end
    -- ten passes a second is plenty for whole-second numbers; cooldown events
    -- call UpdateAllSpells directly, so a new cooldown still shows at once
    spellTick = spellTick + elapsed
    if spellTick >= 0.1 then UpdateAllSpells() else ME.TickTimers() end
end)

-----------------------------------------------------------------------
-- Boot
-----------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
    -- only for the warrior: the class is asked once, here
    local okClass, _, classFile = pcall(UnitClass, "player")
    if not (okClass and IsReadable(classFile) and classFile == "WARRIOR") then
        ME.wrongClass = true
        for _, fr in ipairs(ALL_ITEMS) do fr:Hide() end
        panel:Hide()
        if gridFrame then gridFrame:Hide() end
        driver:SetScript("OnUpdate", nil)
        driver:SetScript("OnEvent", nil)
        if driver.UnregisterAllEvents then driver:UnregisterAllEvents() end
        return
    end
    if type(ForeverWarriorHUD2_DB) ~= "table" then
        -- first run of the 2 build: start from the original's saved setup if it is loaded
        ForeverWarriorHUD2_DB = (type(ForeverWarriorHUD_DB) == "table") and DeepCopy(ForeverWarriorHUD_DB) or {}
    end
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("ForeverWarriorHUD") then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD2|r ForeverWarriorHUD is enabled as well: two HUDs are drawn. Disable one of them.")
    end
    db = ForeverWarriorHUD2_DB
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = (type(v) == "table") and DeepCopy(v) or v end
    end
    -- upgrade from 1.3.0 and older: old x/y become the base offset
    if db.point ~= nil then
        db.baseX = db.x or 0
        db.baseY = db.y or -140
        db.point, db.x, db.y = nil, nil, nil
    end
    for key, v in pairs(DEFAULTS.elements) do
        if type(db.elements[key]) ~= "table" then db.elements[key] = DeepCopy(v) end
        for kk, vv in pairs(v) do
            if db.elements[key][kk] == nil then db.elements[key][kk] = vv end
        end
    end
    if type(db.spells) ~= "table" then db.spells = {} end
    for key, v in pairs(DEFAULTS.spells) do
        if type(db.spells[key]) ~= "table" then db.spells[key] = DeepCopy(v) end
        for kk, vv in pairs(v) do
            if db.spells[key][kk] == nil then db.spells[key][kk] = vv end
        end
    end
    -- saved profiles: own table, never rebuilt from defaults
    if type(db.profiles) ~= "table" then db.profiles = {} end
    -- swing options: fill and clamp, so an upgrade from 1.8.0 or a hand-edited
    -- file cannot leave a nil or a string where the swing bar expects a number
    ClampSwing(db.elements.swing, db.elements.swing, DEFAULTS.elements.swing)
    -- an unknown skin name falls back to the default look
    if not SKIN_BY_KEY[db.skin] then db.skin = SKIN_DEFAULT end
    db.cooldownText = db.cooldownText ~= false
    TXT.LoadSharedFonts()
    TXT.Clamp(db.text)
    UF.Clamp(db.frames)
    MP.Clamp(db.map)
    -- once: a countdown still sitting on the old default (centre, size 12) moves to the corner
    if not db.timerCorner then
        db.timerCorner = true
        local tt = db.text.timer
        if tt.anchor == "CENTER" and tt.x == 0 and tt.y == 0 then
            tt.anchor, tt.x, tt.y = "BOTTOMRIGHT", -1, 1
            if tt.size == 12 then tt.size = 10 end
        end
    end
    for _, sp in pairs(db.spells) do TXT.ClampItem(sp, sp) end
    ResolveSpells()
    ME.ClampNotify(db.notify)
    ME.ClampCustom(db.custom, db.customOn)
    if type(db.schemes) ~= "table" then db.schemes = {} end
    if db.art ~= "low" and db.art ~= "off" then db.art = "high" end
    if db.artBanner ~= "b" then db.artBanner = "a" end
    -- before 2.0 one switch turned every bar; now each item has its own rotation
    for _, e in pairs(db.elements) do
        if db.orientation == "v" and (e.rot or 0) == 0 then e.rot = 90 end
        e.rot = ME.Norm(e.rot, false)
    end
    db.orientation = "h"
    for _, sp in pairs(db.spells) do sp.rot = ME.Norm(sp.rot, true) end
    ApplySkin(db.skin)
    UF.Apply()
    MP.Apply()
    ApplyAll()
    ReflowAll(true)
    FRHW2_RefreshPanel()
    RefreshProfileList()
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD2|r " .. FRHW2_VERSION
        .. " loaded — /fw2 for options, /fw2 help for how it works, /fw2 abilities for spell tracking, /fw2 skins for skins, /fw2 profiles for saved setups.")
end)

-----------------------------------------------------------------------
-- Slash commands
-----------------------------------------------------------------------
SLASH_FOREVERWARRIORHUD21 = "/fw2"
SlashCmdList.FOREVERWARRIORHUD2 = function(msg)
    if ME.wrongClass or not db then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD2|r is for the warrior class and stays off on this character.")
        return
    end
    local raw = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    msg = raw:lower()
    if msg == "" or msg == "options" or msg == "panel" then
        if panel:IsShown() then panel:Hide() else panel:Show(); SelectTab("hud"); FRHW2_RefreshPanel() end
    elseif msg == "config" or msg == "abilities" then
        panel:Show(); SelectTab("config"); FRHW2_RefreshPanel()
    elseif msg == "profiles" or msg == "profile" then
        panel:Show(); SelectTab("profiles"); FRHW2_RefreshPanel()
    elseif msg == "text" or msg == "font" or msg == "fonts" then
        panel:Show(); SelectTab("text"); FRHW2_RefreshPanel()
    elseif msg == "frames" or msg == "frame" then
        panel:Show(); SelectTab("frames"); FRHW2_RefreshPanel()
    elseif msg == "apply" then
        FRHW2_ApplyNow()
    elseif msg == "map" or msg == "minimap" then
        panel:Show(); SelectTab("map"); FRHW2_RefreshPanel()
    elseif msg == "skins" then
        panel:Show(); SelectTab("skins"); FRHW2_RefreshPanel()
    elseif msg:match("^skin%s") then
        -- accept the key ("gilded_reliquary") or the display name ("Gilded Reliquary")
        local want = msg:match("^skin%s+(.+)$"):gsub("%s+", "_")
        if FRHW2_SetSkin(want) then
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD2|r skin: " .. SKIN_BY_KEY[want].name)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD2|r no skin named '" .. want .. "'. Open /fw2 skins for the list.")
        end
    elseif msg:match("^save") then
        -- profile names keep their case, so take them from the raw message
        local name = raw:match("^%S+%s+(.+)$")
        if not EditMode() then
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD2|r open the options window first (/fw2 profiles) to save a profile.")
        elseif not name or name == "" then
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD2|r usage: /fw2 save <name>")
        elseif type(db.profiles) == "table" and db.profiles[TrimName(name)] ~= nil then
            FRHW2_PendingProfile = TrimName(name)
            StaticPopup_Show("FRHW2_CONFIRM_OVERWRITE", TrimName(name))
        else
            local ok, m = SaveProfile(name)
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD2|r " .. m)
            if ok then selectedProfile = TrimName(name); RefreshProfileList() end
        end
    elseif msg:match("^load") then
        local name = raw:match("^%S+%s+(.+)$")
        if not EditMode() then
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD2|r open the options window first (/fw2 profiles) to load a profile.")
        elseif not name or name == "" then
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD2|r usage: /fw2 load <name>")
        else
            local ok, m = LoadProfile(name)
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD2|r " .. m)
            if ok then selectedProfile = TrimName(name); RefreshProfileList() end
        end
    elseif msg == "show" then db.shown = true;  ApplyAll()
    elseif msg == "hide" then db.shown = false; ApplyAll()
    elseif msg == "lock" then db.locked = true
    elseif msg == "unlock" then db.locked = false
    elseif msg:match("^energy") or msg:match("^regen") or msg:match("^swing") or msg:match("^combo") or msg:match("^trail") then
        local key, st = msg:match("^(%a+)%s*(%a*)")
        if elems[key] then
            if st == "off" then db.elements[key].enabled = false
            elseif st == "on" or st == "" then db.elements[key].enabled = true end
            ApplyElement(key)
        end
    elseif msg:match("^cooldown") then
        local st = msg:match("^cooldown%s+(%a+)")
        if st == "on" then db.cooldownText = true
        elseif st == "off" then db.cooldownText = false
        else db.cooldownText = not db.cooldownText end
        FRHW2_RefreshPanel(); UpdateAllSpells()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD2|r countdown numbers " .. (db.cooldownText and "on" or "off"))
    elseif msg:match("^sticky") then
        db.sticky = not db.sticky; FRHW2_RefreshPanel()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD2|r sticky items " .. (db.sticky and "on" or "off"))
    elseif msg:match("^grid") then
        db.gridSnap = not db.gridSnap; FRHW2_RefreshPanel()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD2|r snap to grid " .. (db.gridSnap and "on" or "off"))
    elseif msg == "help" or msg == "?" then
        panel:Show(); SelectTab("help"); FRHW2_RefreshPanel()
    elseif msg == "reset" then
        StaticPopup_Show("FRHW2_CONFIRM_RESET")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverWarriorHUD2|r /fw2, /fw2 help, /fw2 abilities, /fw2 skins, /fw2 profiles, show|hide, "
            .. "energy|regen|swing|combo|trail on|off, cooldown on|off, lock|unlock, sticky, grid, skin <name>, save <name>, load <name>, reset")
    end
end
