-- The README's Simple Example, kept here so the tests prove it works
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
