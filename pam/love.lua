local M = {}

local function graphics()
  assert(love and love.graphics, "pam.love requires a running LOVE2D graphics context")
  return love.graphics
end

function M.draw_grid(grid, opts)
  opts = opts or {}
  local lg = graphics()
  local size = grid.cell_size
  local colors = opts.colors or {}
  local blocked = colors.blocked or { 0.16, 0.17, 0.2, 1 }
  local open = colors.open or { 0, 0, 0, 0 }
  local line = colors.line or { 1, 1, 1, 0.08 }

  for y = 1, grid.height do
    for x = 1, grid.width do
      if not grid:is_walkable(x, y) then
        lg.setColor(blocked)
        lg.rectangle("fill", (x - 1) * size, (y - 1) * size, size, size)
      elseif open[4] and open[4] > 0 then
        lg.setColor(open)
        lg.rectangle("fill", (x - 1) * size, (y - 1) * size, size, size)
      end
    end
  end

  if opts.lines ~= false then
    lg.setColor(line)
    for x = 0, grid.width do
      lg.line(x * size, 0, x * size, grid.height * size)
    end
    for y = 0, grid.height do
      lg.line(0, y * size, grid.width * size, y * size)
    end
  end
end

function M.draw_path(path, opts)
  opts = opts or {}
  if #path == 0 then
    return
  end
  local lg = graphics()
  local size = opts.cell_size or 1
  local points = {}
  local offset = opts.center ~= false and size / 2 or 0

  for index, point in ipairs(path) do
    local x = opts.world and point.x or (point.x - 1) * size + offset
    local y = opts.world and point.y or (point.y - 1) * size + offset
    points[#points + 1] = x
    points[#points + 1] = y
  end

  if #points >= 4 then
    lg.setColor(opts.color or { 0.35, 0.85, 0.6, 0.9 })
    lg.setLineWidth(opts.width or 2)
    lg.line(points)
  end

  if opts.nodes then
    lg.setColor(opts.node_color or { 0.95, 0.95, 0.95, 0.7 })
    local radius = opts.node_radius or 2
    for index = 1, #points, 2 do
      lg.circle("fill", points[index], points[index + 1], radius)
    end
  end
end

function M.draw_spatial(spatial, opts)
  opts = opts or {}
  local lg = graphics()
  lg.setColor(opts.color or { 0.3, 0.6, 1, 0.5 })
  lg.setLineWidth(opts.width or 1)
  spatial:each(function(item)
    lg.rectangle("line", item.x, item.y, item.w, item.h)
  end)
end

function M.follow(path, state, speed, dt, opts)
  opts = opts or {}
  state = state or {}
  state.index = state.index or 1
  if #path == 0 then
    return state, true
  end
  if not state.x then
    state.x = path[1].x
    state.y = path[1].y
  end

  local remaining = speed * dt
  local epsilon = opts.epsilon or 0.001

  while remaining > 0 and state.index <= #path do
    local target = path[state.index]
    local dx = target.x - state.x
    local dy = target.y - state.y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance <= epsilon then
      state.x = target.x
      state.y = target.y
      state.index = state.index + 1
    elseif distance <= remaining then
      state.x = target.x
      state.y = target.y
      state.index = state.index + 1
      remaining = remaining - distance
    else
      state.x = state.x + dx / distance * remaining
      state.y = state.y + dy / distance * remaining
      remaining = 0
    end
  end

  return state, state.index > #path
end

return M
