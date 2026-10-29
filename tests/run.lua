local root = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") .. "/.."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local PAM = require("pam")
local Heap = PAM.Heap
local Grid = PAM.Grid
local Spatial = PAM.Spatial
local astar = PAM.astar
local pathlib = PAM.path
local align = PAM.alignment

local passed = 0
local failed = 0

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print("PASS " .. name)
  else
    failed = failed + 1
    print("FAIL " .. name .. ": " .. tostring(err))
  end
end

local function eq(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label or "value", tostring(expected), tostring(actual)), 2)
  end
end

local function near(actual, expected, tolerance, label)
  tolerance = tolerance or 0.0001
  if math.abs(actual - expected) > tolerance then
    error(string.format("%s: expected %s, got %s", label or "value", tostring(expected), tostring(actual)), 2)
  end
end

local function assert_path(grid, path)
  assert(path and #path > 0, "path exists")
  for index, cell in ipairs(path) do
    assert(grid:is_walkable(cell.x, cell.y), "walkable at " .. cell.x .. "," .. cell.y)
    if index > 1 then
      local previous = path[index - 1]
      local dx = math.abs(cell.x - previous.x)
      local dy = math.abs(cell.y - previous.y)
      assert(dx <= 1 and dy <= 1 and dx + dy > 0, "adjacent step")
    end
  end
end

test("heap pops in order", function()
  local heap = Heap.new()
  for _, value in ipairs({ 9, 3, 7, 1, 8, 2, 6, 4, 5 }) do
    heap:push(value)
  end
  eq(heap:size(), 9, "size")
  eq(heap:peek(), 1, "peek")
  for expected = 1, 9 do
    eq(heap:pop(), expected, "pop " .. expected)
  end
  eq(heap:empty(), true, "empty")
  eq(heap:pop(), nil, "pop empty")
end)

test("heap honours a custom comparator", function()
  local heap = Heap.new(function(a, b)
    return a.priority > b.priority
  end)
  heap:push({ priority = 1 })
  heap:push({ priority = 5 })
  heap:push({ priority = 3 })
  eq(heap:pop().priority, 5, "highest first")
end)

test("grid reads rows and overrides", function()
  local grid = Grid.from_rows({
    "..#..",
    ".....",
    "..X..",
  })
  eq(grid.width, 5, "width")
  eq(grid.height, 3, "height")
  eq(grid:is_walkable(3, 1), false, "hash blocked")
  eq(grid:is_walkable(3, 3), false, "X blocked")
  eq(grid:is_walkable(1, 1), true, "open")
  grid:set_blocked(1, 1, true)
  eq(grid:is_walkable(1, 1), false, "override blocks")
  grid:clear_override(1, 1)
  eq(grid:is_walkable(1, 1), true, "override cleared")
  eq(grid:is_walkable(0, 0), false, "outside")
end)

test("grid cost is at least one", function()
  local grid = Grid.new({
    width = 3,
    height = 3,
    cost = function(x, y)
      if x == 2 and y == 2 then
        return 0.25
      end
      return 4
    end,
  })
  eq(grid:cell_cost(2, 2), 1, "clamped cost")
  eq(grid:cell_cost(1, 1), 4, "custom cost")
  grid:set_blocked(3, 3, true)
  eq(grid:cell_cost(3, 3), nil, "blocked has no cost")
end)

test("corner cutting is off by default", function()
  local grid = Grid.new({ width = 3, height = 3 })
  grid:set_blocked(2, 1, true)
  local neighbors = grid:neighbors(1, 1)
  local has_diagonal = false
  for _, cell in ipairs(neighbors) do
    if cell.x == 2 and cell.y == 2 then
      has_diagonal = true
    end
  end
  eq(has_diagonal, false, "diagonal through corner blocked")

  local open_grid = Grid.new({ width = 3, height = 3, corner_cutting = true })
  open_grid:set_blocked(2, 1, true)
  local open_neighbors = open_grid:neighbors(1, 1)
  local allowed = false
  for _, cell in ipairs(open_neighbors) do
    if cell.x == 2 and cell.y == 2 then
      allowed = true
    end
  end
  eq(allowed, true, "corner cutting allows diagonal")
end)

test("astar finds a direct diagonal path", function()
  local grid = Grid.new({ width = 8, height = 8 })
  local path, stats = astar.find(grid, { x = 1, y = 1 }, { x = 5, y = 5 })
  assert(path, "path returned")
  eq(#path, 5, "four diagonal steps")
  eq(path[1].x, 1, "start x")
  eq(path[#path].y, 5, "goal y")
  assert(stats.expanded > 0, "stats expanded")
  near(pathlib.length(path), 4 * math.sqrt(2), 0.0001, "length")
end)

test("astar walks around a wall", function()
  local grid = Grid.from_rows({
    "..#..",
    "..#..",
    "..#..",
    "..#..",
    ".....",
  })
  local path = astar.find(grid, { x = 1, y = 1 }, { x = 5, y = 1 })
  assert_path(grid, path)
  for _, cell in ipairs(path) do
    assert(not (cell.x == 3 and cell.y < 5), "did not cross wall")
  end
end)

test("astar respects weighted cells", function()
  local grid = Grid.new({
    width = 5,
    height = 3,
    cost = function(x, y)
      if y == 1 and x > 1 and x < 5 then
        return 20
      end
      return 1
    end,
  })
  local path = astar.find(grid, { x = 1, y = 1 }, { x = 5, y = 1 })
  assert(path, "path exists")
  local crossed_expensive = false
  for _, cell in ipairs(path) do
    if cell.y == 1 and cell.x > 1 and cell.x < 5 then
      crossed_expensive = true
    end
  end
  eq(crossed_expensive, false, "path avoids expensive row")
end)

test("astar reports unreachable and blocked starts", function()
  local grid = Grid.from_rows({
    "..#..",
    "..#..",
    "..#..",
  })
  local path, _, reason = astar.find(grid, { x = 1, y = 1 }, { x = 5, y = 1 })
  eq(path, nil, "no path")
  eq(reason, "unreachable", "reason")
  local _, _, blocked_reason = astar.find(grid, { x = 3, y = 1 }, { x = 1, y = 1 })
  eq(blocked_reason, "start blocked", "blocked start")
end)

test("astar returns a single node for identical points", function()
  local grid = Grid.new({ width = 4, height = 4 })
  local path = astar.find(grid, { x = 2, y = 2 }, { x = 2, y = 2 })
  eq(#path, 1, "one node")
end)

test("astar honours the node budget", function()
  local grid = Grid.new({ width = 40, height = 40 })
  local path, _, reason = astar.find(grid, { x = 1, y = 1 }, { x = 40, y = 40 }, { max_nodes = 2 })
  eq(path, nil, "budget stops search")
  eq(reason, "node budget exceeded", "reason")
end)

test("astar accepts a custom heuristic", function()
  local grid = Grid.new({ width = 6, height = 6 })
  local path = astar.find(grid, { x = 1, y = 1 }, { x = 6, y = 6 }, {
    heuristic = function(dx, dy)
      return math.max(math.abs(dx), math.abs(dy))
    end,
  })
  assert(path, "custom heuristic works")
end)

test("line of sight follows walkable cells", function()
  local grid = Grid.new({ width = 5, height = 5 })
  eq(pathlib.line_of_sight(grid, 1, 1, 5, 5), true, "open diagonal")
  grid:set_blocked(3, 3, true)
  eq(pathlib.line_of_sight(grid, 1, 1, 5, 5), false, "blocked middle")
end)

test("smoothing keeps every segment visible", function()
  local grid = Grid.from_rows({
    ".....",
    "..#..",
    "..#..",
    ".....",
  })
  local raw = astar.find(grid, { x = 1, y = 1 }, { x = 5, y = 4 })
  local smoothed = pathlib.smooth(grid, raw)
  assert(#smoothed < #raw, "smoothed is shorter")
  for index = 2, #smoothed do
    assert(pathlib.line_of_sight(grid, smoothed[index - 1].x, smoothed[index - 1].y, smoothed[index].x, smoothed[index].y), "visible segment")
  end
  local both = PAM.walkable_path(grid, { x = 1, y = 1 }, { x = 5, y = 4 })
  assert(both, "walkable_path helper")
end)

test("compress removes collinear nodes", function()
  local path = {
    { x = 1, y = 1 },
    { x = 2, y = 1 },
    { x = 3, y = 1 },
    { x = 4, y = 1 },
    { x = 4, y = 2 },
  }
  local compressed = pathlib.compress(path)
  eq(#compressed, 3, "corner and ends")
  eq(compressed[2].x, 4, "corner kept")
  local reversed = pathlib.reverse(path)
  eq(reversed[1].x, 4, "reversed first")
end)

test("spatial hash stores across cells and deduplicates queries", function()
  local hash = Spatial.new(10)
  hash:insert("a", 5, 5, 12, 5)
  hash:insert("b", 100, 100, 2, 2)
  eq(hash.count, 2, "count")
  local hits = hash:query_rect(0, 0, 20, 10)
  eq(#hits, 1, "deduplicated hit")
  eq(hits[1].id, "a", "hit id")
  local none = hash:query_rect(50, 50, 5, 5)
  eq(#none, 0, "empty area")
end)

test("spatial hash updates and removes items", function()
  local hash = Spatial.new(10)
  hash:insert("npc", 5, 5, 2, 2)
  eq(#hash:query_rect(4, 4, 4, 4), 1, "found before move")
  hash:update("npc", 50, 50, 2, 2)
  eq(#hash:query_rect(4, 4, 4, 4), 0, "gone after move")
  eq(#hash:query_rect(49, 49, 4, 4), 1, "found at new position")
  eq(hash:remove("npc"), true, "removed")
  eq(hash.count, 0, "count after remove")
  eq(hash:remove("npc"), false, "missing remove")
end)

test("spatial circle and nearest queries", function()
  local hash = Spatial.new(16)
  hash:insert("close", 20, 20, 2, 2)
  hash:insert("far", 80, 80, 2, 2)
  local hits = hash:query_circle(20, 20, 10)
  eq(#hits, 1, "circle hit")
  local nearest, distance = hash:nearest(15, 15, 60)
  eq(nearest.id, "close", "nearest id")
  assert(distance < 15, "nearest distance")
  hash:insert("layer2", 21, 21, 2, 2, "hazards")
  eq(#hash:query_circle(20, 20, 10, "hazards"), 1, "layer filter")
end)

test("spatial hash handles negative coordinates", function()
  local hash = Spatial.new(10)
  hash:insert("negative", -25, -25, 4, 4)
  eq(#hash:query_rect(-30, -30, 10, 10), 1, "negative query")
end)

test("alignment converts between cells and world space", function()
  local cx, cy = align.world_to_cell(0, 0, 32)
  eq(cx, 1, "first cell x")
  eq(cy, 1, "first cell y")
  cx, cy = align.world_to_cell(64, 96, 32)
  eq(cx, 3, "third cell x")
  eq(cy, 4, "fourth cell y")
  local x, y = align.cell_to_world(3, 4, 32, true)
  eq(x, 80, "center x")
  eq(y, 112, "center y")
  eq(align.snap(53, 32), 64, "snap nearest")
  eq(align.snap(53, 32, "floor"), 32, "snap floor")
  eq(align.snap(53, 32, "ceil"), 64, "snap ceil")
end)

test("formations return the requested count and spacing", function()
  local line = align.formation(100, 100, 3, { spacing = 10, angle = 0 })
  eq(#line, 3, "line count")
  eq(line[1].y, 90, "line start")
  eq(line[3].y, 110, "line end")
  near(line[2].x, 100, 0.0001, "line center x")

  local column = align.formation(0, 0, 3, { spacing = 10, shape = "column" })
  eq(#column, 3, "column count")
  near(column[2].x, -10, 0.0001, "column steps back")

  local wedge = align.formation(0, 0, 5, { spacing = 10, shape = "wedge" })
  eq(#wedge, 5, "wedge count")

  local circle = align.formation(0, 0, 4, { radius = 10, shape = "circle" })
  eq(#circle, 4, "circle count")
  for _, point in ipairs(circle) do
    near(math.sqrt(point.x * point.x + point.y * point.y), 10, 0.0001, "circle radius")
  end
end)

test("path to world aligns cell centers", function()
  local world = align.path_to_world({ { x = 1, y = 1 }, { x = 2, y = 2 } }, 20, true)
  eq(world[1].x, 10, "first center")
  eq(world[2].y, 30, "second center")
  eq(world[2].cx, 2, "cell kept")
end)

test("separation pushes overlapping entities apart", function()
  local hash = Spatial.new(32)
  local entities = {
    { id = 1, x = 10, y = 10, radius = 5 },
    { id = 2, x = 14, y = 10, radius = 5 },
  }
  for _, entity in ipairs(entities) do
    local item = hash:insert(entity.id, entity.x - entity.radius, entity.y - entity.radius, entity.radius * 2, entity.radius * 2)
    item.radius = entity.radius
  end
  local pushes = align.separation(entities, hash, { radius = 5, strength = 0.5 })
  assert(pushes[1].dx < 0, "first pushed left")
  assert(pushes[2].dx > 0, "second pushed right")
  near(pushes[1].dx, -3, 0.5, "half overlap")
  align.resolve(entities, hash, { radius = 5, strength = 0.5 })
  assert(entities[1].x < 10, "entity moved")
  local item = hash:get(1)
  near(item.x, entities[1].x - 5, 0.0001, "spatial item follows entity")
end)

test("love follow consumes a world path", function()
  local world = { { x = 0, y = 0 }, { x = 10, y = 0 }, { x = 10, y = 10 } }
  local state, finished = PAM.love.follow(world, {}, 5, 1)
  eq(finished, false, "not finished")
  near(state.x, 5, 0.0001, "moved half way")
  state, finished = PAM.love.follow(world, state, 20, 1)
  eq(finished, true, "finished")
  eq(state.x, 10, "final x")
  eq(state.y, 10, "final y")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
  os.exit(1)
end
