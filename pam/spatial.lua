local Spatial = {}
Spatial.__index = Spatial

local floor = math.floor
local sqrt = math.sqrt
local min = math.min
local max = math.max

function Spatial.new(cell_size)
  assert(cell_size == nil or cell_size > 0, "cell_size must be positive")
  return setmetatable({
    cell_size = cell_size or 64,
    buckets = {},
    items = {},
    count = 0,
  }, Spatial)
end

function Spatial:_range(x, y, w, h)
  local size = self.cell_size
  return floor(x / size), floor(y / size), floor((x + w) / size), floor((y + h) / size)
end

function Spatial:_attach(item)
  local x0, y0, x1, y1 = self:_range(item.x, item.y, item.w, item.h)
  local buckets = self.buckets
  local cells = {}
  local index = 0
  for cx = x0, x1 do
    local column = buckets[cx]
    if not column then
      column = {}
      buckets[cx] = column
    end
    for cy = y0, y1 do
      local bucket = column[cy]
      if not bucket then
        bucket = {}
        column[cy] = bucket
      end
      bucket[#bucket + 1] = item
      index = index + 1
      cells[index] = { cx, cy }
    end
  end
  item.cells = cells
end

function Spatial:_detach(item)
  local buckets = self.buckets
  for _, key in ipairs(item.cells) do
    local column = buckets[key[1]]
    if column then
      local bucket = column[key[2]]
      if bucket then
        for index = #bucket, 1, -1 do
          if bucket[index] == item then
            table.remove(bucket, index)
          end
        end
        if #bucket == 0 then
          column[key[2]] = nil
        end
      end
      if next(column) == nil then
        buckets[key[1]] = nil
      end
    end
  end
  item.cells = nil
end

function Spatial:insert(id, x, y, w, h, layer)
  assert(id ~= nil, "id is required")
  local existing = self.items[id]
  if existing then
    self:remove(id)
  end
  local item = {
    id = id,
    x = x,
    y = y,
    w = w or 0,
    h = h or 0,
    layer = layer,
  }
  self.items[id] = item
  self.count = self.count + 1
  self:_attach(item)
  return item
end

function Spatial:update(id, x, y, w, h)
  local item = self.items[id]
  if not item then
    return nil
  end
  self:_detach(item)
  item.x = x
  item.y = y
  if w ~= nil then
    item.w = w
  end
  if h ~= nil then
    item.h = h
  end
  self:_attach(item)
  return item
end

function Spatial:move(id, x, y)
  return self:update(id, x, y)
end

function Spatial:remove(id)
  local item = self.items[id]
  if not item then
    return false
  end
  self:_detach(item)
  self.items[id] = nil
  self.count = self.count - 1
  return true
end

function Spatial:get(id)
  return self.items[id]
end

function Spatial:clear()
  self.buckets = {}
  self.items = {}
  self.count = 0
end

function Spatial:query_rect(x, y, w, h, layer)
  local x0, y0, x1, y1 = self:_range(x, y, w, h)
  local found = {}
  local seen = {}
  local right = x + w
  local bottom = y + h
  local buckets = self.buckets
  for cx = x0, x1 do
    local column = buckets[cx]
    if column then
      for cy = y0, y1 do
        local bucket = column[cy]
        if bucket then
          for index = 1, #bucket do
            local item = bucket[index]
            if not seen[item] then
              seen[item] = true
              if (layer == nil or item.layer == layer) and item.x <= right and item.x + item.w >= x
                  and item.y <= bottom and item.y + item.h >= y then
                found[#found + 1] = item
              end
            end
          end
        end
      end
    end
  end
  return found
end

function Spatial:query_point(x, y, layer)
  return self:query_rect(x, y, 0, 0, layer)
end

local function rect_distance_sq(item, x, y)
  local closest_x = max(item.x, min(x, item.x + item.w))
  local closest_y = max(item.y, min(y, item.y + item.h))
  local dx = x - closest_x
  local dy = y - closest_y
  return dx * dx + dy * dy
end

function Spatial:query_circle(x, y, radius, layer)
  local candidates = self:query_rect(x - radius, y - radius, radius * 2, radius * 2, layer)
  local found = {}
  local radius_sq = radius * radius
  for _, item in ipairs(candidates) do
    if rect_distance_sq(item, x, y) <= radius_sq then
      found[#found + 1] = item
    end
  end
  return found
end

function Spatial:nearest(x, y, radius, layer, filter)
  local candidates = self:query_circle(x, y, radius, layer)
  local best
  local best_sq = math.huge
  for _, item in ipairs(candidates) do
    if not filter or filter(item) then
      local distance = rect_distance_sq(item, x, y)
      if distance < best_sq then
        best_sq = distance
        best = item
      end
    end
  end
  if not best then
    return nil
  end
  return best, sqrt(best_sq)
end

function Spatial:each(callback)
  for id, item in pairs(self.items) do
    callback(item, id)
  end
end

function Spatial:cell_of(x, y)
  return floor(x / self.cell_size), floor(y / self.cell_size)
end

function Spatial:cell_bounds(cx, cy)
  local size = self.cell_size
  return cx * size, cy * size, size, size
end

return Spatial
