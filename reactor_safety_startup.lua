-- Mekanism Fission Reactor Safety Controller
-- Advanced Computer connected to Logic Adapter on BACK

local reactor = peripheral.wrap("back")

if not reactor then
    error("No fission reactor logic adapter found on back!")
end

local latchedSCRAM = false
local lastReason = "None"

local function log(message)
    local f = fs.open("reactor_safety.log", "a")
    if f then
        f.writeLine(os.date("%H:%M:%S") .. " - " .. message)
        f.close()
    end
end

log("Safety controller started.")

while true do
    local status = reactor.getStatus()
    local temp = reactor.getTemperature()

    -- Mekanism returns fractions:
    -- 1.0 = 100%
    -- 0.5 = 50%
    -- 0.25 = 25%

    local coolant = reactor.getCoolantFilledPercentage() * 100
    local heatedCoolant = reactor.getHeatedCoolantFilledPercentage() * 100
    local waste = reactor.getWasteFilledPercentage() * 100
    local damage = reactor.getDamagePercent()

    local burnRate = reactor.getBurnRate()
    local maxBurnRate = reactor.getMaxBurnRate()

    local scramReason = nil

    --------------------------------------------------
    -- SAFETY CHECKS
    --------------------------------------------------

    if damage > 0 then
        scramReason = string.format(
            "Damage detected: %.2f%%",
            damage
        )

    elseif temp >= 1000 then
        scramReason = string.format(
            "Core temperature critical: %.0fK",
            temp
        )

    elseif waste >= 85 then
        scramReason = string.format(
            "Waste storage high: %.2f%%",
            waste
        )

    elseif coolant <= 25 then
        scramReason = string.format(
            "Coolant low: %.2f%%",
            coolant
        )
    end

    --------------------------------------------------
    -- SCRAM
    --------------------------------------------------

    if scramReason and not latchedSCRAM then
        if status then
            reactor.scram()
        end

        latchedSCRAM = true
        lastReason = scramReason

        log("SCRAM: " .. scramReason)
    end

    --------------------------------------------------
    -- DISPLAY
    --------------------------------------------------

    term.clear()
    term.setCursorPos(1,1)

    print("     MEKANISM FISSION SAFETY")
    print("--------------------------------")
    print("Status:        " .. tostring(status))
    print(string.format("Temp:          %.2fK", temp))
    print(string.format("Damage:        %.2f%%", damage))
    print(string.format("Coolant:       %.2f%%", coolant))
    print(string.format("Heated Coolant %.2f%%", heatedCoolant))
    print(string.format("Waste:         %.2f%%", waste))
    print(string.format(
        "Burn Rate:     %.2f / %.2f",
        burnRate,
        maxBurnRate
    ))
    print("Latched SCRAM: " .. tostring(latchedSCRAM))
    print("Last Reason:   " .. lastReason)
    print("--------------------------------")
    print("Log: reactor_safety.log")

    sleep(1)
end
