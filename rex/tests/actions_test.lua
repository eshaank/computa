-- Exercises Computa's Rex actions against a real Rex server.
--
-- Run it with scripts/test-rex-actions.sh, which makes a throwaway session
-- for it and removes the session afterwards. It opens a process viewer tab
-- and creates and closes one pane, all inside that session.

local repo = rex.args.repo
if repo == nil then
  rex.log("pass repo=/path/to/computa")
  rex.stop(2)
end
dofile(repo .. "/rex/computa.lua")

local SHELL = "com.superlogical.terminal.shell"
local failures = {}
local function check(name, condition)
  if not condition then failures[#failures + 1] = name end
end

-- Returns the set of pane ids and the list of tab labels in this session.
local function panes_and_tabs()
  local view = assert(rex.call("session.view", { session_id = rex.session_id }))
  local ids, labels = {}, {}
  for _, window in ipairs(view.windows) do
    labels[window.label] = true
    for _, layer in ipairs(window.layers) do
      for _, block in ipairs(layer.blocks) do ids[block.block_id] = true end
    end
  end
  return ids, labels
end

-- computa_open_top opens a tab labelled "processes".
local opened, open_err = rex.invoke("computa_open_top", {})
check("open_top returns a window: " .. tostring(open_err), opened ~= nil and opened.window_id ~= nil)
rex.sleep(0.5)
local _, labels = panes_and_tabs()
check("a tab labelled processes exists", labels["processes"] == true)

-- computa_close_pane closes exactly the pane it is given.
local split = assert(rex.call("session.new_split", {
  session_id = rex.session_id,
  direction = "horizontal",
  side = "after",
  layout = rex.layout.block{ flavor = SHELL, options = { command = { "sleep", "300" } } },
}))
local victim = split.block_ids[1]
local before = panes_and_tabs()
check("the new pane exists before closing", before[victim] == true)
local closed, close_err = rex.invoke("computa_close_pane", { block_id = victim })
check("close_pane reports the pane it closed: " .. tostring(close_err), closed ~= nil and closed.closed == victim)
rex.sleep(0.5)
local after = panes_and_tabs()
check("the pane is gone after closing", after[victim] == nil)
local survivors = 0
for id in pairs(before) do
  if id ~= victim and after[id] then survivors = survivors + 1 end
end
local others = 0
for id in pairs(before) do
  if id ~= victim then others = others + 1 end
end
check("no other pane was closed", survivors == others)

-- A pane that does not exist is refused with a message.
local bad, bad_err = rex.invoke("computa_close_pane", { block_id = "block:00000000-0000-0000-0000-000000000000" })
check("an unknown pane is refused", bad == nil and tostring(bad_err):find("could not close", 1, true) ~= nil)

if #failures > 0 then
  rex.log("FAILED: " .. table.concat(failures, "; "))
  rex.stop(1)
end
return { passed = 7 }
