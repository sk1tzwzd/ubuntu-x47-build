local wezterm = require 'wezterm'
local config = wezterm.config_builder and wezterm.config_builder() or {}
local home = os.getenv('HOME') or ''

-- Base look
config.font = wezterm.font_with_fallback { 'DejaVu Sans Mono', 'Noto Sans Mono' }
config.font_size = 11.0
config.color_scheme = 'Tokyo Night'
config.window_background_opacity = 1.0
config.enable_scroll_bar = false
config.window_padding = { left = 8, right = 8, top = 6, bottom = 6 }

-- X47 ASCII watermark: sits BEHIND the text, small, anchored to the right.
config.background = {
  -- opaque base fill (terminal background colour)
  {
    source = { Color = '#16161e' },
    width = '100%',
    height = '100%',
    opacity = 1.0,
  },
  -- the ascii art, faint, right-aligned, vertically centred, not repeated.
  -- width/height MUST be set to explicit pixels: WezTerm defaults them to
  -- "100%" which stretches the image to fill the window (huge + centred).
  -- Fixed 520x353 px keeps it small, on the right, at its true aspect ratio.
  {
    source = { File = home .. '/.config/wzd/watermark.png' },
    repeat_x = 'NoRepeat',
    repeat_y = 'NoRepeat',
    width = 520,
    height = 353,
    horizontal_align = 'Right',
    horizontal_offset = '-24px',
    vertical_align = 'Middle',
    opacity = 0.35,
  },
}

return config
