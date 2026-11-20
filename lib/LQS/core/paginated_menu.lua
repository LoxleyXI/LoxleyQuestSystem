-----------------------------------
-- LQS: LQS.paginatedMenu
-----------------------------------
-- Part of the Loxley Quest System. LSB loads lib/LQS/ before lib/LQS.lua, and
-- the parts in name order, so nothing here may call another part while loading:
-- shared helpers live on LQS._ and are looked up when they run.
-----------------------------------
LQS   = LQS or {}
LQS._ = LQS._ or {}

local P = LQS._

-----------------------------------
-- LQS.paginatedMenu
-- General-purpose paginated menu builder
-----------------------------------
LQS.paginatedMenu = function(player, config)
    local title        = config.title or "Select Option"
    local items        = config.items or {}
    local itemsPerPage = config.itemsPerPage or 5
    local filter       = config.filter
    local onSelect     = config.onSelect
    local showNav      = config.showNavigation ~= false
    local cycle        = config.cycle == true
    local onCancel     = config.onCancel
    local npc          = config.npc

    -- Filter items if filter function provided
    local filteredItems = {}
    for _, item in ipairs(items) do
        if filter == nil or filter(player, item) then
            table.insert(filteredItems, item)
        end
    end

    -- Return early if no items available
    if #filteredItems == 0 then
        if onCancel then
            onCancel(player, "no_items")
        end
        return
    end

    local totalPages = math.ceil(#filteredItems / itemsPerPage)

    local function showPage(pageNum)
        local options  = {}
        local startIdx = (pageNum - 1) * itemsPerPage + 1
        local endIdx   = math.min(startIdx + itemsPerPage - 1, #filteredItems)

        -- Previous page navigation
        if showNav and (pageNum > 1 or (cycle and totalPages > 1)) then
            table.insert(options, {
                "(Prev)",
                function(playerArg)
                    local prev = pageNum > 1 and pageNum - 1 or totalPages
                    showPage(prev)
                end
            })
        end

        -- Add items for current page
        for i = startIdx, endIdx do
            local item  = filteredItems[i]
            local label = item.label or item.name or item[1]

            -- Allow label to be a function
            if type(label) == "function" then
                label = label(player, item)
            end

            table.insert(options, {
                label,
                function(playerArg)
                    if onSelect then
                        onSelect(playerArg, item, npc)
                    end
                end
            })
        end

        -- Next page navigation
        if showNav and (pageNum < totalPages or (cycle and totalPages > 1)) then
            table.insert(options, {
                "(Next)",
                function(playerArg)
                    local next = pageNum < totalPages and pageNum + 1 or 1
                    showPage(next)
                end
            })
        end

        -- First page navigation (if more than 2 pages and not on first page)
        if showNav and totalPages > 2 and pageNum > 1 then
            table.insert(options, {
                "(First)",
                function(playerArg)
                    showPage(1)
                end
            })
        end

        -- Cancel option
        if onCancel then
            table.insert(options, {
                "Cancel",
                function(playerArg)
                    onCancel(playerArg, "cancelled")
                end
            })
        end

        -- Build title
        local menuTitle = title
        if type(title) == "function" then
            menuTitle = title(pageNum, totalPages)
        elseif totalPages > 1 then
            menuTitle = string.format("%s (%d/%d)", title, pageNum, totalPages)
        end

        -- Show menu with slight delay to prevent context issues
        player:timer(100, function(playerArg)
            playerArg:customMenu({
                title   = menuTitle,
                options = options,
            })
        end)
    end

    -- Start at page 1
    showPage(1)
end

return {}
