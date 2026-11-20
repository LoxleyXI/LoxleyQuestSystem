-----------------------------------
-- LQS: LQS.shop, LQS.simpleShop
-----------------------------------
-- Part of the Loxley Quest System. LSB loads lib/LQS/ before lib/LQS.lua, and
-- the parts in name order, so nothing here may call another part while loading:
-- shared helpers live on LQS._ and are looked up when they run.
-----------------------------------
LQS   = LQS or {}
LQS._ = LQS._ or {}

local P = LQS._

-----------------------------------
-- LQS.shop
-----------------------------------
LQS.simpleShop = function(player, npc, tbl, func, title, currentPage, param)
    local options  = {}
    local max      = 1
    local lastPage = math.floor((#tbl - 1) / 4)
    local page     = currentPage

    if currentPage == nil then
        page = 0
    end

    if page > 0 then
        table.insert(options, {
            "(Prev)",
            function(player)
                LQS.simpleShop(player, npc, tbl, func, title, page - 1, param)
            end,
        })
    end

    for i = 1, 4 do
        local item  = tbl[page * 4 + i]
        local block = false

        if
            param ~= nil and
            param.milestone ~= nil
        then
            local milestoneVal = player:getCharVar(param.milestone)

            if utils.mask.getBit(milestoneVal, page * 4 + i) then
                block = true
            end
        end

        if item ~= nil then
            local itemName = item[1]
            local itemCost = item[3]
            local label    = itemName

            if itemCost > 0 then
                if block then
                    label = string.format("-Claimed- (%u)", itemCost)
                else
                    label = string.format("%s (%u)", label, itemCost)
                end
            end

            table.insert(options, {
                label,
                function(playerArg)
                    if not block then
                        func(player, npc, item, param)
                    end
                end
            })

            max = page * 4 + i
        end
    end

    if max < #tbl then
        table.insert(options, {
            "(Next)",
            function(player)
                LQS.simpleShop(player, npc, tbl, func, title, page + 1, param)
            end,
        })
    end

    P.delaySendMenu(player, {
        title   = title,
        options = options,
    })
end

LQS.purchaseItem = function(player, npc, item, obj)
    local balance  = player:getCharVar(obj.var)

    if item[3] > balance then
        player:sys("You can't afford this purchase.")
        return
    end

    P.delaySendMenu(player, {
        title   = fmt("Buy {} ({})?", item[1], item[3]),
        options =
        {
            {
                "No",
                function()
                end,
            },
            {
                "Yes",
                function()
                    if type(item[2]) == "string" then
                        player:setCharVar(item[2], 1)
                        player:sys(item[4])
                        player:incrementCharVar(obj.var, -item[3])
                    else
                        if npcUtil.giveItem(player, item[2]) then
                            npc:facePlayer(player, true)
                            player:incrementCharVar(obj.var, -item[3])
                            if obj.onPurchase then
                                obj.onPurchase(player, npc, item)
                            end
                        end
                    end
                end,
            },
        },
    })
end

LQS.shop = function(obj)
    return P.handler("shop", { obj = obj, onTrigger = function(ctx)
        local player, npc = ctx.player, ctx.npc
        local balance     = player:getCharVar(obj.var)
        local purchase = function(player, npc, item)
            LQS.purchaseItem(player, npc, item, obj)
        end

        if obj.dialog ~= nil then
            LQS.event(player, nil, obj.dialog)
        end

        local list = {}

        for _, item in pairs(obj.list) do
            if type(item[2]) == "string" then
                if player:getCharVar(item[2]) == 0 then
                    table.insert(list, item)
                end
            else
                table.insert(list, item)
            end
        end

        LQS.simpleShop(player, npc, list, purchase, fmt(obj.title, balance))
    end })
end

return {}
