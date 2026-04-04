--[[
=head1 NAME
applets.Spotify.SpotifyApplet - Spotify Connect for Squeezebox Touch
=head1 DESCRIPTION
Squeezeplay applet for controlling librespot Spotify Connect receiver.
On/Off radio buttons, status display, and current track.
=cut
--]]

-- Lua builtins must be declared before module(...)
local tostring  = tostring
local tonumber  = tonumber
local math      = math
local table     = table
local pairs     = pairs
local ipairs    = ipairs
local pcall     = pcall
local type      = type

local oo          = require("loop.simple")
local string      = require("string")
local Applet      = require("jive.Applet")
local RadioButton = require("jive.ui.RadioButton")
local RadioGroup  = require("jive.ui.RadioGroup")
local Window      = require("jive.ui.Window")
local SimpleMenu  = require("jive.ui.SimpleMenu")
local Popup       = require("jive.ui.Popup")
local Textarea    = require("jive.ui.Textarea")
local Group       = require("jive.ui.Group")
local io          = require("io")
local os          = require("os")

local appletManager = appletManager

module(...)
oo.class(_M, Applet)

function jiveVersion(meta) return 1, 1 end

local LOG_FILE  = "/tmp/librespot.log"
local PID_FILE  = "/tmp/librespot.pid"
local START_SH  = "/media/mmcblk0p1/spotify_start.sh"
local STOP_SH   = "/media/mmcblk0p1/spotify_stop.sh"

local function _isRunning()
    local f = io.open(PID_FILE, "r")
    if not f then return false end
    local pid = f:read("*l"); f:close()
    if not pid or pid == "" then return false end
    local s = io.open("/proc/" .. pid .. "/status", "r")
    if s then s:close(); return true end
    return false
end

local function _getNowPlaying()
    local f = io.open(LOG_FILE, "r")
    if not f then return "" end
    local last = ""
    local count = 0
    for line in f:lines() do
        count = count + 1
        if count > 500 then break end
        local t = string.match(line, "Loading <(.-)>")
        if t then last = t end
    end
    f:close()
    return last or ""
end

local function _toast(self, text)
    local p = Popup("toast_popup_text")
    p:addWidget(Group("group", {
        text = Textarea("toast_popup_textarea", tostring(text or ""))
    }))
    p:showBriefly(2000, nil,
        Window.transitionPushPopupUp,
        Window.transitionPushPopupDown)
end

function menu(self, menuItem)
    log:info("Spotify: menu")
    local win   = Window("text_list", self:string("SPOTIFY"))
    local isOn  = _isRunning()
    local group = RadioGroup()

    local track = _getNowPlaying()
    local statusText
    if isOn then
        statusText = track ~= "" and (">>" .. track:sub(1, 30)) or "Vantar pa Spotify..."
    else
        statusText = "Spotify Connect: AV"
    end

    local m = SimpleMenu("menu", {
        {
            text = self:string("SPOTIFY_ON"),
            icon = RadioButton("radio", group,
                function()
                    log:info("Spotify: ON")
                    self:getSettings()["enabled"] = true
                    self:storeSettings()
                    os.execute(START_SH .. " >/dev/null 2>&1 &")
                    _toast(self, self:string("SPOTIFY_STARTING"))
                end,
                isOn
            ),
        },
        {
            text = self:string("SPOTIFY_OFF"),
            icon = RadioButton("radio", group,
                function()
                    log:info("Spotify: OFF")
                    self:getSettings()["enabled"] = false
                    self:storeSettings()
                    os.execute(STOP_SH .. " >/dev/null 2>&1 &")
                    _toast(self, self:string("SPOTIFY_STOPPING"))
                end,
                not isOn
            ),
        },
        { text = "---", callback = function() end },
        {
            text = self:string("SPOTIFY_PREV"),
            callback = function()
                _toast(self, self:string("SPOTIFY_PREV"))
            end,
        },
        {
            text = self:string("SPOTIFY_PLAYPAUSE"),
            callback = function()
                _toast(self, self:string("SPOTIFY_PLAYPAUSE"))
            end,
        },
        {
            text = self:string("SPOTIFY_NEXT"),
            callback = function()
                _toast(self, self:string("SPOTIFY_NEXT"))
            end,
        },
        { text = "---", callback = function() end },
        {
            text = self:string("SPOTIFY_SHOW_STATUS"),
            callback = function() self:showStatus() end,
        },
    })

    m:setHeaderWidget(Textarea("help", statusText))
    win:addWidget(m)
    self:tieAndShowWindow(win)
end

function showStatus(self)
    local win = Window("text_list", self:string("SPOTIFY_STATUS"))
    local lines = {}
    if _isRunning() then
        table.insert(lines, tostring(self:string("SPOTIFY_RUNNING")))
        table.insert(lines, "")
        local track = _getNowPlaying()
        if track ~= "" then
            table.insert(lines, ">>" .. track)
            table.insert(lines, "")
        end
        table.insert(lines, "Oppna Spotify-appen")
        table.insert(lines, "och valj 'Squeezebox'")
    else
        table.insert(lines, tostring(self:string("SPOTIFY_STOPPED")))
        table.insert(lines, "")
        table.insert(lines, "Valj 'Pa' for att starta")
    end
    win:addWidget(Textarea("text", table.concat(lines, "\n")))
    self:tieAndShowWindow(win)
end

do
    pcall(function()
        os.execute("rdate -s time.cloudflare.com >/dev/null 2>&1 &")
    end)
end
