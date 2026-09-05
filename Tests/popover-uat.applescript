-- Run with the target app running; optionally pass expected connected device names.
-- osascript Tests/popover-uat.applescript AudioPriorityBar "MacBook Air Microphone"
-- Checks the rendered viewport, then closes and reopens the popover and checks again.
-- Does not change audio devices, priorities, or automation settings.
on run arguments
    if (count of arguments) < 1 then error "Pass the target app process name."
    set appName to item 1 of arguments
    set expectedNames to rest of arguments
    tell application "System Events" to tell process appName
        repeat with attempt from 1 to 2
            if (count of windows) is 0 then
                set iconPosition to position of menu bar item "Volume High" of menu bar 2
                set iconSize to size of menu bar item "Volume High" of menu bar 2
                tell application "System Events" to click at {(item 1 of iconPosition) + (item 1 of iconSize) / 2, (item 2 of iconPosition) + (item 2 of iconSize) / 2}
            end if
            repeat 20 times
                if (count of windows) > 0 then exit repeat
                delay 0.1
            end repeat
            set viewport to scroll area 1 of group 1 of window 1
            set viewportSize to size of viewport
            if (item 2 of viewportSize) < 200 then error "Device list collapsed: height=" & (item 2 of viewportSize)
            set rowNames to name of every static text of viewport
            repeat with expectedName in expectedNames
                if rowNames does not contain (expectedName as text) then error "Missing microphone: " & expectedName
            end repeat
            if attempt is 1 then
                set iconPosition to position of menu bar item "Volume High" of menu bar 2
                set iconSize to size of menu bar item "Volume High" of menu bar 2
                tell application "System Events" to click at {(item 1 of iconPosition) + (item 1 of iconSize) / 2, (item 2 of iconPosition) + (item 2 of iconSize) / 2}
                delay 0.1
                if (count of windows) is not 0 then error "Popover did not close when its menu icon was clicked"
            end if
        end repeat
        return "PASS: device list stays visible after reopening; expected microphones are present. Height=" & (item 2 of viewportSize)
    end tell
end run
