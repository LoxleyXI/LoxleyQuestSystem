# Loxley Quest System (LQS)
[![LQS](https://github.com/LoxleyXI/LoxleyQuestSystem/blob/main/lqs.png)](https://github.com/LoxleyXI/LoxleyQuestSystem)

## Overview
The Loxley Quest System (LQS) is a module for the [LandSandBoat](https://github.com/LandSandBoat/server) FFXI server emulator. It allows server operators to easily create their own custom quests and script custom events using a simple template system. The system provides an authentic experience and is actively in use by multiple prominent FFXI server projects.

If you found this module helpful, please consider kindly supporting my other work and/or starring the repository. Thank you.

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/loxleygames)

## Features
* **LQS now comes bundled with Questpack, providing 25+ new quests to experience**
* Fully scriptable dialog events with NPC animations and simulated cutscenes
* Flexible item trading system offers endless possibilities
* Mob encounters featuring spawn requirements, level caps and other restrictions
* NPC look/model utility functions allow easy creation of any appearance
* Each step can be gated by any number of requirements
* Custom quest tracker with a new `!quest` command providing quest info and hints
* LQS Quest modules are fully reloadable and will refresh simply by saving the file

(ie. You can update NPCs or implement new quest steps without any need for a server restart!)

## Setup
* `LQS.lua` must be located inside `modules/` and included to `init.txt` before any of your quests
* Also include `questpack` inside `init.txt` to load the provided additional quests
* Initialise your new quests using `LQS.add()`, following the examples provided in this repository
* Save time by using my [`pos` Ashita Addon](https://github.com/LoxleyXI/ashita-addons) to copy NPC/Mob positions straight to the clipboard
* Ensure `lqs_util.cpp` is included in your modules and [clear the CMake cache](https://github.com/LandSandBoat/server/wiki/Module-Guide#cpp-modules) before [rebuilding the C++](https://github.com/LandSandBoat/server/wiki/Quick-Start-Guide)

## Questpack
**LQS now comes bundled with Questpack, providing 25+ new quests to experience.** Each quest features tastefully written dialog, appropriate to the game's setting and a variety of new rewards, including augmented items and repeatable gil rewards. These quests are designed to better balance the starting areas and provide meaningful content for new players to complete at the start of their journey.

* San d'Oria **(7)**: Hatchet Job, Hungry Customer, In Sheep's Clothing, Rambling Around, Staying Afloat, Fleeing Daylight, Ring Around the Roses
* Bastok **(8)**: Bird Search, Bug Report, Chasing Tails, Mining My Business, That's All Folks, Earthen Echoes, Running Rings Around, Lode of Gil
* Windurst **(7)**: Down to Earth, Neck and Neck, Only the Dose, Reaping Rewards, Rustling Feathers, Slowing Down, Give Me a Ring
* Other Areas **(3)**: Head First, Here Be Dragons, Likely Tails
* Aht Urhgan **(2)**: Insult to Gingery, Pecking Battles

## Simple Example
A minimal quest. (For a fuller one, see [Here Be Dragons](https://github.com/LoxleyXI/LoxleyQuestSystem/blob/main/questpack/other_areas/lqs_here_be_dragons.lua).)

```lua
local m = Module:new("lqs_example")

local SimpleQuest = "Simple Quest"
local Example     = "Example"

LQS.add(m, {
    info =
    {
        name   = SimpleQuest,
        author = "Loxley",
        var    = "[LQS]EXAMPLE",
    },
    entities =
    {
        ["Upper_Jeuno"] =
        {
            {
                name    = Example,
                type    = xi.objType.NPC,
                look    = LQS.look({ race = xi.race.HUME_M, face = LQS.face.A1, body = 21 }),
                pos     = { -3.276, -0.000, 25.295, 106 }, -- !pos -3.276 -0.000 25.295 244
                default = { "Lovely weather today." },
            },
        },
    },
    steps =
    {
        {
            [Example] = LQS.dialog({
                accept = SimpleQuest,
                event  =
                {
                    "Could you bring me some rock salt?",
                    { emote = xi.emote.THINK },
                },
            }),
        },
        {
            [Example] = LQS.trade({
                required = xi.item.CHUNK_OF_ROCK_SALT,
                reward   = { gil = 500 },
                complete = SimpleQuest,
                accepted = { "Perfect, thank you!" },
                declined = { "That's not rock salt." },
            }),
        },
    },
})

return m
```

The quest var counts the steps a player has done: `steps[var + 1]` is the step they're on. Each step names the entities that do something on it; everyone else shows their `default`.

## Steps and handlers
A step entry is a builder (`LQS.dialog`, `LQS.trade`, `LQS.menu`, `LQS.defeat`, `LQS.shop`), a function of your own, or a table of them:

```lua
[Khartes] = LQS.dialog({ ... }),                     -- talking
[Altar]   = LQS.trade({ ... }),                      -- trading
[Beast]   = LQS.defeat({ ... }),                     -- a mob dying
[Khartes] = function(ctx) ... end,                   -- your own (on a mob: when it dies)
[Altar]   = { onTrigger = LQS.dialog({ ... }), onTrade = LQS.trade({ ... }), check = { level = 30 } },
```

A `check` on a step, or on a handler table, means the NPC shows its default until the player meets it.

Steps name entities by `name`. Two entities with the same name in different zones (the same NPC met twice, say) each take a `key = "REISLE_2"`, and steps name the key.

### ctx
Every handler receives one `ctx`:

| Field | What |
|---|---|
| `ctx.player` | the player (for a mob death: each credited party member in turn) |
| `ctx.npc`, `ctx.mob`, `ctx.trade` | what was talked to, killed or traded |
| `ctx.quest` | `{ name, var, info }` |
| `ctx.step` | the step the player is on (var + 1) |
| `ctx.entity` | this entity's definition |
| `ctx.isKiller` | for a mob death |

| Method | What |
|---|---|
| `ctx:advance(n)` | this step is done (or n steps on) |
| `ctx:setVar(v)` | set the quest var outright |
| `ctx:event(e)` | play an event as this NPC |
| `ctx:reward(spec)` | give a reward, all or nothing; true if given |
| `ctx:find(name)` | a quest entity in the player's zone |
| `ctx:locked(fn)` | run fn under the quest's reward lock |
| `ctx:busy()` | the player is mid-dialog |

`LQS.spawn(ctx, { "Mob" }, { delay, levelCap, partySize, hideSpawner, ... })` starts an encounter from your own handler.

```lua
[Well] =
{
    onTrade = function(ctx)
        if npcUtil.tradeHasOnly(ctx.trade, xi.item.WORN_PENDANT) then
            ctx.player:tradeComplete()
            ctx:advance()
            ctx:event({ { object = true }, "The water stills." })
        end
    end,
},
```

The reward lock stops a player collecting a reward twice by talking or trading again before it lands. Builders take it for you; `ctx:reward` takes it in your own handlers.

Mob deaths are handled once for each credited party member, each at their own step.

### Quest messages
Builders say which message to show: `accept = "Quest Name"` (Quest Accepted), `complete = "Quest Name"` (Quest Completed) or `mission = "Mission Name"`. Add `music = id` to play a track with it.

### LQS.dialog
```lua
[Khartes] = LQS.dialog({
    event    = { "Have you been to Gustav Tunnel?", { emote = xi.emote.THINK } },
    check    = { level = 30 },       -- else `fail`, or the NPC's default
    fail     = { "Come back when you're stronger." },
    reward   = spec,                 -- given once the event finishes
    step     = false,                -- a hint: doesn't advance or reward
    accept   = "Here Be Dragons",    -- or complete = / mission =
    as       = "Leidl",              -- swap this NPC for another quest entity during the event
    object   = true,                 -- speaks without a name (signs, markers)
    after    = function(ctx) end,    -- once it succeeds
}),
```

### LQS.trade
```lua
[Shop] = LQS.trade({
    required  = { { xi.item.LIZARD_TAIL, 12 } },   -- npcUtil format, or function(ctx, trade)
    accepted  = { "Thanks!" },
    declined  = { "That's not what I asked for." },
    reward    = { gil = 600 },
    step      = false,             -- repeatable
    tally     = "[LQS]TAILS",      -- adds the items traded to a var
    keep      = true,              -- give the items back instead of taking them
    spawn     = { "Ore Melter" },  -- start an encounter instead (levelCap, partySize, scaleVar...)
    complete  = "Chasing Tales",
}),
```

Several trades on one NPC: `list = { case, case, ... }`. Each case takes the same keys and falls back to the trade's own:

```lua
LQS.trade({
    list =
    {
        { required = xi.item.MOSSY_SHIELD, accepted = HINT, step = false, keep = true },
        { required = FULL_SET, accepted = AWAKEN },
    },
    declined = LQS.NOTHING,
})
```

`exchange` turns an NPC into an exchange: each traded item rolls a reward from its own weighted table (`sellrate` buys anything else for gil).

### LQS.menu
```lua
[Helmet] = LQS.menu({
    title   = "Pick up the helmet?",
    spawn   = { "Ore Melter" },
    options =
    {
        { "No way!" },                                       -- no event: nothing happens
        { "Let's take a closer look...", spawn = true },     -- spawns the menu's group
        { "Take it.", event = { "You take the helmet." }, reward = xi.item.MINERS_HELMET },
    },
    onChoice = nil,       -- or function(ctx, index) to handle every pick yourself
}),
```

### LQS.defeat
```lua
[OreMelter] = LQS.defeat({
    mobs    = { "Ore Melter" },       -- all must be down
    spawner = "Miner's Helmet",       -- shown again afterwards
    event   = { "The dragon falls." },
    exp     = 500,
    after   = function(ctx) end,
}),
```

Mob entities can also carry `loot`, `pool` (weighted rolls), `points`, `tally`, `title`, `restore` and `util` (see Mob utilities below).

### LQS.shop
A points shop: `LQS.shop({ var = "[LQS]POINTS", title = "Points: {}", list = { { "Item", itemId, cost }, ... } })`.

## Checks
A check is a table or a `function(player)`:

```lua
check = { level = 50, job = xi.job.WAR, vareq = { "[LQS]OTHER", 3 }, item = xi.item.PICKAXE }
```

Keys: `level job jobvar gm vareq varin vargt varlt varlist zero allzero timeout cooldown bool item ki skill quest gil cp rank hasTeleport currency eval`. A server adds its own before quests load:

```lua
LQS.checks.define("member", function(player, value)
    return (player:getCharVar("[SERVER]MEMBER") == 1) == value
end)
```

## Rewards
One format everywhere (`reward =`, `ctx:reward`, `info.reward`):
* a number: one item
* a list: `{ { itemId, qty }, itemId }`
* a table: `item`, `qty`, `augment`, `gil`, `exp`, `keyitem` (one or a list), `currency = { name, amount }`, `points = { var, amount, message }`, `slots = { bag, n }`, `title`, `byJob = { [xi.job.WAR] = spec, default = spec }`, `after = function(ctx)` (once it's all given), `feature` (shown by `!quest`)

All or nothing: if the item can't be given, nothing else is.

## Events
An event is a list of rows. A string is a line of dialog; a leading space continues the paragraph without the name again. `{ object = true }` first drops the NPC's name.

| Row | Options | Does |
|---|---|---|
| `{ delay = ms }` | | waits (`delay` may also ride on any other row) |
| `{ emote = id }` | `entity` | an emote, by the NPC or another entity (`"player"` for the player) |
| `{ narrate = "looks around." }` | `name` | a third-person emote line |
| `{ face = "player" }` | `entity` | turn to the player, an angle, or another entity |
| `{ say = "You've helped {} times.", var = "[VAR]" }` | | a line with a var filled in |
| `{ message = "..." }` | `after` | a system message |
| `{ spawn = { names } }`, `{ despawn = { names } }` | | show or hide quest entities for this player |
| `{ glimpse = { ms, { names } } }` | | show entities for a moment |
| `{ animate = id }` | `entity`, `target`, `mode` | an effect animation |
| `{ pose = id, target = "player", duration = ms }` | | hold the player in an animation |
| `{ action = { id, anim } }` | `entity`, `target`, `playerOnly` | an action packet |
| `{ packet = "cate" }` | `entity`, `target` | a FourCC animation |
| `{ addEffect = ... }`, `{ removeEffect = id }` | | status effects |
| `{ charvar = "[VAR]", value = n }` | `expiry` | set a char var |
| `{ teleport = id or { x, y, z, rot, zone } }` | `teleportDelay`, `region` | teleport |
| `{ music = id }`, `{ pos = { ... } }`, `{ special = id }`, `{ costume = id }` | | |
| `{ menu = { title, options } }` | | open a menu at this point |
| a function | | called with `(player, ctx)` |

A function in place of a whole event (an NPC's `default`, say) is called with `(player, npc, ctx)`.

### LQS.event
Play an event from your own code: `LQS.event(player, npc, { "Hello!", { emote = xi.emote.WAVE } })`.

### LQS.look
The look utility builds NPC looks without converting each model ID into a little endian byte string (eg. `"0x01000F020010032008300A400850006000700000"`). Model IDs are the `MId` in [LSB's `item_equipment.sql`](https://github.com/LandSandBoat/server/blob/base/sql/item_equipment.sql).

```lua
LQS.look({ race = xi.race.ELVAAN_F, face = LQS.face.B2, head = 0, body = 6, hand = 6, legs = 6, feet = 6, main = 0, offh = 0 })
```

## Hooks
Server-specific behaviour goes in hooks, set after LQS loads:

```lua
LQS.hooks.onQuestAccepted  = function(player, name, opts) end   -- opts: { mission, music, info }
LQS.hooks.onQuestCompleted = function(player, name, opts) end
LQS.hooks.questAvailable   = function(player, info) return true end  -- false: the quest stays closed
LQS.hooks.onMobDeath       = function(mob, player, entity) end
LQS.hooks.giveCurrency     = function(player, name, amount) end
```

An entity with its own `onTrigger(ctx)` skips the steps entirely, which is how a mob utility adds a companion NPC (a loot chest, say).

## Validation
`LQS.add` checks the whole quest and refuses one with faults, naming the quest and the place (a running version keeps working when you save a broken file):

```
[LQS] Here Be Dragons: steps[2]["Miner's Helmet"].event[3].emotion: renamed to narrate
[LQS] Here Be Dragons: steps[1]["Khartes"].check.lvl: unknown check
```

It checks builder options, check keys, event rows, entity names used in steps and events, mobs without a `base`, and quest vars used twice. Names over 15 characters are a warning (the client shows 15). Set `LQS.settings.VALIDATE = "warn"` to load quests with faults anyway.

## Mob utilities
Add behaviour to a quest mob with `util = { ... }`: `LQS.util.ignorePet`, `LQS.util.reqPenalty`, tethers, fixates, doom roulettes, rage timers and more (`lib/LQS/util/`). Each is a table of mob callbacks LQS composes for you.

## Standalone NPCs
### LQS.npc
NPCs that aren't part of a quest. Handlers take `ctx` (with `ctx.quest` nil).

```lua
local m = Module:new("my_npc")

LQS.npc(m, {
    ["Port_Jeuno"] =
    {
        {
            name      = "Shop Keeper",
            look      = 1415,
            pos       = { -22.000, 0.000, -77.000, 128 },
            onTrigger = function(ctx)
                ctx:event({ "Welcome!" })
            end,
        },
    },
})

return m
```

## Extensions
Extensions live in `lib/LQS/` and add functions to the `LQS` table.

### LQS.teleporter
Returns an `onTrigger` handler for config-driven teleporter NPCs with paginated menus and costs.

```lua
LQS.npc(m, {
    ["Port_Jeuno"] =
    {
        {
            name      = "Dimensional Guide",
            pos       = { 10, 0, -20, 128 },
            look      = 1415,
            onTrigger = LQS.teleporter({
                destinations =
                {
                    { name = "Sanctuary", pos = { -37, 0, -141, 69, 121 }, costs = { gil = 500 }, level = 25 },
                    { name = "Crag of Dem", teleport = xi.teleport.id.DEM, costs = { cp = 100 } },
                },
                preTeleportEffects = { LQS.signetEffect() },
            }),
        },
    },
})
```

### LQS.outpostTeleporter
A ready outpost warper: all 17 regions, unlock checks and retail costs. Use it as `onTrigger = LQS.outpostTeleporter({ preTeleportEffects = { LQS.signetEffect() } })`.

### LQS.signetEffect
The standard Signet effect with rank-based duration, for `preTeleportEffects`.

### Writing Extensions
A file in `lib/LQS/` that adds to the `LQS` table. LSB loads `lib/LQS/` before `lib/LQS.lua`, so an extension may not call LQS while it loads, only from the functions it defines.

```lua
-- lib/LQS/my_extension.lua
LQS = LQS or {}

LQS.myThing = function(config)
    return function(ctx)
        -- an onTrigger handler
    end
end

return {}
```

## Migrating from 2.x
3.0 changes the API, not your players' progress: quest vars and step numbers mean the same. `tools/migrate_v3.py` converts quest files:

```sh
python3 tools/migrate_v3.py --check path/to/quests   # list what would change
python3 tools/migrate_v3.py path/to/quests           # rewrite in place
```

It handles `quest` (to `accept` or `complete`, by the same rules 2.x used), `beginQuest`, `spawn = "NPC"` (to `as`), `name = ""` (to `object = true`), defeat `func` (to `after`), the event renames (`emotion` to `narrate`, `fmt` to `say`, player `animation` to `pose`), and hand-written handlers (`function(player, npc)` to `function(ctx)` with the old names unpacked). Code that calls a builder's result as a function, or a quest's own helpers that LQS calls, need a look by hand: the tests and the validator point at them.

## Tests
LQS comes with a test harness that runs every quest without a server: a small stand-in for the LandSandBoat map server (players, NPCs, mobs, zones, timers, menus and trades) using LSB's own enums and `npc_util.lua`. A walker plays each quest from its `steps` table: it meets each step's checks, talks to NPCs, picks menu options, trades the required items and kills the mobs that spawn, then checks the quest finished, each reward arrived once, and talking to everyone again changes nothing.

You need [LuaJIT](https://luajit.org/) and a LandSandBoat checkout.

```sh
LSB_DIR=/path/to/server luajit test/run.lua             # unit tests, then every quest
LSB_DIR=/path/to/server luajit test/run.lua questpack/bastok/lqs_bug_report.lua -v
```

`-v` prints each quest's transcript (dialog, choices, vars, items); `--record <dir>` saves it (one file per quest, named by var and quest name), to compare a quest before and after a change.

Your own quests run the same way. Point the harness at your server's files:

| Variable | What |
|----------|------|
| `LSB_DIR` | LandSandBoat checkout (enums, `npc_util.lua`, the binding lists) |
| `LQS_LIB` | folder holding `LQS.lua` and `LQS/`, if not this repo's `lib/` |
| `MODULES_DIR` | folder that `require("modules/...")` resolves against |
| `LQS_PRELOAD` | files or folders loaded before LQS (your enums and shared systems), `:` separated |
| `LQS_BINDINGS` | your C++ modules, so methods they add to `CBaseEntity` are known, `:` separated |
| `LQS_SCRIPTS` | folder of quest scripts (below) |
| `LQS_HARNESS_EXT` | a Lua file returning `function(S, W)`: teaches the walker your own check keys (`W.satisfy.key = function(player, value) ... end`) and prepares the player (`table.insert(W.playerSetup, function(player, quest) ... end)`) |

Most quests need nothing more. A quest with a hand-written trade or an `eval` check needs a script telling the walker what to do, named after its var (`[LQS]VINE_WARD` is `LQS_VINE_WARD.lua`):

```lua
return
{
    -- Called before each step
    setup  = function(player, step, S) player:setCharVar("[MY]OTHER_QUEST", 11) end,
    -- Items to hand over for trades LQS.trade doesn't describe
    trades = { ["Mossy Roots"] = { { 1446, 12 }, { 703, 12 } } },
}
```

Pull requests run the tests on GitHub: a change to LQS runs everything, a change to quests runs just those quests.

## History
This system has been developed over a couple of years by myself and now supports over 130+ live custom quests and content systems.

* The [first version](https://www.bg-wiki.com/ffxi/CatsEyeXI_Systems/Quests) was initially developed by me for [Crystal Warrior](https://www.catseyexi.com/cw) on [CatsEyeXI](https://www.catseyexi.com/) in 2023
* This __definitive version__ was developed by me in 2025 to give the system a permanent home and make it more accessible to the community

## Final Note
If you found this module useful for your server, please provide a link back to it!

~ Loxley ~
