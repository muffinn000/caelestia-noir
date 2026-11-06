hl.config({ input = { kb_layout = "us,ru", kb_options = "grp:alt_shift_toggle" } })

-- Hide scratchpads (for example Spotify) when switching regular workspaces.
hl.config({ binds = { hide_special_on_workspace_change = true } })

-- Avoid disappearing/flickering hardware cursors with nouveau.
hl.config({ cursor = { no_hardware_cursors = 1 } })

-- Main MSI: native resolution at 180 Hz with the NVIDIA driver.
hl.monitor({
    output = "DP-1",
    mode = "1920x1080@180",
    position = "0x0",
    scale = 1,
})

-- LG: left of the MSI, approximately 5 cm lower; native scale.
hl.monitor({
    output = "HDMI-A-1",
    mode = "1440x900@59.887",
    position = "-1440x180",
    scale = 1,
})

-- Start the session on the MSI, regardless of monitor discovery order.
hl.config({ cursor = { default_monitor = "DP-1" } })
hl.on("hyprland.start", function()
    hl.dispatch(hl.dsp.focus({ monitor = "DP-1" }))
    -- This session starts Hyprland directly, without graphical-session.target.
    hl.exec_cmd("systemctl --user start opentabletdriver.service")
end)

-- CS2: use the MSI's full screen for its stretched 4:3 game surface.
hl.window_rule({
    name = "cs2-msi-fullscreen",
    match = { class = "^cs2$" },
    monitor = "DP-1",
    fullscreen = true,
    opaque = true,
    no_blur = true,
})

-- osu!stable: allow immediate presentation on the 180 Hz MSI.
hl.config({ general = { allow_tearing = true } })
hl.window_rule({
    name = "osu-stable-low-latency",
    match = { class = "^osu!\\.exe$" },
    monitor = "DP-1",
    immediate = true,
    fullscreen = true,
    opaque = true,
    no_blur = true,
    no_shadow = true,
    no_anim = true,
})

-- One by Wacom: absolute coordinates cover the gaming monitor only.
hl.device({
    name = "wacom-one-by-wacom-m-pen",
    output = "DP-1",
    relative_input = false,
})

-- Artist Mode uses Wayland's tablet protocol, including inside osu! on XWayland.
-- OTD covers the virtual desktop; Hyprland maps the device to the MSI once.
hl.device({
    name = "opentabletdriver-virtual-artist-tablet",
    output = "DP-1",
    relative_input = false,
})

-- NOIR desktop widgets and compact top controls.
hl.on("hyprland.start", function()
    hl.exec_cmd("~/.local/bin/noir-panel")
end)


-- NOIR: short, controlled motion with a soft finish.
hl.curve("noirEase", { type = "bezier", points = { { 0.16, 1 }, { 0.3, 1 } } })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4, bezier = "noirEase" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 3, bezier = "noirEase" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 4, bezier = "noirEase" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "noirEase" })
