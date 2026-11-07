--[[
    SpecterLib  -  dark / purple GUI library for Roblox (Luau)

    Rebuilds the "specter.lua" menu layout: watermark bar, bordered window,
    tab strip, two-column sections with gradient headers, and these elements:
      Toggle (+ color picker / keybind addons), Dropdown (single + multi),
      Slider ("value/max" readout), Button, Label, Textbox, Divider, Keybind.

    - Mouse AND touch input (drag window, sliders, color picker, etc.)
    - Parents to gethui() -> CoreGui -> PlayerGui (whatever is allowed)
    - Library.Toggles / Library.Options registries, config save/load
    - Live theming through Library:SetTheme({ Accent = Color3 ... })

    Usage:
        local Library = loadstring(readfile("SpecterLib.lua"))()
        -- or in Studio:  local Library = require(script.Parent.SpecterLib)

    This is UI only. Put your own logic inside the Callback functions.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)

local env = (getgenv and getgenv()) or _G
if type(env.SpecterLib) == "table" and type(env.SpecterLib.Unload) == "function" then
    pcall(env.SpecterLib.Unload, env.SpecterLib)
end

local Library = {
    Toggles = {},
    Options = {},
    Windows = {},
    Connections = {},
    Registry = {},
    Refreshers = {},
    UnloadCallbacks = {},
    FPS = 60,
    Visible = true,
    Unloaded = false,
    ActivePopup = nil,

    Theme = {
        Font = Enum.Font.Code,
        TextSize = 13,

        Window = Color3.fromRGB(21, 21, 21),
        Panel = Color3.fromRGB(24, 24, 24),
        Section = Color3.fromRGB(22, 22, 22),
        Field = Color3.fromRGB(31, 31, 31),
        Track = Color3.fromRGB(25, 25, 25),
        Border = Color3.fromRGB(46, 46, 46),
        Black = Color3.fromRGB(9, 9, 9),

        Text = Color3.fromRGB(200, 200, 200),
        TextOff = Color3.fromRGB(170, 170, 170),
        TextDim = Color3.fromRGB(150, 150, 150),
        TextBright = Color3.fromRGB(235, 235, 235),

        Accent = Color3.fromRGB(122, 84, 232),
        AccentText = Color3.fromRGB(152, 120, 255),
        HeaderTop = Color3.fromRGB(46, 29, 92),
        BorderA = Color3.fromRGB(128, 72, 240),
        BorderB = Color3.fromRGB(206, 72, 190),
        Watermark = Color3.fromRGB(84, 50, 214),
    },
}
env.SpecterLib = Library

--------------------------------------------------------------------------------
-- Utilities
--------------------------------------------------------------------------------

local COLOR_PROPS = {
    BackgroundColor3 = true,
    TextColor3 = true,
    Color = true,
    ScrollBarImageColor3 = true,
    PlaceholderColor3 = true,
}

-- Any color property given as a STRING is treated as a theme key and is
-- re-applied whenever the theme changes.
local function Create(class, props, children)
    local obj = Instance.new(class)
    local parent
    for key, value in pairs(props) do
        if key == "Parent" then
            parent = value
        elseif COLOR_PROPS[key] and type(value) == "string" then
            obj[key] = Library.Theme[value]
            table.insert(Library.Registry, { obj, key, value })
        else
            obj[key] = value
        end
    end
    if children then
        for _, child in ipairs(children) do
            child.Parent = obj
        end
    end
    obj.Parent = parent
    return obj
end

local function Frame(props)
    props.BorderSizePixel = 0
    if props.BackgroundColor3 == nil and props.BackgroundTransparency == nil then
        props.BackgroundTransparency = 1
    end
    return Create("Frame", props)
end

local function Label(props)
    props.BackgroundTransparency = 1
    props.BorderSizePixel = 0
    props.Font = props.Font or Library.Theme.Font
    props.TextSize = props.TextSize or Library.Theme.TextSize
    props.TextColor3 = props.TextColor3 or "Text"
    props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
    props.Text = props.Text or ""
    return Create("TextLabel", props)
end

local function Button(props)
    props.BackgroundTransparency = props.BackgroundTransparency or 1
    props.BorderSizePixel = 0
    props.AutoButtonColor = false
    props.Font = props.Font or Library.Theme.Font
    props.TextSize = props.TextSize or Library.Theme.TextSize
    props.TextColor3 = props.TextColor3 or "Text"
    props.Text = props.Text or ""
    return Create("TextButton", props)
end

local function Stroke(parent, color, thickness)
    return Create("UIStroke", {
        Color = color or "Border",
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = parent,
    })
end

local function List(parent, padding, order)
    return Create("UIListLayout", {
        Padding = UDim.new(0, padding or 0),
        SortOrder = order or Enum.SortOrder.LayoutOrder,
        Parent = parent,
    })
end

local function Clamp(n, lo, hi)
    return math.max(lo, math.min(hi, n))
end

local function Round(n, decimals)
    local m = 10 ^ (decimals or 0)
    return math.floor(n * m + 0.5) / m
end

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then
        return
    end
    local ok, err = pcall(fn, ...)
    if not ok then
        warn("[SpecterLib] callback error: " .. tostring(err))
    end
end

local function Fire(obj, info, ...)
    SafeCall(info.Callback, ...)
    for _, fn in ipairs(obj.Callbacks) do
        SafeCall(fn, ...)
    end
end

local TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local function Apply(obj, props, animate)
    if animate and not Library.Unloaded then
        TweenService:Create(obj, TWEEN, props):Play()
    else
        for key, value in pairs(props) do
            obj[key] = value
        end
    end
end

local function AccentSequence()
    local a = Library.Theme.Accent
    return ColorSequence.new(a:Lerp(WHITE, 0.14), a:Lerp(BLACK, 0.38))
end

local function IsPress(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
end

--------------------------------------------------------------------------------
-- Core
--------------------------------------------------------------------------------

function Library:Connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(self.Connections, connection)
    return connection
end

-- Runs fn now and again on every theme update.
function Library:Bind(fn)
    table.insert(self.Refreshers, fn)
    fn(false)
    return fn
end

function Library:UpdateTheme()
    for _, entry in ipairs(self.Registry) do
        local obj = entry[1]
        if obj.Parent then
            obj[entry[2]] = self.Theme[entry[3]]
        end
    end
    for _, fn in ipairs(self.Refreshers) do
        SafeCall(fn, false)
    end
end

function Library:SetTheme(overrides)
    for key, value in pairs(overrides) do
        self.Theme[key] = value
    end
    self:UpdateTheme()
end

-- Press + drag helper that works for mouse and touch.
local function BindDrag(target, onBegin, onMove, onEnd)
    Library:Connect(target.InputBegan, function(input)
        if not IsPress(input) then
            return
        end
        if onBegin then
            onBegin(input)
        end
        local moveConn, endConn
        moveConn = UserInputService.InputChanged:Connect(function(changed)
            if changed.UserInputType == Enum.UserInputType.MouseMovement
                or changed.UserInputType == Enum.UserInputType.Touch then
                onMove(changed.Position)
            end
        end)
        endConn = input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                moveConn:Disconnect()
                endConn:Disconnect()
                if onEnd then
                    onEnd()
                end
            end
        end)
        onMove(input.Position)
    end)
end

local function Mount(gui)
    pcall(function()
        if syn and syn.protect_gui then
            syn.protect_gui(gui)
        end
    end)
    local sources = {
        function() return gethui() end,
        function() return game:GetService("CoreGui") end,
        function() return LocalPlayer:WaitForChild("PlayerGui", 5) end,
    }
    for _, source in ipairs(sources) do
        local ok, parent = pcall(source)
        if ok and parent then
            local assigned = pcall(function()
                gui.Parent = parent
            end)
            if assigned and gui.Parent == parent then
                return
            end
        end
    end
end

function Library:_Init()
    if self.Gui then
        return
    end

    local Gui = Create("ScreenGui", {
        Name = "SpecterLib",
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 999,
    })
    Mount(Gui)
    self.Gui = Gui

    self.Overlay = Frame({ Name = "Overlay", Size = UDim2.fromScale(1, 1), ZIndex = 100, Parent = Gui })

    self.NotifyHolder = Frame({
        Name = "Notifications",
        Position = UDim2.fromOffset(10, 38),
        Size = UDim2.fromOffset(300, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        ZIndex = 50,
        Parent = Gui,
    })
    List(self.NotifyHolder, 4)

    local frames, last = 0, os.clock()
    self:Connect(RunService.RenderStepped, function()
        frames = frames + 1
        local now = os.clock()
        if now - last >= 0.5 then
            self.FPS = math.floor(frames / (now - last) + 0.5)
            frames, last = 0, now
            self:_UpdateWatermark()
        end
    end)
end

--------------------------------------------------------------------------------
-- Popups (dropdown lists / color picker) - rendered on the overlay layer
--------------------------------------------------------------------------------

function Library:ShowPopup(popup, anchor, width, height, align, onClose)
    self:ClosePopup()

    local catcher = Button({ Name = "Catcher", Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = self.Overlay })
    catcher.Activated:Connect(function()
        self:ClosePopup()
    end)

    local overlayPos, overlaySize = self.Overlay.AbsolutePosition, self.Overlay.AbsoluteSize
    local anchorPos, anchorSize = anchor.AbsolutePosition, anchor.AbsoluteSize

    local x = anchorPos.X - overlayPos.X
    if align == "Right" then
        x = x + anchorSize.X - width
    end
    local y = anchorPos.Y - overlayPos.Y + anchorSize.Y + 2
    if y + height > overlaySize.Y then
        y = math.max(0, anchorPos.Y - overlayPos.Y - height - 2)
    end
    x = Clamp(x, 0, math.max(0, overlaySize.X - width))

    popup.Size = UDim2.fromOffset(width, height)
    popup.Position = UDim2.fromOffset(x, y)
    popup.Visible = true

    self.ActivePopup = { Popup = popup, Catcher = catcher, OnClose = onClose }
end

function Library:ClosePopup()
    local active = self.ActivePopup
    if not active then
        return
    end
    self.ActivePopup = nil
    active.Popup.Visible = false
    active.Catcher:Destroy()
    if active.OnClose then
        SafeCall(active.OnClose)
    end
end

--------------------------------------------------------------------------------
-- Watermark / notifications / visibility / unload
--------------------------------------------------------------------------------

function Library:_UpdateWatermark()
    if not self.WatermarkLabel or not self.WatermarkText then
        return
    end
    local clock = os.date("%I:%M %p"):gsub("^0", "")
    local text = self.WatermarkText:gsub("{fps}", tostring(self.FPS)):gsub("{time}", clock)
    self.WatermarkLabel.Text = text
end

-- Tokens: {fps} and {time}.  e.g. "specter.lua | member | {fps} FPS | {time}"
function Library:SetWatermark(text)
    self:_Init()
    self.WatermarkText = text
    if not self.Watermark then
        local Box = Frame({
            Name = "Watermark",
            Position = UDim2.fromOffset(10, 8),
            Size = UDim2.fromOffset(0, 22),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = "Window",
            ZIndex = 60,
            Parent = self.Gui,
        })
        Stroke(Box, "Watermark")
        Create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = Box })
        self.WatermarkLabel = Label({
            Size = UDim2.fromOffset(0, 22),
            AutomaticSize = Enum.AutomaticSize.X,
            TextColor3 = "AccentText",
            Parent = Box,
        })
        self.Watermark = Box
    end
    self:_UpdateWatermark()
end

function Library:SetWatermarkVisible(state)
    if self.Watermark then
        self.Watermark.Visible = state
    end
end

function Library:Notify(text, duration)
    self:_Init()
    local Note = Frame({
        Size = UDim2.fromOffset(0, 20),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = "Window",
        Parent = self.NotifyHolder,
    })
    Stroke(Note)
    Frame({ Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = "Accent", Parent = Note })
    local Text = Label({
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.fromOffset(0, 20),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = tostring(text),
        Parent = Note,
    })
    Create("UIPadding", { PaddingRight = UDim.new(0, 8), Parent = Text })
    task.delay(duration or 3, function()
        if Note.Parent then
            Note:Destroy()
        end
    end)
end

function Library:SetVisible(state)
    self.Visible = state
    for _, window in ipairs(self.Windows) do
        window.Outer.Visible = state
    end
    if not state then
        self:ClosePopup()
    end
end

function Library:Toggle()
    self:SetVisible(not self.Visible)
end

function Library:OnUnload(fn)
    table.insert(self.UnloadCallbacks, fn)
end

function Library:Unload()
    if self.Unloaded then
        return
    end
    self.Unloaded = true
    for _, fn in ipairs(self.UnloadCallbacks) do
        SafeCall(fn)
    end
    for _, connection in ipairs(self.Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    if self.Gui then
        self.Gui:Destroy()
    end
    self.Registry, self.Refreshers, self.Connections = {}, {}, {}
    if env.SpecterLib == self then
        env.SpecterLib = nil
    end
end

--------------------------------------------------------------------------------
-- Color picker widget (swatch + popup)
--------------------------------------------------------------------------------

local function BuildColorPicker(parent, info)
    local Picker = { Type = "ColorPicker", Callbacks = {}, NoSave = info.NoSave }
    local start = info.Default or Color3.fromRGB(50, 25, 200)
    Picker.Hue, Picker.Sat, Picker.Val = start:ToHSV()
    Picker.Value = start

    local Swatch = Button({
        Name = "ColorSwatch",
        Size = UDim2.fromOffset(20, 11),
        BackgroundColor3 = WHITE,
        BackgroundTransparency = 0,
        Parent = parent,
    })
    Stroke(Swatch)
    local SwatchGradient = Create("UIGradient", { Rotation = 90, Parent = Swatch })

    local Popup = Frame({
        Name = "ColorPicker",
        Visible = false,
        BackgroundColor3 = "Panel",
        Active = true,
        ZIndex = 2,
        Parent = Library.Overlay,
    })
    Stroke(Popup)
    Frame({ Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = "Accent", Parent = Popup })

    -- saturation / value square
    local SV = Frame({
        Position = UDim2.fromOffset(6, 7),
        Size = UDim2.fromOffset(128, 100),
        BackgroundColor3 = WHITE,
        Active = true,
        ClipsDescendants = true,
        Parent = Popup,
    })
    local SatLayer = Frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, Parent = SV })
    Create("UIGradient", { Transparency = NumberSequence.new(0, 1), Parent = SatLayer })
    local ValLayer = Frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, Parent = SV })
    Create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0), Parent = ValLayer })
    local SVCursor = Frame({
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(5, 5),
        BackgroundColor3 = WHITE,
        Parent = SV,
    })
    Stroke(SVCursor, BLACK)

    -- hue bar
    local HueBar = Frame({
        Position = UDim2.fromOffset(140, 7),
        Size = UDim2.fromOffset(14, 100),
        BackgroundColor3 = WHITE,
        Active = true,
        Parent = Popup,
    })
    Create("UIGradient", {
        Rotation = 90,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
            ColorSequenceKeypoint.new(1 / 6, Color3.fromRGB(255, 255, 0)),
            ColorSequenceKeypoint.new(2 / 6, Color3.fromRGB(0, 255, 0)),
            ColorSequenceKeypoint.new(3 / 6, Color3.fromRGB(0, 255, 255)),
            ColorSequenceKeypoint.new(4 / 6, Color3.fromRGB(0, 0, 255)),
            ColorSequenceKeypoint.new(5 / 6, Color3.fromRGB(255, 0, 255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
        }),
        Parent = HueBar,
    })
    local HueCursor = Frame({
        AnchorPoint = Vector2.new(0, 0.5),
        Size = UDim2.new(1, 0, 0, 2),
        BackgroundColor3 = WHITE,
        Parent = HueBar,
    })
    Stroke(HueCursor, BLACK)

    -- hex input
    local Hex = Create("TextBox", {
        Position = UDim2.fromOffset(6, 113),
        Size = UDim2.fromOffset(148, 15),
        BackgroundColor3 = "Field",
        BorderSizePixel = 0,
        Font = Library.Theme.Font,
        TextSize = 12,
        TextColor3 = "Text",
        PlaceholderText = "#RRGGBB",
        PlaceholderColor3 = "TextDim",
        ClearTextOnFocus = false,
        Text = "",
        Parent = Popup,
    })
    Stroke(Hex)

    local function Update()
        local color = Color3.fromHSV(Picker.Hue, Picker.Sat, Picker.Val)
        Picker.Value = color
        SV.BackgroundColor3 = Color3.fromHSV(Picker.Hue, 1, 1)
        SVCursor.Position = UDim2.fromScale(Picker.Sat, 1 - Picker.Val)
        HueCursor.Position = UDim2.fromScale(0, Picker.Hue)
        SwatchGradient.Color = ColorSequence.new(color, color:Lerp(BLACK, 0.4))
        Hex.Text = "#" .. string.upper(color:ToHex())
    end

    local function Commit()
        Update()
        Fire(Picker, info, Picker.Value)
    end

    BindDrag(SV, nil, function(pos)
        local p, s = SV.AbsolutePosition, SV.AbsoluteSize
        Picker.Sat = Clamp((pos.X - p.X) / s.X, 0, 1)
        Picker.Val = 1 - Clamp((pos.Y - p.Y) / s.Y, 0, 1)
        Commit()
    end)

    BindDrag(HueBar, nil, function(pos)
        local p, s = HueBar.AbsolutePosition, HueBar.AbsoluteSize
        Picker.Hue = Clamp((pos.Y - p.Y) / s.Y, 0, 1)
        Commit()
    end)

    Hex.FocusLost:Connect(function()
        local r, g, b = Hex.Text:match("^#?(%x%x)(%x%x)(%x%x)$")
        if r then
            Picker:SetValue(Color3.fromRGB(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)))
        else
            Update()
        end
    end)

    Swatch.Activated:Connect(function()
        Library:ShowPopup(Popup, Swatch, 160, 134, "Right")
    end)

    function Picker:SetValue(color, silent)
        self.Hue, self.Sat, self.Val = color:ToHSV()
        Update()
        if not silent then
            Fire(self, info, self.Value)
        end
    end

    function Picker:OnChanged(fn)
        table.insert(self.Callbacks, fn)
    end

    Update()
    return Picker
end

--------------------------------------------------------------------------------
-- Keybind widget ([NONE] text button)
--------------------------------------------------------------------------------

local KEY_SHORT = {
    LeftShift = "LSHIFT", RightShift = "RSHIFT", LeftControl = "LCTRL", RightControl = "RCTRL",
    LeftAlt = "LALT", RightAlt = "RALT", MouseButton1 = "MB1", MouseButton2 = "MB2",
    MouseButton3 = "MB3", Return = "ENTER", Backspace = "BKSP", Escape = "ESC",
}
local MODES = { "Toggle", "Hold", "Always" }

local function KeyText(value)
    return "[" .. string.upper(KEY_SHORT[value] or value) .. "]"
end

local function BuildKeybind(parent, info, linked)
    local Keybind = {
        Type = "KeyPicker",
        Value = info.Default or "None",
        Mode = info.Mode or "Toggle",
        State = false,
        Picking = false,
        Callbacks = {},
        Clicks = {},
        NoSave = info.NoSave,
    }
    if typeof(Keybind.Value) == "EnumItem" then
        Keybind.Value = Keybind.Value.Name
    end

    local Display = Button({
        Name = "Keybind",
        Size = UDim2.fromOffset(0, 12),
        AutomaticSize = Enum.AutomaticSize.X,
        TextSize = 8,
        TextColor3 = Library.Theme.TextDim,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = parent,
    })

    local function Refresh()
        Display.Text = Keybind.Picking and "[...]" or KeyText(Keybind.Value)
        Display.TextColor3 = Keybind.Picking and Library.Theme.AccentText or Library.Theme.TextDim
    end
    Library:Bind(Refresh)

    local function Matches(input)
        if Keybind.Value == "None" then
            return false
        end
        if input.UserInputType == Enum.UserInputType.Keyboard then
            return input.KeyCode.Name == Keybind.Value
        end
        return input.UserInputType.Name == Keybind.Value
    end

    local function Press()
        if Keybind.Mode == "Toggle" then
            if linked then
                linked:SetValue(not linked.Value)
                Keybind.State = linked.Value
            else
                Keybind.State = not Keybind.State
            end
        elseif Keybind.Mode == "Hold" then
            Keybind.State = true
            if linked then
                linked:SetValue(true)
            end
        end
        for _, fn in ipairs(Keybind.Clicks) do
            SafeCall(fn)
        end
        Fire(Keybind, info, Keybind.State)
    end

    local function Release()
        if Keybind.Mode == "Hold" and Keybind.State then
            Keybind.State = false
            if linked then
                linked:SetValue(false)
            end
            Fire(Keybind, info, false)
        end
    end

    Library:Connect(UserInputService.InputBegan, function(input, processed)
        if Keybind.Picking then
            local name
            if input.UserInputType == Enum.UserInputType.Keyboard then
                name = input.KeyCode.Name
            elseif input.UserInputType == Enum.UserInputType.MouseButton2
                or input.UserInputType == Enum.UserInputType.MouseButton3 then
                name = input.UserInputType.Name
            end
            if name and name ~= "Unknown" then
                Keybind.Picking = false
                Keybind:SetValue((name == "Escape" or name == "Backspace") and "None" or name)
            elseif IsPress(input) then
                -- tap / click anywhere cancels picking (touch has no keyboard)
                Keybind.Picking = false
                Keybind.CancelTime = os.clock()
                Refresh()
            end
            return
        end
        if not processed and Matches(input) then
            Press()
        end
    end)

    Library:Connect(UserInputService.InputEnded, function(input)
        if Matches(input) then
            Release()
        end
    end)

    Display.Activated:Connect(function()
        if Keybind.CancelTime and os.clock() - Keybind.CancelTime < 0.25 then
            return -- this press just cancelled picking
        end
        Keybind.Picking = true
        Refresh()
    end)

    -- right click cycles the mode (Toggle -> Hold -> Always)
    Display.MouseButton2Click:Connect(function()
        local nextIndex = (table.find(MODES, Keybind.Mode) or 0) % #MODES + 1
        Keybind:SetMode(MODES[nextIndex])
    end)

    function Keybind:SetValue(key, mode)
        if typeof(key) == "EnumItem" then
            key = key.Name
        end
        self.Value = key or "None"
        self.Picking = false
        if mode then
            self.Mode = mode
        end
        Refresh()
    end

    function Keybind:SetMode(mode)
        self.Mode = mode
        if mode == "Always" then
            self.State = true
            if linked then
                linked:SetValue(true)
            end
        end
    end

    function Keybind:GetState()
        return self.Mode == "Always" or self.State
    end

    function Keybind:OnClick(fn)
        table.insert(self.Clicks, fn)
    end

    function Keybind:OnChanged(fn)
        table.insert(self.Callbacks, fn)
    end

    return Keybind
end

-- Gives a row (toggle / label) the :AddColorPicker() and :AddKeybind() methods.
local function AttachAddons(obj, row)
    local holder
    local function Get()
        if not holder then
            holder = Frame({
                Name = "Addons",
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.fromScale(1, 0),
                Size = UDim2.fromScale(0, 1),
                AutomaticSize = Enum.AutomaticSize.X,
                ZIndex = 3,
                Parent = row,
            })
            Create("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal,
                HorizontalAlignment = Enum.HorizontalAlignment.Right,
                VerticalAlignment = Enum.VerticalAlignment.Center,
                Padding = UDim.new(0, 5),
                SortOrder = Enum.SortOrder.LayoutOrder,
                Parent = holder,
            })
        end
        return holder
    end

    function obj:AddColorPicker(idx, info)
        local picker = BuildColorPicker(Get(), info or {})
        if idx then
            Library.Options[idx] = picker
        end
        return picker
    end

    function obj:AddKeybind(idx, info)
        local keybind = BuildKeybind(Get(), info or {}, obj.Type == "Toggle" and obj or nil)
        if idx then
            Library.Options[idx] = keybind
        end
        return keybind
    end
end

--------------------------------------------------------------------------------
-- Section elements
--------------------------------------------------------------------------------

local Section = {}
Section.__index = Section

function Section:AddToggle(idx, info)
    info = info or {}
    local Toggle = { Type = "Toggle", Value = info.Default == true, Callbacks = {}, NoSave = info.NoSave }

    local Row = Frame({ Name = "Toggle", Size = UDim2.new(1, 0, 0, 14), Parent = self.Content })
    local Box = Frame({
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.fromScale(0, 0.5),
        Size = UDim2.fromOffset(11, 11),
        BackgroundColor3 = "Field",
        Parent = Row,
    })
    Stroke(Box)
    local Fill = Frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, Parent = Box })
    local FillGradient = Create("UIGradient", { Rotation = 90, Parent = Fill })
    local Text = Label({
        Position = UDim2.fromOffset(18, 0),
        Size = UDim2.new(1, -18, 1, 0),
        Text = info.Text or tostring(idx),
        Parent = Row,
    })
    local Hit = Button({ Name = "Hit", Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = Row })

    local function Refresh(animate)
        local on = Toggle.Value
        FillGradient.Color = AccentSequence()
        Apply(Fill, { BackgroundTransparency = on and 0 or 1 }, animate)
        Apply(Text, { TextColor3 = on and Library.Theme.AccentText or Library.Theme.TextOff }, animate)
    end
    Library:Bind(Refresh)

    function Toggle:SetValue(value, silent)
        value = value and true or false
        if self.Value == value then
            return
        end
        self.Value = value
        Refresh(true)
        if not silent then
            Fire(self, info, value)
        end
    end

    function Toggle:OnChanged(fn)
        table.insert(self.Callbacks, fn)
    end

    Hit.Activated:Connect(function()
        Toggle:SetValue(not Toggle.Value)
    end)

    AttachAddons(Toggle, Row)
    if idx then
        Library.Toggles[idx] = Toggle
    end
    return Toggle
end

function Section:AddLabel(text, wrap)
    local Obj = { Type = "Label" }
    local Row = Frame({ Name = "Label", Size = UDim2.new(1, 0, 0, 14), Parent = self.Content })
    local Text = Label({ Size = UDim2.fromScale(1, 1), Text = text or "", Parent = Row })
    if wrap then
        Row.Size = UDim2.new(1, 0, 0, 0)
        Row.AutomaticSize = Enum.AutomaticSize.Y
        Text.Size = UDim2.new(1, 0, 0, 0)
        Text.AutomaticSize = Enum.AutomaticSize.Y
        Text.TextWrapped = true
    end
    function Obj:SetText(value)
        Text.Text = tostring(value)
    end
    AttachAddons(Obj, Row)
    return Obj
end

function Section:AddKeybind(idx, info)
    info = info or {}
    return self:AddLabel(info.Text or tostring(idx)):AddKeybind(idx, info)
end

function Section:AddDivider()
    local Row = Frame({ Name = "Divider", Size = UDim2.new(1, 0, 0, 6), Parent = self.Content })
    Frame({
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.fromScale(0, 0.5),
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = "Border",
        Parent = Row,
    })
end

function Section:AddButton(a, b)
    local info = type(a) == "table" and a or { Text = a, Callback = b }
    local Obj = { Type = "Button" }

    local Btn = Button({
        Name = "Button",
        Size = UDim2.new(1, 0, 0, 15),
        BackgroundColor3 = "Field",
        BackgroundTransparency = 0,
        Parent = self.Content,
    })
    Stroke(Btn)
    local Text = Label({
        Size = UDim2.fromScale(1, 1),
        Text = info.Text or "Button",
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = Btn,
    })

    Btn.MouseEnter:Connect(function()
        Apply(Btn, { BackgroundColor3 = Library.Theme.Border }, true)
    end)
    Btn.MouseLeave:Connect(function()
        Apply(Btn, { BackgroundColor3 = Library.Theme.Field }, true)
    end)
    Btn.Activated:Connect(function()
        Text.TextColor3 = Library.Theme.AccentText
        Apply(Text, { TextColor3 = Library.Theme.Text }, true)
        SafeCall(info.Callback or info.Func)
    end)

    function Obj:SetText(value)
        Text.Text = tostring(value)
    end
    return Obj
end

function Section:AddTextbox(idx, info)
    info = info or {}
    local Input = { Type = "Input", Value = info.Default or "", Callbacks = {}, NoSave = info.NoSave }

    local Holder = Frame({
        Name = "Textbox",
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = self.Content,
    })
    List(Holder, 2)
    if info.Text then
        Label({ Size = UDim2.new(1, 0, 0, 14), Text = info.Text, LayoutOrder = 1, Parent = Holder })
    end
    local Box = Create("TextBox", {
        Size = UDim2.new(1, 0, 0, 15),
        BackgroundColor3 = "Field",
        BorderSizePixel = 0,
        Font = Library.Theme.Font,
        TextSize = Library.Theme.TextSize,
        TextColor3 = "Text",
        PlaceholderText = info.Placeholder or "",
        PlaceholderColor3 = "TextDim",
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = Input.Value,
        LayoutOrder = 2,
        Parent = Holder,
    })
    Create("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = Box })
    Stroke(Box)

    if info.Numeric then
        Box:GetPropertyChangedSignal("Text"):Connect(function()
            local cleaned = Box.Text:gsub("[^%d%.%-]", "")
            if cleaned ~= Box.Text then
                Box.Text = cleaned
            end
        end)
    end

    Box.FocusLost:Connect(function()
        Input.Value = Box.Text
        Fire(Input, info, Input.Value)
    end)

    function Input:SetValue(value, silent)
        self.Value = tostring(value or "")
        Box.Text = self.Value
        if not silent then
            Fire(self, info, self.Value)
        end
    end

    function Input:OnChanged(fn)
        table.insert(self.Callbacks, fn)
    end

    if idx then
        Library.Options[idx] = Input
    end
    return Input
end

function Section:AddSlider(idx, info)
    info = info or {}
    local Slider = {
        Type = "Slider",
        Min = info.Min or 0,
        Max = info.Max or 100,
        Rounding = info.Rounding or 0,
        Callbacks = {},
        NoSave = info.NoSave,
    }
    Slider.Value = Clamp(info.Default or Slider.Min, Slider.Min, Slider.Max)

    local Holder = Frame({
        Name = "Slider",
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = self.Content,
    })
    List(Holder, 2)
    if info.Text and not info.Compact then
        Label({ Size = UDim2.new(1, 0, 0, 14), Text = info.Text, LayoutOrder = 1, Parent = Holder })
    end

    local Bar = Frame({
        Name = "Bar",
        Size = UDim2.new(1, 0, 0, 11),
        BackgroundColor3 = "Track",
        Active = true,
        LayoutOrder = 2,
        Parent = Holder,
    })
    Stroke(Bar)
    local Fill = Frame({ Size = UDim2.fromScale(0, 1), BackgroundColor3 = WHITE, Parent = Bar })
    local FillGradient = Create("UIGradient", { Rotation = 90, Parent = Fill })
    local Value = Label({
        Size = UDim2.fromScale(1, 1),
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextColor3 = "TextBright",
        Parent = Bar,
    })

    local function Refresh()
        local range = Slider.Max - Slider.Min
        local alpha = range > 0 and (Slider.Value - Slider.Min) / range or 1
        Fill.Size = UDim2.fromScale(alpha, 1)
        FillGradient.Color = AccentSequence()

        if info.Display then
            Value.Text = tostring(info.Display(Slider.Value, Slider.Max))
        else
            local fmt = "%." .. tostring(Slider.Rounding) .. "f"
            local suffix = info.Suffix or ""
            Value.Text = string.format(fmt, Slider.Value) .. suffix .. "/" .. string.format(fmt, Slider.Max) .. suffix
        end
    end
    Library:Bind(Refresh)

    function Slider:SetValue(value, silent)
        value = Clamp(Round(tonumber(value) or self.Min, self.Rounding), self.Min, self.Max)
        local changed = value ~= self.Value
        self.Value = value
        Refresh()
        if changed and not silent then
            Fire(self, info, value)
        end
    end

    function Slider:OnChanged(fn)
        table.insert(self.Callbacks, fn)
    end

    local column = self.Column
    BindDrag(Bar, function()
        if column then
            column.ScrollingEnabled = false
        end
    end, function(pos)
        local p, s = Bar.AbsolutePosition, Bar.AbsoluteSize
        local alpha = Clamp((pos.X - p.X) / s.X, 0, 1)
        Slider:SetValue(Slider.Min + (Slider.Max - Slider.Min) * alpha)
    end, function()
        if column then
            column.ScrollingEnabled = true
        end
    end)

    if idx then
        Library.Options[idx] = Slider
    end
    return Slider
end

function Section:AddDropdown(idx, info)
    info = info or {}
    local Dropdown = {
        Type = "Dropdown",
        Values = info.Values or {},
        Multi = info.Multi == true,
        Callbacks = {},
        NoSave = info.NoSave,
    }
    local OptionLabels = {}

    local Holder = Frame({
        Name = "Dropdown",
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = self.Content,
    })
    List(Holder, 2)
    if info.Text then
        Label({ Size = UDim2.new(1, 0, 0, 14), Text = info.Text, LayoutOrder = 1, Parent = Holder })
    end

    local Box = Button({
        Name = "Box",
        Size = UDim2.new(1, 0, 0, 15),
        BackgroundColor3 = "Field",
        BackgroundTransparency = 0,
        LayoutOrder = 2,
        Parent = Holder,
    })
    Stroke(Box)
    local ValueText = Label({
        Position = UDim2.fromOffset(6, 0),
        Size = UDim2.new(1, -24, 1, 0),
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = Box,
    })
    local Arrow = Label({
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -7, 0, 0),
        Size = UDim2.fromOffset(10, 15),
        Text = "+",
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = Box,
    })

    local Popup = Create("ScrollingFrame", {
        Name = "DropdownList",
        Visible = false,
        BackgroundColor3 = "Field",
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = "Accent",
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Active = true,
        ZIndex = 2,
        Parent = Library.Overlay,
    })
    Stroke(Popup)
    List(Popup, 0)

    -- default value
    if Dropdown.Multi then
        Dropdown.Value = {}
        if type(info.Default) == "table" then
            for k, v in pairs(info.Default) do
                if type(k) == "number" then
                    Dropdown.Value[v] = true
                elseif v then
                    Dropdown.Value[k] = true
                end
            end
        end
    else
        local default = info.Default
        if type(default) == "number" then
            default = Dropdown.Values[default]
        end
        Dropdown.Value = default
    end

    local function Display()
        local text
        if Dropdown.Multi then
            local picked = {}
            for _, v in ipairs(Dropdown.Values) do
                if Dropdown.Value[v] then
                    table.insert(picked, tostring(v))
                end
            end
            text = #picked > 0 and table.concat(picked, ", ") or "None"
        else
            text = tostring(Dropdown.Value)
        end
        ValueText.Text = text

        for value, optionLabel in pairs(OptionLabels) do
            local selected
            if Dropdown.Multi then
                selected = Dropdown.Value[value] == true
            else
                selected = Dropdown.Value == value
            end
            optionLabel.TextColor3 = selected and Library.Theme.AccentText or Library.Theme.Text
        end
    end

    local function Select(value)
        if Dropdown.Multi then
            Dropdown.Value[value] = not Dropdown.Value[value] or nil
        else
            if Dropdown.Value == value and info.AllowNull then
                Dropdown.Value = nil
            else
                Dropdown.Value = value
            end
            Library:ClosePopup()
        end
        Display()
        Fire(Dropdown, info, Dropdown.Value)
    end

    local function Build()
        for _, child in ipairs(Popup:GetChildren()) do
            if child:IsA("TextButton") then
                child:Destroy()
            end
        end
        OptionLabels = {}
        for i, value in ipairs(Dropdown.Values) do
            local Option = Button({
                Name = tostring(value),
                Size = UDim2.new(1, 0, 0, 15),
                BackgroundColor3 = "Border",
                BackgroundTransparency = 1,
                LayoutOrder = i,
                Parent = Popup,
            })
            OptionLabels[value] = Label({
                Position = UDim2.fromOffset(6, 0),
                Size = UDim2.new(1, -12, 1, 0),
                Text = tostring(value),
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = Option,
            })
            Option.MouseEnter:Connect(function()
                Option.BackgroundTransparency = 0
            end)
            Option.MouseLeave:Connect(function()
                Option.BackgroundTransparency = 1
            end)
            Option.Activated:Connect(function()
                Select(value)
            end)
        end
    end

    Build()
    Library:Bind(Display)

    Box.Activated:Connect(function()
        local height = math.max(1, math.min(#Dropdown.Values, 8)) * 15
        Arrow.Text = "-"
        Library:ShowPopup(Popup, Box, Box.AbsoluteSize.X, height, "Left", function()
            Arrow.Text = "+"
        end)
    end)

    function Dropdown:SetValue(value, silent)
        if self.Multi then
            self.Value = {}
            if type(value) == "table" then
                for k, v in pairs(value) do
                    if type(k) == "number" then
                        self.Value[v] = true
                    elseif v then
                        self.Value[k] = true
                    end
                end
            end
        else
            if value ~= nil and not table.find(self.Values, value) then
                return
            end
            self.Value = value
        end
        Display()
        if not silent then
            Fire(self, info, self.Value)
        end
    end

    function Dropdown:SetValues(values)
        self.Values = values
        if self.Multi then
            for key in pairs(self.Value) do
                if not table.find(values, key) then
                    self.Value[key] = nil
                end
            end
        elseif self.Value ~= nil and not table.find(values, self.Value) then
            self.Value = nil
        end
        Build()
        Display()
    end

    function Dropdown:OnChanged(fn)
        table.insert(self.Callbacks, fn)
    end

    if idx then
        Library.Options[idx] = Dropdown
    end
    return Dropdown
end

--------------------------------------------------------------------------------
-- Config save / load
--------------------------------------------------------------------------------

function Library:Serialize()
    local data = {}
    for idx, toggle in pairs(self.Toggles) do
        if not toggle.NoSave then
            data[idx] = { Type = "Toggle", Value = toggle.Value }
        end
    end
    for idx, option in pairs(self.Options) do
        if not option.NoSave then
            if option.Type == "Slider" or option.Type == "Input" or option.Type == "Dropdown" then
                data[idx] = { Type = option.Type, Value = option.Value }
            elseif option.Type == "ColorPicker" then
                local c = option.Value
                data[idx] = {
                    Type = "ColorPicker",
                    Value = { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) },
                }
            elseif option.Type == "KeyPicker" then
                data[idx] = { Type = "KeyPicker", Key = option.Value, Mode = option.Mode }
            end
        end
    end
    return HttpService:JSONEncode(data)
end

function Library:Deserialize(json)
    local ok, data = pcall(function()
        return HttpService:JSONDecode(json)
    end)
    if not ok or type(data) ~= "table" then
        return false
    end
    for idx, entry in pairs(data) do
        pcall(function()
            if entry.Type == "Toggle" then
                local toggle = self.Toggles[idx]
                if toggle then
                    toggle:SetValue(entry.Value)
                end
            else
                local option = self.Options[idx]
                if option and option.Type == entry.Type then
                    if entry.Type == "ColorPicker" then
                        option:SetValue(Color3.fromRGB(entry.Value[1], entry.Value[2], entry.Value[3]))
                    elseif entry.Type == "KeyPicker" then
                        option:SetValue(entry.Key, entry.Mode)
                        option:SetMode(entry.Mode or option.Mode)
                    else
                        option:SetValue(entry.Value)
                    end
                end
            end
        end)
    end
    return true
end

-- Builds a "config name / list / create / load / save / delete" block.
function Library:CreateConfigManager(section, folder)
    folder = folder or "SpecterLib"
    local dir = folder .. "/configs"

    local function FsReady()
        if not (writefile and readfile and isfolder and makefolder and listfiles) then
            return false
        end
        if not isfolder(folder) then
            makefolder(folder)
        end
        if not isfolder(dir) then
            makefolder(dir)
        end
        return true
    end

    local function Names()
        local out = {}
        if FsReady() then
            for _, path in ipairs(listfiles(dir)) do
                local name = path:match("([^/\\]+)%.json$")
                if name then
                    table.insert(out, name)
                end
            end
            table.sort(out)
        end
        return out
    end

    local function Need(callback)
        if not FsReady() then
            self:Notify("Filesystem functions are not available here.")
            return
        end
        callback()
    end

    local NameBox = section:AddTextbox("SpecterConfigName", { Text = "Config Name", Placeholder = "name", NoSave = true })
    local ListBox = section:AddDropdown("SpecterConfigList", {
        Text = "Config List",
        Values = Names(),
        AllowNull = true,
        NoSave = true,
    })

    section:AddButton("Create", function()
        Need(function()
            local name = (NameBox.Value or ""):gsub("[^%w%-_ ]", "")
            if name == "" then
                return self:Notify("Enter a config name first.")
            end
            writefile(dir .. "/" .. name .. ".json", self:Serialize())
            ListBox:SetValues(Names())
            ListBox:SetValue(name, true)
            self:Notify("Created config '" .. name .. "'")
        end)
    end)

    section:AddButton("Load", function()
        Need(function()
            local name = ListBox.Value
            local path = name and (dir .. "/" .. name .. ".json")
            if path and isfile and isfile(path) and self:Deserialize(readfile(path)) then
                self:Notify("Loaded config '" .. name .. "'")
            else
                self:Notify("Select a valid config first.")
            end
        end)
    end)

    section:AddButton("Save", function()
        Need(function()
            local name = ListBox.Value
            if not name then
                return self:Notify("Select a config to overwrite.")
            end
            writefile(dir .. "/" .. name .. ".json", self:Serialize())
            self:Notify("Saved config '" .. name .. "'")
        end)
    end)

    section:AddButton("Delete", function()
        Need(function()
            local name = ListBox.Value
            if name and delfile then
                delfile(dir .. "/" .. name .. ".json")
                ListBox:SetValues(Names())
                self:Notify("Deleted config '" .. name .. "'")
            else
                self:Notify("Select a config to delete.")
            end
        end)
    end)

    section:AddButton("Refresh List", function()
        ListBox:SetValues(Names())
    end)
end

--------------------------------------------------------------------------------
-- Window / tabs
--------------------------------------------------------------------------------

function Library:CreateWindow(config)
    config = config or {}
    self:_Init()

    local Window = {
        Tabs = {},
        TabX = 0,
        Active = nil,
        ToggleKey = config.ToggleKey == nil and Enum.KeyCode.RightShift or config.ToggleKey,
    }

    local size = config.Size or Vector2.new(545, 348)
    if typeof(size) == "UDim2" then
        size = Vector2.new(size.X.Offset, size.Y.Offset)
    end

    -- 1px gradient border -> 1px near-black line -> body
    local Outer = Frame({
        Name = "Window",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = config.Position or UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(size.X, size.Y),
        BackgroundColor3 = WHITE,
        Active = true,
        Parent = self.Gui,
    })
    local BorderGradient = Create("UIGradient", { Parent = Outer })
    self:Bind(function()
        BorderGradient.Color = ColorSequence.new(self.Theme.BorderA, self.Theme.BorderB)
    end)

    local Inner = Frame({
        Position = UDim2.fromOffset(1, 1),
        Size = UDim2.new(1, -2, 1, -2),
        BackgroundColor3 = "Black",
        Parent = Outer,
    })
    local Body = Frame({
        Position = UDim2.fromOffset(1, 1),
        Size = UDim2.new(1, -2, 1, -2),
        BackgroundColor3 = "Window",
        Parent = Inner,
    })
    Window.Outer = Outer

    local Title = Label({
        Position = UDim2.fromOffset(12, 4),
        Size = UDim2.new(1, -24, 0, 14),
        Text = config.Title or "Window",
        TextColor3 = "AccentText",
        Parent = Body,
    })

    -- drag handle (title row)
    local DragBar = Frame({ Size = UDim2.new(1, 0, 0, 26), Active = true, Parent = Body })
    local startMouse, startPos
    BindDrag(DragBar, function(input)
        startMouse, startPos = input.Position, Outer.Position
    end, function(pos)
        if not startMouse then
            return
        end
        local delta = pos - startMouse
        Outer.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end, function()
        startMouse = nil
    end)

    local TabHolder = Frame({
        Position = UDim2.fromOffset(11, 27),
        Size = UDim2.new(1, -22, 0, 22),
        ZIndex = 2,
        Parent = Body,
    })

    local Panel = Frame({
        Position = UDim2.fromOffset(12, 48),
        Size = UDim2.new(1, -24, 1, -60),
        BackgroundColor3 = "Panel",
        Parent = Body,
    })
    Stroke(Panel)

    function Window:SetTitle(text)
        Title.Text = text
    end

    function Window:SelectTab(tab)
        self.Active = tab
        for _, other in ipairs(self.Tabs) do
            other:_Style()
        end
        Library:ClosePopup()
    end

    function Window:SetToggleKey(key)
        self.ToggleKey = key
    end

    function Window:AddTab(name)
        local Tab = { Name = name, Window = Window, Order = 0 }

        local textWidth = TextService:GetTextSize(
            name, Library.Theme.TextSize, Library.Theme.Font, Vector2.new(1000, 100)
        ).X
        local width = math.ceil(textWidth) + 18
        local x = Window.TabX
        Window.TabX = x + width + 3

        -- tab button: outline frame > fill frame > accent top line + text
        local Btn = Button({
            Name = name,
            Position = UDim2.fromOffset(x, 3),
            Size = UDim2.fromOffset(width, 18),
            BackgroundColor3 = "Border",
            BackgroundTransparency = 0,
            Parent = TabHolder,
        })
        local Fill = Frame({
            Position = UDim2.fromOffset(1, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BackgroundColor3 = WHITE,
            Parent = Btn,
        })
        local Top = Frame({ Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = "Accent", Visible = false, Parent = Fill })
        local Text = Label({
            Size = UDim2.fromScale(1, 1),
            Text = name,
            TextXAlignment = Enum.TextXAlignment.Center,
            Parent = Fill,
        })

        -- page with two scrolling columns
        local Page = Frame({ Name = name, Size = UDim2.fromScale(1, 1), Visible = false, Parent = Panel })
        local Columns = Frame({
            Position = UDim2.fromOffset(8, 9),
            Size = UDim2.new(1, -16, 1, -18),
            Parent = Page,
        })

        local function MakeColumn(position, size)
            local Column = Create("ScrollingFrame", {
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Position = position,
                Size = size,
                CanvasSize = UDim2.new(),
                AutomaticCanvasSize = Enum.AutomaticSize.Y,
                ScrollBarThickness = 2,
                ScrollBarImageColor3 = "Accent",
                ScrollingDirection = Enum.ScrollingDirection.Y,
                Parent = Columns,
            })
            List(Column, 11)
            Create("UIPadding", {
                PaddingTop = UDim.new(0, 1), PaddingBottom = UDim.new(0, 1),
                PaddingLeft = UDim.new(0, 1), PaddingRight = UDim.new(0, 1),
                Parent = Column,
            })
            return Column
        end
        Tab.Left = MakeColumn(UDim2.fromOffset(0, 0), UDim2.new(0.5, -7, 1, 0))
        Tab.Right = MakeColumn(UDim2.new(0.5, 7, 0, 0), UDim2.new(0.5, -7, 1, 0))

        function Tab:_Style()
            local active = Window.Active == self
            Btn.Position = UDim2.fromOffset(x, active and 0 or 3)
            Btn.Size = UDim2.fromOffset(width, active and 22 or 18)
            Fill.Size = UDim2.new(1, -2, 1, active and -1 or -2)
            Fill.BackgroundColor3 = active and Library.Theme.Panel or Library.Theme.Field
            Top.Visible = active
            Text.TextColor3 = active and Library.Theme.AccentText or Library.Theme.TextDim
            Page.Visible = active
        end

        function Tab:AddSection(title, side)
            local column = (tostring(side):lower() == "right") and self.Right or self.Left
            self.Order = self.Order + 1

            local Box = Frame({
                Name = title,
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundColor3 = "Section",
                LayoutOrder = self.Order,
                Parent = column,
            })
            Stroke(Box)

            local Header = Frame({ Size = UDim2.new(1, 0, 0, 19), BackgroundColor3 = WHITE, Parent = Box })
            local HeaderGradient = Create("UIGradient", { Rotation = 90, Parent = Header })
            Library:Bind(function()
                HeaderGradient.Color = ColorSequence.new(Library.Theme.HeaderTop, Library.Theme.Section)
            end)
            Frame({ Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = "Accent", Parent = Header })
            Label({
                Position = UDim2.fromOffset(7, 1),
                Size = UDim2.new(1, -14, 1, -1),
                Text = title,
                TextColor3 = "AccentText",
                Parent = Header,
            })

            local Content = Frame({
                Name = "Content",
                Position = UDim2.fromOffset(0, 19),
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                Parent = Box,
            })
            List(Content, 2)
            Create("UIPadding", {
                PaddingTop = UDim.new(0, 1), PaddingBottom = UDim.new(0, 6),
                PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7),
                Parent = Content,
            })

            return setmetatable({ Tab = Tab, Content = Content, Column = column }, Section)
        end

        function Tab:AddLeftSection(title)
            return self:AddSection(title, "Left")
        end

        function Tab:AddRightSection(title)
            return self:AddSection(title, "Right")
        end

        Library:Connect(Btn.Activated, function()
            Window:SelectTab(Tab)
        end)

        table.insert(Window.Tabs, Tab)
        if not Window.Active then
            Window.Active = Tab
        end
        Library:Bind(function()
            Tab:_Style()
        end)
        return Tab
    end

    -- show / hide
    self:Connect(UserInputService.InputBegan, function(input, processed)
        if processed or self.Unloaded then
            return
        end
        if Window.ToggleKey and input.KeyCode == Window.ToggleKey then
            self:Toggle()
        end
    end)

    if config.MobileButton ~= false and UserInputService.TouchEnabled then
        local Toggler = Button({
            Name = "MobileToggle",
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -10, 0, 10),
            Size = UDim2.fromOffset(34, 34),
            BackgroundColor3 = "Window",
            BackgroundTransparency = 0,
            Text = string.upper(string.sub(config.Title or "S", 1, 1)),
            TextSize = 16,
            TextColor3 = "AccentText",
            ZIndex = 70,
            Parent = self.Gui,
        })
        Stroke(Toggler, "Accent")
        Toggler.Activated:Connect(function()
            self:Toggle()
        end)
    end

    table.insert(self.Windows, Window)
    return Window
end

return Library
