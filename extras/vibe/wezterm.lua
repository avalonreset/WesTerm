local wezterm = require 'wezterm'
local act = wezterm.action

local target = wezterm.target_triple or ''
local is_windows = target:find('windows', 1, true) ~= nil

local function env_is_truthy(name)
  local value = os.getenv(name)
  if type(value) ~= 'string' then
    return false
  end
  local v = value:lower()
  return v == '1' or v == 'true' or v == 'yes' or v == 'on'
end

local force_alt_v_image_paste = env_is_truthy 'BENJAMINTERM_FORCE_ALT_V_IMAGE_PASTE'
local claude_image_path_backstop = env_is_truthy 'BENJAMINTERM_CLAUDE_IMAGE_PATH_BACKSTOP'
local use_at_prefix_for_image_paths = env_is_truthy 'BENJAMINTERM_USE_AT_IMAGE_PATH'
local paste_clipboard_image_path_into_prompt

local function normalize_front_end_name(value)
  if type(value) ~= 'string' or value == '' then
    return nil
  end
  local v = value:gsub('%s+', ''):lower()
  if v == 'webgpu' or v == 'wgpu' then
    return 'WebGpu'
  end
  if v == 'opengl' or v == 'gl' then
    return 'OpenGL'
  end
  if v == 'software' or v == 'cpu' then
    return 'Software'
  end
  return nil
end

local paste_undo_window_seconds = 30
local paste_undo_max_chars = 200000
local paste_undo_fallback_chars = 50000

local click_open_extensions = 'html?|pdf|md|txt|json|csv|ya?ml'

-- Theme/font: "hacker-ish", pure black background.
-- Use a curated set of built-in schemes and provide a hotkey to cycle them.

-- Persist the last selected theme/font so it survives restart/crash.
-- IMPORTANT: this distro may load its config from the install directory
-- (eg: `wezterm.lua` next to the exe). That directory may not be writable,
-- so store state in the per-user home directory instead.
local state_path = wezterm.home_dir .. '/.wezterm-vibe-state.json'

local function read_file(path)
  local f = io.open(path, 'rb')
  if not f then
    return nil
  end
  local s = f:read '*a'
  f:close()
  return s
end

local function write_file_atomic(path, data)
  local tmp = path .. '.tmp'
  local f = io.open(tmp, 'wb')
  if not f then
    return false
  end
  f:write(data)
  f:close()

  -- On Windows, rename over an existing file can fail, so remove first.
  pcall(os.remove, path)
  local ok = os.rename(tmp, path)
  if not ok then
    pcall(os.remove, tmp)
    return false
  end
  return true
end

local function load_state()
  local s = read_file(state_path)
  if not s or s == '' then
    return {}
  end
  local ok, decoded = pcall(wezterm.json_parse, s)
  if ok and type(decoded) == 'table' then
    return decoded
  end
  return {}
end

local function save_state(st)
  local ok, json = pcall(wezterm.json_encode, st)
  if not ok or type(json) ~= 'string' then
    return
  end
  pcall(write_file_atomic, state_path, json)
end

local function decode_percent_escapes(s)
  return (s:gsub('%%(%x%x)', function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

local function resolve_clicked_path(uri_path, pane)
  local path = decode_percent_escapes(uri_path or '')
  path = path:gsub('^%s+', ''):gsub('%s+$', '')
  path = path:gsub('^[<%(%[{]+', ''):gsub('[>%)%]}:,;]+$', '')
  if path == '' then
    return nil
  end

  if is_windows and path:match('^/[A-Za-z]:[\\/]') then
    path = path:sub(2)
  end

  if path:match('^[A-Za-z]:[\\/]') or path:match('^\\\\') or path:match('^/') then
    return path
  end

  -- Strip leading ./ when resolving relative artifacts.
  if path:match('^%.[\\/]') then
    path = path:sub(3)
  end

  local cwd = pane:get_current_working_dir()
  if cwd and cwd.scheme == 'file' and type(cwd.file_path) == 'string' and cwd.file_path ~= '' then
    local base = cwd.file_path
    if is_windows and base:match('^/[A-Za-z]:[\\/]') then
      base = base:sub(2)
    end
    local sep = base:find('\\', 1, true) and '\\' or '/'
    if base:sub(-1) ~= '\\' and base:sub(-1) ~= '/' then
      base = base .. sep
    end
    return base .. path
  end

  return path
end

wezterm.on('open-uri', function(window, pane, uri)
  local raw_path = uri:match '^benpath:(.+)$'
  if not raw_path then
    return
  end

  local path = resolve_clicked_path(raw_path, pane)
  if not path then
    return false
  end

  wezterm.open_with(path)
  return false
end)

local builtin_schemes = wezterm.color.get_builtin_schemes()
-- Distro defaults (what a brand new install will start with).
-- If the scheme/font aren't available on the target machine, the config will
-- fall back gracefully.
local DEFAULT_COLOR_SCHEME = 'Blue Matrix'
local DEFAULT_FONT_PRIMARY = 'OCR A Extended'

local function is_pure_black_background(value)
  if type(value) ~= 'string' then
    return false
  end

  local v = value:lower()
  if v == '#000' or v == '#000000' or v == '#000000ff' then
    return true
  end
  if v == 'rgb:0000/0000/0000' then
    return true
  end
  return false
end

local function scheme_visual_signature(value)
  local t = type(value)
  if t == 'string' then
    return '"' .. value:lower() .. '"'
  end
  if t == 'number' or t == 'boolean' then
    return tostring(value)
  end
  if t ~= 'table' then
    return ''
  end

  local keys = {}
  for k, _ in pairs(value) do
    if
      k ~= 'name'
      and k ~= 'author'
      and k ~= 'aliases'
      and k ~= 'origin_url'
      and k ~= 'wezterm_version'
      and k ~= 'metadata'
    then
      table.insert(keys, k)
    end
  end
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)

  local out = { '{' }
  for _, k in ipairs(keys) do
    table.insert(out, tostring(k))
    table.insert(out, '=')
    table.insert(out, scheme_visual_signature(value[k]))
    table.insert(out, ';')
  end
  table.insert(out, '}')
  return table.concat(out)
end

local similar_scheme_max_distance = 0.07
local min_scheme_avg_saturation = 0.20
local min_scheme_unique_colors = 10

local function parse_hex_component_to_unit(s)
  if type(s) ~= 'string' or s == '' then
    return nil
  end
  local n = tonumber(s, 16)
  if not n then
    return nil
  end
  local max = (16 ^ #s) - 1
  if max <= 0 then
    return nil
  end
  return n / max
end

local function color_to_rgb_unit(value)
  if type(value) ~= 'string' then
    return nil
  end

  local v = value:lower()
  local hex = v:match '^#([0-9a-f]+)$'
  if hex then
    if #hex == 3 or #hex == 4 then
      local r = parse_hex_component_to_unit(hex:sub(1, 1) .. hex:sub(1, 1))
      local g = parse_hex_component_to_unit(hex:sub(2, 2) .. hex:sub(2, 2))
      local b = parse_hex_component_to_unit(hex:sub(3, 3) .. hex:sub(3, 3))
      if r and g and b then
        return { r, g, b }
      end
    elseif #hex == 6 or #hex == 8 then
      local r = parse_hex_component_to_unit(hex:sub(1, 2))
      local g = parse_hex_component_to_unit(hex:sub(3, 4))
      local b = parse_hex_component_to_unit(hex:sub(5, 6))
      if r and g and b then
        return { r, g, b }
      end
    end
  end

  local rhex, ghex, bhex = v:match '^rgb:([0-9a-f]+)/([0-9a-f]+)/([0-9a-f]+)$'
  if rhex and ghex and bhex then
    local r = parse_hex_component_to_unit(rhex)
    local g = parse_hex_component_to_unit(ghex)
    local b = parse_hex_component_to_unit(bhex)
    if r and g and b then
      return { r, g, b }
    end
  end

  return nil
end

local function append_color_sample(samples, value)
  local rgb = color_to_rgb_unit(value)
  if rgb then
    table.insert(samples, rgb)
  end
end

local function build_scheme_color_samples(scheme)
  local samples = {}
  if type(scheme) ~= 'table' then
    return samples
  end

  if type(scheme.ansi) == 'table' then
    for i = 1, 8 do
      append_color_sample(samples, scheme.ansi[i])
    end
  end
  if type(scheme.brights) == 'table' then
    for i = 1, 8 do
      append_color_sample(samples, scheme.brights[i])
    end
  end

  append_color_sample(samples, scheme.foreground)
  append_color_sample(samples, scheme.cursor_bg)
  append_color_sample(samples, scheme.cursor_border)
  append_color_sample(samples, scheme.cursor_fg)
  append_color_sample(samples, scheme.selection_bg)
  append_color_sample(samples, scheme.selection_fg)

  return samples
end

local function compute_samples_brightness(samples)
  if type(samples) ~= 'table' or #samples == 0 then
    return 0
  end

  local total = 0
  for _, rgb in ipairs(samples) do
    total = total + (0.2126 * rgb[1]) + (0.7152 * rgb[2]) + (0.0722 * rgb[3])
  end
  return total / #samples
end

local function compute_rgb_saturation(rgb)
  local max_c = math.max(rgb[1], math.max(rgb[2], rgb[3]))
  local min_c = math.min(rgb[1], math.min(rgb[2], rgb[3]))
  if max_c <= 0 then
    return 0
  end
  return (max_c - min_c) / max_c
end

local function compute_samples_avg_saturation(samples)
  if type(samples) ~= 'table' or #samples == 0 then
    return 0
  end

  local total = 0
  for _, rgb in ipairs(samples) do
    total = total + compute_rgb_saturation(rgb)
  end
  return total / #samples
end

local function compute_samples_unique_count(samples)
  if type(samples) ~= 'table' or #samples == 0 then
    return 0
  end

  local seen = {}
  for _, rgb in ipairs(samples) do
    local key = string.format('%.3f-%.3f-%.3f', rgb[1], rgb[2], rgb[3])
    seen[key] = true
  end

  local n = 0
  for _ in pairs(seen) do
    n = n + 1
  end
  return n
end

local function compute_scheme_distance(samples_a, samples_b)
  local n = math.min(#samples_a, #samples_b)
  if n <= 0 then
    return 1
  end

  local total = 0
  for i = 1, n do
    local a = samples_a[i]
    local b = samples_b[i]
    total = total + math.abs(a[1] - b[1]) + math.abs(a[2] - b[2]) + math.abs(a[3] - b[3])
  end
  return total / (3 * n)
end

local prefiltered_hacker_schemes = {}
local seen_scheme_signatures = {}
for name, scheme in pairs(builtin_schemes) do
  if type(scheme) == 'table' and is_pure_black_background(scheme.background) then
    local sig = scheme_visual_signature(scheme)
    if not seen_scheme_signatures[sig] then
      seen_scheme_signatures[sig] = name
      table.insert(prefiltered_hacker_schemes, name)
    end
  end
end

local ranked_hacker_candidates = {}
for _, name in ipairs(prefiltered_hacker_schemes) do
  local scheme = builtin_schemes[name]
  local samples = build_scheme_color_samples(scheme)
  table.insert(ranked_hacker_candidates, {
    name = name,
    samples = samples,
    brightness = compute_samples_brightness(samples),
    avg_saturation = compute_samples_avg_saturation(samples),
    unique_count = compute_samples_unique_count(samples),
  })
end
table.sort(ranked_hacker_candidates, function(a, b)
  if a.brightness ~= b.brightness then
    return a.brightness > b.brightness
  end
  return a.name:lower() < b.name:lower()
end)

local selected_hacker_candidates = {}
for _, candidate in ipairs(ranked_hacker_candidates) do
  local too_similar = false
  for _, kept in ipairs(selected_hacker_candidates) do
    if compute_scheme_distance(candidate.samples, kept.samples) <= similar_scheme_max_distance then
      too_similar = true
      break
    end
  end
  if not too_similar then
    table.insert(selected_hacker_candidates, candidate)
  end
end

local hacker_schemes = {}
for _, candidate in ipairs(selected_hacker_candidates) do
  if candidate.avg_saturation >= min_scheme_avg_saturation and candidate.unique_count >= min_scheme_unique_colors then
    table.insert(hacker_schemes, candidate.name)
  end
end
table.sort(hacker_schemes, function(a, b)
  return a:lower() < b:lower()
end)
if #hacker_schemes == 0 then
  hacker_schemes = { 'Builtin Dark' }
end
local hacker_scheme_set = {}
for _, name in ipairs(hacker_schemes) do
  hacker_scheme_set[name] = true
end

local persisted = load_state()

local function pick_default_scheme()
  local name = persisted and persisted.color_scheme
  if type(name) == 'string' and hacker_scheme_set[name] then
    return name
  end
  if hacker_scheme_set[DEFAULT_COLOR_SCHEME] then
    return DEFAULT_COLOR_SCHEME
  end
  return hacker_schemes[1]
end

local rng_seeded = false
local function seed_rng_once(seed_hint)
  if rng_seeded then
    return
  end
  local now_s = tonumber(wezterm.time.now():format '%s') or 0
  local micros = tonumber(wezterm.time.now():format '%f') or 0
  local hint = tonumber(seed_hint) or 0
  -- Mix seconds, sub-second time and a caller hint to avoid deterministic startup picks.
  local seed = (now_s * 1000003 + micros * 9176 + hint * 7919) % 2147483647
  if seed <= 0 then
    seed = 1
  end
  math.randomseed(seed)
  -- Warm up the PRNG to avoid first-call bias on some Lua builds.
  math.random()
  math.random()
  rng_seeded = true
end

local function build_shuffled_scheme_bag(previous)
  local bag = {}
  for _, name in ipairs(hacker_schemes) do
    table.insert(bag, name)
  end

  for i = #bag, 2, -1 do
    local j = math.random(i)
    bag[i], bag[j] = bag[j], bag[i]
  end

  -- Avoid immediate back-to-back repeats across bag boundaries.
  if type(previous) == 'string' and #bag > 1 and bag[1] == previous then
    local swap_idx = math.random(2, #bag)
    bag[1], bag[swap_idx] = bag[swap_idx], bag[1]
  end

  return bag
end

local function bag_matches_current_schemes(bag)
  if type(bag) ~= 'table' or #bag ~= #hacker_schemes then
    return false
  end

  local seen = {}
  for _, name in ipairs(bag) do
    if type(name) ~= 'string' or (not hacker_scheme_set[name]) or seen[name] then
      return false
    end
    seen[name] = true
  end
  return true
end

local function pick_scheme_from_shuffle_bag(seed_hint)
  if #hacker_schemes == 1 then
    local only = hacker_schemes[1]
    persisted.last_random_scheme = only
    persisted.random_scheme_bag = { only }
    persisted.random_scheme_bag_index = 2
    save_state(persisted)
    return only
  end

  seed_rng_once(seed_hint)

  local previous = persisted and persisted.last_random_scheme
  local bag = persisted and persisted.random_scheme_bag
  local idx = persisted and persisted.random_scheme_bag_index
  if type(idx) ~= 'number' then
    idx = 1
  end

  if (not bag_matches_current_schemes(bag)) or idx > #bag then
    bag = build_shuffled_scheme_bag(previous)
    idx = 1
  end

  local picked = bag[idx]
  idx = idx + 1

  if idx > #bag then
    bag = build_shuffled_scheme_bag(picked)
    idx = 1
  end

  persisted.last_random_scheme = picked
  persisted.random_scheme_bag = bag
  persisted.random_scheme_bag_index = idx
  save_state(persisted)
  return picked
end

-- Font cycling: curated "snob/hacker" fonts.
--
-- Notes:
-- - The first entries are fonts detected on this machine via `wezterm ls-fonts --list-system`.
-- - The "aspirational" fonts at the bottom require installation; until installed, they'll fall back.
local hacker_font_candidates = {
  -- Installed (Windows)
  { family = 'JetBrains Mono', weight = 'Medium' },
  'Cascadia Mono',
  'Cascadia Code',
  'IBM Plex Mono',
  'Source Code Pro',
  'Roboto Mono',
  'Ubuntu Mono',
  'Consolas',
  'PT Mono',
  'Lucida Sans Typewriter',
  'OCR A Extended',
  'VT323',

  -- If you want to expand this list, add only fonts that are freely redistributable,
  -- or keep them out-of-tree to avoid bundling/license friction.
}

local function make_hacker_font(primary)
  return wezterm.font_with_fallback {
    primary,
    -- Ensure we always have a sane mono fallback even if the "vibe" font isn't installed.
    { family = 'Cascadia Mono' },
    { family = 'Cascadia Code' },
    { family = 'JetBrains Mono', weight = 'Medium' },
    'Consolas',
    'DejaVu Sans Mono',
    'monospace',
    'Symbols Nerd Font Mono',
    'Noto Color Emoji',
  }
end

local function same_primary_font(a, b)
  if type(a) ~= type(b) then
    return false
  end
  if type(a) == 'string' then
    return a == b
  end
  if type(a) == 'table' then
    return a.family == b.family and a.weight == b.weight and a.style == b.style and a.stretch == b.stretch
  end
  return false
end

local function pick_default_font_primary()
  local want = persisted and persisted.font_primary
  if want then
    for _, cand in ipairs(hacker_font_candidates) do
      if same_primary_font(cand, want) then
        return cand
      end
    end
  end

  -- Distro default: try to use the selected "vibe" font if it's in the rotation.
  for _, cand in ipairs(hacker_font_candidates) do
    if same_primary_font(cand, DEFAULT_FONT_PRIMARY) then
      return cand
    end
  end

  return hacker_font_candidates[1]
end

local function idx_for_primary(primary)
  for i, cand in ipairs(hacker_font_candidates) do
    if same_primary_font(cand, primary) then
      return i
    end
  end
  return 1
end

-- Align font cycling with the actual starting font, so Ctrl+Alt+F moves to the
-- next font in the list rather than an arbitrary entry.
local default_font_primary = pick_default_font_primary()
local default_font_idx = idx_for_primary(default_font_primary)

local font_idx_by_window_id = {}
local function get_font_idx(window)
  local id = window:window_id()
  local idx = font_idx_by_window_id[id]
  if not idx then
    idx = default_font_idx
    font_idx_by_window_id[id] = idx
  end
  return idx
end

-- Initialize every newly created window with BenjaminTerm defaults.
-- This ensures all windows (not just the first) get the expected font sizing
-- behavior and a randomized hacker theme.
wezterm.on('window-config-reloaded', function(window, pane)
  local overrides = window:get_config_overrides()
  if overrides then
    -- Clean up legacy forced background overrides so color schemes can render
    -- their intended backgrounds.
    if overrides.colors and overrides.colors.background then
      overrides.colors = nil
      window:set_config_overrides(overrides)
    end
    return
  end

  local id = window:window_id()
  font_idx_by_window_id[id] = default_font_idx

  local picked_scheme = pick_scheme_from_shuffle_bag(id)

  window:set_config_overrides {
    font = make_hacker_font(default_font_primary),
    font_size = 16.0,
    adjust_window_size_when_changing_font_size = false,
    color_scheme = picked_scheme,
  }
end)

-- Smart paste for Windows:
-- If the clipboard currently holds an image, forward Ctrl+V into the running program
-- (so apps like the Codex TUI can handle image paste). Otherwise, paste text normally.
local function clipboard_has_image()
  if is_windows then
    local ok, stdout, _ = wezterm.run_child_process {
      'powershell.exe',
      '-STA',
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      -- Try both PowerShell clipboard APIs because different screenshot tools and
      -- Windows versions expose different image formats.
      table.concat({
        "$has = $false",
        "try { $img = Get-Clipboard -Format Image -ErrorAction Stop; if ($null -ne $img) { $has = $true } } catch {}",
        "if (-not $has) {",
        "  try {",
        "    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop | Out-Null",
        "    $has = [System.Windows.Forms.Clipboard]::ContainsImage()",
        "  } catch {}",
        "}",
        "if ($has) { 'HAS_IMAGE' }",
      }, '; '),
    }
    return ok and stdout and stdout:find('HAS_IMAGE', 1, true) ~= nil
  end

  -- We intentionally do NOT try to forward Ctrl+V on Linux/macOS: Ctrl+V can be a
  -- meaningful keybinding inside shells and TUI apps (eg: readline "quoted insert").
  return false
end

local function looks_like_claude_value(value)
  if type(value) ~= 'string' or value == '' then
    return false
  end

  local v = value:lower()
  if v == 'claude' or v == 'claude.exe' or v == 'claude.cmd' or v == 'claude.ps1' then
    return true
  end

  local hints = {
    'claude-code',
    '@anthropic-ai\\claude-code',
    '@anthropic-ai/claude-code',
    '\\claude.exe',
    '/claude.exe',
    '\\claude.cmd',
    '/claude.cmd',
    '\\claude.ps1',
    '/claude.ps1',
  }
  for _, hint in ipairs(hints) do
    if v:find(hint, 1, true) ~= nil then
      return true
    end
  end

  return false
end

local function process_info_looks_like_claude(info)
  if type(info) ~= 'table' then
    return false
  end

  if looks_like_claude_value(info.name) or looks_like_claude_value(info.executable) then
    return true
  end

  if type(info.argv) == 'table' then
    for _, arg in ipairs(info.argv) do
      if looks_like_claude_value(arg) then
        return true
      end
    end
  end

  if type(info.children) == 'table' then
    for _, child in pairs(info.children) do
      if process_info_looks_like_claude(child) then
        return true
      end
    end
  end

  return false
end

local function is_claude_foreground(pane)
  local info = pane:get_foreground_process_info()
  if process_info_looks_like_claude(info) then
    return true
  end

  if looks_like_claude_value(pane:get_foreground_process_name()) then
    return true
  end

  local ok, title = pcall(function()
    return pane:get_title()
  end)
  if ok and looks_like_claude_value(title) then
    return true
  end

  return false
end

local function send_image_paste_key(window, pane)
  local is_claude = is_claude_foreground(pane)

  -- Deterministic path for Claude: materialize clipboard image to a temp file
  -- and paste it as an @mention. This avoids fragile terminal clipboard MIME
  -- interactions in some Windows/WSL/terminal combinations.
  if is_claude and (not force_alt_v_image_paste) and paste_clipboard_image_path_into_prompt then
    if paste_clipboard_image_path_into_prompt(window, pane) then
      return
    end
  end

  -- Fallback key chords:
  -- Claude Code on Windows expects Alt+V for clipboard-image paste.
  -- Other image-aware TUIs typically use Ctrl+V.
  if force_alt_v_image_paste or is_claude then
    window:perform_action(act.SendKey { key = 'v', mods = 'ALT' }, pane)
  else
    window:perform_action(act.SendKey { key = 'v', mods = 'CTRL' }, pane)
  end
end

local function clipboard_image_to_temp_png_path()
  if not is_windows then
    return nil
  end

  local ok, stdout, _ = wezterm.run_child_process {
    'powershell.exe',
    '-STA',
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    table.concat({
      "$ErrorActionPreference = 'Stop'",
      "$dir = Join-Path $env:LOCALAPPDATA 'BenjaminTerm\\clipboard'",
      "New-Item -ItemType Directory -Path $dir -Force | Out-Null",
      "$path = Join-Path $dir ('clip-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8) + '.png')",
      "$img = $null",
      "try { $img = Get-Clipboard -Format Image -ErrorAction Stop } catch {}",
      "if ($null -eq $img) {",
      "  Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop | Out-Null",
      "  if ([System.Windows.Forms.Clipboard]::ContainsImage()) {",
      "    $img = [System.Windows.Forms.Clipboard]::GetImage()",
      "  }",
      "}",
      "if ($null -eq $img) { exit 1 }",
      "Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue | Out-Null",
      "$img.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)",
      "[Console]::Out.Write($path)",
    }, '; '),
  }

  if not ok or type(stdout) ~= 'string' then
    return nil
  end

  local path = stdout:gsub('[\r\n]+$', '')
  if path == '' then
    return nil
  end
  return path
end

local function windows_path_to_wsl_path(path)
  if type(path) ~= 'string' then
    return nil
  end

  local drive, rest = path:match '^([A-Za-z]):[\\/](.*)$'
  if not drive then
    return nil
  end

  rest = rest:gsub('\\', '/')
  return '/mnt/' .. drive:lower() .. '/' .. rest
end

local function windows_path_to_forward_slash(path)
  if type(path) ~= 'string' then
    return nil
  end
  return path:gsub('\\', '/')
end

paste_clipboard_image_path_into_prompt = function(_window, pane)
  local path = clipboard_image_to_temp_png_path()
  if not path then
    return false
  end

  if is_claude_foreground(pane) then
    local candidates = {}
    local win_path = windows_path_to_forward_slash(path) or path
    table.insert(candidates, win_path)
    local wsl_path = windows_path_to_wsl_path(path)
    if wsl_path then
      table.insert(candidates, wsl_path)
    end

    if use_at_prefix_for_image_paths then
      for i = 1, #candidates do
        candidates[i] = '@' .. candidates[i]
      end
    end

    -- Use plain visible paths by default because some Claude terminal builds
    -- appear to render @mentions as empty chips when the path isn't accepted.
    pane:send_paste(table.concat(candidates, ' '))
    return true
  end

  pane:send_paste(path)
  return true
end

local function get_clipboard_text()
  if is_windows then
    local ok, stdout, _ = wezterm.run_child_process {
      'powershell.exe',
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      -- Use Console.Out.Write to avoid adding a trailing newline.
      "try { $t = Get-Clipboard -Raw -ErrorAction Stop } catch { $t = $null }; if ($null -ne $t) { [Console]::Out.Write($t) }",
    }
    if not ok then
      return nil
    end
    return stdout or ''
  end

  -- Best-effort on Linux/macOS. If no helper is available, we simply won't
  -- enable paste-undo for that paste (we avoid destructive "guess delete" logic).
  local commands = {
    -- Wayland
    { 'sh', '-lc', "command -v wl-paste >/dev/null 2>&1 && wl-paste --no-newline 2>/dev/null || true" },
    -- X11
    { 'sh', '-lc', "command -v xclip >/dev/null 2>&1 && xclip -selection clipboard -o 2>/dev/null || true" },
    { 'sh', '-lc', "command -v xsel >/dev/null 2>&1 && xsel --clipboard --output 2>/dev/null || true" },
    -- macOS (pbpaste always exists on normal installs)
    { 'sh', '-lc', "command -v pbpaste >/dev/null 2>&1 && pbpaste || true" },
  }

  for _, cmd in ipairs(commands) do
    local ok, stdout, _ = wezterm.run_child_process(cmd)
    if ok and type(stdout) == 'string' and stdout ~= '' then
      return stdout
    end
  end

  return nil
end

local function now_epoch_seconds()
  return tonumber(wezterm.time.now():format '%s') or 0
end

local paste_state_by_pane_id = {}

local function state_for_pane(pane)
  local id = pane:pane_id()
  local st = paste_state_by_pane_id[id]
  if not st then
    st = { undo = {}, redo = {}, last_paste_s = 0 }
    paste_state_by_pane_id[id] = st
  end
  return st
end

local function char_len(s)
  if utf8 and utf8.len then
    local n = utf8.len(s)
    if n then
      return n
    end
  end
  return #s
end

local function send_back_delete(pane, count)
  -- Use BS (0x08) for broadest compatibility. (DEL 0x7f is also common,
  -- but some Windows console applications expect BS).
  local chunk = 4096
  local bs = string.char(0x08)
  while count > 0 do
    local n = math.min(count, chunk)
    pane:send_text(string.rep(bs, n))
    count = count - n
  end
end

local smart_paste = wezterm.action_callback(function(window, pane)
  local before = pane:get_logical_lines_as_text(3) or ''

  -- Paste text first and *then* check for image.
  --
  -- This ordering matters for tools that do "paste via clipboard": they may
  -- temporarily replace clipboard contents, send Ctrl+V, and then restore the
  -- previous clipboard quickly. If we spend time checking for image *before*
  -- pasting, we can miss the temporary text and paste the restored clipboard.
  window:perform_action(act.PasteFrom 'Clipboard', pane)

  local after = pane:get_logical_lines_as_text(3) or ''
  local changed = before ~= after

  -- If the clipboard holds an image, forward the app-specific paste chord.
  -- Claude Code on Windows uses Alt+V; Codex/Gemini-style TUIs generally use Ctrl+V.
  -- Only do this if the paste didn't visibly change the viewport; otherwise
  -- we'd risk forwarding a second paste chord after successfully pasting text.
  if is_windows and (not changed) and clipboard_has_image() then
    send_image_paste_key(window, pane)
    return
  end

  local st = state_for_pane(pane)
  st.last_paste_s = now_epoch_seconds()

  -- Record a best-effort "undo last paste" entry for text pastes.
  -- This is not a full editor undo system; it tries to delete the pasted
  -- characters by sending DEL repeatedly.
  local text = get_clipboard_text()
  if text and text ~= '' then
    if char_len(text) > paste_undo_max_chars then
      return
    end
    table.insert(st.undo, {
      text = text,
      len = char_len(text),
    })
    st.redo = {}
  end
end)

local undo_paste = wezterm.action_callback(function(window, pane)
  local st = state_for_pane(pane)
  local age = now_epoch_seconds() - (st.last_paste_s or 0)
  local entry = st.undo[#st.undo]

  -- Only steal Ctrl+Z shortly after we performed a paste; otherwise, pass through.
  if age > paste_undo_window_seconds then
    window:perform_action(act.SendKey { key = 'z', mods = 'CTRL' }, pane)
    return
  end

  -- If we didn't record the pasted text (eg: clipboard helper not available),
  -- don't guess. Pass Ctrl+Z through instead of deleting arbitrary input.
  if not entry then
    window:perform_action(act.SendKey { key = 'z', mods = 'CTRL' }, pane)
    return
  end

  -- Delete the recorded paste length.
  send_back_delete(pane, entry.len)

  if entry then
    table.remove(st.undo)
    table.insert(st.redo, entry)
  end
end)

local redo_paste = wezterm.action_callback(function(window, pane)
  local st = state_for_pane(pane)
  local entry = st.redo[#st.redo]
  if not entry then
    return
  end

  pane:send_paste(entry.text)
  table.remove(st.redo)
  table.insert(st.undo, entry)
  st.last_paste_s = now_epoch_seconds()
end)

local paste_image_path = wezterm.action_callback(function(window, pane)
  paste_clipboard_image_path_into_prompt(window, pane)
end)

local cycle_theme = wezterm.action_callback(function(window, pane)
  local overrides = window:get_config_overrides() or {}
  local current = overrides.color_scheme or pick_default_scheme()
  local idx = 1
  for i, name in ipairs(hacker_schemes) do
    if name == current then
      idx = i
      break
    end
  end
  local next_name = hacker_schemes[(idx % #hacker_schemes) + 1]
  overrides.color_scheme = next_name
  -- Ensure stale per-window color overrides don't pin the background.
  overrides.colors = nil
  window:set_config_overrides(overrides)

  persisted.color_scheme = overrides.color_scheme
  persisted.last_random_scheme = overrides.color_scheme
  -- Manual cycling invalidates the current shuffle-bag cursor.
  persisted.random_scheme_bag = nil
  persisted.random_scheme_bag_index = nil
  save_state(persisted)
end)

local cycle_font = wezterm.action_callback(function(window, pane)
  local id = window:window_id()
  local idx = get_font_idx(window)
  idx = (idx % #hacker_font_candidates) + 1
  font_idx_by_window_id[id] = idx

  local overrides = window:get_config_overrides() or {}
  local primary = hacker_font_candidates[idx]
  overrides.font = make_hacker_font(primary)
  window:set_config_overrides(overrides)

  persisted.font_primary = primary
  save_state(persisted)
end)

local function pick_default_window_decorations()
  local deco = persisted and persisted.window_decorations
  if type(deco) == 'string' and deco ~= '' then
    return deco
  end
  -- Default: keep the normal titlebar+resize border.
  return 'TITLE|RESIZE'
end

local toggle_borderless = wezterm.action_callback(function(window, pane)
  local overrides = window:get_config_overrides() or {}
  local current = overrides.window_decorations or pick_default_window_decorations()

  if current == 'RESIZE' then
    overrides.window_decorations = 'TITLE|RESIZE'
  else
    overrides.window_decorations = 'RESIZE'
  end

  window:set_config_overrides(overrides)

  persisted.window_decorations = overrides.window_decorations
  save_state(persisted)
end)

local keys = {
  -- Ctrl+C: if there is a selection, copy it. Otherwise, send Ctrl+C to the app (SIGINT).
  -- This avoids the "I tried to copy and it killed my session" footgun.
  {
    key = 'c',
    mods = 'CTRL',
    action = wezterm.action_callback(function(window, pane)
      local has_selection = window:get_selection_text_for_pane(pane) ~= ''
      if has_selection then
        window:perform_action(act.CopyTo 'ClipboardAndPrimarySelection', pane)
        window:perform_action(act.ClearSelection, pane)
      else
        window:perform_action(act.SendKey { key = 'c', mods = 'CTRL' }, pane)
      end
    end),
  },

  -- Undo/redo the most recent paste (best-effort).
  -- Ctrl+Z is `key='z', mods='CTRL'` and Ctrl+Shift+Z is `key='Z', mods='CTRL|SHIFT'`.
  { key = 'z', mods = 'CTRL', action = undo_paste },
  { key = 'Z', mods = 'CTRL|SHIFT', action = redo_paste },
  -- More explicit variants to be resilient to `key_map_preference` and layout differences.
  { key = 'mapped:z', mods = 'CTRL', action = undo_paste },
  { key = 'mapped:Z', mods = 'CTRL|SHIFT', action = redo_paste },

  -- Reload config (Ctrl+Shift+R). Don't steal Ctrl+R: shells use it for history search.
  -- Bind both shifted/mapped variants so Caps Lock/layout quirks don't break it.
  { key = 'r', mods = 'CTRL|SHIFT', action = act.ReloadConfiguration },
  { key = 'R', mods = 'CTRL|SHIFT', action = act.ReloadConfiguration },
  { key = 'mapped:r', mods = 'CTRL|SHIFT', action = act.ReloadConfiguration },
  { key = 'mapped:R', mods = 'CTRL|SHIFT', action = act.ReloadConfiguration },

  { key = '-', mods = 'CTRL', action = act.DecreaseFontSize },
  { key = '=', mods = 'CTRL', action = act.IncreaseFontSize },
  { key = '0', mods = 'CTRL', action = act.ResetFontSize },

  -- Letter hotkeys intentionally bind shifted + mapped variants to be resilient
  -- to Caps Lock and layout translation behavior.
  { key = 'f', mods = 'CTRL', action = act.Search { CaseSensitiveString = '' } },
  { key = 'mapped:f', mods = 'CTRL', action = act.Search { CaseSensitiveString = '' } },
  { key = 'F', mods = 'CTRL|SHIFT', action = act.Search { CaseSensitiveString = '' } },
  { key = 'mapped:F', mods = 'CTRL|SHIFT', action = act.Search { CaseSensitiveString = '' } },

  -- Theme cycling (no OS notifications).
  { key = 't', mods = 'CTRL|ALT', action = cycle_theme },
  { key = 'mapped:t', mods = 'CTRL|ALT', action = cycle_theme },
  { key = 'T', mods = 'CTRL|ALT|SHIFT', action = cycle_theme },
  { key = 'mapped:T', mods = 'CTRL|ALT|SHIFT', action = cycle_theme },

  -- Font cycling (no OS notifications).
  { key = 'f', mods = 'CTRL|ALT', action = cycle_font },
  { key = 'mapped:f', mods = 'CTRL|ALT', action = cycle_font },
  { key = 'F', mods = 'CTRL|ALT|SHIFT', action = cycle_font },
  { key = 'mapped:F', mods = 'CTRL|ALT|SHIFT', action = cycle_font },

  -- Borderless toggle (removes the title bar; keeps resizable border).
  { key = 'b', mods = 'CTRL|ALT', action = toggle_borderless },
  { key = 'mapped:b', mods = 'CTRL|ALT', action = toggle_borderless },
  { key = 'B', mods = 'CTRL|ALT|SHIFT', action = toggle_borderless },
  { key = 'mapped:B', mods = 'CTRL|ALT|SHIFT', action = toggle_borderless },

  -- Easier window move when borderless (titlebar hidden).
  { key = 'd', mods = 'CTRL|ALT', action = act.StartWindowDrag },
  { key = 'mapped:d', mods = 'CTRL|ALT', action = act.StartWindowDrag },
  { key = 'D', mods = 'CTRL|ALT|SHIFT', action = act.StartWindowDrag },
  { key = 'mapped:D', mods = 'CTRL|ALT|SHIFT', action = act.StartWindowDrag },

  -- Always send Ctrl+C, even if there is a selection.
  -- Useful when an accidental selection would otherwise cause Ctrl+C to copy instead of interrupt.
  { key = 'c', mods = 'CTRL|ALT', action = act.SendKey { key = 'c', mods = 'CTRL' } },
  { key = 'mapped:c', mods = 'CTRL|ALT', action = act.SendKey { key = 'c', mods = 'CTRL' } },
  { key = 'C', mods = 'CTRL|ALT|SHIFT', action = act.SendKey { key = 'c', mods = 'CTRL' } },
  { key = 'mapped:C', mods = 'CTRL|ALT|SHIFT', action = act.SendKey { key = 'c', mods = 'CTRL' } },

  -- Emergency fallback: capture clipboard image to a temp PNG and paste its path.
  { key = 'v', mods = 'CTRL|ALT', action = paste_image_path },
  { key = 'mapped:v', mods = 'CTRL|ALT', action = paste_image_path },
  { key = 'V', mods = 'CTRL|ALT|SHIFT', action = paste_image_path },
  { key = 'mapped:V', mods = 'CTRL|ALT|SHIFT', action = paste_image_path },
}

-- Clipboard paste keybindings:
-- Windows:
-- - Ctrl+V: smart paste (text normally; screenshot image clipboard is forwarded
--   to image-aware apps like Codex/Gemini/Claude).
-- - Ctrl+Shift+V: guaranteed plain clipboard paste fallback.
if is_windows then
  table.insert(keys, 2, { key = 'v', mods = 'CTRL', action = smart_paste })
  table.insert(keys, 3, { key = 'mapped:v', mods = 'CTRL', action = smart_paste })
  table.insert(keys, 4, { key = 'V', mods = 'CTRL|SHIFT', action = act.PasteFrom 'Clipboard' })
  table.insert(keys, 5, { key = 'v', mods = 'CTRL|SHIFT', action = act.PasteFrom 'Clipboard' })
  table.insert(keys, 6, { key = 'mapped:V', mods = 'CTRL|SHIFT', action = act.PasteFrom 'Clipboard' })
  table.insert(keys, 7, { key = 'mapped:v', mods = 'CTRL|SHIFT', action = act.PasteFrom 'Clipboard' })
else
  table.insert(keys, 2, { key = 'V', mods = 'CTRL|SHIFT', action = act.PasteFrom 'Clipboard' })
  table.insert(keys, 3, { key = 'v', mods = 'CTRL|SHIFT', action = act.PasteFrom 'Clipboard' })
  -- A guaranteed plain paste that doesn't depend on shift-state.
  table.insert(keys, 4, { key = 'v', mods = 'ALT', action = act.PasteFrom 'Clipboard' })
end

-- Compatibility binding used by many clipboard helpers on Windows terminals.
if is_windows then
  table.insert(keys, { key = 'Insert', mods = 'SHIFT', action = smart_paste })
else
  table.insert(keys, { key = 'Insert', mods = 'SHIFT', action = act.PasteFrom 'Clipboard' })
end

local config = {
  enable_tab_bar = false,
  disable_default_key_bindings = true,

  -- Font: pick a crisp "hacker" mono with sensible fallbacks.
  font = make_hacker_font(default_font_primary),
  -- Start larger by default: equivalent to hitting Ctrl++ four times from the
  -- default 12.0pt size.
  font_size = 16.0,
  -- When we change font size, keep the window pixel size fixed; reflow by
  -- changing rows/cols instead of resizing the whole window.
  adjust_window_size_when_changing_font_size = false,
  -- Disable ligatures for a more "terminal" look.
  harfbuzz_features = { 'calt=0', 'clig=0', 'liga=0' },

  -- Theme: start with a built-in scheme.
  color_scheme = pick_default_scheme(),
  window_background_opacity = 1.0,

  -- On Windows the native titlebar color is controlled by the OS; if you want
  -- a "pure black" top edge, the reliable option is to remove the title bar.
  -- Toggle with Ctrl+Alt+B (see keys below).
  window_decorations = pick_default_window_decorations(),

  default_cursor_style = 'BlinkingBlock',

  keys = keys,

  hyperlink_rules = (function()
    local rules = wezterm.default_hyperlink_rules()

    -- Clickable Windows absolute paths like: E:/claude-seo/ or C:\logs\app.txt
    table.insert(rules, {
      regex = [[\b([A-Za-z]:(?:[\\/][^\\/\s<>"'`|:*?]+)+[\\/]?)]],
      format = 'benpath:$1',
      highlight = 1,
    })

    -- Clickable artifact filenames in output (resolved relative to pane cwd).
    table.insert(rules, {
      regex = [[(?<![/\\])\b([0-9A-Za-z][0-9A-Za-z._-]*\.(?i:]] .. click_open_extensions .. [[))\b(?![/\\])]],
      format = 'benpath:$1',
      highlight = 1,
    })

    return rules
  end)(),
}

-- Rendering path:
-- This repository's default front-end is OpenGL. On Windows, live reshaping
-- can be smoother with WebGpu on modern drivers.
-- Override via env var:
--   BENJAMINTERM_FRONT_END=OpenGL|WebGpu|Software
local env_front_end =
  normalize_front_end_name(os.getenv 'BENJAMINTERM_FRONT_END')

if is_windows then
  -- Use PowerShell 7 by default on Windows. Command history is a shell feature (PSReadLine),
  -- whereas cmd.exe history is not persisted across sessions by default.
  config.default_prog = { 'pwsh.exe', '-NoLogo' }
  config.win32_system_backdrop = 'Disable'

  config.front_end = env_front_end or 'WebGpu'
  if config.front_end == 'WebGpu' then
    config.webgpu_power_preference = 'HighPerformance'
  end
elseif env_front_end then
  config.front_end = env_front_end
end

return config

