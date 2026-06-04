-- Mekanism Fission Reactor Safety Controller for CC:Tweaked
-- Save as: startup.lua or startup
-- Install in ComputerCraft with:
--   wget <raw-url> startup
--   reboot

-- =============================
-- USER CONFIG
-- =============================
local REACTOR_SIDE = "back"      -- side where the Fission Reactor Logic Adapter is attached
local CHECK_INTERVAL = 1          -- seconds between safety checks

-- Thresholds. These assume percentage methods return 0-100.
-- If your methods return 0-1, set PERCENT_SCALE = 1.
local PERCENT_SCALE = 100

local MAX_TEMP_K = 1000           -- SCRAM above this temperature
local MAX_DAMAGE_PERCENT = 0      -- SCRAM if damage is above this
local MAX_WASTE_PERCENT = 85      -- SCRAM if waste is above this
local MIN_COOLANT_PERCENT = 25    -- SCRAM if coolant is below this
local MAX_HEATED_COOLANT_PERCENT = 95 -- SCRAM if heated coolant backs up

-- Recovery behavior
local ALLOW_AUTO_RESTART = false  -- safest default: manual restart only
local RESTART_MAX_TEMP_K = 500
local RESTART_MAX_WASTE_PERCENT = 20
local RESTART_MIN_COOLANT_PERCENT = 80
local RESTART_MAX_HEATED_COOLANT_PERCENT = 20

-- Display/logging
local LOG_FILE = "reactor_safety.log"
local CLEAR_SCREEN_EACH_LOOP = true

-- =============================
-- HELPERS
-- =============================
local function now()
    return textutils.formatTime(os.time(), true)
end

local function log(msg)
    local line = "[" .. now() .. "] " .. msg
    print(line)
    local f = fs.open(LOG_FILE, "a")
    if f then
        f.writeLine(line)
        f.close()
    end
end

local function safeCall(obj, method, default)
    if type(obj[method]) ~= "function" then return default end
    local ok, result = pcall(obj[method])
    if ok then return result end
    return default
end

local function toPercent(value)
    if value == nil then return nil end
    if PERCENT_SCALE == 1 then
        return value * 100
    end
    return value
end

local function boolStatus(value)
    if type(value) == "boolean" then return value end
    if type(value) == "string" then
        local s = string.lower(value)
        return s == "active" or s == "online" or s == "running" or s == "true"
    end
    return false
end

local function fmt(value, suffix)
    if value == nil then return "n/a" end
    if type(value) == "number" then return string.format("%.2f%s", value, suffix or "") end
    return tostring(value)
end

local function centerPrint(text)
    local w, _ = term.getSize()
    local x = math.max(1, math.floor((w - #text) / 2) + 1)
    term.setCursorPos(x, select(2, term.getCursorPos()))
    print(text)
end

-- =============================
-- INIT
-- =============================
local reactor = peripheral.wrap(REACTOR_SIDE)
if not reactor then
    error("No reactor peripheral found on side: " .. REACTOR_SIDE)
end

if type(reactor.scram) ~= "function" then
    error("Peripheral on " .. REACTOR_SIDE .. " does not expose scram(). Check side/adapter.")
end

log("Safety controller booted. Reactor side = " .. REACTOR_SIDE)

local latchedScram = false
local lastReason = "None"

-- =============================
-- MAIN LOOP
-- =============================
while true do
    local temp = safeCall(reactor, "getTemperature", nil)
    local damage = toPercent(safeCall(reactor, "getDamagePercent", nil))
    local waste = toPercent(safeCall(reactor, "getWasteFilledPercentage", nil))
    local coolant = toPercent(safeCall(reactor, "getCoolantFilledPercentage", nil))
    local heatedCoolant = toPercent(safeCall(reactor, "getHeatedCoolantFilledPercentage", nil))
    local statusRaw = safeCall(reactor, "getStatus", false)
    local isOnline = boolStatus(statusRaw)
    local burnRate = safeCall(reactor, "getBurnRate", nil)
    local maxBurnRate = safeCall(reactor, "getMaxBurnRate", nil)

    local reason = nil

    if damage ~= nil and damage > MAX_DAMAGE_PERCENT then
        reason = "Damage detected: " .. fmt(damage, "%")
    elseif temp ~= nil and temp >= MAX_TEMP_K then
        reason = "Temperature critical: " .. fmt(temp, "K")
    elseif waste ~= nil and waste >= MAX_WASTE_PERCENT then
        reason = "Waste backup: " .. fmt(waste, "%")
    elseif coolant ~= nil and coolant <= MIN_COOLANT_PERCENT then
        reason = "Coolant low: " .. fmt(coolant, "%")
    elseif heatedCoolant ~= nil and heatedCoolant >= MAX_HEATED_COOLANT_PERCENT then
        reason = "Heated coolant backup: " .. fmt(heatedCoolant, "%")
    end

    if CLEAR_SCREEN_EACH_LOOP then
        term.clear()
        term.setCursorPos(1, 1)
    end

    centerPrint("MEKANISM FISSION SAFETY")
    print(string.rep("-", 31))
    print("Status:        " .. tostring(statusRaw))
    print("Temp:          " .. fmt(temp, "K"))
    print("Damage:        " .. fmt(damage, "%"))
    print("Coolant:       " .. fmt(coolant, "%"))
    print("Heated Coolant:" .. fmt(heatedCoolant, "%"))
    print("Waste:         " .. fmt(waste, "%"))
    print("Burn Rate:     " .. fmt(burnRate, "") .. " / " .. fmt(maxBurnRate, ""))
    print("Latched SCRAM: " .. tostring(latchedScram))
    print("Last Reason:   " .. lastReason)
    print(string.rep("-", 31))
    print("Log: " .. LOG_FILE)

    if reason then
        lastReason = reason
        if not latchedScram then
            latchedScram = true
            log("SCRAM triggered: " .. reason)
        end
        if isOnline then
            local ok, err = pcall(function() reactor.scram() end)
            if not ok then log("SCRAM command failed: " .. tostring(err)) end
        end
    else
        if latchedScram then
            print("Safe now, but SCRAM is latched.")
            print("Manual reset: delete latch by rebooting/editing config, or enable auto restart.")
        end

        if ALLOW_AUTO_RESTART and latchedScram then
            local canRestart = true
            canRestart = canRestart and (temp == nil or temp < RESTART_MAX_TEMP_K)
            canRestart = canRestart and (waste == nil or waste < RESTART_MAX_WASTE_PERCENT)
            canRestart = canRestart and (coolant == nil or coolant > RESTART_MIN_COOLANT_PERCENT)
            canRestart = canRestart and (heatedCoolant == nil or heatedCoolant < RESTART_MAX_HEATED_COOLANT_PERCENT)

            if canRestart and not isOnline and type(reactor.activate) == "function" then
                log("Auto-restart conditions met. Activating reactor.")
                pcall(function() reactor.activate() end)
                latchedScram = false
                lastReason = "Auto-restarted after safe recovery"
            end
        end
    end

    sleep(CHECK_INTERVAL)
end
