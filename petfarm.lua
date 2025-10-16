-- --- GLOBAL DEBUG/LOGGING UTILITY ---
-- Set to 'true' if you ever need to debug the script in the console.
local DEBUG_ENABLED = false 
local function log(...) if DEBUG_ENABLED then print(...) end end
local function log_warn(...) if DEBUG_ENABLED then warn(...) end end

-- --- REMOTE DEHASHING SCRIPT (RUNS FIRST FOR PROPER REMOTE LOADING) ---
local Fsys = require(game.ReplicatedStorage:WaitForChild("Fsys", 999)).load 

local initFunction = Fsys("RouterClient").init

local printedOnce = false

local function inspectUpvalues()
    local remotes = {} 
    for i = 1, math.huge do
        local success, upvalue = pcall(getupvalue, initFunction, i)
        if not success then break end
        if typeof(upvalue) == "table" then
            for k, v in pairs(upvalue) do
                if typeof(v) == "Instance" then
                    if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") or v:IsA("BindableEvent") or v:IsA("BindableFunction") then
                        table.insert(remotes, {key = k, remote = v})
                        if not printedOnce then
                            log("Key: " .. k .. " Type: " .. typeof(k) .. ", Value Type: " .. typeof(v))
                            log("Found remote: " .. v:GetFullName())
                        end
                    end
                end
            end
        end
    end
    return remotes
end

local function rename(remote, key)
    local nameParts = string.split(key, "/") 
    if #nameParts > 1 then
        local remotename = table.concat(nameParts, "/", 1, 2) 
        remote.Name = remotename
    else
        log_warn("Invalid key format for remote: " .. key) 
    end
end

local function renameExistingRemotes()
    local remotes = inspectUpvalues()
    for _, entry in ipairs(remotes) do
        rename(entry.remote, entry.key)
    end
end

local function displayDehashedMessage()
    local uiElement = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("HintApp") and 
                      game:GetService("Players").LocalPlayer.PlayerGui.HintApp:FindFirstChild("LargeTextLabel")

    if uiElement and uiElement:IsA("TextLabel") then
        uiElement.Text = "Remotes has been Dehashed!"
        uiElement.TextColor3 = Color3.fromRGB(0, 255, 0)
        task.wait(3)
        uiElement.Text = ""
        uiElement.TextColor3 = Color3.fromRGB(255, 255, 255)
    end
end

local function monitorForNewRemotes()
    local remoteFolder = game.ReplicatedStorage:WaitForChild("API", 999)
    remoteFolder.ChildAdded:Connect(function(child)
        if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") or child:IsA("BindableEvent") or child:IsA("BindableFunction") then
            log("New remote added: " .. child:GetFullName())
            local remotes = inspectUpvalues()
            for _, entry in ipairs(remotes) do
                rename(entry.remote, entry.key)
            end
        end
    end)
end

local function periodicCheck()
    while true do
        task.wait(10) 
        pcall(renameExistingRemotes)
    end
end

coroutine.wrap(periodicCheck)()
pcall(renameExistingRemotes)
pcall(displayDehashedMessage)
printedOnce = true
log("Script initialized and monitoring remotes.")
-- --- END OF REMOTE DEHASHING SCRIPT ---




--[[
    PlatformCreator.lua

    This script serves three purposes, executed in a safe 5-second loop:
    1. Dynamic Platform Creation: Creates multiple large, anchored platform parts at the
       exact positions of all defined EXTERIOR target instances.
    2. Interior Search Marker: Creates a visible Part named "SearchingforOrigins" 
       inside the 'workspace.Interiors' folder to mark the search process.
    3. Interior Teleportation: Searches for a list of INTERIOR targets and, if found, 
       makes the target visible, changes its size, sets CanCollide=true, and teleports 
       all active players to that location. This happens in every loop cycle if the part is present.
    
    BEHAVIOR: Both exterior platform creation and interior teleportation logic run continuously.
--]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

--------------------------------------------------------------------------------
-- 1. EXTERIOR PLATFORM CREATION CONFIGURATION
--------------------------------------------------------------------------------

-- Define the list of target object paths for platform creation.
local TARGET_PATHS = {
    "StaticMap.Campsite.CampsiteOrigin",
    "StaticMap.Beach.BeachPartyAilmentTarget",
    "StaticMap.Park.AilmentTarget"
}

-- Define the platform properties
local PLATFORM_SIZE = Vector3.new(256, 5.0, 256) -- A massive, flat platform (256x5.0x256 studs)
local PLATFORM_BASE_NAME = "GeneratedPlatform_" -- Base name, will be suffixed by the target name
local PLATFORM_COLOR = Color3.fromRGB(0, 100, 0) -- Dark Green
local PLATFORM_MATERIAL = Enum.Material.SmoothPlastic 

-- Variables for the safe loop
local currentPlatforms = {} -- Stores references: {[targetPath] = platformPart}
local DEBOUNCE_TIME = 5 -- Time in seconds between cycles
local lastCreationTime = 0

--------------------------------------------------------------------------------
-- 2. INTERIOR TELEPORTATION CONFIGURATION
--------------------------------------------------------------------------------

-- Define the list of target object paths for interior teleportation.
local INTERIOR_PATHS = {
    "Interiors.PizzaShop.InteriorOrigin",
    "Interiors.Salon.InteriorOrigin",
    "Interiors.School.InteriorOrigin"
}

local SEARCH_MARKER_NAME = "SearchingforOrigins"
-- Size for the interior search marker part
local INTERIOR_MARKER_SIZE = Vector3.new(20, 20, 20) 

-- The size to set the InteriorOrigin part to when it is successfully found.
-- This is now a very large, flat 200x1x200 square.
local FOUND_ORIGIN_SIZE = Vector3.new(200, 1, 200)

-- NOTE: The flag/table for tracking one-time teleportation has been removed 
-- to allow teleportation to occur every time a part is found.

--------------------------------------------------------------------------------
-- 3. CORE UTILITY FUNCTIONS
--------------------------------------------------------------------------------

-- Function to safely find a target part from its path string
local function findTargetByPath(pathString)
    -- Split the path components (e.g., "Interiors.PizzaShop.InteriorOrigin")
    local components = string.split(pathString, ".")
    local current = Workspace
    
    -- Wait for the top-level container (e.g., Interiors) to ensure it loads
    current = current:WaitForChild(components[1], 5)
    if not current then return nil end
    
    -- Check for subsequent components immediately
    for i = 2, #components do
        current = current:FindFirstChild(components[i])
        if not current then return nil end
    end
    
    return current
end

-- Function to calculate the required CFrame for the flat platform
local function calculatePlatformCFrame(targetOrigin)
    -- Discard any rotation from the origin, creating a perfectly level CFrame
    local worldAlignedCFrame = CFrame.new(targetOrigin.Position)
    -- Offset it vertically by half its height to center the bottom on the target
    return worldAlignedCFrame * CFrame.new(0, PLATFORM_SIZE.Y / 2, 0)
end

--------------------------------------------------------------------------------
-- 4. EXTERIOR PLATFORM LOGIC
--------------------------------------------------------------------------------

-- Function to create and position a single platform (creates, destroys old)
local function createAndReplacePlatform(targetPath, targetOrigin)
    local uniqueName = PLATFORM_BASE_NAME .. targetOrigin.Name
    
    -- 1. Delete the old platform if it exists (the "safe" part of the loop)
    local oldPlatform = currentPlatforms[targetPath]
    if oldPlatform and oldPlatform.Parent then
        oldPlatform:Destroy()
    end
    currentPlatforms[targetPath] = nil -- Clear the reference

    -- 2. Create the new Part (the "creating" part of the loop)
    local platform = Instance.new("Part")
    
    -- 3. Set the platform properties
    platform.Name = uniqueName
    platform.Size = PLATFORM_SIZE
    platform.Material = PLATFORM_MATERIAL
    platform.Color = PLATFORM_COLOR
    platform.Anchored = true 
    platform.CanCollide = true
    platform.CastShadow = true
    
    -- 4. Set the initial CFrame
    platform.CFrame = calculatePlatformCFrame(targetOrigin)
    
    -- 5. Parent the platform to the workspace
    platform.Parent = Workspace
    
    -- 6. Set the new reference
    currentPlatforms[targetPath] = platform
    
    print("Platform successfully created/replaced: '" .. uniqueName .. "' at " .. targetPath)
end

--------------------------------------------------------------------------------
-- 5. INTERIOR TELEPORTATION LOGIC 
--------------------------------------------------------------------------------

-- Function to create the Part that signals the interior search is running.
local function createSearchMarker(parentInstance)
    local marker = parentInstance:FindFirstChild(SEARCH_MARKER_NAME)
    
    if not marker then
        marker = Instance.new("Part")
        marker.Name = SEARCH_MARKER_NAME
        marker.Size = INTERIOR_MARKER_SIZE -- Use the large size
        marker.Color = Color3.fromRGB(255, 255, 0) -- Bright Yellow
        marker.Material = Enum.Material.Neon
        marker.Anchored = true
        marker.CanCollide = false
        
        -- Default placement
        marker.Position = Vector3.new(0, 5, 0) 
        
        marker.Parent = parentInstance
        print("Created interior search marker: " .. SEARCH_MARKER_NAME)
    end
    -- Keep the marker visible
    marker.Transparency = 0 
    
    return marker
end

local function handleInteriorTeleportation()
    -- Print the status message as requested
    print("searching for Interior....")
    
    local interiorsContainer = Workspace:FindFirstChild("Interiors")
    if interiorsContainer then
        -- Create or update the visible search marker
        pcall(createSearchMarker, interiorsContainer)
    end
    
    local teleportOccurred = false
    
    for _, interiorPath in ipairs(INTERIOR_PATHS) do
        -- NOTE: The one-time check logic has been removed. The following code will run
        -- every 5 seconds if the target part is present.
        
        local targetOrigin = findTargetByPath(interiorPath)
        
        if targetOrigin then
            print("Interior found at: " .. interiorPath .. ". Making visible, setting large FLAT size, and performing teleport...")
            
            -- Make the target part visible (Transparency = 0)
            targetOrigin.Transparency = 0 
            
            -- Set CanCollide to true so players can stand on it
            targetOrigin.CanCollide = true
            
            -- Set the InteriorOrigin part to the new large FLAT size
            targetOrigin.Size = FOUND_ORIGIN_SIZE
            
            -- Calculate the teleport CFrame (10 studs above the origin)
            local teleportCFrame = CFrame.new(targetOrigin.Position) * CFrame.new(0, 10, 0) 
            
            -- Loop through all active players on the server
            for _, player in ipairs(Players:GetPlayers()) do
                local character = player.Character
                if character and character:FindFirstChildOfClass("Humanoid") and character:FindFirstChild("HumanoidRootPart") then
                    -- Teleport the character
                    character:SetPrimaryPartCFrame(teleportCFrame)
                    print("Teleported " .. player.Name .. " to " .. targetOrigin.Name)
                    teleportOccurred = true -- Track if any teleport happened this cycle
                end
            end
        end
    end
    
    return teleportOccurred
end

--------------------------------------------------------------------------------
-- 6. MAIN LOOP
--------------------------------------------------------------------------------

-- The main loop function connected to Heartbeat
local function updatePlatformLoop()
    -- Check if enough time has passed since the last cycle
    if tick() - lastCreationTime < DEBOUNCE_TIME then
        return
    end

    local allRefreshed = true
    
    -- A. Run the Interior Teleportation Logic 
    pcall(handleInteriorTeleportation)
    
    -- B. Run the Exterior Platform Creation Logic
    -- Iterate over every defined exterior target path
    for _, targetPath in ipairs(TARGET_PATHS) do
        -- Safely find the target part
        local targetOrigin = findTargetByPath(targetPath)
        
        if targetOrigin then
            -- Run the creation logic inside a protected call (pcall)
            local success, result = pcall(createAndReplacePlatform, targetPath, targetOrigin)
            
            if not success then
                -- Print an error if the function failed for unexpected reasons
                warn("Platform creation loop failed for path '" .. targetPath .. "' with error: " .. result)
                allRefreshed = false
            end
        else
            warn("Target instance not found for path: '" .. targetPath .. "'. Skipping platform creation.")
            allRefreshed = false
        end
    end

    -- Update the time to reset the debounce for the next cycle
    lastCreationTime = tick()
    
    if allRefreshed then
        print("Platform creation cycle complete.")
    end
end

-- Start the continuous main loop
RunService.Heartbeat:Connect(updatePlatformLoop)






--[[
  AilmentAutomationClient.lua
  
  This script combines two primary functions:
  1. Ailment UI Manager: Displays active and impending ailments (needs) for the player's baby and pets in a dedicated UI frame.
  2. Automation Sequence: Automatically teleports the player to fulfill needs in a prioritized sequence, now controlled by an ON/OFF toggle.
  
  Key Features:
  - UPDATE (V11): Toilet Action Block: The 'toilet' need now explicitly uses the "Seat1" interaction block for furniture activation.
  - UPDATE (V12): Large, Visible, Collidable Platforms for Safety: Ensures stable teleports onto large, visible parts.
  - UPDATE (V13): Stroller Fix for 'ride' need (Stability): Smoother circular movement (WalkSpeed=3, longer wait time) to prevent the stroller from unequipping prematurely.
  - **UPDATE (V14): Stroller Fix for 'ride' need (Movement Visibility): Forces a minimum 8-second circular walk to ensure the animation is visible before fulfillment is declared and the sequence moves on.**
  
  Place this script in StarterPlayerScripts.
--]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- --- GLOBAL SCRIPT STATE ---
local isAutomationEnabled = true -- Script starts enabled by default
local isAutomationRunning = false -- Lock to prevent concurrent runs

-- --- REQUIRED MODULES (AILMENT MANAGER) ---
local AilmentsManager = require(ReplicatedStorage.new.modules.Ailments.AilmentsClient)
local ClientDataModule = require(ReplicatedStorage.ClientModules.Core.ClientData)

-- Attempt to require necessary automation modules with error handling
local InteriorsM = nil
local UIManager = nil

local successInteriorsM, errorMessageInteriorsM = pcall(function()
    InteriorsM = require(ReplicatedStorage.ClientModules.Core.InteriorsM.InteriorsM)
end)

if not successInteriorsM then
    warn("Failed to require InteriorsM:", errorMessageInteriorsM)
end

local successUIManager, errorMessageUIManager = pcall(function()
    UIManager = require(ReplicatedStorage:WaitForChild("Fsys")).load("UIManager")
end)

if not successUIManager or not UIManager then
    warn("Failed to require UIManager module:", errorMessageUIManager)
end

print("Automation modules loaded. Proceeding with automatic teleport setup.")


-- --- AILMENT & LOCATION MAPPING (UPDATED) ---

local AilmentToLocationMap = {
    -- Location Needs (Fulfillment assumed by being there)
    ["pizza_party"] = { DestinationId = "PizzaShop", DoorId = "MainDoor", RequiresFurniture = false },
    ["salon"] = { DestinationId = "Salon", DoorId = "MainDoor", RequiresFurniture = false },
    ["school"] = { DestinationId = "School", DoorId = "MainDoor", RequiresFurniture = false },
    ["camping"] = { DestinationId = "MainMap", DoorId = "MainDoor", RequiresFurniture = false, TargetPath = "StaticMap.Campsite.CampsiteOrigin" },
    ["beach_party"] = { DestinationId = "MainMap", DoorId = "MainDoor", RequiresFurniture = false, TargetPath = "StaticMap.Beach.BeachPartyAilmentTarget" },
    ["bored"] = { DestinationId = "MainMap", DoorId = "MainDoor", RequiresFurniture = false, TargetPath = "StaticMap.Park.AilmentTarget" },

    -- Furniture Needs (Requires teleport to house and activation)
    ["sleepy"] = { DestinationId = "housing", DoorId = "MainDoor", RequiresFurniture = true, FurnitureName = "BasicCrib" },
    ["hungry"] = { DestinationId = "housing", DoorId = "MainDoor", RequiresFurniture = true, FurnitureName = "PetFoodBowl" },
    ["thirsty"] = { DestinationId = "housing", DoorId = "MainDoor", RequiresFurniture = true, FurnitureName = "PetWaterBowl" },
    ["dirty"] = { DestinationId = "housing", DoorId = "MainDoor", RequiresFurniture = true, FurnitureName = "CheapPetBathtub" },
    ["toilet"] = { DestinationId = "housing", DoorId = "MainDoor", RequiresFurniture = true, FurnitureName = "Toilet" }, 
}

-- Action Needs that require the Stroller Ride (Equip Stroller + Circular Walk)
local StrollerRideNeeds = {
    ["ride"] = true,
}

-- Action Needs that require the Hold and Circular Walk sequence
local HoldAndWalkNeeds = {
    ["walk"] = true,
    ["pet_me"] = true, -- Often fulfilled by walking/holding
}

-- Action Needs that require the Wear Scare sequence
local WearScareNeeds = {
    ["wear_scare"] = true,
}

-- --- AILMENT DATA STORAGE ---
local activeAilmentUIs = {}
local impendingAilmentUIs = {}

-- --- AILMENT UI SETUP (STANDARD) ---
local AilmentDisplayGui
local AilmentListFrame
local AilmentItemTemplate
local ImpendingAilmentsFrame 
local ImpendingAilmentsListLayout 

local function createAilmentUI()
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

    -- ScreenGui
    AilmentDisplayGui = Instance.new("ScreenGui")
    AilmentDisplayGui.Name = "AilmentDisplayGui"
    AilmentDisplayGui.ResetOnSpawn = false
    AilmentDisplayGui.Parent = PlayerGui

    -- Automation Toggle Button Setup
    local ToggleButton = Instance.new("TextButton")
    ToggleButton.Name = "AutomationToggle"
    ToggleButton.Size = UDim2.new(0.3, 0, 0, 35)
    ToggleButton.Position = UDim2.new(0.01, 0, 0.01, 0)
    ToggleButton.TextScaled = true
    ToggleButton.Font = Enum.Font.ArialBold
    ToggleButton.TextColor3 = Color3.new(0, 0, 0)
    ToggleButton.Parent = AilmentDisplayGui

    local function updateToggleUI()
        if isAutomationEnabled then
            ToggleButton.BackgroundColor3 = Color3.fromRGB(85, 255, 85)
            ToggleButton.Text = "Automation: ON"
        else
            ToggleButton.BackgroundColor3 = Color3.fromRGB(255, 85, 85)
            ToggleButton.Text = "Automation: OFF"
        end
    end

    ToggleButton.MouseButton1Click:Connect(function()
        isAutomationEnabled = not isAutomationEnabled
        updateToggleUI()
        print("[Automation Toggle] Script set to: " .. (isAutomationEnabled and "ENABLED" or "DISABLED"))
        
        if isAutomationEnabled and not isAutomationRunning then
            task.spawn(runAutomationSequence)
        end
    end)

    updateToggleUI()

    -- ScrollingFrame (Active Ailments)
    local ScrollingFrame = Instance.new("ScrollingFrame")
    ScrollingFrame.Name = "ActiveAilmentScrollingFrame"
    ScrollingFrame.Size = UDim2.new(0.3, 0, 0.5, 0)
    ScrollingFrame.Position = UDim2.new(0.01, 0, 0.01, 45)
    ScrollingFrame.BackgroundTransparency = 0.5
    ScrollingFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    ScrollingFrame.Parent = AilmentDisplayGui
    AilmentListFrame = ScrollingFrame

    -- UIListLayout for ACTIVE AILMENTS
    local ListLayout = Instance.new("UIListLayout")
    ListLayout.Parent = AilmentListFrame
    ListLayout.Padding = UDim.new(0, 5)
    ListLayout.FillDirection = Enum.FillDirection.Vertical
    ListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    ScrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y

    -- TextLabel Template for ACTIVE AILMENTS
    AilmentItemTemplate = Instance.new("TextLabel")
    AilmentItemTemplate.Name = "AilmentItemTemplate"
    AilmentItemTemplate.Size = UDim2.new(1, -10, 0, 25)
    AilmentItemTemplate.TextScaled = true
    AilmentItemTemplate.TextXAlignment = Enum.TextXAlignment.Left
    AilmentItemTemplate.BackgroundTransparency = 1
    AilmentItemTemplate.TextColor3 = Color3.fromRGB(255, 255, 255)
    AilmentItemTemplate.Visible = false
    AilmentItemTemplate.Parent = AilmentListFrame

    --- UI FOR IMPENDING AILMENTS ---
    ImpendingAilmentsFrame = Instance.new("Frame")
    ImpendingAilmentsFrame.Name = "ImpendingAilmentsFrame"
    ImpendingAilmentsFrame.Size = UDim2.new(0.3, 0, 0.2, 0)
    ImpendingAilmentsFrame.Position = UDim2.new(0.01, 0, 0.55, 45) 
    ImpendingAilmentsFrame.BackgroundTransparency = 0.7
    ImpendingAilmentsFrame.BackgroundColor3 = Color3.fromRGB(80, 50, 50)
    ImpendingAilmentsFrame.Parent = AilmentDisplayGui
    ImpendingAilmentsFrame.Visible = false

    local HeaderLabel = Instance.new("TextLabel")
    HeaderLabel.Name = "Header"
    HeaderLabel.Size = UDim2.new(1, 0, 0, 20)
    HeaderLabel.Text = "Impending Ailments"
    HeaderLabel.Font = Enum.Font.ArialBold
    HeaderLabel.TextScaled = true
    HeaderLabel.TextColor3 = Color3.fromRGB(255, 200, 200)
    HeaderLabel.BackgroundTransparency = 1
    HeaderLabel.Parent = ImpendingAilmentsFrame

    local WarningScrollingFrame = Instance.new("ScrollingFrame")
    WarningScrollingFrame.Name = "WarningScrollingFrame"
    WarningScrollingFrame.Size = UDim2.new(1, 0, 1, -20)
    WarningScrollingFrame.Position = UDim2.new(0, 0, 0, 20)
    WarningScrollingFrame.BackgroundTransparency = 1
    WarningScrollingFrame.Parent = ImpendingAilmentsFrame
    WarningScrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y

    ImpendingAilmentsListLayout = Instance.new("UIListLayout")
    ImpendingAilmentsListLayout.Name = "ImpendingAilmentsListLayout"
    ImpendingAilmentsListLayout.Padding = UDim.new(0, 3)
    ImpendingAilmentsListLayout.FillDirection = Enum.FillDirection.Vertical
    ImpendingAilmentsListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    ImpendingAilmentsListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    ImpendingAilmentsListLayout.Parent = WarningScrollingFrame
end

-- --- AILMENT HELPER FUNCTIONS (STANDARD) ---

local function getAilmentIdFromInstance(ailmentInstance)
    if not ailmentInstance or type(ailmentInstance) ~= "table" then
        return "UNKNOWN_INSTANCE"
    end
    if ailmentInstance.kind then
        return tostring(ailmentInstance.kind)
    end
    return "UNKNOWN_AILMENT_NAME_FALLBACK"
end

local function formatAilmentDetails(ailmentInstance)
    local details = {}
    if ailmentInstance and type(ailmentInstance) == "table" and type(ailmentInstance.get_progress) == "function" then
        local success, progressValue = pcall(ailmentInstance.get_progress, ailmentInstance)
        if success and progressValue then
            table.insert(details, "Progress: " .. string.format("%.2f", progressValue))
        end
    end
    return #details > 0 and " (" .. table.concat(details, ", ") .. ")" or ""
end

local function getEntityDisplayInfo(entityRef)
    if not entityRef then return "Unknown Entity", "N/A" end
    if not entityRef.is_pet then
        return LocalPlayer.Name .. "'s Baby", tostring(LocalPlayer.UserId)
    else
        local myInventory = ClientDataModule.get("inventory")
        if myInventory and myInventory.pets and myInventory.pets[entityRef.pet_unique] then
            return tostring(myInventory.pets[entityRef.pet_unique].id), tostring(entityRef.pet_unique)
        else
            return "Pet (Unknown Name)", tostring(entityRef.pet_unique)
        end
    end
end

local function createEntityReference(player, isPet, petUniqueId)
    return {
        player = player,
        is_pet = isPet,
        pet_unique = petUniqueId
    }
end

local function addAilmentToUI(ailmentInstance, entityUniqueKey, entityRef)
    local ailmentId = getAilmentIdFromInstance(ailmentInstance)
    local entityDisplayName, entityUniqueIdForDisplay = getEntityDisplayInfo(entityRef)

    if not activeAilmentUIs[entityUniqueKey] then
        activeAilmentUIs[entityUniqueKey] = {}
    end

    if not activeAilmentUIs[entityUniqueKey][ailmentId] then
        local ailmentLabel = AilmentItemTemplate:Clone()
        ailmentLabel.Name = ailmentId .. "_" .. entityUniqueKey:sub(1, math.min(string.len(entityUniqueKey), 8))
        local displayString = ""
        if entityRef.is_pet then
            displayString = string.format("%s (%s) - %s%s", entityDisplayName, entityUniqueIdForDisplay, ailmentId, formatAilmentDetails(ailmentInstance))
        else
            displayString = string.format("%s - %s%s", entityDisplayName, ailmentId, formatAilmentDetails(ailmentInstance))
        end
        ailmentLabel.Text = displayString

        ailmentLabel.LayoutOrder = os.time() + math.random() / 1000
        ailmentLabel.Visible = true
        ailmentLabel.Parent = AilmentListFrame

        activeAilmentUIs[entityUniqueKey][ailmentId] = {
            AilmentInstance = ailmentInstance,
            UiLabel = ailmentLabel,
            EntityRef = entityRef,
            StoredAilmentId = ailmentId
        }
        print(string.format("[Ailment UI Add] Added: %s for %s (%s)", ailmentId, entityDisplayName, entityUniqueIdForDisplay))
    else
        local existingEntry = activeAilmentUIs[entityUniqueKey][ailmentId]
        existingEntry.AilmentInstance = ailmentInstance
        existingEntry.EntityRef = entityRef

        local displayString = ""
        if entityRef.is_pet then
            displayString = string.format("%s (%s) - %s%s", entityDisplayName, entityUniqueIdForDisplay, ailmentId, formatAilmentDetails(ailmentInstance))
        else
            displayString = string.format("%s - %s%s", entityDisplayName, ailmentId, formatAilmentDetails(ailmentInstance))
        end
        existingEntry.UiLabel.Text = displayString
    end
end

local function removeAilmentFromUI(ailmentInstance, entityUniqueKey, entityRef)
    local ailmentIdToRemove = getAilmentIdFromInstance(ailmentInstance)
    local foundEntry = activeAilmentUIs[entityUniqueKey] and activeAilmentUIs[entityUniqueKey][ailmentIdToRemove]

    if not foundEntry then
        for currentAilmentId, entry in pairs(activeAilmentUIs[entityUniqueKey] or {}) do
            if entry.AilmentInstance == ailmentInstance then
                ailmentIdToRemove = currentAilmentId
                foundEntry = entry
                break
            end
        end
    end

    if foundEntry then
        local uiLabel = foundEntry.UiLabel
        local storedAilmentId = foundEntry.StoredAilmentId
        uiLabel:Destroy()
        activeAilmentUIs[entityUniqueKey][storedAilmentId] = nil
        if next(activeAilmentUIs[entityUniqueKey] or {}) == nil then
            activeAilmentUIs[entityUniqueKey] = nil
        end
        local entityDisplayName, entityUniqueIdForDisplay = getEntityDisplayInfo(entityRef)
        print(string.format("[Ailment UI Remove] Removed: %s for %s (%s)", storedAilmentId, entityDisplayName, entityUniqueIdForDisplay))
    end

    if impendingAilmentUIs[entityUniqueKey] and impendingAilmentUIs[entityUniqueKey][ailmentIdToRemove] then
        impendingAilmentUIs[entityUniqueKey][ailmentIdToRemove]:Destroy()
        impendingAilmentUIs[entityUniqueKey][ailmentIdToRemove] = nil
        if next(impendingAilmentUIs[entityUniqueKey] or {}) == nil then
            impendingAilmentUIs[entityUniqueKey] = nil
            ImpendingAilmentsFrame.Visible = false
        end
    end
end

local function initialAilmentUIScan()
    print("Performing initial UI population for ailments.")

    for entityKey, ailmentMap in pairs(activeAilmentUIs) do
        for _, entry in pairs(ailmentMap) do
            if entry.UiLabel and entry.UiLabel.Parent then
                entry.UiLabel:Destroy()
            end
        end
    end
    activeAilmentUIs = {}

    for entityKey, ailmentMap in pairs(impendingAilmentUIs) do
        for _, label in pairs(ailmentMap) do
            if label and label.Parent then
                label:Destroy()
            end
        end
    end
    impendingAilmentUIs = {}
    ImpendingAilmentsFrame.Visible = false

    local localPlayerEntity = createEntityReference(LocalPlayer, false, nil)
    local localPlayerAilments = AilmentsManager.get_ailments_for_pet(localPlayerEntity)
    if localPlayerAilments then
        for _, ailmentInstance in pairs(localPlayerAilments) do
            addAilmentToUI(ailmentInstance, tostring(LocalPlayer.UserId), localPlayerEntity)
        end
    end

    local myInventory = ClientDataModule.get("inventory")
    if myInventory and myInventory.pets then
        for petUniqueId, _ in pairs(myInventory.pets) do
            local petEntityRef = createEntityReference(LocalPlayer, true, petUniqueId)
            local petAilments = AilmentsManager.get_ailments_for_pet(petEntityRef)
            if petAilments then
                for _, ailmentInstance in pairs(petAilments) do
                    addAilmentToUI(ailmentInstance, petUniqueId, petEntityRef)
                end
            end
        end
    end
    print("Initial UI population complete.")
end


-- --- AUTOMATION CORE HELPER FUNCTIONS (STANDARD) ---

local function resolvePath(pathString)
    local current = Workspace
    for partName in string.gmatch(pathString, "[^.]+") do
        local found = current:FindFirstChild(partName)
        if not found then 
            return nil 
        end
        current = found
    end
    return current
end

local function findDeep(parent, objectName)
    for _, child in ipairs(parent:GetChildren()) do
        if child.Name == objectName then
            return child
        end

        if child:IsA("Folder") or child:IsA("Model") then
            local foundItem = findDeep(child, objectName)
            if foundItem then
                return foundItem
            end
        end
    end
    return nil
end

-- NEW: Helper function to create the main large, visible, collidable platform
local function createAndTeleportPlatform(player)
    local platform = Workspace:FindFirstChild("TeleportPlatform")
    if not platform then
        platform = Instance.new("Part")
        platform.Name = "TeleportPlatform"
        platform.Size = Vector3.new(10000, 1, 10000) -- Really large width/depth
        platform.Transparency = 0 -- Make it visible
        platform.Color = Color3.fromRGB(50, 50, 50) -- Dark gray color
        platform.Material = Enum.Material.Concrete
        platform.CanCollide = true
        platform.Anchored = true
        platform.CFrame = CFrame.new(0, 200, -10000) -- Far out of sight
        platform.Parent = Workspace
    else
        -- Ensure existing platform meets the new size/collision requirements
        platform.Size = Vector3.new(10000, 1, 10000)
        platform.Transparency = 0 
        platform.CanCollide = true
    end

    local character = player.Character or player.CharacterAdded:Wait()
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

    -- Teleport the player slightly above the platform
    local newPosition = platform.CFrame * CFrame.new(0, platform.Size.Y/2 + humanoidRootPart.Size.Y/2, 0)
    humanoidRootPart.CFrame = newPosition
    print("[Automation] Player teleported to the new custom platform.")
    
    return character
end

local function getActivePetModel()
    -- Finds the first pet model in Workspace.Pets
    local petsFolder = Workspace:FindFirstChild("Pets")
    if petsFolder then
        for _, petChild in ipairs(petsFolder:GetChildren()) do
            if petChild:IsA("Model") then
                return petChild
            end
        end
    end
    return nil
end

local DEFAULT_TELEPORT_SETTINGS = {
    fade_in_length = 0.5,
    fade_out_length = 0.4,
    fade_color = Color3.new(0, 0, 0),
    anchor_char_immediately = true,
    post_character_anchored_wait = 0.5,
    move_camera = true,
    house_owner = nil, 
    door_id_for_location_module = nil,
    exiting_door = nil,
}




--[[
Guaranteed Flat Landing Platform

This script defines a helper function that creates a large, temporary,
and perfectly level (flat) platform in the Workspace. It strips away
any rotation from the input CFrame to ensure the platform is always
parallel to the world's XZ plane.

IMPORTANT: The 'local' keyword has been removed from the function definition
to ensure it is globally accessible within the scope of the script it is placed in,
which helps resolve scoping issues often seen when integrating helper functions.
--]]

-- IMPORTANT: This function should be defined near the top of your LocalScript, 
-- or made accessible via a ModuleScript, to ensure it is defined before 
-- it is called by 'fulfillFurnitureNeeds' (around line 1071).

function createTemporaryLandingPlatform(cframe) -- **'local' removed to ensure broader accessibility**
    -- Input 'cframe' is the desired target location (position and rotation)

    local tempPlatform = Instance.new("Part")
    
    -- --- Configuration ---
    tempPlatform.Name = "LandingPlatform"
    tempPlatform.Size = Vector3.new(100, 5, 100) -- Large, flat part (100x100 surface, 5 thickness)
    tempPlatform.Transparency = 0
    tempPlatform.Color = Color3.fromRGB(50, 255, 50) -- Bright green
    tempPlatform.Material = Enum.Material.Neon
    tempPlatform.CanCollide = true
    tempPlatform.Anchored = true -- Essential for a stationary platform
    
    -- --- Key Change for Flatness ---
    -- 1. Get the position (Vector3) from the input CFrame.
    local position = cframe.Position
    
    -- 2. Create a *new* CFrame using only the position, which defaults to no rotation (level).
    -- 3. Apply the vertical offset (-5) to position the platform slightly below the target CFrame
    --    so the top surface is aligned with the original target height.
    tempPlatform.CFrame = CFrame.new(position) * CFrame.new(0, -2.5, 0) 
    -- We use -2.5 (half the platform's Y size of 5) so the top of the platform is exactly at the 'position' Y coordinate.
    
    -- We assume 'Workspace' is available in the environment (e.g., a Roblox script)
    local Workspace = game:GetService("Workspace")
    tempPlatform.Parent = Workspace
    
    print("Temporary Landing Platform created at: " .. tostring(position))
    
    -- A simple function to clean up the platform after a delay
    task.delay(10, function()
        tempPlatform:Destroy()
        print("Landing Platform destroyed.")
    end)
    
    return tempPlatform
end







-- --- PHASE 1: LOCATION FULFILLMENT (STANDARD) ---
local function fulfillLocationNeeds(needsToFulfillLocation)
    if #needsToFulfillLocation == 0 then return end
    
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local playerHRP = character:WaitForChild("HumanoidRootPart")

    local uniqueDestinations = {}
    for _, entry in ipairs(needsToFulfillLocation) do
        local config = AilmentToLocationMap[entry.StoredAilmentId]
        if config then
            local destKey = config.DestinationId .. (config.TargetPath or "")
            if not uniqueDestinations[destKey] then
                uniqueDestinations[destKey] = { config = config, ailments = {} }
            end
            table.insert(uniqueDestinations[destKey].ailments, entry)
        end
    end

    for _, destInfo in pairs(uniqueDestinations) do
        local config = destInfo.config
        local targetAilmentEntries = destInfo.ailments
        local destinationId = config.DestinationId
        local targetPath = config.TargetPath
        
        print(string.format("[Location Phase] Prioritizing Location Need. Teleporting to: %s", destinationId))

        InteriorsM.enter_smooth(destinationId, config.DoorId, DEFAULT_TELEPORT_SETTINGS, nil)
        print(string.format("[Location Phase] Teleport to %s initiated. Waiting for entry...", destinationId))
        task.wait(5)

        if targetPath and destinationId == "MainMap" then
            local targetPart = resolvePath(targetPath)
            if targetPart and targetPart:IsA("BasePart") then
                -- NEW: Create a temporary, large, visible platform at the target location
                local targetPlatform = createTemporaryLandingPlatform(targetPart.CFrame)
                
                -- Teleport player onto the new platform
                playerHRP.CFrame = targetPlatform.CFrame * CFrame.new(0, targetPlatform.Size.Y/2 + playerHRP.Size.Y/2 + 5, 0)
                
                print(string.format("[Location Phase] Secondary teleport to MainMap target: %s completed on visible platform.", targetPath))
                task.wait(3) 

                -- Clean up the temporary platform after use
                targetPlatform:Destroy()
            else
                warn(string.format("[Location Phase Error] Could not find MainMap target part using path: %s. Player may land unsafely.", targetPath))
            end
            task.wait(3) 
        end
        
        local totalAilments = #targetAilmentEntries
        local fulfilledCount = 0
        local maxWaitTime = 60

        print(string.format("[Location Phase] Monitoring %d ailments for fulfillment at %s.", totalAilments, destinationId))
        local startTime = tick()
        
        while fulfilledCount < totalAilments and tick() - startTime < maxWaitTime do
            fulfilledCount = 0
            
            for _, entry in ipairs(targetAilmentEntries) do
                local entityKey = entry.EntityRef.is_pet and entry.EntityRef.pet_unique or tostring(LocalPlayer.UserId)
                local isAilmentGone = not (activeAilmentUIs[entityKey] and activeAilmentUIs[entityKey][entry.StoredAilmentId])
                
                if isAilmentGone then
                    fulfilledCount = fulfilledCount + 1
                end
            end
            
            if fulfilledCount < totalAilments then
                 print(string.format("[Location Phase Wait] %d/%d needs fulfilled. Waiting 1s...", fulfilledCount, totalAilments))
                task.wait(1)
            end
        end
        
        if fulfilledCount == totalAilments then
            print(string.format("[Location Phase] SUCCESSFULLY fulfilled all %s location needs.", destinationId))
        else
            warn(string.format("[Location Phase] TIMEOUT/FAILURE. Only %d/%d %s location needs fulfilled.", fulfilledCount, totalAilments, destinationId))
        end
        
        createAndTeleportPlatform(LocalPlayer)
    end
end

-- --- PHASE 2: FURNITURE FULFILLMENT (STANDARD) ---

local function attemptFurnitureFulfillment(needsToFulfillFurniture)
    local furnitureFolder = Workspace:FindFirstChild("HouseInteriors") and Workspace.HouseInteriors:FindFirstChild("furniture")
    local activateFurniture = ReplicatedStorage:WaitForChild("API"):WaitForChild("HousingAPI/ActivateFurniture")
    
    if not furnitureFolder or not activateFurniture then
        warn("[Furniture Phase] Missing 'furniture' folder or 'HousingAPI/ActivateFurniture'. Skipping furniture activation.")
        return
    end

    local foundFurnitureIds = {}
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()

    for _, entry in ipairs(needsToFulfillFurniture) do
        local ailmentId = entry.StoredAilmentId
        local entityRef = entry.EntityRef
        local config = AilmentToLocationMap[ailmentId]
        local furnitureName = config.FurnitureName
        
        -- Explicitly determine the target model for activation.
        local targetModel = entityRef.is_pet and getActivePetModel() or character
        
        if entityRef.is_pet and not targetModel then
            warn(string.format("[Furniture Phase Error] Pet need ('%s') detected, but no Pet Model found in Workspace.Pets. Skipping.", ailmentId))
            continue
        end

        local furnitureId = foundFurnitureIds[furnitureName]
        if not furnitureId then
            local foundItem = findDeep(furnitureFolder, furnitureName)
            if foundItem then
                local furnitureParent = foundItem.Parent
                local parts = string.split(furnitureParent.Name, "/") 
                furnitureId = parts[#parts]
                foundFurnitureIds[furnitureName] = furnitureId
            else
                warn(string.format("[Furniture Phase Error] Could not find furniture item: %s. Skipping.", furnitureName))
                continue
            end
        end

        local cframe = character:WaitForChild("HumanoidRootPart").CFrame
        
        -- Determine the correct action block based on the furniture name
        -- V11: Use "Seat1" for the Toilet to target the correct part of the model.
        local actionBlock = "UseBlock"
        if furnitureName == "Toilet" then
            actionBlock = "Seat1"
        end

        local args = {
            LocalPlayer,
            furnitureId,
            actionBlock, 
            { cframe = cframe },
            targetModel -- The calculated target model (Pet Model or Character)
        }
        
        local success, result = pcall(activateFurniture.InvokeServer, activateFurniture, unpack(args))
        
        if success then
            print(string.format("[Furniture Phase] SUCCESSFULLY activated %s for need: %s (Target: %s).", furnitureName, ailmentId, targetModel.Name))
        else
            warn(string.format("[Furniture Phase] FAILED to call ActivateFurniture for %s (Need: %s). Error: %s", furnitureName, ailmentId, result))
        end
        
        task.wait(2.0)
    end
end

local function fulfillFurnitureNeeds(needsToFulfillFurniture)
    if #needsToFulfillFurniture == 0 then return end
    
    print("[Furniture Phase] Starting Player House/Furniture Fulfillment.")
    
    local config = AilmentToLocationMap[needsToFulfillFurniture[1].StoredAilmentId]
    
    local teleportSettings = DEFAULT_TELEPORT_SETTINGS
    teleportSettings.house_owner = LocalPlayer

    InteriorsM.enter_smooth(config.DestinationId, config.DoorId, teleportSettings, nil)
    print("[Furniture Phase] Teleport to Housing initiated. Waiting for house to load...")
    task.wait(5) 
    
    attemptFurnitureFulfillment(needsToFulfillFurniture)
    
    createAndTeleportPlatform(LocalPlayer)
end

-- --- PHASE 3: RIDE FULFILLMENT (STROLLER + CIRCULAR WALK) ---
local function fulfillStrollerRideNeeds(needsToFulfillStrollerRide)
    if #needsToFulfillStrollerRide == 0 then return end
    
    local myInventory = ClientDataModule.get("inventory")
    local strollers = myInventory and myInventory.strollers
    local firstStrollerUniqueId = nil

    if strollers and next(strollers) then
        for uniqueId, _ in pairs(strollers) do
            firstStrollerUniqueId = uniqueId
            break
        end
    end

    local ToolEquipRemote = ReplicatedStorage:WaitForChild("API"):WaitForChild("ToolAPI/Equip")
    local ToolUnequipRemote = ReplicatedStorage:WaitForChild("API"):WaitForChild("ToolAPI/Unequip")
    local AdoptUnequipStrollerRemote = ReplicatedStorage:WaitForChild("API"):WaitForChild("AdoptAPI/UnequipStroller")
    local UseStrollerRemote = ReplicatedStorage:WaitForChild("API"):WaitForChild("AdoptAPI/UseStroller")

    if firstStrollerUniqueId then
        print("[Stroller Phase] Initiating **RIDE (Equip Stroller + Circular Walk)** sequence for 'ride' needs...")
        local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        local humanoid = character:WaitForChild("Humanoid")
        local originalWalkSpeed = humanoid.WalkSpeed

        local equipArgs = { firstStrollerUniqueId, { use_sound_delay = false, equip_as_last = false } }
        
        local success, result = pcall(ToolEquipRemote.InvokeServer, ToolEquipRemote, unpack(equipArgs))

        if success then
            print(string.format("[Stroller Phase] Successfully equipped stroller %s. Preparing force-seating and circular walk cycle.", firstStrollerUniqueId))
            task.wait(1.5) 
            
            -- Function to seat the pet (Helper function for clarity and re-use)
            local function seatPet()
                local petModel = getActivePetModel()
                local TouchToSitPart = findDeep(character, "TouchToSit") 

                if petModel and TouchToSitPart and TouchToSitPart.Parent.Name == "TouchToSits" then
                    local args = { LocalPlayer, petModel, TouchToSitPart }
                    pcall(UseStrollerRemote.InvokeServer, UseStrollerRemote, unpack(args))
                    print("[Stroller Phase] SUCCESSFULLY invoked AdoptAPI/UseStroller to force pet/baby into the stroller seat.")
                    return true
                end
                warn("[Stroller Phase] Could not find pet model or TouchToSit part to seat the pet.")
                return false
            end
            
            seatPet() -- Initial seating attempt

            -- --- CIRCULAR WALK MOVEMENT LOGIC (Fixed Speed/Wait Time for stability) ---
            local maxRideDuration = 300 
            local startTime = tick()
            local moveWaitTime = 1.0 -- Increased wait time for smoother movement
            local radius = 8
            local angleIncrement = math.pi / 16 -- Decreased angle increment for smoother turns
            humanoid.WalkSpeed = 3 -- Decreased WalkSpeed for stability
            print("[Stroller Phase] Starting circular movement (WalkSpeed set to 3) to fulfill 'ride' needs.")
            
            local needsFulfilled = false
            local currentAngle = 0 
            local PROGRESS_THRESHOLD = 0.01 
            local minWalkDuration = 8.0 -- *** V14 FIX: Force a minimum 8-second walk to make the action visible. ***

            -- Loop runs until the need is fulfilled AND the minimum walk duration has passed.
            while (not needsFulfilled or (tick() - startTime < minWalkDuration)) and tick() - startTime < maxRideDuration do
                local stillNeedsRide = false
                
                for _, need in ipairs(needsToFulfillStrollerRide) do
                    local entityKey = need.EntityRef.is_pet and need.EntityRef.pet_unique or tostring(LocalPlayer.UserId)
                    local currentAilmentEntry = activeAilmentUIs[entityKey] and activeAilmentUIs[entityKey][need.StoredAilmentId]
                    
                    if currentAilmentEntry then
                        local ailmentInstance = currentAilmentEntry.AilmentInstance
                        local progress = 1.0 
                        if type(ailmentInstance.get_progress) == "function" then
                            local successP, progressValue = pcall(ailmentInstance.get_progress, ailmentInstance)
                            if successP and progressValue then progress = progressValue end
                        end

                        if progress > PROGRESS_THRESHOLD then
                            stillNeedsRide = true
                            break
                        end
                    end
                end

                if not stillNeedsRide then
                    needsFulfilled = true
                    -- Do not break yet, the loop condition handles the minimum duration check
                    print("[Stroller Phase] Fulfillment registered. Continuing for minimum walk time...")
                else
                    needsFulfilled = false
                end

                -- Perform ONE step of Circular Movement
                currentAngle = currentAngle + angleIncrement
                if currentAngle > 2 * math.pi then currentAngle = currentAngle - 2 * math.pi end

                local platform = Workspace:FindFirstChild("TeleportPlatform")
                local currentCenter = platform and platform.Position or character.HumanoidRootPart.Position
                local x = currentCenter.X + radius * math.cos(currentAngle)
                local z = currentCenter.Z + radius * math.sin(currentAngle)
                local pos = Vector3.new(x, currentCenter.Y, z)
                
                humanoid:MoveTo(pos)
                task.wait(moveWaitTime)
            end
            
            -- Restore WalkSpeed
            humanoid.WalkSpeed = originalWalkSpeed
            
            -- Manual Cleanup for transactional completion
            if needsFulfilled then
                print("[Stroller Phase] SUCCESS: Minimum walk duration met. Stopping circular walk.")
                for _, need in ipairs(needsToFulfillStrollerRide) do
                    local entityKey = need.EntityRef.is_pet and need.EntityRef.pet_unique or tostring(LocalPlayer.UserId)
                    if activeAilmentUIs[entityKey] and activeAilmentUIs[entityKey][need.StoredAilmentId] then
                        removeAilmentFromUI(need.AilmentInstance, entityKey, need.EntityRef)
                    end
                end
            else
                warn("[Stroller Phase] TIMEOUT/FAILURE. Stopping circular walk and cleaning up.")
            end
            
            -- Cleanup: UNEQUIP the stroller after ride completion/timeout
            pcall(ToolUnequipRemote.InvokeServer, ToolUnequipRemote)
            pcall(AdoptUnequipStrollerRemote.FireServer, AdoptUnequipStrollerRemote)
            print("[Stroller Phase] Cleanup: Stroller unequipped and state reset.")
            task.wait(1) 

        else
            warn(string.format("[Stroller Phase] FAILED to equip stroller %s. Error: %s", firstStrollerUniqueId, tostring(result)))
        end
        
        -- Final teleport out of the area regardless of equip success
        createAndTeleportPlatform(LocalPlayer)

    else
        warn("[Stroller Phase] No stroller found in inventory. Cannot fulfill 'ride' need.")
    end
end

-- --- PHASE 4: WALK/PET_ME FULFILLMENT (HOLD + CIRCULAR WALK) ---
local function fulfillHoldAndWalkNeeds(needsToFulfillHoldAndWalk)
    if #needsToFulfillHoldAndWalk == 0 then return end
    
    print("[Hold/Walk Phase] Initiating **WALK/PET_ME (Hold + Circular Walk)** sequence...")
    local holdBabyRemote = ReplicatedStorage:WaitForChild("API"):WaitForChild("AdoptAPI/HoldBaby", 5)
    local petModel = getActivePetModel()

    if petModel and holdBabyRemote then
        local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        local humanoid = character:WaitForChild("Humanoid")
        local originalWalkSpeed = humanoid.WalkSpeed
        
        -- 1. Hold the pet
        print(string.format("[Hold/Walk Phase] Attempting to hold pet: %s", petModel.Name))
        pcall(holdBabyRemote.FireServer, holdBabyRemote, petModel)
        task.wait(1.5) 

        -- 2. Simulate Circular Movement until completion
        local maxMoveDuration = 300 
        local startTime = tick()
        local moveWaitTime = 0.5 
        local radius = 8
        local angleIncrement = math.pi / 8 
        humanoid.WalkSpeed = 5 
        print("[Hold/Walk Phase] Starting circular movement (WalkSpeed set to 5) to fulfill action needs.")
        
        local needsFulfilled = false
        local currentAngle = 0 
        local PROGRESS_THRESHOLD = 0.01 

        while not needsFulfilled and tick() - startTime < maxMoveDuration do
            local stillNeedsAction = false
            
            for _, need in ipairs(needsToFulfillHoldAndWalk) do
                local entityKey = need.EntityRef.is_pet and need.EntityRef.pet_unique or tostring(LocalPlayer.UserId)
                local currentAilmentEntry = activeAilmentUIs[entityKey] and activeAilmentUIs[entityKey][need.StoredAilmentId]
                
                if currentAilmentEntry then
                    local ailmentInstance = currentAilmentEntry.AilmentInstance
                    local progress = 1.0 
                    if type(ailmentInstance.get_progress) == "function" then
                        local success, progressValue = pcall(ailmentInstance.get_progress, ailmentInstance)
                        if success and progressValue then progress = progressValue end
                    end

                    if progress > PROGRESS_THRESHOLD then
                        stillNeedsAction = true
                        print(string.format("[Hold/Walk Phase Progress] %s at %.1f%%", need.StoredAilmentId, progress * 100))
                        break 
                    end
                end
            end

            if not stillNeedsAction then
                needsFulfilled = true
                print("[Hold/Walk Phase] SUCCESS: All monitored needs fulfilled. Stopping circular movement.")
                break 
            end

            -- Perform ONE step of Circular Movement
            currentAngle = currentAngle + angleIncrement
            if currentAngle > 2 * math.pi then currentAngle = currentAngle - 2 * math.pi end

            local platform = Workspace:FindFirstChild("TeleportPlatform")
            local currentCenter = platform and platform.Position or character.HumanoidRootPart.Position
            local x = currentCenter.X + radius * math.cos(currentAngle)
            local z = currentCenter.Z + radius * math.sin(currentAngle)
            local pos = Vector3.new(x, currentCenter.Y, z)
            
            humanoid:MoveTo(pos)
            task.wait(moveWaitTime)
        end
        
        -- 3. Restore WalkSpeed
        humanoid.WalkSpeed = originalWalkSpeed
        
        -- 4. Release the pet 
        pcall(holdBabyRemote.FireServer, holdBabyRemote, petModel)
        print("[Hold/Walk Phase] Pet released.")
        task.wait(1.5)

    else
        warn("[Hold/Walk Phase Error] Could not find pet model or HoldBaby remote. Skipping.")
    end
    
    createAndTeleportPlatform(LocalPlayer)
end

-- --- PHASE 5: WEAR_SCARE FULFILLMENT (HOLD + EQUIP/WAIT) ---
local function fulfillWearScareNeeds(needsToFulfillWearScare)
    if #needsToFulfillWearScare == 0 then return end
    
    print("[WearScare Phase] Initiating **WEAR_SCARE (Hold + Equip/Wait)** sequence...")
    local holdBabyRemote = ReplicatedStorage:WaitForChild("API"):WaitForChild("AdoptAPI/HoldBaby", 5)
    local petModel = getActivePetModel()

    if petModel and holdBabyRemote then
        
        -- 1. Hold the pet
        print(string.format("[WearScare Phase] Attempting to hold pet: %s", petModel.Name))
        pcall(holdBabyRemote.FireServer, holdBabyRemote, petModel)
        task.wait(1.5) 
        
        -- 2. Simulate equipping and waiting for completion
        local completionTime = 10 -- Wait 10 seconds for the action to complete
        
        print("[WearScare Phase] Action: Simulating **Equip Scare Costume** and waiting for 10 seconds...")
        
        local startTime = tick()
        local PROGRESS_THRESHOLD = 0.01 
        local needsFulfilled = false

        while not needsFulfilled and tick() - startTime < completionTime do
             local stillNeedsAction = false
            
            for _, need in ipairs(needsToFulfillWearScare) do
                local entityKey = need.EntityRef.is_pet and need.EntityRef.pet_unique or tostring(LocalPlayer.UserId)
                local currentAilmentEntry = activeAilmentUIs[entityKey] and activeAilmentUIs[entityKey][need.StoredAilmentId]
                
                if currentAilmentEntry then
                    local ailmentInstance = currentAilmentEntry.AilmentInstance
                    local progress = 1.0 
                    if type(ailmentInstance.get_progress) == "function" then
                        local success, progressValue = pcall(ailmentInstance.get_progress, ailmentInstance)
                        if success and progressValue then progress = progressValue end
                    end

                    if progress > PROGRESS_THRESHOLD then
                        stillNeedsAction = true
                        print(string.format("[WearScare Phase Progress] %s at %.1f%%. Waiting...", need.StoredAilmentId, progress * 100))
                        break 
                    end
                end
            end
            
            if not stillNeedsAction then
                needsFulfilled = true
                print("[WearScare Phase] SUCCESS: Needs fulfilled after wear action.")
                break 
            end

            task.wait(1)
        end
        
        if not needsFulfilled then
            warn("[WearScare Phase] TIMEOUT: Needs not fulfilled within the duration.")
        end

        -- 3. Release the pet
        pcall(holdBabyRemote.FireServer, holdBabyRemote, petModel)
        print("[WearScare Phase] Pet released.")
        task.wait(1.5)

    else
        warn("[WearScare Phase Error] Could not find pet model or HoldBaby remote. Skipping.")
    end
    
    createAndTeleportPlatform(LocalPlayer)
end


-- --- MAIN AUTOMATION SEQUENCE FUNCTION ---

local function runAutomationSequence()
    if not isAutomationEnabled or isAutomationRunning then return end

    isAutomationRunning = true
    print("\n--- Initiating Automation Sequence ---")

    if not InteriorsM then
        warn("[Automation] InteriorsM module is missing. Automation halted.")
        isAutomationRunning = false
        return
    end

    -- 1. IDENTIFY ALL CURRENT NEEDS
    local needsToFulfillLocation = {}
    local needsToFulfillFurniture = {}
    local needsToFulfillStrollerRide = {} 
    local needsToFulfillHoldAndWalk = {}
    local needsToFulfillWearScare = {}

    for entityUniqueKey, ailmentMap in pairs(activeAilmentUIs) do
        for ailmentId, entry in pairs(ailmentMap) do
            local config = AilmentToLocationMap[ailmentId]
            
            if config then
                if config.RequiresFurniture then
                    table.insert(needsToFulfillFurniture, entry)
                elseif config.DestinationId ~= "housing" then
                    table.insert(needsToFulfillLocation, entry)
                end
            elseif StrollerRideNeeds[ailmentId] then 
                table.insert(needsToFulfillStrollerRide, entry)
            elseif HoldAndWalkNeeds[ailmentId] and entry.EntityRef.is_pet then
                 -- Only process if it's a pet for 'walk' and 'pet_me'
                table.insert(needsToFulfillHoldAndWalk, entry)
            elseif WearScareNeeds[ailmentId] and entry.EntityRef.is_pet then
                 -- Only process if it's a pet for 'wear_scare'
                table.insert(needsToFulfillWearScare, entry)
            else
                print(string.format("[Automation Skip] Cannot automate '%s' need.", ailmentId))
            end
        end
    end

    -- 2. EXECUTE PHASES SEQUENTIALLY
    
    -- Phase 1: Location Fulfillment
    fulfillLocationNeeds(needsToFulfillLocation)
    
    -- Phase 2: Furniture Fulfillment
    fulfillFurnitureNeeds(needsToFulfillFurniture)

    -- Phase 3: RIDE Fulfillment (Stroller + Circular Walk)
    fulfillStrollerRideNeeds(needsToFulfillStrollerRide)
    
    -- Phase 4: WALK/PET_ME Fulfillment (Hold + Circular Walk)
    fulfillHoldAndWalkNeeds(needsToFulfillHoldAndWalk)
    
    -- Phase 5: WEAR_SCARE Fulfillment (Hold + Equip/Wait)
    fulfillWearScareNeeds(needsToFulfillWearScare)

    print("--- Automation Sequence Complete ---")
    isAutomationRunning = false
    
    createAndTeleportPlatform(LocalPlayer)
end


-- --- AILMENT EVENT CONNECTIONS & HEARTBEAT LOOP (STANDARD) ---

AilmentsManager.get_ailment_created_signal():Connect(function(ailmentInstance, entityUniqueKey)
    local isPet = string.len(entityUniqueKey) > 10
    local entityRef = createEntityReference(LocalPlayer, isPet, entityUniqueKey)
    addAilmentToUI(ailmentInstance, entityUniqueKey, entityRef)
end)

AilmentsManager.get_ailment_completed_signal():Connect(function(ailmentInstance, entityUniqueKey, completionReason)
    local isPet = string.len(entityUniqueKey) > 10
    local entityRef = createEntityReference(LocalPlayer, isPet, entityUniqueKey)
    removeAilmentFromUI(ailmentInstance, entityUniqueKey, entityRef) 

    local entityDisplayName, entityUniqueIdForDisplay = getEntityDisplayInfo(entityRef)
    print(string.format("[Ailment Event] Ailment COMPLETED for %s ('%s'): '%s' (Reason: %s)", 
        entityDisplayName, 
        entityUniqueIdForDisplay, 
        getAilmentIdFromInstance(ailmentInstance), 
        tostring(completionReason)
    ))
end)

local lastUpdateTime = 0
local WARNING_THRESHOLD_SECONDS = 120 
local function formatTimeRemaining(seconds)
    local minutes = math.floor(seconds / 60)
    local remainingSeconds = math.floor(seconds % 60)
    return string.format("%d:%02d", minutes, remainingSeconds)
end

RunService.Heartbeat:Connect(function() 
    if os.time() - lastUpdateTime < 1 then return end
    lastUpdateTime = os.time() 

    local warningsFound = false

    for entityUniqueKey, ailmentMap in pairs(activeAilmentUIs) do 
        for ailmentId, entry in pairs(ailmentMap) do 
            local ailmentInstance = entry.AilmentInstance 
            local uiLabel = entry.UiLabel 
            local entityRef = entry.EntityRef 

            local entityDisplayName, entityUniqueIdForDisplay = getEntityDisplayInfo(entityRef) 
            local displayString = "" 
            if entityRef.is_pet then 
                displayString = string.format("%s (%s) - %s%s", entityDisplayName, entityUniqueIdForDisplay, ailmentId, formatAilmentDetails(ailmentInstance)) 
            else 
                displayString = string.format("%s - %s%s", entityDisplayName, ailmentId, formatAilmentDetails(ailmentInstance)) 
            end 
            uiLabel.Text = displayString 

            local rateFinishedTimestamp = nil
            if type(ailmentInstance.get_rate_finished_timestamp) == "function" then
                rateFinishedTimestamp = ailmentInstance:get_rate_finished_timestamp()
            end
             
            if rateFinishedTimestamp then 
                local timeLeftSeconds = rateFinishedTimestamp - workspace:GetServerTimeNow() 
                if timeLeftSeconds > 0 and timeLeftSeconds <= WARNING_THRESHOLD_SECONDS then 
                    warningsFound = true 
                    
                    if not impendingAilmentUIs[entityUniqueKey] then 
                        impendingAilmentUIs[entityUniqueKey] = {} 
                    end 

                    local warningLabel = impendingAilmentUIs[entityUniqueKey][ailmentId] 
                    if not warningLabel then 
                        warningLabel = Instance.new("TextLabel") 
                        warningLabel.Name = "Impending_" .. ailmentId .. "_" .. entityUniqueKey:sub(1, math.min(string.len(entityUniqueKey), 8)) 
                        warningLabel.Size = UDim2.new(1, -10, 0, 20) 
                        warningLabel.LayoutOrder = os.time() + math.random() / 1000 
                        warningLabel.BackgroundTransparency = 1 
                        warningLabel.TextScaled = true 
                        warningLabel.TextXAlignment = Enum.TextXAlignment.Left 
                        warningLabel.TextYAlignment = Enum.TextYAlignment.Center 
                        warningLabel.Font = Enum.Font.Arial 
                        warningLabel.TextColor3 = Color3.fromRGB(255, 150, 150)
                        warningLabel.TextStrokeTransparency = 0 
                        warningLabel.Parent = ImpendingAilmentsFrame.WarningScrollingFrame 
                        impendingAilmentUIs[entityUniqueKey][ailmentId] = warningLabel 
                    end 

                    local warningText = "" 
                    if entityRef.is_pet then 
                        warningText = string.format("%s (%s) - %s in %s", entityDisplayName, entityUniqueIdForDisplay, ailmentId, formatTimeRemaining(timeLeftSeconds)) 
                    else 
                        warningText = string.format("%s - %s in %s", entityDisplayName, ailmentId, formatTimeRemaining(timeLeftSeconds)) 
                    end 
                    warningLabel.Text = warningText 
                    warningLabel.Visible = true 
                else 
                    if impendingAilmentUIs[entityUniqueKey] and impendingAilmentUIs[entityUniqueKey][ailmentId] then 
                        impendingAilmentUIs[entityUniqueKey][ailmentId]:Destroy() 
                        impendingAilmentUIs[entityUniqueKey][ailmentId] = nil 
                        if next(impendingAilmentUIs[entityUniqueKey] or {}) == nil then 
                            impendingAilmentUIs[entityUniqueKey] = nil 
                        end 
                    end 
                end 
            else 
                if impendingAilmentUIs[entityUniqueKey] and impendingAilmentUIs[entityUniqueKey][ailmentId] then 
                    impendingAilmentUIs[entityUniqueKey][ailmentId]:Destroy() 
                    impendingAilmentUIs[entityUniqueKey][ailmentId] = nil 
                    if next(impendingAilmentUIs[entityUniqueKey] or {}) == nil then 
                        impendingAilmentUIs[entityUniqueKey] = nil 
                    end 
                end 
            end 
        end 
    end 

    ImpendingAilmentsFrame.Visible = warningsFound or (next(impendingAilmentUIs) ~= nil)
end) 


-- --- STARTUP EXECUTION --- 
task.spawn(function() 
    print("Ailments Automation Script: Started. Creating UI...")
    createAilmentUI() 
    
    print("Ailments Automation Script: UI created. Waiting for modules and data...") 
    task.wait(5) 
    
    print("Ailments Automation Script: Modules and data ready. Starting initial ailment scan.") 
    initialAilmentUIScan() 
    
    createAndTeleportPlatform(LocalPlayer)
    
    -- Start a persistent loop to check and run automation
    while true do
        task.wait(10)
        if isAutomationEnabled then
            runAutomationSequence()
        end
    end
end)
