-- Input Monitor Overlay (IMO): a small draggable overlay of every key and mouse button pressed,
-- with the time since the previous press. The presses run out from the bar: as rows below or
-- above it (the full bar), or as separate keys to its right or left (a small "/imo" tab). Which
-- way follows the screen edge the bar was last dragged to. Right-click it for the menu.
-- /imo opens and closes it; closed, it listens to nothing.

local ADDON = "InputMonitorO"
local MEDIA = "Interface/AddOns/" .. ADDON .. "/"

local BAR_HEIGHT = 26 -- the same as the compact tab is wide: one is the other turned upright
local ROW_HEIGHT = 18
local CAP_SIZE = 30     -- a keyboard key's square box, in the sideways layout
local KEY_HEIGHT = 44   -- the box with its time under it
local KEY_GAP = 4
local KEY_PAD = 6       -- inside the sideways keys' panel, around the keys
local TUCK = 10         -- how far that panel's near end runs under the tab
local KEY_RAISE = 8     -- that panel sits this much above the tab's middle, level with "/imo"
local KEY_WIDTH = 42    -- every sideways press takes this much room; long names shrink to fit
local TAB_THIN, TAB_LONG = 26, 76 -- the compact tab (light, then "/imo")
local MIN_WIDTH, MAX_WIDTH = 200, 800
local MIN_ROWS, MAX_ROWS = 3, 40
local EDGE = 100 -- dragged this close to a screen edge, the presses turn to run away from it
local SNAP = 12  -- dragged this close to an edge, the bar is pulled flush to it
local DEFAULTS = {
    width = 249, rows = 18, mode = "right", locked = true,
    keyCount = 10,     -- sideways keys shown (rows has its own: rows)
    newestAtBar = true, -- new presses appear next to the bar (else at the far end, chat style)
    hold = 3,          -- seconds a press stays fully visible
    fade = 0.2,        -- seconds it then takes to fade out
    showAction = true, -- what the key is bound to (rows only)
    showClock = true,  -- the clock time of each press (rows only)
    strata = "TOOLTIP", -- the game's drawing layer: the top one, over everything
}
-- The game's layers, top first (the menu steps through them).
local STRATA = { "TOOLTIP", "FULLSCREEN_DIALOG", "FULLSCREEN", "DIALOG", "HIGH", "MEDIUM", "LOW", "BACKGROUND" }
local STRATA_NAME = { TOOLTIP = "Top", FULLSCREEN_DIALOG = "Fullscreen dialog", FULLSCREEN = "Fullscreen",
    DIALOG = "Dialog", HIGH = "High", MEDIUM = "Medium", LOW = "Low", BACKGROUND = "Background" }
-- mode: which way the presses run from the bar.
local ANGLE = { right = 0, up = math.pi / 2, left = math.pi, down = -math.pi / 2 }
local OPPOSITE = { right = "left", left = "right", up = "down", down = "up" }
local EDGE_MODE = { left = "right", right = "left", top = "down", bottom = "up" }
local MODE_EDGE = { right = "left", left = "right", down = "top", up = "bottom" }

local BARE_MODIFIERS = { LSHIFT = "SHIFT", RSHIFT = "SHIFT", LCTRL = "CTRL", RCTRL = "CTRL",
    LALT = "ALT", RALT = "ALT", LMETA = "META", RMETA = "META" }
local MOUSE_NAMES = { LeftButton = "LMB", RightButton = "RMB", MiddleButton = "MMB" }
-- Button4 and up (an MMO mouse reports its side buttons as Button6 and up, to Button31): MB4...
local function MouseName(button)
    return MOUSE_NAMES[button] or (tostring(button):gsub("^Button(%d+)$", "MB%1"))
end
-- The names key bindings use for the mouse: BUTTON1 (left), BUTTON2 (right), BUTTON3 (middle),
-- then BUTTON4 and up.
local BIND_NAMES = { LeftButton = "BUTTON1", RightButton = "BUTTON2", MiddleButton = "BUTTON3" }
local function MouseBindName(button)
    return BIND_NAMES[button] or tostring(button):upper()
end

local db
local entries = {}  -- newest first: { key, action, at (GetTime), clock, delta }
local lastAt        -- GetTime() of the previous press
local held = {}     -- keys currently down (a held key repeats OnKeyDown; shown once)
local dragging, sizing = false, false
local menu -- the right-click menu, made further down

local function Sideways() return db.mode == "right" or db.mode == "left" end
-- The full bar's round end hangs out past the rows' panel, as the tab's does past its keys.
local HANG = 17 -- (measured: as far past the panel as the tab's round end is past its keys')
local OVER = 2  -- and at the far end, as far past the panel as the tab's top is
-- How many presses show: rows and sideways keys each keep their own count.
local function Limit() return Sideways() and db.keyCount or db.rows end
local function Trim()
    while #entries > Limit() do table.remove(entries) end
end
-- Compact (the "/imo" tab) goes with sideways keys, the full bar with rows: switching one
-- switches the other, so the change shows at a glance.
local Compact = Sideways
-- The bar's size: the full bar, or the compact tab (standing up when the keys run sideways).
local function BarWidth()
    if Compact() then return TAB_THIN end
    return db.width + HANG + OVER
end
local function BarHeight()
    if Compact() then return TAB_LONG end
    return BAR_HEIGHT
end

-- Window --------------------------------------------------------------------------------
local WHITE = "Interface/Buttons/WHITE8x8"
-- JetBrains Mono (SIL Open Font License, Fonts/OFL.txt): same-width digits keep times steady.
local MONO = MEDIA .. "Fonts/JetBrainsMono-Bold.ttf"
local PAD = 4 -- space inside the rows' panel, above the first row and below the last
local GAP = 1 -- between the bar and the presses
-- The game's own rounded tooltip frame, used for the bar, the rows' panel and the popups.
local ROUNDED = {
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local CAP = {
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}
local BORDER = { 0.55, 0.55, 0.6, 1 }
local GOLD = "|cffffd100"

local BAR_COLOR = { 0.07, 0.07, 0.08, 0.95 }
local monitor = CreateFrame("Frame", "InputMonitorOverlayFrame", UIParent)
monitor:SetHeight(BAR_HEIGHT)
monitor:SetFrameStrata("TOOLTIP")
monitor:SetFrameLevel(500) -- high within its layer too, over other frames sharing it
monitor:SetMovable(true)
monitor:EnableMouse(true)
monitor:RegisterForDrag("LeftButton")
monitor:Hide()

-- The plate: the rounded frame, with a pill-round end where the light sits (the left of the
-- full bar, the bottom of the tab). The round end is a half circle drawn below the plate's
-- end, whose own corners and edge there are hidden.
local plate = CreateFrame("Frame", nil, monitor, "BackdropTemplate")
-- Layers, bottom to top: the presses' panel (its near end tucks under the tab), the round
-- end, the plate, then the light, text and buttons.
local LEVEL = monitor:GetFrameLevel()
plate:SetFrameLevel(LEVEL + 3)
-- The plate reaches one corner's width (12) past the circle's middle on the round side, its
-- corners there hidden, so its straight border starts right where the circle's does; its
-- background stops at the circle's middle (the disc fills the rest).
local PILL = {}
for side in pairs({ left = true, bottom = true }) do
    local insets = { left = 3, right = 3, top = 3, bottom = 3 }
    insets[side] = 12
    -- A flat fill (the tooltip background is a slightly grey picture, the round end's is
    -- flat white): both tinted the same, so the two halves of the pill match exactly.
    PILL[side] = { bgFile = WHITE, edgeFile = ROUNDED.edgeFile, edgeSize = 12, insets = insets }
end
local DISC = "Interface/CHARACTERFRAME/TempPortraitAlphaMask"
-- Matching the plate's border: its edge is a hollow ring picture (Icons/pill_edge.tga: a soft
-- dark shadow at the frame's edge, then a thin grey line, measured from the plate's own), and
-- inside it the plate's fill. Nothing sits under the fill, so it looks just like the plate's.
local PILL_LINE_IN = 2.15 -- where the ring's line ends inside the frame edge
local LED_DROP = -2 -- the light picture's ball sits this much high in it (measured in game)
local pill = CreateFrame("Frame", nil, monitor)
pill:SetAllPoints()
pill:SetFrameLevel(LEVEL + 2)
local edge = pill:CreateTexture(nil, "BACKGROUND", nil, 1)
edge:SetTexture(MEDIA .. "Icons/pill_edge.tga")
local disc = pill:CreateTexture(nil, "BACKGROUND", nil, 2)
disc:SetTexture(DISC)
disc:SetVertexColor(unpack(BAR_COLOR)) -- the plate's own fill (see-through as much), so no seam
-- What sits on the plate (the light and the tab's text) draws above it.
local face = CreateFrame("Frame", nil, monitor)
face:SetAllPoints()
face:SetFrameLevel(LEVEL + 6)

-- Holds the presses. For rows it is one rounded panel around them all, growing and shrinking
-- with them; for sideways keys it is bare (each key has its own box).
-- The presses' panel draws only on the far side of the tab's edge: the tab is a hard stop
-- (the panel's tucked end and corners never show), the panel seeming to slide out from it.
local clip = CreateFrame("Frame", nil, monitor)
clip:SetClipsChildren(true)
clip:SetFrameLevel(LEVEL + 1)
local list = CreateFrame("Frame", nil, clip, "BackdropTemplate")
list:SetFrameLevel(LEVEL + 1)
list:SetBackdrop(ROUNDED)
list:SetClipsChildren(true)
list:Hide()
local listSize = 0 -- drawn length (height for rows, width for keys), easing toward the target
local listTarget = 0

-- Full bar: light, title and buttons. Compact: just "/imo".
local full = CreateFrame("Frame", nil, monitor)
full:SetAllPoints()
full:SetFrameLevel(LEVEL + 6)
-- A small light before the name: flashes on each press, glows softly while presses show.
local led = face:CreateTexture(nil, "OVERLAY")
led:SetTexture("Interface/COMMON/Indicator-Green") -- placed by Relayout
local title = full:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
title:SetPoint("LEFT", BAR_HEIGHT + 2, 0) -- just past the round end, as on the tab
title:SetFont(MONO, 12, "") -- the tab's font and size (gold, from the font object)
title:SetText("/imo")

local tabText = face:CreateFontString(nil, "OVERLAY")
tabText:SetFont(MONO, 12, "")
tabText:SetTextColor(1, 0.82, 0)
tabText:SetText("/imo")

-- Bar buttons, right to left: close, lock, sort order. (The menu: right-click the bar.)
local function BarButton(anchorTo)
    local b = CreateFrame("Button", nil, full)
    b:SetSize(20, BAR_HEIGHT)
    if anchorTo then b:SetPoint("RIGHT", anchorTo, "LEFT", 0, 0) else b:SetPoint("RIGHT", -2, 0) end
    return b
end

-- Beside the bar, with room on screen: the tooltips go right by it; the popups (`clearRows`)
-- also clear the rows, which are wider than the compact tab.
local function Beside(frame, clearRows)
    frame:ClearAllPoints()
    local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
    if Sideways() then
        local h = db.mode == "right" and "LEFT" or "RIGHT"
        if (monitor:GetTop() or 0) + frame:GetHeight() + 2 <= screenH then
            frame:SetPoint("BOTTOM" .. h, monitor, "TOP" .. h, 0, 2)
        else
            frame:SetPoint("TOP" .. h, monitor, "BOTTOM" .. h, 0, -2)
        end
    else
        -- Clear of the rows too (they are wider than the compact tab).
        local v = db.mode == "up" and "BOTTOM" or "TOP"
        local reach = clearRows and math.max(BarWidth(), db.width) or BarWidth()
        if (monitor:GetLeft() or 0) + reach + frame:GetWidth() + 2 <= screenW then
            frame:SetPoint(v .. "LEFT", monitor, v .. "LEFT", reach + 2, 0)
        else
            frame:SetPoint(v .. "RIGHT", monitor, v .. "LEFT", -2, 0)
        end
    end
end

-- Tooltips -------------------------------------------------------------------------------
-- The game's own mouse button pictures, when this client has them; plain words otherwise.
local function MouseIcon(atlases, fallback, size)
    local info = C_Texture and C_Texture.GetAtlasInfo
    for _, atlas in ipairs(atlases) do
        if info and info(atlas) then return "|A:" .. atlas .. ":" .. size .. ":" .. size .. "|a" end
    end
    return fallback
end
local LEFT_ATLASES = { "NPE_LeftClick", "newplayertutorial-icon-mouse-leftbutton" }
local RIGHT_ATLASES = { "NPE_RightClick", "newplayertutorial-icon-mouse-rightbutton" }
local LMB = MouseIcon(LEFT_ATLASES, "Left-click:", 14)
local RMB = MouseIcon(RIGHT_ATLASES, "Right-click:", 14)
-- In the rows, the two main mouse buttons show as the mouse picture (sized to the text); the
-- wheel as words.
local PRESS_ICON = { LMB = MouseIcon(LEFT_ATLASES, "LMB", 0), RMB = MouseIcon(RIGHT_ATLASES, "RMB", 0),
    WHEELUP = "Wheel\226\134\145", WHEELDOWN = "Wheel\226\134\147" }
-- The middle button: a white mouse with a red wheel between its buttons. The wheel turned: a
-- picture of the wheel with a red arrow (Icons/).
local WHEEL_AT = { 0.5, 0.33 }  -- where the wheel sits in the mouse picture (0..1 across, down)
local WHEEL_ICON = { WHEELUP = MEDIA .. "Icons/wheel_up.tga", WHEELDOWN = MEDIA .. "Icons/wheel_down.tga" }
local function FirstAtlas(atlases)
    local info = C_Texture and C_Texture.GetAtlasInfo
    for _, atlas in ipairs(atlases) do
        if info and info(atlas) then return atlas end
    end
end
local MOUSE_ATLAS = { LMB = FirstAtlas(LEFT_ATLASES), RMB = FirstAtlas(RIGHT_ATLASES) }

-- Shows (part of, from..to across) one of the game's pictures on `tex`. Done with the
-- picture's own file and position, never SetAtlas: on this client a texture that has been
-- through SetAtlas and a crop (or the other way round) can come out blank or stale when it
-- is reused for another picture.
local function ShowAtlas(tex, name, from, to)
    local info = C_Texture.GetAtlasInfo(name)
    from, to = from or 0, to or 1
    local l, r = info.leftTexCoord, info.rightTexCoord
    tex:SetTexture(info.file or info.filename)
    tex:SetTexCoord(l + (r - l) * from, l + (r - l) * to, info.topTexCoord, info.bottomTexCoord)
end

-- Ctrl and Alt pressed alone read as words on their keys (Shift is the arrow picture).
local MOD_LABEL = { CTRL = "Ctrl", ALT = "Alt" }
-- The side buttons: the white mouse with a white 4 or 5 in its middle, on a small dark pill so
-- it reads, and a red arc on the mouse's left edge for the button pressed (Icons/side_*.tga):
-- the upper one forward (5), the lower one back (4). Buttons 6 and up (an MMO mouse's extra
-- side buttons): the same mouse and number, with no arc (where they sit differs by mouse).
local function SideLabel(mouseName) return mouseName and mouseName:match("^MB(%d+)$") end
local SIDE_ARC = { MB4 = "lower", MB5 = "upper" }
local OTHER_ARC = { lower = "upper", upper = "lower" } -- the button not pressed: faded grey
-- Long key names get the short labels printed on keyboards, so they stay readable.
local KEYCAP = {
    ESCAPE = "ESC", PAGEUP = "Pg\nUp", PAGEDOWN = "Pg\nDn", BACKSPACE = "BKSP", CAPSLOCK = "CAPS",
    INSERT = "INS", DELETE = "DEL", META = "WIN",
    NUMLOCK = "NUM", PRINTSCREEN = "PRSC", SCROLLLOCK = "SCRL", TAB = "Tab",
    -- The arrow keys as plain arrows (JetBrains Mono has them).
    LEFT = "\226\134\144", UP = "\226\134\145", RIGHT = "\226\134\146", DOWN = "\226\134\147",
}
-- Keys drawn as one large symbol: no outline (it doubles thin lines), nudged to the middle.
local SYMBOL_KEY = { LEFT = true, UP = true, RIGHT = true, DOWN = true }
-- Keys shaped like the real ones (width, height), the whole word on them, in the usual slot:
-- Space, Enter, Ctrl and Alt are wide and flat (Space the flattest).
local WIDE_KEY = { SPACE = { 42, 16 }, ENTER = { 42, 20 }, CTRL = { 42, 20 }, ALT = { 42, 20 }, TAB = { 42, 20 } }
-- Ctrl, Alt and Tab match: one text size (Ctrl a touch smaller, it is the longest word).
local FIXED_SIZE = { CTRL = 11, ALT = 12, TAB = 12 }
-- Shift and Backspace: a fat hollow arrow picture (Icons/shift.tga), up or turned left.
local ARROW_KEY = { SHIFT = 0, BACKSPACE = math.pi / 2 }
local ARROW_ICON = MEDIA .. "Icons/shift.tga"
-- Punctuation sits high or low in the font: moved to the middle of the square.
local PUNCT_NUDGE = { ["."] = 5, [","] = 4, [";"] = 2, [":"] = 1, ["`"] = -5, ["'"] = -5, ["-"] = 0 }
local function Keycap(name)
    return KEYCAP[name] or name:gsub("^NUMPAD", "N")
end
-- Held with another key, the modifiers read as short words above it.
local MOD_WORD = { SHIFT = "SHFT", CTRL = "CTRL", ALT = "ALT" }
local function SplitMods(key)
    local mods, rest = {}, key
    while true do
        local m, after = rest:match("^(%u+)%-(.+)$")
        if not (m and MOD_WORD[m]) then break end
        mods[#mods + 1] = MOD_WORD[m]
        rest = after
    end
    return table.concat(mods, " "), rest
end
local function Pretty(key)
    local mods, name = key:match("^(.-)(%u+)$")
    if name and PRESS_ICON[name] then return mods .. PRESS_ICON[name] end
    return key
end

-- Shows `lines` (a function returning them, so they follow the current state) on hover. The
-- first is the tooltip's title (the game draws it larger); the rest are normal lines.
local function Tip(frame, lines, onEnter, onLeave)
    frame:SetScript("OnEnter", function(self)
        if onEnter then onEnter(self) end
        if dragging or sizing or (menu and menu:IsShown()) then return end
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        for i, line in ipairs(lines()) do
            if i == 1 then GameTooltip:SetText(line, 1, 1, 1) else GameTooltip:AddLine(line, 1, 1, 1) end
        end
        GameTooltip:Show()
        Beside(GameTooltip)
    end)
    frame:SetScript("OnLeave", function(self)
        if onLeave then onLeave(self) end
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
end
local function RefreshTip(frame)
    if GameTooltip:IsOwned(frame) then frame:GetScript("OnEnter")(frame) end
end

local function Gold(self) self.icon:SetVertexColor(1, 0.82, 0) end
local function Plain(self) self.icon:SetVertexColor(1, 1, 1) end

local close = BarButton()
local closeText = close:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
closeText:SetPoint("CENTER", 0, 2)
closeText:SetText("x")
Tip(close, function() return { "Quit IMO" } end,
    function() closeText:SetTextColor(1, 0.3, 0.3) end,
    function() closeText:SetTextColor(1, 1, 1) end)

-- The lock: gold while locked, grey while unlocked.
local lock = BarButton(close)
lock.icon = lock:CreateTexture(nil, "OVERLAY")
lock.icon:SetSize(12, 14)
lock.icon:SetPoint("CENTER")
lock.icon:SetTexture("Interface/LFGFrame/UI-LFG-ICON-LOCK")
lock.icon:SetDesaturated(true) -- (tinted below)
local function LockLook(hover)
    if db.locked then
        lock.icon:SetVertexColor(1, hover and 0.9 or 0.82, hover and 0.3 or 0)
        lock.icon:SetAlpha(1)
    else
        local g = hover and 0.85 or 0.62
        lock.icon:SetVertexColor(g, g, g + 0.02)
        lock.icon:SetAlpha(0.85)
    end
end

-- The sort order arrow points to where new presses appear: at the bar, or at the far end.
local ARROW = "Interface/ChatFrame/ChatFrameExpandArrow" -- points right
local function ArrowWay() return db.newestAtBar and OPPOSITE[db.mode] or db.mode end
local function ArrowIcon()
    local way = ArrowWay()
    if way == "up" or way == "down" then
        return "|TInterface/Buttons/Arrow-" .. (way == "up" and "Up" or "Down") .. "-Up:14:14|t"
    end
    return "|T" .. ARROW .. ":14:14:0:0:32:32:" .. (way == "right" and "0:32" or "32:0") .. ":0:32|t"
end
local arrow = BarButton(lock)
arrow.icon = arrow:CreateTexture(nil, "OVERLAY")
arrow.icon:SetSize(12, 12)
arrow.icon:SetPoint("CENTER")
arrow.icon:SetTexture(ARROW)
arrow:RegisterForClicks("LeftButtonUp", "RightButtonUp")
Tip(arrow, function()
    return { ArrowIcon() .. " Sort Order", LMB .. " Switch side the list grows", RMB .. " Switch old/new order" }
end, Gold, Plain)


-- Unlocked: an outline of the room the presses may take, with a resize grip.
local area = CreateFrame("Frame", nil, clip, "BackdropTemplate")
area:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
area:SetBackdropBorderColor(1, 0.82, 0, 0.35)
area:EnableMouse(false)

local grip = CreateFrame("Button", nil, area)
grip:SetSize(16, 16)
grip.icon = grip:CreateTexture(nil, "OVERLAY")
grip.icon:SetAllPoints()
grip.icon:SetTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")

-- Rows (below or above the bar) and keys (beside it), made as needed.
local rows, keysShown = {}, {}
local function Row(i)
    if rows[i] then return rows[i] end
    local row = CreateFrame("Frame", nil, list)
    row:SetHeight(ROW_HEIGHT)
    row.key = row:CreateFontString(nil, "OVERLAY")
    row.key:SetFont(MONO, 12, "OUTLINE")
    row.key:SetPoint("LEFT", 9, 0)
    row.key:SetJustifyH("LEFT")
    row.time = row:CreateFontString(nil, "OVERLAY")
    row.time:SetFont(MONO, 9, "")
    row.time:SetShadowOffset(1, -1)
    row.time:SetPoint("RIGHT", -8, 0)
    row.time:SetJustifyH("RIGHT")
    row.action = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.action:SetPoint("LEFT", row.key, "RIGHT", 6, 0)
    row.action:SetPoint("RIGHT", row.time, "LEFT", -6, 0)
    row.action:SetJustifyH("LEFT")
    row.action:SetWordWrap(false)
    row:Hide()
    rows[i] = row
    return row
end

-- A sideways key: its own small rounded box, the time under it.
local function Key(i)
    if keysShown[i] then return keysShown[i] end
    local k = CreateFrame("Frame", nil, list)
    k:SetHeight(KEY_HEIGHT)
    k.box = CreateFrame("Frame", nil, k, "BackdropTemplate")
    k.box:SetBackdrop(CAP)
    k.box:SetBackdropColor(0.07, 0.07, 0.08, 0.92)
    k.box:SetBackdropBorderColor(unpack(BORDER))
    k.box:SetPoint("TOP")
    k.box:SetSize(CAP_SIZE, CAP_SIZE)
    -- Text and pictures sit on a layer above the square (a child frame draws over its parent).
    local top = CreateFrame("Frame", nil, k)
    top:SetAllPoints()
    top:SetFrameLevel(k.box:GetFrameLevel() + 1)
    k.key = top:CreateFontString(nil, "OVERLAY")
    k.key:SetFont(MONO, 13, "OUTLINE")
    k.key:SetPoint("CENTER", k.box, "CENTER", 0, 0)
    k.icon = top:CreateTexture(nil, "ARTWORK")
    k.icon:SetSize(CAP_SIZE - 2, CAP_SIZE - 2)
    k.icon:SetPoint("CENTER", k.box, "CENTER")
    -- The Windows key: four small squares in a 2 x 2 grid.
    k.win = {}
    for row = 0, 1 do
        for col = 0, 1 do
            local sq = top:CreateTexture(nil, "OVERLAY")
            sq:SetColorTexture(1, 1, 1, 1)
            sq:SetSize(6, 6)
            sq.dx, sq.dy = (col - 0.5) * 7.5, (0.5 - row) * 7.5
            sq:Hide()
            k.win[#k.win + 1] = sq
        end
    end
    k.arrow = top:CreateTexture(nil, "OVERLAY")
    k.arrow:SetTexture(ARROW_ICON)
    k.arrow:SetSize(20, 20)
    k.arrow:Hide()
    k.icon2 = top:CreateTexture(nil, "ARTWORK") -- the middle click's right half (see below)
    k.icon2:SetSize((CAP_SIZE - 2) / 2, CAP_SIZE - 2)
    k.icon2:SetPoint("LEFT", k.box, "CENTER")
    k.icon2:Hide()
    k.sideArc = top:CreateTexture(nil, "OVERLAY", nil, 1) -- a side button's red arc
    k.sideArc:SetSize(CAP_SIZE - 2, CAP_SIZE - 2)
    k.sideArc:SetPoint("CENTER", k.box, "CENTER")
    k.sideArc:SetVertexColor(0.9, 0.16, 0.12, 1)
    k.sideArc:Hide()
    k.otherArc = top:CreateTexture(nil, "OVERLAY", nil, 1)
    k.otherArc:SetSize(CAP_SIZE - 2, CAP_SIZE - 2)
    k.otherArc:SetPoint("CENTER", k.box, "CENTER")
    k.otherArc:SetVertexColor(0.6, 0.6, 0.64, 0.5)
    k.otherArc:Hide()
    k.pill = top:CreateTexture(nil, "OVERLAY", nil, 1) -- behind a side button's number
    k.pill:SetTexture(DISC)
    k.pill:SetVertexColor(0.05, 0.05, 0.06, 0.8)
    k.pill:SetSize(8, 10)
    k.pill:SetPoint("CENTER", k.box, "CENTER", 0, -1)
    k.pill:Hide()
    k.wheel = top:CreateTexture(nil, "OVERLAY", nil, 1) -- the red wheel over the mouse picture
    k.wheel:SetColorTexture(0.86, 0.16, 0.13, 1)
    k.wheel:Hide()
    k.count = top:CreateFontString(nil, "OVERLAY") -- "x3": that many wheel notches in a row
    k.count:SetFont(MONO, 10, "OUTLINE")
    k.count:SetPoint("BOTTOMRIGHT", k.box, "BOTTOMRIGHT", 4, -1)
    -- Held modifiers: plain words (SHFT, CTRL, ALT) on the panel's top edge above this key
    -- (outside the panel, which clips what it holds, so they hang from the bar instead).
    k.modBox = CreateFrame("Frame", nil, monitor)
    k.modBox:SetFrameLevel(LEVEL + 5)
    k.modBox:SetHeight(15)
    k.modBox:Hide()
    k.mods = k.modBox:CreateFontString(nil, "OVERLAY")
    k.mods:SetFont(MONO, 9, "OUTLINE")
    k.mods:SetPoint("CENTER", 0, 0)
    k:HookScript("OnHide", function() k.modBox:Hide() end)

    k.time = k:CreateFontString(nil, "OVERLAY")
    k.time:SetFont(MONO, 9, "OUTLINE")
    k.time:SetPoint("BOTTOM", 0, 1)
    k:Hide()
    keysShown[i] = k
    return k
end

-- Layout --------------------------------------------------------------------------------
-- The bar's home is where it was dragged to (its bottom-left corner). When the presses would
-- run off the screen, the bar moves just far enough, and back as they fade.
local function RowsHeight(shown)
    return shown > 0 and (shown * ROW_HEIGHT + 2 * PAD) or 0
end

local function Bounds(shown)
    local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
    local w, h = BarWidth(), BarHeight()
    local minX, maxX = 0, math.max(0, screenW - w)
    local minY, maxY = 0, screenH - h
    if Sideways() then
        -- Keys may be taller than the bar and are centred on it: keep them on screen too.
        local over = shown > 0 and math.max(0, (KEY_HEIGHT + 2 * KEY_PAD - h) / 2) or 0
        minY, maxY = over, maxY - over
    else
        local room = shown > 0 and (RowsHeight(shown) + GAP) or 0
        if db.mode == "up" then maxY = maxY - room else minY = room end
    end
    return minX, maxX, minY, math.max(minY, maxY)
end

local function PlaceBar(shown)
    if dragging then return end
    local minX, maxX, minY, maxY = Bounds(shown)
    -- Until it is first dragged: on the left edge, a third of the way up.
    local x = math.max(minX, math.min(db.x or 0, maxX))
    local y = math.max(minY, math.min(db.y or UIParent:GetHeight() * 0.325, maxY))
    local _, _, _, cx, cy = monitor:GetPoint()
    if monitor:GetNumPoints() ~= 1 or math.abs((cx or 0) - x) > 0.5 or math.abs((cy or 0) - y) > 0.5 then
        monitor:ClearAllPoints()
        monitor:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
    end
end

local function Relayout()
    monitor:SetSize(BarWidth(), BarHeight())
    full:SetShown(not Compact())
    tabText:SetShown(Compact())
    -- The pill end: radius half the plate's thickness; the light sits in its middle.
    local r = (Compact() and BarWidth() or BarHeight()) / 2
    local side = Compact() and "bottom" or "left"
    if plate.side ~= side then
        plate.side = side
        plate:SetBackdrop(PILL[side])
        plate:SetBackdropColor(unpack(BAR_COLOR))
        plate:SetBackdropBorderColor(unpack(BORDER))
    end
    plate:ClearAllPoints()
    edge:ClearAllPoints()
    disc:ClearAllPoints()
    led:ClearAllPoints()
    tabText:ClearAllPoints()
    -- Only the outer half of the circle is drawn (no border inside the pill).
    local fill = r - PILL_LINE_IN
    local seam, corners
    if not Compact() then
        plate:SetPoint("TOPLEFT", r - 12, 0)
        plate:SetPoint("BOTTOMRIGHT")
        for _, t in ipairs({ edge, disc }) do
            t:SetTexCoord(0, 0.5, 0, 1)
            t:SetPoint("RIGHT", monitor, "LEFT", r, 0)
        end
        edge:SetSize(r, 2 * r)
        disc:SetSize(fill, 2 * fill)
        led:SetSize(17, 17)
        led:SetPoint("CENTER", monitor, "LEFT", r, LED_DROP)
        seam, corners = "LeftEdge", { "TopLeftCorner", "BottomLeftCorner" }
    else
        plate:SetPoint("TOPLEFT")
        plate:SetPoint("BOTTOMRIGHT", 0, r - 12)
        for _, t in ipairs({ edge, disc }) do
            t:SetTexCoord(0, 1, 0.5, 1)
            t:SetPoint("TOP", monitor, "BOTTOM", 0, r)
        end
        edge:SetSize(2 * r, r)
        disc:SetSize(2 * fill, fill)
        led:SetSize(17, 17)
        led:SetPoint("CENTER", monitor, "BOTTOM", 0, r + LED_DROP)
        seam, corners = "BottomEdge", { "BottomLeftCorner", "BottomRightCorner" }
        -- The tab stands beside the keys and "/imo" reads bottom to top, centred in the space
        -- above the round end. Turned text is drawn about 13 px higher and 5 px right of its
        -- anchor (measured in game). A client without text rotation gets the letters stacked.
        local mid = r -- (the space above the round end is centred r above the tab's middle)
        if tabText.SetRotation then
            tabText:SetRotation(math.pi / 2)
            tabText:SetText("/imo")
            tabText:SetPoint("CENTER", -5, mid - 13)
        else
            tabText:SetText("/\ni\nm\no")
            tabText:SetPoint("CENTER", 0, mid)
        end
    end
    -- (The border pieces are reused when the round side changes: show them all again first,
    -- or the last side's hidden ones stay hidden.)
    for _, piece in ipairs({ "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
        "TopEdge", "BottomEdge", "LeftEdge", "RightEdge" }) do
        if plate[piece] then plate[piece]:Show() end
    end
    for _, piece in ipairs(corners) do
        if plate[piece] then plate[piece]:Hide() end
    end
    if plate[seam] then plate[seam]:Hide() end
    -- The arrow is drawn a little left of the middle of its texture; turned, that offset turns
    -- too, so shift it back the way it points.
    local angle = ANGLE[ArrowWay()]
    arrow.icon:SetRotation(angle)
    arrow.icon:ClearAllPoints()
    arrow.icon:SetPoint("CENTER", 1.5 * math.cos(angle), 1.5 * math.sin(angle))
    LockLook(lock:IsMouseOver())

    -- Rows and sideways keys both sit in the rounded panel, which grows and shrinks with them.
    list:SetBackdropColor(0.04, 0.04, 0.05, 0.55)
    list:SetBackdropBorderColor(unpack(BORDER))
    -- The cut: just inside the tab's edge (under its border line), as far as the screen goes.
    clip:ClearAllPoints()
    if db.mode == "right" then
        clip:SetPoint("TOPLEFT", monitor, "TOPRIGHT", -2, 0)
        clip:SetPoint("BOTTOMLEFT", monitor, "BOTTOMRIGHT", -2, 0)
        clip:SetPoint("RIGHT", UIParent, "RIGHT")
    elseif db.mode == "left" then
        clip:SetPoint("TOPRIGHT", monitor, "TOPLEFT", 2, 0)
        clip:SetPoint("BOTTOMRIGHT", monitor, "BOTTOMLEFT", 2, 0)
        clip:SetPoint("LEFT", UIParent, "LEFT")
    elseif db.mode == "up" then
        clip:SetPoint("BOTTOM", monitor, "TOP", 0, -2)
        clip:SetPoint("TOP", UIParent, "TOP")
        clip:SetPoint("LEFT", UIParent, "LEFT")
        clip:SetPoint("RIGHT", UIParent, "RIGHT")
    else
        clip:SetPoint("TOP", monitor, "BOTTOM", 0, 2)
        clip:SetPoint("BOTTOM", UIParent, "BOTTOM")
        clip:SetPoint("LEFT", UIParent, "LEFT")
        clip:SetPoint("RIGHT", UIParent, "RIGHT")
    end
    list:ClearAllPoints()
    if db.mode == "up" then
        list:SetPoint("BOTTOMLEFT", monitor, "TOPLEFT", HANG, -TUCK) -- (its end tucks under the bar)
        list:SetWidth(db.width)
    elseif db.mode == "down" then
        list:SetPoint("TOPLEFT", monitor, "BOTTOMLEFT", HANG, TUCK)
        list:SetWidth(db.width)
    elseif db.mode == "right" then
        list:SetPoint("LEFT", monitor, "RIGHT", -TUCK, KEY_RAISE)
        list:SetHeight(KEY_HEIGHT + 2 * KEY_PAD)
    else
        list:SetPoint("RIGHT", monitor, "LEFT", TUCK, KEY_RAISE)
        list:SetHeight(KEY_HEIGHT + 2 * KEY_PAD)
    end
    for i, row in ipairs(rows) do
        row:ClearAllPoints()
        row:SetWidth(db.width)
        if db.mode == "up" then
            row:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", 0, TUCK + GAP + PAD + (i - 1) * ROW_HEIGHT)
        else
            row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -TUCK - GAP - PAD - (i - 1) * ROW_HEIGHT)
        end
        if Sideways() then row:Hide() end
    end
    if not Sideways() then
        for _, k in ipairs(keysShown) do k:Hide() end
    end

    area:ClearAllPoints()
    area:SetSize(db.width, RowsHeight(db.rows) + TUCK + GAP)
    grip:ClearAllPoints()
    if Sideways() then
        -- Sideways, unlocking only sets how many keys show: the outline is the room they take
        -- (up to the screen's edge), the grip at its far end.
        local fixed = TUCK + GAP + 2 * KEY_PAD - KEY_GAP
        local room = db.mode == "right" and (UIParent:GetWidth() - (monitor:GetRight() or 0))
            or (monitor:GetLeft() or 0)
        area:SetSize(math.min(fixed + db.keyCount * (KEY_WIDTH + KEY_GAP), room + TUCK), KEY_HEIGHT + 2 * KEY_PAD)
        if db.mode == "right" then
            area:SetPoint("LEFT", monitor, "RIGHT", -TUCK, KEY_RAISE)
            grip:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -1, 1)
            grip.icon:SetTexCoord(0, 1, 0, 1)
        else
            area:SetPoint("RIGHT", monitor, "LEFT", TUCK, KEY_RAISE)
            grip:SetPoint("BOTTOMLEFT", area, "BOTTOMLEFT", 1, 1)
            grip.icon:SetTexCoord(1, 0, 0, 1) -- the grabber points down-left
        end
    elseif db.mode == "up" then
        area:SetPoint("BOTTOMLEFT", monitor, "TOPLEFT", HANG, -TUCK)
        grip:SetPoint("TOPRIGHT", area, "TOPRIGHT", -1, -1)
        grip.icon:SetTexCoord(0, 1, 1, 0) -- the grabber points up-right
    else
        area:SetPoint("TOPLEFT", monitor, "BOTTOMLEFT", HANG, TUCK)
        grip:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -1, 1)
        grip.icon:SetTexCoord(0, 1, 0, 1)
    end
    area:SetShown(not db.locked)
end

local function FormatDelta(delta)
    if not delta then return "|cff808080first|r" end
    if delta < 1 then return string.format("+%d ms", math.floor(delta * 1000 + 0.5)) end
    if delta < 60 then return string.format("+%.2f s", delta) end
    return string.format("+%dm %02ds", math.floor(delta / 60), math.floor(delta % 60))
end

local function Alpha(e, now)
    local age = now - e.at
    if age <= db.hold then return 1 end
    return db.fade > 0 and math.max(0, 1 - (age - db.hold) / db.fade) or 0
end

local function KeyText(e)
    return (e == entries[1] and "|cffffffff" or "|cffd8d8d8") .. Pretty(e.key) .. "|r"
end

local function RenderRows(now, n)
    for i = 1, math.max(n, #rows) do
        -- Row 1 is next to the bar: the newest press, or (newest at the far end) the oldest.
        local e = db.newestAtBar and entries[i] or entries[n - i + 1]
        if e then
            local row = Row(i)
            if not row.placed then
                row.placed = true
                Relayout()
            end
            row.key:SetText(KeyText(e))
            row.action:SetText(db.showAction and e.action or "")
            row.time:SetText(FormatDelta(e.delta) .. (db.showClock and ("  |cff808080" .. e.clock .. "|r") or ""))
            row:SetAlpha(Alpha(e, now))
            row:Show()
        elseif rows[i] then
            rows[i]:Hide()
        end
    end
    listTarget = n > 0 and (RowsHeight(n) + TUCK + GAP) or 0
end

local function RenderKeys(now, n)
    -- Keys run out from the bar until the screen edge; the rest wait off screen.
    local room = db.mode == "right" and (UIParent:GetWidth() - (monitor:GetRight() or 0))
        or (monitor:GetLeft() or 0)
    room = room - GAP - 2 * KEY_PAD
    local used, shown = 0, 0
    local side = db.mode == "right" and "LEFT" or "RIGHT"
    local sign = db.mode == "right" and 1 or -1
    for i = 1, math.max(n, #keysShown) do
        local e = db.newestAtBar and entries[i] or entries[n - i + 1]
        local k = e and Key(i) or keysShown[i]
        if e then
            if k.name ~= e.key then
                k.name = e.key
                -- Left and right mouse: the game's mouse picture, no box. Middle and side
                -- buttons: a white mouse (red wheel; or 4 / 5 and an arc). The wheel turned: its
                -- own picture. Keyboard: a square key.
                local mods, main = SplitMods(e.key)
                local plain = MOUSE_ATLAS.LMB -- (the fallback mouse, if the white one cannot be made)
                local wheelTex = e.mouse and WHEEL_ICON[e.mouse]
                local middle = e.mouse == "MMB"
                local atlas = e.mouse and not wheelTex and (MOUSE_ATLAS[e.mouse] or plain)
                local side = e.mouse and not middle and not MOUSE_ATLAS[e.mouse] and SideLabel(e.mouse)
                local pictured = (atlas or wheelTex) and true or false
                k.box:SetShown(not e.mouse)
                k.icon:SetShown(pictured)
                k.key:SetShown(not pictured or side and true or false)
                k.mods:SetText(mods)
                k.hasMods = mods ~= ""
                k.modBox:SetWidth(math.max(18, k.mods:GetStringWidth() + 10))
                k.label = side or MOD_LABEL[main] or Keycap(main)
                k.wheel:ClearAllPoints()
                k.wheel:SetShown(middle and atlas and true or false)
                k.pill:SetShown(side and atlas and true or false)
                k.pill:SetWidth(side and #side > 1 and 13 or 8) -- (wider for 10 and up)
                local arc = side and atlas and SIDE_ARC[e.mouse]
                k.sideArc:SetShown(arc and true or false)
                k.otherArc:SetShown(arc and true or false)
                if arc then
                    k.sideArc:SetTexture(MEDIA .. "Icons/side_" .. arc .. ".tga")
                    k.otherArc:SetTexture(MEDIA .. "Icons/side_" .. OTHER_ARC[arc] .. ".tga")
                end
                -- The white mouse: the left half of the right-click picture and the right half
                -- of the left-click one (each half's button is the white one).
                local halves = (middle or side) and MOUSE_ATLAS.LMB and MOUSE_ATLAS.RMB
                k.icon:ClearAllPoints()
                if halves then
                    k.icon:SetSize((CAP_SIZE - 2) / 2, CAP_SIZE - 2)
                    k.icon:SetPoint("RIGHT", k.box, "CENTER")
                else
                    k.icon:SetSize(CAP_SIZE - 2, CAP_SIZE - 2)
                    k.icon:SetPoint("CENTER", k.box, "CENTER")
                end
                k.icon2:SetShown(halves and true or false)
                if wheelTex then
                    k.icon:SetTexture(wheelTex)
                    k.icon:SetTexCoord(0, 1, 0, 1)
                    k.icon:SetDesaturated(false)
                    k.icon:SetAlpha(1)
                elseif halves then
                    -- (A sliver is left off at the seam: the other button's red starts there.)
                    ShowAtlas(k.icon, MOUSE_ATLAS.RMB, 0, 0.45)
                    ShowAtlas(k.icon2, MOUSE_ATLAS.LMB, 0.55, 1)
                    for _, tex in ipairs({ k.icon, k.icon2 }) do
                        tex:SetDesaturated(false)
                        tex:SetAlpha(1)
                    end
                    if middle then
                        k.wheel:SetSize(2, 5)
                        k.wheel:SetPoint("CENTER", k.box, "CENTER", 0, (0.5 - WHEEL_AT[2]) * (CAP_SIZE - 2))
                    end
                elseif atlas then
                    ShowAtlas(k.icon, atlas)
                    k.icon:SetDesaturated((side or middle) and true or false)
                    k.icon:SetAlpha(side and 0.45 or 1)
                    local size = k.icon:GetWidth()
                    local wx, wy = (WHEEL_AT[1] - 0.5) * size, (0.5 - WHEEL_AT[2]) * size
                    if middle then
                        k.wheel:SetSize(3, 7)
                        k.wheel:SetPoint("CENTER", k.icon, "CENTER", wx, wy)
                    end
                end
                -- Space, Enter, Ctrl, Alt and Tab: wide, flat keys in the same slot.
                local flat = not e.mouse and WIDE_KEY[main]
                k.box:ClearAllPoints()
                if flat then
                    k.box:SetSize(flat[1], flat[2])
                    k.box:SetPoint("TOP", 0, -(CAP_SIZE - flat[2]) / 2)
                else
                    k.box:SetSize(CAP_SIZE, CAP_SIZE)
                    k.box:SetPoint("TOP")
                end
                local winKey = not e.mouse and main == "META"
                for _, sq in ipairs(k.win) do sq:SetShown(winKey) end
                local turn = not e.mouse and ARROW_KEY[main]
                k.arrow:SetShown(turn and true or false)
                if turn then k.arrow:SetRotation(turn) end
                if winKey or turn then k.key:Hide() end
                if side then
                    k.key:SetText(k.label)
                    k.key:SetFont(MONO, 9, "")
                elseif SYMBOL_KEY[main] and not atlas then
                    k.key:SetText(k.label)
                    k.key:SetFont(MONO, 17, "")
                elseif not atlas then
                    -- Big on the key (so labels and the times below never get mixed up); longer
                    -- names step down until they fit.
                    k.key:SetText(k.label)
                    local size = FIXED_SIZE[main] or 16
                    k.key:SetFont(MONO, size, "OUTLINE")
                    while not FIXED_SIZE[main] and size > 7 and k.key:GetStringWidth() > k.box:GetWidth() - 6 do
                        size = size - 1
                        k.key:SetFont(MONO, size, "OUTLINE")
                    end
                end
                k.key:ClearAllPoints()
                if side then
                    k.key:SetPoint("CENTER", k.pill, "CENTER", 0.5, 0)
                elseif SYMBOL_KEY[main] then
                    -- The arrow glyphs sit a little high and left of the font's middle.
                    k.key:SetPoint("CENTER", k.box, "CENTER", 0.5, -1.5)
                else
                    k.key:SetPoint("CENTER", k.box, "CENTER", 0, PUNCT_NUDGE[main] or 0)
                end
                k.arrow:ClearAllPoints()
                k.arrow:SetPoint("CENTER", k.box, "CENTER")
                for _, sq in ipairs(k.win) do
                    sq:ClearAllPoints()
                    sq:SetPoint("CENTER", k.box, "CENTER", sq.dx, sq.dy)
                end
            end
            k.key:SetText((e == entries[1] and "|cffffffff" or "|cffd8d8d8") .. k.label .. "|r")
            local bright = e == entries[1] and 1 or 0.85
            k.icon:SetVertexColor(bright, bright, bright)
            k.icon2:SetVertexColor(bright, bright, bright)
            for _, sq in ipairs(k.win) do sq:SetVertexColor(bright, bright, bright) end
            k.arrow:SetVertexColor(bright, bright, bright)
            k.count:SetText((e.count or 1) > 1 and ("x" .. e.count) or "")
            k.time:SetText(FormatDelta(e.delta))
            local shade = e.alt and 0.68 or 1
            k.time:SetTextColor(shade, shade, shade)
            local w = KEY_WIDTH
            if used + w > room then
                k:Hide()
            else
                k:SetWidth(w)
                k:ClearAllPoints()
                k:SetPoint(side, list, side, sign * (TUCK + GAP + KEY_PAD + used), 0)
                k:SetAlpha(Alpha(e, now))
                k:Show()
                -- The modifier key, centred on the panel's top edge; only once the panel has
                -- grown out to this key (the panel's clipping does not reach it).
                local reached = TUCK + GAP + KEY_PAD + used + w <= listSize + 0.5
                if k.hasMods and reached then
                    k.modBox:ClearAllPoints()
                    k.modBox:SetPoint("CENTER", k, "TOP", 0, KEY_PAD)
                    k.modBox:SetAlpha(Alpha(e, now))
                    k.modBox:Show()
                else
                    k.modBox:Hide()
                end
                used = used + w + KEY_GAP
                shown = shown + 1
            end
        elseif k then
            k:Hide()
        end
    end
    listTarget = shown > 0 and (TUCK + GAP + used - KEY_GAP + 2 * KEY_PAD) or 0
end

local function Render()
    local now, n = GetTime(), #entries
    if Sideways() then RenderKeys(now, n) else RenderRows(now, n) end
    -- The light: red while paused; otherwise green, flashing on each press.
    local colour = db.paused and "Red" or "Green"
    if led.colour ~= colour then
        led.colour = colour
        led:SetTexture("Interface/COMMON/Indicator-" .. colour)
    end
    if db.paused then
        led:SetDesaturated(false)
        led:SetAlpha(0.9)
    else
        local flash = lastAt and math.max(0, 1 - (now - lastAt) / 0.3) or 0
        led:SetDesaturated(n == 0 and flash == 0)
        led:SetAlpha(math.max(n > 0 and 0.55 or 0.3, flash))
    end
    -- Unlocked with rows: keep room for every row (so the resize outline stays on screen).
    local outline = not db.locked and not Compact() and not Sideways()
    PlaceBar(outline and db.rows or n)
end

-- The presses' frame eases toward its target length every frame (one resize while moving).
local function EaseList(elapsed)
    -- Growing is instant (the panel never clips a new press while catching up); only
    -- shrinking eases.
    if listTarget >= listSize or math.abs(listSize - listTarget) < 0.5 then
        listSize = listTarget
    else
        listSize = listSize + (listTarget - listSize) * math.min(1, elapsed * 16)
    end
    -- Below the border's own size the rounded corners would bunch up: gone instead.
    if listSize < 14 and listTarget == 0 then
        if list:IsShown() then list:Hide() end
        return
    end
    if not list:IsShown() then list:Show() end
    local size = math.max(14, listSize)
    if Sideways() then
        if math.abs(list:GetWidth() - size) > 0.05 then list:SetWidth(size) end
    elseif math.abs(list:GetHeight() - size) > 0.05 then
        list:SetHeight(size)
    end
end

local Drag -- moving the bar by hand, below
local sinceDraw = 0
monitor:SetScript("OnUpdate", function(_, elapsed)
    if dragging then Drag() end
    EaseList(elapsed)
    -- A few redraws a second is plenty for fading and ages.
    sinceDraw = sinceDraw + elapsed
    if sinceDraw < 0.05 then return end
    sinceDraw = 0
    -- Drop presses that have faded out completely.
    local now = GetTime()
    for i = #entries, 1, -1 do
        if now - entries[i].at > db.hold + db.fade then table.remove(entries, i) end
    end
    Render()
    EaseList(0) -- (a new press: the panel is already its size in the frame it appears)
end)

-- A change of layout: the presses' frame grows out again on its new side.
local function Rebuild()
    listSize, listTarget = 0, 0
    list:Hide()
    Relayout()
    Render()
    if menu:IsShown() then Beside(menu, true) end
end

local function SetMode(mode)
    if mode == db.mode then return end
    db.mode = mode
    Trim()
    menu:Hide() -- (what it offers depends on the way)
    Rebuild()
end

-- Switching side by hand (the arrow, the menu): the bar stays where it is now (it may have
-- been pushed out of the way of its list), so it does not jump out from under the pointer.
local function SwitchSide()
    if monitor:GetLeft() then db.x, db.y = monitor:GetLeft(), monitor:GetBottom() end
    SetMode(OPPOSITE[db.mode])
end

-- Moving (always) and resizing (unlocked) ---------------------------------------------------
local grabX, grabY
local nearEdge = {} -- which screen edges the bar was within EDGE of, last frame of the drag
local function Cursor()
    local scale = monitor:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    return cx / scale, cy / scale
end
-- Which screen edges the pointer at (cx, cy) is within EDGE of.
local function NearEdges(cx, cy)
    -- Measured from the pointer, not the bar: the bar changes shape when it turns into the tab
    -- (and back), which would make it seem near other edges at once and flip again.
    local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
    local d = { left = cx, right = screenW - cx, bottom = cy, top = screenH - cy }
    local near = {}
    for edge, dist in pairs(d) do
        if dist < EDGE then near[edge] = dist end
    end
    return near
end

local wasDragged = false -- this press became a drag (so letting go is not a click)
monitor:SetScript("OnMouseDown", function() wasDragged = false end)
monitor:SetScript("OnDragStart", function(self)
    -- The bar always drags; the lock only hides the outline and resize grip.
    wasDragged = true
    GameTooltip:Hide()
    if menu then menu:Hide() end
    local cx, cy = Cursor()
    grabX, grabY = cx - self:GetLeft(), cy - self:GetBottom()
    nearEdge = NearEdges(cx, cy) -- where it starts never switches it
    dragging = true
end)
monitor:SetScript("OnDragStop", function(self)
    dragging = false
    db.x, db.y = self:GetLeft(), self:GetBottom()
end)
function Drag()
    if not IsMouseButtonDown("LeftButton") then
        dragging = false
        db.x, db.y = monitor:GetLeft(), monitor:GetBottom()
        return
    end
    local cx, cy = Cursor()
    local x, y = cx - grabX, cy - grabY
    -- Intent: the presses turn when the pointer is brought near an edge it was not near
    -- already (in a corner, the edge just reached wins); or when it leaves the edge the current
    -- way belongs to while still near another (sliding out of a corner along one side). Away
    -- from every edge, they keep their way.
    local near = NearEdges(cx, cy)
    local reached, closest
    for edge, dist in pairs(near) do
        if not nearEdge[edge] and (not closest or dist < closest) then reached, closest = edge, dist end
    end
    local mine = MODE_EDGE[db.mode]
    if not reached and nearEdge[mine] and not near[mine] then -- (just left it)
        for edge, dist in pairs(near) do
            if not closest or dist < closest then reached, closest = edge, dist end
        end
    end
    nearEdge = near
    if reached and EDGE_MODE[reached] ~= db.mode then
        -- The bar turns into the tab (or back): the pointer is put on its "/imo" label, the
        -- part one holds (scaling the old hold by the change in size threw it far along
        -- the 263 px bar from the 26 px tab).
        SetMode(EDGE_MODE[reached])
        if Compact() then
            grabX, grabY = TAB_THIN / 2, (TAB_LONG + TAB_THIN) / 2
        else
            grabX, grabY = BAR_HEIGHT + 2 + 14, BAR_HEIGHT / 2
        end
        x, y = cx - grabX, cy - grabY
    end

    -- While dragging, the bar keeps only itself on screen and stays with the pointer; room for
    -- its presses is made when it is let go (PlaceBar), not by holding it back from the edge.
    local minX, maxX, minY, maxY = Bounds(0)
    x = math.max(minX, math.min(x, maxX))
    y = math.max(minY, math.min(y, maxY))
    if x - minX < SNAP then x = minX elseif maxX - x < SNAP then x = maxX end
    if y - minY < SNAP then y = minY elseif maxY - y < SNAP then y = maxY end
    monitor:ClearAllPoints()
    monitor:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
end

grip:SetScript("OnMouseDown", function()
    if db.locked then return end
    sizing = true
end)
grip:SetScript("OnMouseUp", function() sizing = false end)
grip:SetScript("OnUpdate", function()
    if not sizing then return end
    if not IsMouseButtonDown("LeftButton") then
        sizing = false
        return
    end
    local cx, cy = Cursor()
    if Sideways() then
        -- Only the number of keys: one key's room per step from the tab's edge.
        local reach = db.mode == "right" and (cx - monitor:GetRight()) or (monitor:GetLeft() - cx)
        local each = KEY_WIDTH + KEY_GAP
        local fit = math.floor((reach - GAP - 2 * KEY_PAD + KEY_GAP) / each + 0.5)
        db.keyCount = math.max(MIN_ROWS, math.min(MAX_ROWS, fit))
        Trim()
        Relayout()
        if menu:IsShown() then menu:Hide() end
        return
    end
    -- Never wider or taller than the screen leaves room for.
    local maxW = math.min(MAX_WIDTH, UIParent:GetWidth() - monitor:GetLeft() - HANG)
    local maxRows = math.min(MAX_ROWS, math.floor((UIParent:GetHeight() - BAR_HEIGHT - GAP - 2 * PAD) / ROW_HEIGHT))
    db.width = math.max(MIN_WIDTH, math.min(maxW, math.floor(cx - monitor:GetLeft() - HANG + 0.5)))
    local reach = db.mode == "up" and (cy - monitor:GetTop()) or (monitor:GetBottom() - cy)
    db.rows = math.max(MIN_ROWS, math.min(maxRows, math.floor((reach - GAP - 2 * PAD) / ROW_HEIGHT + 0.5)))
    Trim()
    Relayout()
end)

-- Popups: shared pieces ------------------------------------------------------------------
-- Is the mouse over `frame`, or within `pad` pixels of it? (The game's MouseIsOver helper is
-- missing on this client; the frames' own IsMouseOver does the same.)
local function Near(frame, pad)
    pad = pad or 0
    return frame:IsVisible() and frame:IsMouseOver(pad, -pad, -pad, pad) or false
end

-- A popup closes on Esc, a click anywhere else, or once the mouse wanders well away from it
-- (and from `keep`, frames that count as part of it).
local function Popup(name, keep)
    local f = CreateFrame("Frame", name, monitor, "BackdropTemplate")
    tinsert(UISpecialFrames, name)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(monitor:GetFrameLevel() + 20)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetBackdrop(ROUNDED)
    f:SetBackdropColor(0.07, 0.07, 0.08, 0.97)
    f:SetBackdropBorderColor(unpack(BORDER))
    f:Hide()
    local function Over(pad)
        if Near(f, pad) then return true end
        for _, other in ipairs(keep) do
            if Near(other, pad) then return true end
        end
        return false
    end
    f:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    f:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
    f:SetScript("OnEvent", function(self)
        if not Over(0) then self:Hide() end
    end)
    f:SetScript("OnUpdate", function(self)
        if IsMouseButtonDown("LeftButton") then return end -- mid slider drag
        if not Over(60) then self:Hide() end
    end)
    return f
end

-- A thin slider for a saved number. Returns it with :Bind(key, min, max, step, unit, valueText).
local function MakeSlider(parent, width)
    local s = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    s:SetOrientation("HORIZONTAL")
    s:SetSize(width, 8)
    s:SetBackdrop({ bgFile = WHITE })
    s:SetBackdropColor(1, 1, 1, 0.15)
    s:SetThumbTexture(WHITE)
    s:GetThumbTexture():SetSize(8, 14)
    s:GetThumbTexture():SetVertexColor(1, 0.82, 0)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    function s:Bind(key, minV, maxV, step, unit, valueText)
        local fmt = step < 1 and "%.1f" or "%d"
        self.bound = nil -- no saving while the range and value are set
        self:SetMinMaxValues(minV, maxV)
        self:SetValueStep(step)
        self:SetValue(db[key])
        valueText:SetText(string.format(fmt, db[key]) .. unit)
        self.bound = { key = key, step = step, fmt = fmt, unit = unit, text = valueText }
    end
    s:SetScript("OnValueChanged", function(self, v)
        local b = self.bound
        if not b then return end
        v = tonumber(string.format(b.fmt, math.floor(v / b.step + 0.5) * b.step))
        db[b.key] = v
        b.text:SetText(string.format(b.fmt, v) .. b.unit)
        Trim()
        if b.key == "rows" or b.key == "keyCount" then Relayout() end
    end)
    return s
end

local SLIDERS = {
    rows = { "Lines", MIN_ROWS, MAX_ROWS, 1, "" },
    keyCount = { "Keys", MIN_ROWS, MAX_ROWS, 1, "" },
    hold = { "Stay visible", 0.5, 10, 0.1, " s" },
    fade = { "Fade out", 0, 3, 0.1, " s" },
}

-- The menu: right-click the bar or tab. Everything lives here. ---------------------------
local flyout -- a slider that pops out beside a menu line
menu = Popup("InputMonitorOverlayMenu", {})
local MENU_W, LINE_H = 150, 18
local items = {} -- menu lines and separators, in order; laid out each time the menu opens

local menuTitle = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
menuTitle:SetPoint("TOPLEFT", 10, -8)
menuTitle:SetText("Input Monitor Overlay")

-- `show` (optional): a function saying whether the item belongs in the menu right now.
local function Separator(show)
    local t = menu:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(1, 1, 1, 0.15)
    t:SetHeight(1)
    items[#items + 1] = { frame = t, height = 9, gap = 4, show = show }
end

-- A menu line. `text` is a function (lines follow the current state); `onClick` closes the
-- menu unless it returns true; `popout` names a slider (SLIDERS key) shown beside the line.
local function Line(text, onClick, popout, show)
    local b = CreateFrame("Button", nil, menu)
    b:SetHeight(LINE_H)
    local hl = b:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    hl:Hide()
    local label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 6, 0)
    local right = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    right:SetPoint("RIGHT", -6, 0)
    b.Sync = function()
        label:SetText(text())
        right:SetText(popout and ">" or "")
    end
    b:SetScript("OnEnter", function(self)
        hl:Show()
        if popout then flyout:Open(self, popout) elseif flyout then flyout:Hide() end
    end)
    b:SetScript("OnLeave", function() hl:Hide() end)
    if onClick then
        b:SetScript("OnClick", function()
            if onClick() then
                for _, item in ipairs(items) do
                    if item.frame.Sync then item.frame.Sync() end
                end
            else
                menu:Hide()
            end
        end)
    end
    items[#items + 1] = { frame = b, height = LINE_H, gap = 0, show = show }
    return b
end

local function Checked(on, label)
    return (on and "|TInterface/Buttons/UI-CheckBox-Check:14:14|t" or "|T:14:14|t") .. " " .. label
end

local function ToggleLock()
    db.locked = not db.locked
    sizing = false
    Relayout()
end

-- Paused: nothing is recorded and the light turns red (click the light, or the menu).
local function TogglePause()
    db.paused = not db.paused
    wipe(held)
end

local function RowsOnly() return not Sideways() end

Line(function() return db.locked and "Unlock" or "Lock" end, function() ToggleLock() end)
Line(function() return db.paused and "Resume" or "Pause" end, function() TogglePause() return true end)
Separator()
Line(function() return "Lines" end, nil, "rows", RowsOnly)
Line(function() return "Keys" end, nil, "keyCount", Sideways)
Line(function() return "Life" end, nil, "hold")
Line(function() return "Fade" end, nil, "fade")
Line(function() return Checked(db.showAction, "Key bindings") end, function()
    db.showAction = not db.showAction
    return true
end, nil, RowsOnly)
Line(function() return Checked(db.showClock, "Clock time") end, function()
    db.showClock = not db.showClock
    return true
end, nil, RowsOnly)
Separator()
Line(function() return "Switch side" end, function()
    SwitchSide()
    return true
end)
Line(function() return ArrowIcon() .. " Sort order" end, function()
    db.newestAtBar = not db.newestAtBar
    Relayout()
    return true
end)
Line(function() return "Layer: " .. (STRATA_NAME[db.strata] or db.strata) end, function()
    -- Steps down through the game's layers, then back to the top.
    local nextIndex = 1
    for i, name in ipairs(STRATA) do
        if name == db.strata then nextIndex = i % #STRATA + 1 end
    end
    db.strata = STRATA[nextIndex]
    monitor:SetFrameStrata(db.strata)
    return true
end)
Separator()
local SetOpen -- below
Line(function() return "Quit " .. GOLD .. "/imo|r" end, function() SetOpen(false) end)

-- Lays the menu out with the items that belong right now.
local function LayoutMenu()
    local y = -8 - LINE_H
    for _, item in ipairs(items) do
        local f = item.frame
        if not item.show or item.show() then
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", f.Sync and 4 or 8, y - item.gap)
            f:SetPoint("TOPRIGHT", f.Sync and -4 or -8, y - item.gap)
            if f.Sync then f.Sync() end
            f:Show()
            y = y - item.height
        else
            f:Hide()
        end
    end
    menu:SetSize(MENU_W, -y + 8)
end

flyout = CreateFrame("Frame", nil, menu, "BackdropTemplate")
flyout:SetSize(170, 40)
flyout:SetFrameLevel(menu:GetFrameLevel() + 5)
flyout:SetClampedToScreen(true)
flyout:EnableMouse(true)
flyout:SetBackdrop(ROUNDED)
flyout:SetBackdropColor(0.07, 0.07, 0.08, 0.97)
flyout:SetBackdropBorderColor(unpack(BORDER))
flyout:Hide()
local flyName = flyout:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
flyName:SetPoint("TOPLEFT", 10, -7)
local flyValue = flyout:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
flyValue:SetPoint("TOPRIGHT", -10, -7)
local flySlider = MakeSlider(flyout, 150)
flySlider:SetPoint("TOPLEFT", 10, -23)
function flyout:Open(line, key)
    local spec = SLIDERS[key]
    flyName:SetText(spec[1])
    flySlider:Bind(key, spec[2], spec[3], spec[4], spec[5], flyValue)
    self:ClearAllPoints()
    if (menu:GetRight() or 0) + self:GetWidth() <= UIParent:GetWidth() then
        self:SetPoint("LEFT", line, "RIGHT", 6, 0)
    else
        self:SetPoint("RIGHT", line, "LEFT", -6, 0)
    end
    self:Show()
end
-- The flyout counts as part of the menu for closing it.
menu:SetScript("OnUpdate", function(self)
    if IsMouseButtonDown("LeftButton") then return end
    local over = Near(self, 60) or Near(flyout, 60)
    if not over then self:Hide() end
end)
menu:SetScript("OnEvent", function(self)
    if not (Near(self) or Near(flyout) or Near(monitor)) then self:Hide() end
end)
menu:HookScript("OnHide", function() flyout:Hide() end)

local function ToggleMenu()
    if menu:IsShown() then
        menu:Hide()
        return
    end
    GameTooltip:Hide()
    LayoutMenu()
    flyout:Hide()
    Beside(menu, true)
    menu:Show()
end

-- Bar clicks ----------------------------------------------------------------------------
-- Right-clicking anywhere on the bar opens the menu (the lock and close buttons included; the
-- arrow keeps its own right-click).
arrow:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
        db.newestAtBar = not db.newestAtBar
        Relayout()
    else
        SwitchSide()
    end
    RefreshTip(self)
end)
lock:RegisterForClicks("LeftButtonUp", "RightButtonUp")
lock:SetScript("OnClick", function(_, button)
    if button == "RightButton" then return ToggleMenu() end
    ToggleLock()
    RefreshTip(lock)
end)
Tip(lock, function() return { db.locked and "Unlock" or "Lock" } end,
    function() LockLook(true) end, function() LockLook(false) end)
-- The bar or tab itself: drag to move; click the light to pause or resume; right-click for
-- the menu.
monitor:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" then
        ToggleMenu()
    elseif button == "LeftButton" and not wasDragged and led:IsMouseOver() then
        TogglePause()
        RefreshTip(self)
    end
end)
Tip(monitor, function()
    return { "Input Monitor Overlay", LMB .. " Drag window", RMB .. " Menu",
        LMB .. " on the light: " .. (db.paused and "Resume" or "Pause") }
end)

-- Input ---------------------------------------------------------------------------------
-- The clock's tenths: counted from the frame its second last ticked over (the game timer's
-- own fractions run on a different beat from the wall clock).
local clockSecond, secondStart = 0, 0
local function Clock()
    local tenth = math.max(0, math.min(9, math.floor((GetTime() - secondStart) * 10)))
    return date("%H:%M:%S") .. "." .. tenth
end

local function Push(key, action, mouseName, mods)
    local now = GetTime()
    -- Sideways, the times under the keys take turns white and light grey so neighbours are
    -- easy to tell apart; with nothing on screen, the next one starts white.
    local prev = entries[1]
    local alt = prev and not prev.alt or false
    table.insert(entries, 1, {
        key = key,
        action = action,
        at = now,
        clock = Clock(),
        delta = lastAt and (now - lastAt) or nil,
        alt = alt,
        mouse = mouseName, -- "LMB", "MB4", ... for a mouse button
        mods = mods or "",
    })
    lastAt = now
    Trim()
end

local function Modifiers()
    return (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
        .. (IsShiftKeyDown() and "SHIFT-" or "")
end

-- What the key is bound to, if anything ("Toggle World Map Pane").
local function BindingLabel(fullKey)
    local action = GetBindingAction and GetBindingAction(fullKey, true)
    if not action or action == "" then return nil end
    return _G["BINDING_NAME_" .. action] or action
end

-- A keyboard frame that lets every key through to the game: it only watches.
local keys = CreateFrame("Frame", nil, UIParent)
keys:EnableKeyboard(true)
keys:SetPropagateKeyboardInput(true)
keys:Hide()
keys:SetScript("OnKeyDown", function(_, key)
    if db.paused then return end
    -- A held key repeats OnKeyDown: show it once. The game does not always report the key going
    -- up again (movement keys), so a key counts as held only while it really is down (checked
    -- each frame below) or, without a way to check, while its repeats keep coming.
    local now = GetTime()
    local last = held[key]
    held[key] = now
    if last and (IsKeyDown or now - last < 0.15) then return end
    local bare = BARE_MODIFIERS[key]
    if bare then
        Push(bare, nil)
        return
    end
    local fullKey = Modifiers() .. key
    Push(fullKey, BindingLabel(fullKey))
end)
keys:SetScript("OnKeyUp", function(_, key) held[key] = nil end)
keys:SetScript("OnUpdate", function()
    local sec = time()
    if sec ~= clockSecond then clockSecond, secondStart = sec, GetTime() end
    if not IsKeyDown then return end
    local now = GetTime()
    for key, last in pairs(held) do
        -- Some key names (the Windows key, ...) are refused by the check: those count as held
        -- only while their repeats keep coming.
        local ok, down = pcall(IsKeyDown, key)
        if ok then
            if not down then held[key] = nil end
        elseif now - last > 0.6 then
            held[key] = nil
        end
    end
end)

local mouse = CreateFrame("Frame")
mouse:SetScript("OnEvent", function(_, _, button)
    if db.paused then return end
    local mods = Modifiers()
    local name = MouseName(button)
    Push(mods .. name, BindingLabel(mods .. MouseBindName(button)), name, mods)
end)

-- The wheel. The game tells addons nothing about it (and catching it would stop the camera
-- zooming), so it is read from the camera zoom it drives: every notch over the game world.
-- Quick notches the same way add up on one press ("x3") instead of filling the list.
local function Wheel(up)
    if not keys:IsShown() or db.paused then return end
    local mods = Modifiers()
    local name = up and "WHEELUP" or "WHEELDOWN"
    local top, now = entries[1], GetTime()
    if top and top.key == mods .. name and now - top.at < 0.4 then
        top.count = (top.count or 1) + 1
        top.at = now
        lastAt = now
        return
    end
    Push(mods .. name, BindingLabel(mods .. "MOUSE" .. name), name, mods)
end
if CameraZoomIn then hooksecurefunc("CameraZoomIn", function() Wheel(true) end) end
if CameraZoomOut then hooksecurefunc("CameraZoomOut", function() Wheel(false) end) end

function SetOpen(open)
    db.open = open and true or false
    if open then
        wipe(entries)
        wipe(held)
        lastAt = nil
        listSize, listTarget = 0, 0
        list:Hide()
        keys:Show()
        mouse:RegisterEvent("GLOBAL_MOUSE_DOWN")
        Relayout()
        monitor:Show()
        Render()
    else
        keys:Hide()
        mouse:UnregisterAllEvents()
        sizing, dragging = false, false
        menu:Hide()
        monitor:Hide()
    end
end

close:RegisterForClicks("LeftButtonUp", "RightButtonUp")
close:SetScript("OnClick", function(_, button)
    if button == "RightButton" then return ToggleMenu() end
    SetOpen(false)
end)

SLASH_INPUTMONITOROVERLAY1 = "/imo"
SlashCmdList.INPUTMONITOROVERLAY = function() SetOpen(not monitor:IsShown()) end

-- Saved: position, size, which way the presses run, lock, settings, and whether it was open
-- (so it carries on after a /reload).
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON then return end
    self:UnregisterAllEvents()
    InputMonitorOverlayDB = type(InputMonitorOverlayDB) == "table" and InputMonitorOverlayDB or {}
    db = InputMonitorOverlayDB
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    if not ANGLE[db.mode] then db.mode = DEFAULTS.mode end
    if not STRATA_NAME[db.strata] then db.strata = DEFAULTS.strata end
    monitor:SetFrameStrata(db.strata)
    db.hold = math.max(0.5, math.min(db.hold, 10))
    db.fade = math.max(0, math.min(db.fade, 3))
    if db.open then SetOpen(true) end
end)
