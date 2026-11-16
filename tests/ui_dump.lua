-- Dump the window's views as frame-tree JSON and lint them (wow-ui-harness: tests/vendor/wow-ui-harness, AGENTS.md
-- "Seeing the UI"). From the repository root:
--   lua tests/ui_dump.lua --out <work dir> [--locale plPL --prefix plPL/] [--font-root "Fonts\=<fonts dir>"]
--       [--all-files] [--atlases <file>] [--only home,picker] [--update-baseline]
-- Exit code 1 when the lint finds something not in tests/ui_lint_baseline.txt.

package.path = "./tests/?.lua;./tests/vendor/wow-ui-harness/lua/?.lua;" .. package.path
math.randomseed(42)

local mock = require("wowmock")
local runner = require("wowui.runner")
local views = require("ui_views")

os.exit(runner.Main(mock, views, arg))
