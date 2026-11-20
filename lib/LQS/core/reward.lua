-----------------------------------
-- LQS: Rewards: items, gil, key items, container slots
-----------------------------------
-- Part of the Loxley Quest System. LSB loads lib/LQS/ before lib/LQS.lua, and
-- the parts in name order, so nothing here may call another part while loading:
-- shared helpers live on LQS._ and are looked up when they run.
-----------------------------------
LQS   = LQS or {}
LQS._ = LQS._ or {}

local P = LQS._

-----------------------------------
-- Container / slot names
-----------------------------------
P.bagNames =
{
    [xi.inv.INVENTORY]  = "Inventory",
    [xi.inv.MOGSAFE]    = "Mog Safe",
    [xi.inv.STORAGE]    = "Storage",
    [xi.inv.TEMPITEMS]  = "Temp. Items",
    [xi.inv.MOGLOCKER]  = "Mog Locker",
    [xi.inv.MOGSATCHEL] = "Mog Satchel",
    [xi.inv.MOGSACK]    = "Mog Sack",
    [xi.inv.MOGCASE]    = "Mog Case",
    [xi.inv.WARDROBE]   = "Mog Wardrobe 1",
    [xi.inv.MOGSAFE2]   = "Mog Safe 2",
    [xi.inv.WARDROBE2]  = "Mog Wardrobe 2",
    [xi.inv.WARDROBE3]  = "Mog Wardrobe 3",
    [xi.inv.WARDROBE4]  = "Mog Wardrobe 4",
    [xi.inv.WARDROBE5]  = "Mog Wardrobe 5",
    [xi.inv.WARDROBE6]  = "Mog Wardrobe 6",
    [xi.inv.WARDROBE7]  = "Mog Wardrobe 7",
    [xi.inv.WARDROBE8]  = "Mog Wardrobe 8",
    [xi.inv.RECYCLEBIN] = "Recycle Bin",
}

-----------------------------------
-- Increase a player's container size
-- Usage: LQS.rewardSlots(player, { xi.inv.WARDROBE4, 2 })
--   or in a reward table: slots = { xi.inv.WARDROBE4, 2 }
-----------------------------------
LQS.rewardSlots = function(player, unlock)
    local bag         = unlock[1]
    local bagIncrease = unlock[2]
    local bagName     = P.bagNames[bag] or "Unknown"

    local oldSize = player:getContainerSize(bag)
    player:changeContainerSize(bag, bagIncrease)
    local newSize = player:getContainerSize(bag)

    player:sys(
        "\129\154 Your {} capacity has been increased by {} from {} to {}! \129\154",
        bagName, bagIncrease, oldSize, newSize
    )
end

-----------------------------------
-- Reward utils
-----------------------------------
function P.giveReward(player, reward, questName)
    if
        type(reward) == "number" or
        type(reward[1]) == "table"
    then
        return npcUtil.giveItem(player, reward)
    end

    if reward.item ~= nil then
        if reward.augment ~= nil then
            local ID = zones[player:getZoneID()]

            if
                player:getFreeSlotsCount() > 0 and
                player:canObtainItem(reward.item) and
                player:addItem(reward.item, 1, unpack(reward.augment))
            then
                player:messageSpecial(ID.text.ITEM_OBTAINED, reward.item)
            else
                player:messageSpecial(ID.text.ITEM_CANNOT_BE_OBTAINED, reward.item)
                return false
            end
        elseif not npcUtil.giveItem(player, reward.item) then
            return false
        end
    end

    if reward.exp ~= nil then
        player:addExp(reward.exp)
    end

    if reward.currency ~= nil then
        npcUtil.giveCurrency(player, reward.currency[1], reward.currency[2])
    end

    if reward.gil ~= nil then
        npcUtil.giveCurrency(player, "gil", reward.gil)
    end

    if reward.keyitem ~= nil then
        if type(reward.keyitem) == "table" then
            for _, keyItem in pairs(reward.keyitem) do
                npcUtil.giveKeyItem(player, keyItem)
            end
        else
            npcUtil.giveKeyItem(player, reward.keyitem)
        end
    end

    if reward.slots ~= nil then
        LQS.rewardSlots(player, reward.slots)
    end

    -- Execute optional quest registry override
    if
        questName ~= nil and
        LQS.registry[questName] ~= nil and
        LQS.registry[questName].after ~= nil
    then
        LQS.registry[questName].after(player)
    end

    return true
end

return {}
