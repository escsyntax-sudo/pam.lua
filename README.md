# pam.lua

A 2D grid pathfinding and spatial alignment library for LÖVE2D. The core is plain Lua and does not import LÖVE, so the same code runs in a test harness or on a server. The optional `pam.love` module adds drawing and path following helpers.

What it includes:

- A* over a rectangular grid with a binary heap and configurable heuristics.
- Diagonal movement with optional corner cutting.
- Weighted cells and runtime blocking overrides.
- Line of sight, path smoothing, compression, and length helpers.
- A spatial hash for broad phase collision queries and neighbor lookups.
- World/cell conversion, formation layouts, and overlap separation for NPC groups.
- A LÖVE adapter for debug drawing and movement along a world path.

## Install

Copy the `pam` directory into your game next to `main.lua`. LÖVE adds the game root to `package.path`, so `require("pam")` resolves to `pam/init.lua`.

```
your-game/
  main.lua
  pam/
    init.lua
    astar.lua
    grid.lua
    heap.lua
    path.lua
    spatial.lua
    alignment.lua
    love.lua
  tests/
```

The library targets Lua 5.1 and LuaJIT. It also runs on Lua 5.4.

## Quick start

```lua
local PAM = require("pam")

local grid = PAM.Grid.from_rows({
  "..........",
  "..####....",
  "..........",
  "....##....",
  "..........",
}, { cell_size = 32 })

local start = { x = 1, y = 1 }
local goal = { x = 10, y = 5 }

local path, stats, reason = PAM.astar.find(grid, start, goal)
if not path then
  print("no route: " .. reason)
  return
end

local smooth = PAM.path.smooth(grid, path)
local world = PAM.alignment.path_to_world(smooth, grid.cell_size, true)

-- In love.update:
local state, finished = PAM.love.follow(world, { x = world[1].x, y = world[1].y }, 120, dt)
```

The repository root contains a demo `main.lua`. Run `love .` from a clone:

```sh
love .
```

Click any open tile. The agent routes to it, and the blue NPCs wander while pushing apart through the spatial hash.

## Grid

```lua
local grid = PAM.Grid.new({
  width = 64,
  height = 48,
  cell_size = 32,
  diagonal = true,
  corner_cutting = false,
  walkable = function(x, y)
    return heightmap[y][x] < 20
  end,
  cost = function(x, y)
    return terrain_cost[y][x]
  end,
})
```

`Grid.from_rows(rows, opts)` builds a grid from strings. `#` and `X` are blocked, every other character is open. The optional `walkable` callback is applied after the string map.

| Method | Result |
| --- | --- |
| `is_inside(x, y)` | Whether the cell is in bounds. |
| `is_walkable(x, y)` | Bounds, override, then the walkable callback. |
| `cell_cost(x, y)` | Cost for entering a walkable cell, or `nil` when blocked. Costs are clamped to a minimum of 1. |
| `set_blocked(x, y, blocked)` | Runtime override. `blocked` defaults to true. |
| `clear_override(x, y)` | Remove the override and fall back to the callback. |
| `neighbors(x, y)` | Array of `{ x, y, cost }`, orthogonal first, then diagonals. |
| `world_to_cell(wx, wy)` | 1-based cell coordinates. |
| `cell_to_world(cx, cy, center)` | Top-left pixel, or center when `center` is true. |

Cells are 1-based. When `corner_cutting` is false, a diagonal step needs both adjacent orthogonal cells to be walkable.

## A*

```lua
local path, stats, reason = PAM.astar.find(grid, start, goal, {
  diagonal = true,
  corner_cutting = false,
  heuristic = "octile",
  heuristic_weight = 1,
  max_nodes = 100000,
})
```

`start` and `goal` are tables with `x` and `y` cell coordinates. The return value is a list of cells including both ends, a stats table, and a failure reason.

| Option | Default | Meaning |
| --- | --- | --- |
| `diagonal` | grid setting | Allow eight way movement. |
| `corner_cutting` | grid setting | Allow diagonals between two blocked orthogonal cells. |
| `heuristic` | `"octile"` or `"manhattan"` | A name or a function of `dx, dy`. Names: `manhattan`, `euclidean`, `octile`, `chebyshev`. |
| `heuristic_weight` | `1` | Values above 1 trade optimality for speed. |
| `max_nodes` | `100000` | Expansion budget. |

Failure reasons are `"start outside grid"`, `"goal outside grid"`, `"start blocked"`, `"goal blocked"`, `"unreachable"`, and `"node budget exceeded"`.

Stats contain `expanded`, `generated`, `max_open`, and `open_at_end`.

`PAM.walkable_path(grid, start, goal, opts)` runs A* and smooths the result in one call.

## Path helpers

| Function | Result |
| --- | --- |
| `PAM.path.line_of_sight(grid, x0, y0, x1, y1, opts)` | True when every cell on the supercover line is walkable. |
| `PAM.path.each_cell(x0, y0, x1, y1, callback, opts)` | Visit cells on a line. Return `false` from the callback to stop. |
| `PAM.path.smooth(grid, path, opts)` | Greedy string pulling. Each segment is checked with line of sight. |
| `PAM.path.compress(path, opts)` | Remove collinear intermediate nodes. |
| `PAM.path.length(path, cell_size)` | Euclidean length of a cell path. |
| `PAM.path.reverse(path)` | Reversed copy. |

Line of sight uses a supercover DDA, so a diagonal that passes exactly through a blocked corner is rejected unless corner cutting is enabled.

## Spatial hash

```lua
local hash = PAM.Spatial.new(64)

local item = hash:insert("guard-1", x - 12, y - 12, 24, 24, "enemies")
hash:move("guard-1", new_x - 12, new_y - 12)
hash:remove("guard-1")

local hits = hash:query_rect(0, 0, 200, 200)
local nearby = hash:query_circle(player.x, player.y, 120)
local closest, distance = hash:nearest(player.x, player.y, 300)
```

`insert` uses axis aligned boxes with a top-left origin. A point is an item with zero width and height. Items can span several buckets, and queries deduplicate them before returning. Negative coordinates work.

| Method | Result |
| --- | --- |
| `insert(id, x, y, w, h, layer)` | Item. Reinserting an id replaces it. |
| `update(id, x, y, w, h)` | Moved item, or `nil` when the id is unknown. |
| `move(id, x, y)` | Position only update. |
| `remove(id)` | Boolean. |
| `get(id)` | Item or `nil`. |
| `query_rect(x, y, w, h, layer)` | Items whose boxes intersect the rectangle. |
| `query_point(x, y, layer)` | Items whose boxes contain the point. |
| `query_circle(x, y, r, layer)` | Items whose boxes intersect the circle. |
| `nearest(x, y, r, layer, filter)` | Closest item and distance, or `nil`. |
| `each(fn)` | Iterate `fn(item, id)`. |
| `clear()` | Empty the hash. |

Broad phase queries are proportional to the occupied buckets, not to the total number of items.

## Alignment

```lua
local cx, cy = PAM.alignment.world_to_cell(mouse_x, mouse_y, grid.cell_size)
local wx, wy = PAM.alignment.cell_to_world(cx, cy, grid.cell_size, true)
PAM.alignment.snap(53, 32)         -- 64
PAM.alignment.snap(53, 32, "floor") -- 32

local slots = PAM.alignment.formation(origin_x, origin_y, 6, {
  shape = "wedge",
  spacing = 28,
  angle = facing,
})
```

Formation shapes:

| Shape | Layout |
| --- | --- |
| `line` | Centered row, perpendicular to `angle`. |
| `column` | Single file behind the center, opposite `angle`. |
| `wedge` | Leader at the center, then rows spreading behind. |
| `circle` | Ring with `radius`, or a radius derived from `spacing`. |

Separation uses the spatial hash to find neighbors and returns a push vector per entity:

```lua
local pushes = PAM.alignment.separation(npcs, hash, {
  radius = 12,
  strength = 0.6,
  max_push = 4,
  layer = "enemies",
})

PAM.alignment.resolve(npcs, hash, { radius = 12 })
```

Entities need `id`, `x`, and `y` as center coordinates. `radius` is optional. Items inserted into the hash should use the same center convention (`x - radius`, `y - radius`, `radius * 2`, `radius * 2`). `resolve` applies the push vectors and updates the hash entries.

## LÖVE helpers

| Function | Result |
| --- | --- |
| `PAM.love.draw_grid(grid, opts)` | Filled blocked cells and optional grid lines. |
| `PAM.love.draw_path(path, opts)` | Polyline through a cell path, with optional nodes. |
| `PAM.love.draw_spatial(hash, opts)` | Outline of every tracked box. |
| `PAM.love.follow(path, state, speed, dt, opts)` | Consumes a world path and returns the new state plus a finished flag. |

`draw_grid` loops over every cell. It is meant for debug views, not production rendering.

## How A* is implemented

The open set is a binary min heap ordered by `f`, then `h`, then insertion order. The last key keeps results deterministic when several nodes share the same score. The closed set is a hash table keyed by cell index. `g` scores use the same index, and the parent map stores the previous cell index.

The heuristic is scaled by `heuristic_weight`. With the default weight of 1 and cell costs of at least 1, the search is optimal. Higher weights can expand fewer nodes and may return a longer path.

Path smoothing walks from the current node and picks the farthest node with line of sight, then repeats. The check is a supercover DDA, so it visits every cell the segment touches, not just sampled points.

Spatial hashing uses two levels of tables, one per column and one per row inside it. Items store the bucket keys they occupy, which makes updates and removals proportional to the item's footprint instead of the whole hash.

## Development

Run the tests with Lua 5.1 or newer:

```sh
lua tests/run.lua
```

The suite covers heap ordering, grid overrides and costs, corner rules, A* routes and failure reasons, weighted movement, line of sight, smoothing, compression, spatial queries, negative coordinates, formations, separation, and path following. CI runs Lua 5.1 and 5.4.

## License

MIT. See `LICENSE`.
