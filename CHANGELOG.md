# Changelog

## 3.0.3

- `!quest` shows the hint for the step the player is on (`hint[var + 1]`); it was off by two.
- A step's hint names what moves the quest on: a builder that advances before your own function,
  either before a reminder (`step = false`); a mob to defeat before a trade before someone to talk
  to; ties by name, so the hint never depends on table order.
- A quest counts as done when its var passes the last step that moves it on. A quest ending on its
  reward step showed "Completed" one step early; a repeatable mid-loop showed "Completed" too.
  Single-step entries (systems run from one NPC) stay unlisted.

## 3.0.2

- `!quest` hints could name the wrong step's NPC: the registry built them with `pairs` over the
  steps table, which isn't in step order when the table's keys sit in its hash part (a constructor
  with explicit `[n] =` keys, say). Now `ipairs`. This has been so since 2.x.

## 3.0.1

- Tests: every quest file is checked for globals it reads that nothing defines, on every line
  (not only the lines a walk reaches); `test/run.lua --globals <files>` checks other Lua files the
  same way. Servers name globals the harness doesn't load in `W.knownGlobals`.
- `WEAPONSKILL_TAKE` listeners in `wsProc`, `reqPenalty` and `vulnerability` take LSB's current
  argument order (user, target, skill) and accept the skill as an id or an object
  (`LQS.util.skillId`).
- Questpack: Running Rings Around, Reaping Rewards and Neck and Neck read names that didn't exist
  (an NPC's emote in a reminder, and two unused fields).

## 3.0.0

A new API. Players' progress carries over: quest vars and step numbers mean what they did in 2.x.
`tools/migrate_v3.py` converts 2.x quest files (README, "Migrating from 2.x").

**Layout**
- `LQS.lua` is split into parts under `lib/LQS/core/` (ctx, steps, dialog, trade, menu, defeat,
  encounter, event, reward, checks, entity, quest, validate, loot, shop, look, hooks). Install
  `lib/LQS.lua` and `lib/LQS/` together; `tools/sync.sh` copies them into a server.

**Handlers**
- Every handler receives one `ctx`: `ctx.player`, `ctx.npc`, `ctx.mob`, `ctx.trade`, `ctx.quest`,
  `ctx.step`, `ctx.entity`, with `ctx:advance()`, `ctx:setVar()`, `ctx:event()`, `ctx:reward()`,
  `ctx:locked()`, `ctx:lockedAfter()`, `ctx:busy()`, `ctx:find()`. `LQS.ctx({...})` builds one.
- One dispatch path: step entries are normalised when the quest loads. A builder returns a handler
  table, not a function.
- Mob deaths are handled once for each credited party member, each at their own step.
- A reward lock per quest stops a reward being collected twice by talking or trading again before
  it lands. Builders take it; `ctx:reward` and `ctx:lockedAfter` take it in your own handlers.
- `LQS.spawn(ctx, mobs, opts)` starts an encounter from your own handler.

**Builders**
- `accept`, `complete` and `mission` say which quest message to show (replacing `quest` and
  `beginQuest`), with `music`.
- `as` swaps the NPC for another quest entity during an event (was `spawn = "Name"`); `object`
  drops the name (was `name = ""`); `after(ctx)` runs once a builder succeeds.
- `LQS.trade`: `list` of cases on one NPC, `required` may be a function, `keep`; exchange trades
  now count toward `tally`.
- `LQS.menu`: options take named fields only (`event =`, `spawn = true`, `reward =`, `step = false`);
  `onChoice(ctx, index)`; `job`, `subjob`, `hideSpawner`.
- `LQS.dialog`: `spawn` starts an encounter; `event` is optional.
- `LQS.defeat`: `event`; `resetStep` takes a number; `helper` rewards go only to party members not
  on the step (once per mob); `func` is now `after(ctx)`.
- A trade that only spawns says nothing and logs nothing.

**Entities and events**
- `key`, for two entities with one name in different zones; entities may be a flat list with
  `zone` on each. Mob fields `job`, `animationsub`, `onMobSpellChoose`, `onSpellPrecast`,
  `widescan`. Markers speak their default without a name.
- An entity with its own `onTrigger(ctx)` skips the steps (how a mob utility adds a companion NPC).
- Event rows `narrate` (was `emotion`), `pose` (was player `animation` with `duration`), `say` (was
  `fmt`), and `menu`; `noturn` is gone; `delay` may ride on any row; `byJob` picks an event or a
  reward by main job. A string as an event is a key of the entity's `dialog` table. 2.x row names
  in `LQS.event` calls are skipped with a log line.
- `LQS.eventDelay` of a function event is 0.

**Hooks and checks**
- Server behaviour goes in `LQS.hooks`: `onQuestAccepted`, `onQuestCompleted`, `questAvailable`,
  `onMobDeath`, `giveCurrency`.
- `LQS.checks.define(key, fn)` adds a server's own check keys; `LQS.checks` errors on unknown keys.

**Validation**
- `LQS.add` checks the whole quest and refuses one with faults, naming the place: unknown builder
  options, check keys, event rows and dialog keys; entity names in steps and events; mobs without
  `base`; duplicate quest vars and names; two entities with one key in a zone; a builder used as an
  event; handlers in the 2.x `(player, npc)` form; positional menu options. 2.x keys say what
  replaced them. `LQS.settings.VALIDATE = "warn"` loads faulty quests anyway.
- Warnings (names over 15 characters, near misses of entity fields, entities nothing reaches)
  print with `LQS.settings.WARNINGS`.

**Tests**
- `test/`: a stand-in for the LandSandBoat map server using LSB's own enums and `npc_util.lua`,
  and a walker that plays each quest from its steps, checks it finishes and that each reward
  arrives once. Unit tests; the questpack, npcpack and README example are tests too.
- Servers point it at their own quests (`LSB_DIR`, `LQS_LIB`, `LQS_PRELOAD`, `LQS_SCRIPTS`,
  `LQS_HARNESS_EXT` with `W.satisfy` and `W.playerSetup`), with per-quest scripts for what the
  walker can't do alone. Transcripts (`--record`) compare a quest before and after a change.
- CI runs everything when LQS changes, and only the changed quests otherwise.

**Fixes**
- Party tally counted once per member times the party size; a failed builder check crashed on an
  entity with a `default`; a declined encounter trade crashed; a list of item ids as a reward gave
  nothing.
- Questpack: Only the Dose printed `%u` instead of the count.

## 2.4.0

The last 2.x release (branch `v2`).
- Add-effect riders, charvar expiry in events, `playerOnly` action packets, and the glimpse
  despawn on the player's timer.
- Fixes found by the new tests: `LQS.defeat` with a check on the mob crashed; the points multiplier
  crashed; `resetStep` read an undefined global; menu item rewards gave the wrong option's item;
  trades and menus spawning two or more mobs gave their reward and advanced twice; a failed trade
  reward never released the reward lock; augmented rewards reported success when the item couldn't
  be added; `LQS.checks` crashed on an unknown key and `hasTeleport` never worked; `eventDelay`
  read an undefined name; the teleporter examples placed no NPC; the outpost warper crashed on
  current LSB.
