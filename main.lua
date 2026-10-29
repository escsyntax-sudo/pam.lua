local PAM = require("pam")

local CELL = 24
local COLS = 32
local ROWS = 22

local grid
local agent
local path
local world_path
local npcs = {}
local hash

local function build_map()
  local rows = {}
  for y = 1, ROWS do
    local row = {}
    for x = 1, COLS do
      local wall = x == 1 or y == 1 or x == COLS or y == ROWS
      wall = wall or (x % 7 == 0 and y > 3 and y < ROWS - 3)
      wall = wall or (y % 6 == 0 and x > 8 and x < COLS - 8)
      row[x] = wall and "#" or "."
    end
    rows[y] = table.concat(row)
  end
  return PAM.Grid.from_rows(rows, { cell_size = CELL })
end

local function random_open_cell()
  for _ = 1, 200 do
    local x = math.random(2, COLS - 1)
    local y = math.random(2, ROWS - 1)
    if grid:is_walkable(x, y) then
      return x, y
    end
  end
  return 2, 2
end

function love.load()
  love.window.setTitle("PAM demo: click to path")
  local width, height = COLS * CELL, ROWS * CELL
  love.window.setMode(width, height, { resizable = true })
  math.randomseed(11)

  grid = build_map()
  local sx, sy = grid:cell_to_world(2, 2, true)
  agent = { x = sx, y = sy, radius = 7, speed = 150, index = 1 }

  for index = 1, 10 do
    local cx, cy = random_open_cell()
    local x, y = grid:cell_to_world(cx, cy, true)
    npcs[index] = {
      id = index,
      x = x,
      y = y,
      radius = 6,
      angle = math.random() * math.pi * 2,
      speed = 30 + math.random() * 25,
    }
  end
end

function love.mousepressed(mx, my, button)
  if button ~= 1 then
    return
  end
  local goal_x, goal_y = grid:world_to_cell(mx, my)
  if not grid:is_walkable(goal_x, goal_y) then
    return
  end
  local start_x, start_y = grid:world_to_cell(agent.x, agent.y)
  local raw = PAM.astar.find(grid, { x = start_x, y = start_y }, { x = goal_x, y = goal_y })
  if not raw then
    return
  end
  path = PAM.path.smooth(grid, raw)
  world_path = PAM.alignment.path_to_world(path, CELL, true)
  agent.index = 1
end

function love.update(dt)
  if world_path then
    local state, finished = PAM.love.follow(world_path, {
      x = agent.x,
      y = agent.y,
      index = agent.index,
    }, agent.speed, dt)
    agent.x = state.x
    agent.y = state.y
    agent.index = state.index
    if finished then
      world_path = nil
      path = nil
    end
  end

  hash = PAM.Spatial.new(48)
  for _, npc in ipairs(npcs) do
    npc.angle = npc.angle + (math.random() - 0.5) * dt * 3
    local nx = npc.x + math.cos(npc.angle) * npc.speed * dt
    local ny = npc.y + math.sin(npc.angle) * npc.speed * dt
    local cx, cy = grid:world_to_cell(nx, ny)
    if grid:is_walkable(cx, cy) then
      npc.x = nx
      npc.y = ny
    else
      npc.angle = npc.angle + math.pi
    end
    local item = hash:insert(npc.id, npc.x - npc.radius, npc.y - npc.radius, npc.radius * 2, npc.radius * 2)
    item.radius = npc.radius
  end

  PAM.alignment.resolve(npcs, hash, { radius = 6, strength = 0.6, max_push = 3 })
end

function love.draw()
  love.graphics.clear(0.07, 0.08, 0.1)
  PAM.love.draw_grid(grid, {
    colors = {
      blocked = { 0.16, 0.18, 0.23 },
      open = { 0.09, 0.1, 0.13 },
      line = { 1, 1, 1, 0.04 },
    },
  })

  if path then
    PAM.love.draw_path(path, {
      cell_size = CELL,
      color = { 0.4, 0.9, 0.65, 0.9 },
      nodes = true,
      node_radius = 2,
    })
  end

  for _, npc in ipairs(npcs) do
    love.graphics.setColor(0.35, 0.55, 1, 0.9)
    love.graphics.circle("fill", npc.x, npc.y, npc.radius)
  end

  love.graphics.setColor(1, 0.75, 0.3, 1)
  love.graphics.circle("fill", agent.x, agent.y, agent.radius)
  love.graphics.setColor(1, 1, 1, 0.85)
  love.graphics.print("Click a floor tile to route the agent", 12, 10)
end
