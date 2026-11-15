-- Dealership client. Everything here goes through a public whip_core export, as a worked example of building on whip.
-- Simon himself is a whip NPC the server makes (server/main.lua), so this side only has his prompt and the showroom.

local menuOpen = false
local typing = false   -- whip's keyboard is up for the search

-- Controller: whip's pad reader for screens (Whip.padScreen) sends presses to the page ('pad', dealership.js
-- padPress); the mouse moving brings the cursor back. Typing a search is whip's keyboard (OpenKeyboard).
local screen = Whip.padScreen()

-- ============================================
-- The menu
-- ============================================

--- Each car's performance from GTA's model stats: top speed in km/h, acceleration, braking, traction, seats. Read
--- from the model, so nothing is spawned; a model the game does not have gets none.
---@param vehicles table[]
local function addStats(vehicles)
    for _, v in ipairs(vehicles) do
        local hash = GetHashKey(v.model)
        if IsModelInCdimage(hash) and IsModelAVehicle(hash) then
            v.stats = {
                speed    = GetVehicleModelEstimatedMaxSpeed(hash) * 3.6,
                accel    = GetVehicleModelAcceleration(hash),
                braking  = GetVehicleModelMaxBraking(hash),
                traction = GetVehicleModelMaxTraction(hash),
                seats    = GetVehicleModelNumberOfSeats(hash),
            }
        end
    end
end

local function closeMenu()
    if not menuOpen then return end
    menuOpen = false
    typing = false
    screen:close()
    SendNUIMessage({ action = 'dealershipClose' })
    exports.whip_core:SetScreenOpen(false)
end

local function openMenu()
    if menuOpen then return end

    -- The catalogue is assembled server-side so prices cannot be read out of a player's memory. A refusal comes
    -- back as `false, why` (too far away, asked too often): show the why.
    local data, why = exports.whip_core:Callback('whip_dealership:catalogue')
    if not data then
        exports.whip_core:Notify(why or 'The dealership is not answering', 'error', 5000)
        return
    end
    if not data.vehicles or #data.vehicles == 0 then
        exports.whip_core:Notify('The dealership has nothing for sale right now', 'error', 5000)
        return
    end
    addStats(data.vehicles)

    menuOpen = true
    -- Opened on a pad: no cursor from the first frame, and the page draws its pad hints.
    SendNUIMessage({ action = 'dealershipOpen', data = data, pad = screen:open() })

    -- TELL WHIP A SCREEN IS UP. The prompts, aim targeting, the HUD and chat all read this one
    -- switch; without it Simon's own prompt kept scoring every frame behind the menu. The same call
    -- the gunny bench and whip_autos make.
    exports.whip_core:SetScreenOpen(true)
end

RegisterNUICallback('dealershipClose', function(_, cb)
    cb('ok')
    closeMenu()
end)

--- The search on a pad: whip's keyboard (it waits, so in a thread), its text back to the page. While it
--- is up the pad is the keyboard's (the screen leaves it alone by itself); after, the menu's focus again.
RegisterNUICallback('dealershipType', function(data, cb)
    cb('ok')
    if not menuOpen or typing then return end
    typing = true
    CreateThread(function()
        local text = Whip.call('OpenKeyboard', {
            title = 'Search cars', maxLength = 30,
            value = type(data) == 'table' and type(data.value) == 'string' and data.value or '',
        })
        typing = false
        if not menuOpen then return end
        if type(text) == 'string' then SendNUIMessage({ action = 'dealershipSearch', text = text }) end
    end)
end)

RegisterNUICallback('dealershipBuy', function(data, cb)
    cb('ok')
    if not data or not data.model then return end
    -- Only the model travels. The price is whatever the server decides it is.
    TriggerServerEvent('whip_dealership:server:buy', tostring(data.model), tostring(data.payment or 'cash'),
        tonumber(data.accountId) or 0)
end)

-- The purchase result comes back as its own event, so the UI is not blocked while the server finishes. A failed
-- purchase is not toasted here: whip shows the handler's `false, 'why'` itself; this only tells the open menu.
RegisterNetEvent('whip_dealership:client:purchaseResult', function(ok, message, model)
    SendNUIMessage({ action = 'dealershipResult', ok = ok, message = message, model = model })
    if ok then
        closeMenu()
        exports.whip_core:Notify(message or 'Purchased', 'success', 7000)
    end
end)

-- ============================================
-- Manage Keys
-- ============================================
--
-- Simon's second option is a menu on his prompt, FILLED WHEN IT OPENS: `options` is a function, so the list is the
-- cars this player owns now, asked of the server each time (it may wait: whip shows "One moment…" meanwhile). Each car
-- is a menu of its own, filled the same way, so its key count is current. `stay = true` keeps the prompt on the car's
-- page after a press, and whip fills it again, so the count follows a key made or the old ones stopped.
--
-- The server decides everything: the 'vehicle' param refuses a car that is not theirs, and the key and the locks are
-- whip_core's (GiveVehicleKey, ChangeVehicleLocks, CountVehicleKeys).

--- One of the player's cars: its page, with the car's picture above it (the catalog's, as the showroom's).
---@param car table  { vehicleId, name, plate, image? } from the server
local function carPage(car)
    local id = car.vehicleId
    return {
        id      = 'veh' .. tostring(id),
        label   = ('%s  %s'):format(car.name, car.plate),
        icon    = 'car',
        image   = car.image,
        options = function()
            local count = exports.whip_core:Callback('whip_dealership:keyCount', id)
            return {
                {
                    id = 'make', label = 'Make new key', icon = 'give', stay = true,
                    onSelect = function(ctx)
                        local made, why = exports.whip_core:Callback('whip_dealership:makeKey', id)
                        if made then
                            ctx.flash(80, 220, 120)
                            ctx.status('Key made', 2000)
                        else
                            ctx.refuse(why or 'No key was made')
                        end
                    end,
                },
                {
                    -- Held, as it can't be undone: every key made before stops fitting, wherever it is.
                    id = 'disable', label = 'Disable previous keys', icon = 'lock', stay = true, holdMs = 1500,
                    onSelect = function(ctx)
                        local done, why = exports.whip_core:Callback('whip_dealership:disableKeys', id)
                        if done then
                            ctx.flash(80, 220, 120)
                            ctx.status('Old keys no longer fit', 2500)
                        else
                            ctx.refuse(why or 'The locks were not changed')
                        end
                    end,
                },
                -- Only a number: not where the keys are. Pressing it does nothing.
                { id = 'count', icon = 'info', stay = true,
                  label = type(count) == 'number' and ('Active keys: %d'):format(count) or 'Active keys: ?' },
            }
        end,
    }
end

--- The cars this player owns, each a page (carPage). A refusal (too far from Simon) or none owned is one row saying so.
local function myCars()
    local cars, why = exports.whip_core:Callback('whip_dealership:myVehicles')
    if not cars then
        return { { id = 'why', label = why or 'The dealership is not answering', icon = 'warning', stay = true } }
    end
    if #cars == 0 then
        return { { id = 'none', label = 'You own no vehicles', icon = 'info', stay = true } }
    end
    local list = {}
    for i, car in ipairs(cars) do list[i] = carPage(car) end
    return list
end

-- ============================================
-- Registration
-- ============================================

-- The interaction point lives in whip_core's tables, so it is declared through Whip.register, which re-runs it when
-- core restarts (AddAction with a fixed id replaces rather than adds). It is at Simon's spot rather than riding his
-- ped: he never moves, and the prompt is there before his ped has reached this game.
Whip.register(function()
    local c = Config.Salesman.coords
    local ok, why = exports.whip_core:AddAction({
        id      = 'simon',
        at      = { coords = vector3(c.x, c.y, c.z) },
        label   = Config.Salesman.label,
        icon    = 'car',
        group   = 'dealership',
        options = {
            { id = 'browse', label = Config.Salesman.label, icon = 'car', onSelect = function() openMenu() end },
            { id = 'keys', label = Config.Salesman.keysLabel, icon = 'lock', options = myCars },
        },
    })
    if not ok then print('[whip_dealership] could not add Simon\'s action: ' .. tostring(why)) end
end)

-- ============================================
-- Test command
-- ============================================

--- Buy without the menu: /buycar <model> [cash|bank] [accountId]
--- Exercises the money, ownership, key and spawn path on its own. It uses the same secure event as the menu, so the
--- proximity check, rate limit and server-side price still apply. Gated on whip.devtools.
RegisterCommand('buycar', function(_, args)
    local model = (args[1] or ''):lower()
    if model == '' then
        print('[whip_dealership] usage: /buycar <model> [cash|bank] [accountId]')
        return
    end
    -- whip's developer-mode check (only what this game shows: the purchase itself is the server's, with its checks).
    if not exports.whip_core:HasDevTools() then
        exports.whip_core:Notify('/buycar is a developer tool: turn developer mode on in /w', 'error', 5000)
        return
    end

    TriggerServerEvent('whip_dealership:server:buy', model,
        (args[2] or 'cash'):lower(), tonumber(args[3]) or 0)
end, false)

-- No onResourceStop here: whip removes what a stopping resource made through it (Simon, his prompt, the blip),
-- Whip.padScreen gives the focus back, and whip drops a stopping resource's screen and blocks itself.

-- Shot in the showroom, or gone to character select: the catalogue closes (16 Oct 2026, death investigation). It
-- stayed over the death screen with the focus, and over character select.
AddEventHandler('whip_core:player:died', closeMenu)
AddEventHandler('whip_core:player:logout', closeMenu)
