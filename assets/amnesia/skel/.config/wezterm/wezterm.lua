local wezterm = require 'wezterm'
local act = wezterm.action
local config = wezterm.config_builder and wezterm.config_builder() or {}
local home = os.getenv('HOME') or ''
local mux = wezterm.mux

-- Read ~/.config/x47/settings.conf (managed by x47-settings).
local function x47_setting_enabled(key, default_on)
  local path = home .. '/.config/x47/settings.conf'
  local f = io.open(path, 'r')
  if not f then
    return default_on
  end
  for line in f:lines() do
    local k, v = line:match('^([%w_]+)%s*=%s*(%S+)')
    if k == key then
      f:close()
      v = string.lower(v or '')
      return v == '1' or v == 'true' or v == 'on' or v == 'yes'
    end
  end
  f:close()
  return default_on
end

-- Window size profiles (inner pixels). Override per launch with:
--   X47_TERM_SIZE=default|tool|large|vulnscape
--   X47_TERM_WIDTH / X47_TERM_HEIGHT  (pixels; wins over named size)
-- Desktop tool launchers open as "tool" (or vulnscape); plain WezTerm = default.
local TERM_SIZES = {
  -- Matched to the reference window screenshot (≈933×638 outer with
  -- title + tab chrome; inner is the terminal cell area).
  default = { 933, 584 },
  tool = { 1340, 720 },
  large = { 1520, 860 },
  vulnscape = { 1600, 920 },
}

local function args_blob(cmd)
  if not cmd or not cmd.args then
    return ''
  end
  return table.concat(cmd.args, ' ')
end

local function resolve_term_size(cmd)
  local w = tonumber(os.getenv('X47_TERM_WIDTH') or '')
  local h = tonumber(os.getenv('X47_TERM_HEIGHT') or '')
  if w and h and w > 0 and h > 0 then
    return w, h, 'env-pixels'
  end

  local profile = os.getenv('X47_TERM_SIZE') or ''
  profile = string.lower(profile)

  if profile == '' then
    local blob = args_blob(cmd)
    if blob:find('vulnscape') then
      profile = 'vulnscape'
    elseif blob ~= '' then
      -- Anything started with a command (app-grid tools, `wezterm -e …`)
      -- gets the larger tool window; bare `wezterm start` stays default.
      profile = 'tool'
    else
      profile = 'default'
    end
  end

  local sz = TERM_SIZES[profile] or TERM_SIZES.default
  return sz[1], sz[2], profile
end

-- Base look
config.font = wezterm.font_with_fallback { 'DejaVu Sans Mono', 'Noto Sans Mono' }
config.font_size = 11.0
config.color_scheme = 'Tokyo Night'
config.window_background_opacity = 1.0
config.enable_scroll_bar = false
config.window_padding = { left = 8, right = 8, top = 14, bottom = 6 }

-- Default spawn cells (used when gui-startup is skipped).
config.initial_cols = 120
config.initial_rows = 36

-- Tab-bar chrome (no separate OS title bar). Gnome-style integrated buttons
-- stay visible (Windows style only reveals them on hover).
config.window_decorations = 'INTEGRATED_BUTTONS|RESIZE'
config.integrated_title_buttons = { 'Hide', 'Maximize', 'Close' }
config.integrated_title_button_style = 'Gnome'
config.integrated_title_button_alignment = 'Right'
config.use_fancy_tab_bar = true
config.hide_tab_bar_if_only_one_tab = false
config.tab_bar_at_bottom = false
config.window_frame = {
  font = wezterm.font { family = 'DejaVu Sans', weight = 'Bold' },
  font_size = 10.0,
  active_titlebar_bg = '#16161e',
  inactive_titlebar_bg = '#16161e',
}

wezterm.on('gui-startup', function(cmd)
  local _tab, _pane, window = mux.spawn_window(cmd or {})
  local gui = window:gui_window()
  local w, h = resolve_term_size(cmd)
  gui:set_inner_size(w, h)
end)

-- Optional PuTTY-style clipboard (toggle: x47-settings set putty_clipboard on|off).
if x47_setting_enabled('putty_clipboard', true) then
  -- drag left → copy; right-click → paste; Ctrl+C copy-or-SIGINT; Ctrl+V paste
  config.mouse_bindings = {
    {
      event = { Up = { streak = 1, button = 'Left' } },
      mods = 'NONE',
      action = act.CompleteSelectionOrOpenLinkAtMouseCursor 'ClipboardAndPrimarySelection',
    },
    {
      event = { Down = { streak = 1, button = 'Right' } },
      mods = 'NONE',
      action = act.PasteFrom 'Clipboard',
    },
  }

  config.keys = {
    {
      key = 'c',
      mods = 'CTRL',
      action = wezterm.action_callback(function(window, pane)
        local selection = window:get_selection_text_for_pane(pane)
        if selection and selection ~= '' then
          window:perform_action(act.CopyTo 'ClipboardAndPrimarySelection', pane)
          window:perform_action(act.ClearSelection, pane)
        else
          window:perform_action(act.SendKey { key = 'c', mods = 'CTRL' }, pane)
        end
      end),
    },
    {
      key = 'v',
      mods = 'CTRL',
      action = act.PasteFrom 'Clipboard',
    },
  }
end

-- X47 ASCII watermark: sits BEHIND the text, small, anchored to the right.
config.background = {
  {
    source = { Color = '#16161e' },
    width = '100%',
    height = '100%',
    opacity = 1.0,
  },
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
