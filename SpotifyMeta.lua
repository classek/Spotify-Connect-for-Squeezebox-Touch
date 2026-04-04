local oo         = require("loop.simple")
local AppletMeta = require("jive.AppletMeta")
local jiveMain   = jiveMain

module(...)
oo.class(_M, AppletMeta)

function jiveVersion(meta) return 1, 1 end

function defaultSettings(meta)
    return { enabled = false }
end

function registerApplet(meta)
end

function configureApplet(meta)
    jiveMain:addItem(meta:menuItem(
        'appletSpotify',
        'home',
        'SPOTIFY',
        function(applet, ...) applet:menu(...) end,
        25
    ))
end
