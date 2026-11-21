-- Computa's Rex actions.
--
-- Rex runs these on the Rex server's machine. The Computa app calls them with
-- `rex do <action>`, and they also appear in Rex's command palette.
--
-- The computad daemon only reports numbers. Anything that changes a Rex
-- session lives here instead, behind Rex's own access control.
--
-- Install: `just install-rex-actions`, then `rex config reload`.

local SHELL = "com.superlogical.terminal.shell"
local TOP_CANDIDATES = { "/opt/homebrew/bin/btop", "/usr/local/bin/btop", "/usr/bin/top" }

local function fail(message)
  -- Level 0 keeps Lua from prefixing the message with a file and line.
  error("computa: " .. message, 0)
end

local function file_exists(path)
  local file = io.open(path, "r")
  if file == nil then return false end
  file:close()
  return true
end

rex.action{
  name = "computa_open_top",
  title = "Computa: Open Process Viewer",
  description = "Open btop, or top if btop is not installed, in a new tab.",
  category = "Computa",
  keywords = "btop top processes",
  run = function(ctx)
    local program
    for _, candidate in ipairs(TOP_CANDIDATES) do
      if file_exists(candidate) then
        program = candidate
        break
      end
    end
    if program == nil then fail("neither btop nor top was found") end
    local window, err = rex.call("session.new_window", {
      session_id = ctx.session_id,
      window_label = "processes",
      layout = rex.layout.block{ flavor = SHELL, options = { command = { program } } },
    })
    if window == nil then fail("could not open a tab: " .. tostring(err)) end
    return { window_id = window.window_id, program = program }
  end,
}

rex.action{
  name = "computa_close_pane",
  title = "Computa: Close Pane",
  description = "Close one pane and end the program running in it.",
  category = "Computa",
  args = { block_id = "string", session_id = "string?" },
  run = function(ctx, args)
    local session_id = args.session_id or ctx.session_id
    local _, err = rex.call("block.close", { session_id = session_id, block_id = args.block_id })
    if err ~= nil then fail("could not close " .. args.block_id .. ": " .. tostring(err)) end
    return { closed = args.block_id, session_id = session_id }
  end,
}
