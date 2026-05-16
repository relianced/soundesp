local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local V2 = Vector2.new
local C3 = Color3.fromRGB

-- ============================================================
-- ⚙️ SETTINGS ⚙️
-- ============================================================

-- ESP appearance
local MARKER_RADIUS = 5
local MARKER_SIDES = 24
local TERRORIST_COLOR = C3(255, 100, 100)  -- Red for Terrorists
local CT_COLOR = C3(100, 100, 255)         -- Blue for Counter-Terrorists
local MARKER_THICKNESS = 2

-- How long marker stays on screen (seconds)
local MARKER_DURATION = 0.01

-- Sound detection settings
local MAX_SOUND_DISTANCE = 70
local MIN_SOUND_DISTANCE = 0

-- Movement speed thresholds (studs per second)
-- Walking is typically 8-14, running is 14-22, sprinting is 22+
local MIN_WALK_SPEED = 12    -- Only detect movement ABOVE this speed (ignore slow walk)
local MAX_WALK_SPEED = 50    -- Maximum speed to consider (ignore glitches)

-- Sound types to detect
local DETECT_RUNNING = true   -- Running/fast movement
local DETECT_JUMPING = true
local DETECT_SHOOTING = true

-- Update speeds
local DETECTION_SPEED = 0  -- ~30 FPS detection
local VISUAL_SPEED = 0   -- 240 FPS

-- Hotkey to toggle (F5)
local TOGGLE_KEY = 0x74

-- Hide self
local HIDE_SELF = true

-- ============================================================
-- DO NOT EDIT BELOW THIS LINE
-- ============================================================

local espActive = true
local activeMarkers = {}

-- Find Characters folder
local function findCharactersFolder()
    local allDescendants = workspace:GetDescendants()
    for i = 1, #allDescendants do
        local obj = allDescendants[i]
        if obj.Name == "Characters" and (obj:IsA("Folder") or obj:IsA("Model")) then
            return obj
        end
    end
    return nil
end

-- Get all characters
local function getAllCharacters()
    local characters = {}
    
    local charactersFolder = findCharactersFolder()
    if not charactersFolder then
        return characters
    end
    
    -- Terrorists
    local terroristsFolder = charactersFolder:FindFirstChild("Terrorists")
    if terroristsFolder then
        local terroristPlayers = terroristsFolder:GetChildren()
        for i = 1, #terroristPlayers do
            local playerFolder = terroristPlayers[i]
            if playerFolder:IsA("Folder") or playerFolder:IsA("Model") then
                local humanoidRootPart = playerFolder:FindFirstChild("HumanoidRootPart")
                if humanoidRootPart and humanoidRootPart.Parent then
                    table.insert(characters, {
                        object = playerFolder,
                        rootPart = humanoidRootPart,
                        name = playerFolder.Name,
                        team = "Terrorist"
                    })
                end
            end
        end
    end
    
    -- Counter-Terrorists
    local ctFolder = charactersFolder:FindFirstChild("Counter-Terrorists")
    if ctFolder then
        local ctPlayers = ctFolder:GetChildren()
        for i = 1, #ctPlayers do
            local playerFolder = ctPlayers[i]
            if playerFolder:IsA("Folder") or playerFolder:IsA("Model") then
                local humanoidRootPart = playerFolder:FindFirstChild("HumanoidRootPart")
                if humanoidRootPart and humanoidRootPart.Parent then
                    table.insert(characters, {
                        object = playerFolder,
                        rootPart = humanoidRootPart,
                        name = playerFolder.Name,
                        team = "CT"
                    })
                end
            end
        end
    end
    
    return characters
end

-- Get color based on team
local function getTeamColor(team)
    if team == "Terrorist" then
        return TERRORIST_COLOR
    else
        return CT_COLOR
    end
end

-- Create a marker
local function createMarker(character, position, characterName, team, distance)
    -- Remove old marker if exists
    if activeMarkers[character] then
        local old = activeMarkers[character]
        if old.ring then old.ring:Remove() end
        if old.fill then old.fill:Remove() end
        if old.name then old.name:Remove() end
        activeMarkers[character] = nil
    end
    
    local markerColor = getTeamColor(team)
    local teamLabel = (team == "Terrorist") and "🔴" or "🔵"
    
    local ring = Drawing.new("Circle")
    ring.Radius = MARKER_RADIUS
    ring.NumSides = MARKER_SIDES
    ring.Filled = false
    ring.Color = markerColor
    ring.Thickness = MARKER_THICKNESS
    ring.Visible = true
    ring.ZIndex = 4
    
    local fill = Drawing.new("Circle")
    fill.Radius = MARKER_RADIUS - 1
    fill.NumSides = MARKER_SIDES
    fill.Filled = true
    fill.Color = markerColor
    fill.Transparency = 0.85
    fill.Visible = true
    fill.ZIndex = 3
    
    local name = Drawing.new("Text")
    name.Size = 10
    name.Font = Drawing.Fonts.System
    name.Color = markerColor
    name.Center = true
    name.Outline = false
    name.Transparency = 0.3
    name.Visible = true
    name.ZIndex = 5
    name.Text = teamLabel .. " " .. math.floor(distance) .. "s"
    
    activeMarkers[character] = {
        ring = ring,
        fill = fill,
        name = name,
        position = position,
        expireTime = tick() + MARKER_DURATION,
        team = team,
        distance = distance
    }
    
    -- Fast pulse effect
    ring.Radius = MARKER_RADIUS + 8
    task.spawn(function()
        task.wait(0)
        if activeMarkers[character] and activeMarkers[character].ring then
            activeMarkers[character].ring.Radius = MARKER_RADIUS
        end
    end)
end

-- Update marker positions (240 FPS)
local function updateMarkers()
    local currentTime = tick()
    local toRemove = {}
    
    for character, marker in pairs(activeMarkers) do
        if currentTime >= marker.expireTime then
            table.insert(toRemove, character)
        else
            local screenPos, onScreen = WorldToScreen(marker.position)
            
            if onScreen then
                marker.ring.Position = screenPos
                marker.fill.Position = screenPos
                marker.name.Position = V2(screenPos.X, screenPos.Y - MARKER_RADIUS - 8)
                marker.ring.Visible = true
                marker.fill.Visible = true
                marker.name.Visible = true
            else
                marker.ring.Visible = false
                marker.fill.Visible = false
                marker.name.Visible = false
            end
        end
    end
    
    for i = 1, #toRemove do
        local marker = activeMarkers[toRemove[i]]
        if marker then
            if marker.ring then marker.ring:Remove() end
            if marker.fill then marker.fill:Remove() end
            if marker.name then marker.name:Remove() end
            activeMarkers[toRemove[i]] = nil
        end
    end
end

-- Detect sounds from players
local function detectSounds()
    local characters = getAllCharacters()
    local localChar = LocalPlayer.Character
    local localPos = nil
    
    if localChar then
        local root = localChar:FindFirstChild("HumanoidRootPart") or localChar:FindFirstChild("Head")
        if root then
            localPos = root.Position
        end
    end
    
    for i = 1, #characters do
        local charInfo = characters[i]
        local character = charInfo.object
        local rootPart = charInfo.rootPart
        local team = charInfo.team
        local characterName = charInfo.name
        
        if rootPart and rootPart.Parent then
            local position = rootPart.Position
            local detectedSound = false
            
            local distance = 0
            if localPos then
                local dx = position.X - localPos.X
                local dy = position.Y - localPos.Y
                local dz = position.Z - localPos.Z
                distance = math.sqrt(dx*dx + dy*dy + dz*dz)
            end
            
            if distance <= MAX_SOUND_DISTANCE and distance >= MIN_SOUND_DISTANCE then
                
                -- Running/fast movement detection (IGNORES slow walking)
                if DETECT_RUNNING then
                    local velocity = rootPart.Velocity
                    local speed = math.sqrt(velocity.X*velocity.X + velocity.Z*velocity.Z)
                    -- ONLY detect if speed is above MIN_WALK_SPEED (ignores slow walk)
                    if speed > MIN_WALK_SPEED and speed < MAX_WALK_SPEED then
                        detectedSound = true
                    end
                end
                
                -- Jumping detection
                if DETECT_JUMPING and not detectedSound then
                    local terrainHeight = workspace.Terrain:GetHeight(position.X, position.Z)
                    if position.Y - 3 > terrainHeight + 2 then
                        detectedSound = true
                    end
                end
                
                -- Shooting detection
                if DETECT_SHOOTING and not detectedSound then
                    local weapon = character:FindFirstChild("Weapon")
                    if weapon then
                        local muzzle = weapon:FindFirstChild("MuzzlePart")
                        if muzzle then
                            local vel = muzzle.Velocity
                            if vel.Magnitude > 10 then
                                detectedSound = true
                            end
                        end
                    end
                end
                
                -- Create marker IMMEDIATELY on sound
                if detectedSound then
                    createMarker(character, position, characterName, team, distance)
                end
            end
        end
    end
end

-- Clean up all markers
local function cleanupAll()
    for character, marker in pairs(activeMarkers) do
        if marker.ring then marker.ring:Remove() end
        if marker.fill then marker.fill:Remove() end
        if marker.name then marker.name:Remove() end
    end
    activeMarkers = {}
end

-- ============================================================
-- MAIN LOOP
-- ============================================================
local running = true
local prevToggle = false


print("✅ ESP Active - F5 to toggle")
print("🏃 Running speed threshold: " .. MIN_WALK_SPEED .. "+ studs/sec")


-- Detection loop
task.spawn(function()
    while running do
        if espActive then
            pcall(detectSounds)
        end
        task.wait(DETECTION_SPEED)
    end
end)

-- Visual update loop (240 FPS)
task.spawn(function()
    while running do
        if espActive then
            pcall(updateMarkers)
        end
        task.wait(VISUAL_SPEED)
    end
end)

-- Toggle with F5
while running do
    local keyPressed = false
    pcall(function() keyPressed = iskeypressed(TOGGLE_KEY) end)
    if keyPressed and not prevToggle then
        espActive = not espActive
        if not espActive then
            cleanupAll()
            print("[SoundESP] Disabled (F5)")
        else
            print("[SoundESP] Enabled (F5)")
        end
    end
    prevToggle = keyPressed
    task.wait(0.016)
end

cleanupAll()
print("[SoundESP] Stopped")
