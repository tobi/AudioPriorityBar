-- Run with the target app running; optionally pass expected connected device names.
-- osascript Tests/popover-uat.applescript AudioPriorityBar "MacBook Air Microphone"
-- Checks the rendered viewport, then closes and reopens the popover and checks again.
-- Does not change audio devices, priorities, or automation settings.
on run arguments
    if (count of arguments) < 1 then error "Pass the target app process name."
    set appName to item 1 of arguments
    set expectedNames to rest of arguments
    set passes to 2
    set minimumViewportHeight to 200
    if expectedNames is not {} and item 1 of expectedNames is "--window-only" then
        set expectedNames to rest of expectedNames
        set passes to 1
        set minimumViewportHeight to 1
    end if
    tell application "System Events" to tell process appName
        repeat 30 times
            if (count of windows) > 0 or (count of menu bars) > 1 then exit repeat
            delay 0.1
        end repeat
        repeat with attempt from 1 to passes
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
            if (item 2 of viewportSize) < minimumViewportHeight then error "Device list collapsed: height=" & (item 2 of viewportSize)
            set rowNames to name of every static text of viewport
            repeat with expectedName in expectedNames
                if rowNames does not contain (expectedName as text) then error "Missing microphone: " & expectedName
            end repeat
            set panelPosition to position of window 1
            set panelSize to size of window 1
            -- The top-level buttons include Login, Edit, and Quit, outside the scroll view.
            repeat with panelButton in buttons of group 1 of window 1
                set controlPosition to position of panelButton
                set controlSize to size of panelButton
                if (item 2 of controlPosition) < (item 2 of panelPosition) - 1 or (item 2 of controlPosition) + (item 2 of controlSize) > (item 2 of panelPosition) + (item 2 of panelSize) + 1 then error "Header or footer button is clipped"
            end repeat
            if attempt is 1 and passes is 2 then
                set iconPosition to position of menu bar item "Volume High" of menu bar 2
                set iconSize to size of menu bar item "Volume High" of menu bar 2
                tell application "System Events" to click at {(item 1 of iconPosition) + (item 1 of iconSize) / 2, (item 2 of iconPosition) + (item 2 of iconSize) / 2}
                delay 0.1
                if (count of windows) is not 0 then error "Popover did not close when its menu icon was clicked"
            end if
        end repeat
        return "PASS: viewport and top-level controls visible; expected microphones present. Passes=" & passes & "; height=" & (item 2 of viewportSize)
    end tell
end run
