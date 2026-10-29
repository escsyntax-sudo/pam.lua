local Heap = {}
Heap.__index = Heap

local function default_less(a, b)
  return a < b
end

function Heap.new(less)
  return setmetatable({
    items = {},
    less = less or default_less,
  }, Heap)
end

function Heap:size()
  return #self.items
end

function Heap:empty()
  return #self.items == 0
end

function Heap:peek()
  return self.items[1]
end

function Heap:push(value)
  local items = self.items
  local index = #items + 1
  items[index] = value
  while index > 1 do
    local parent = math.floor(index / 2)
    if not self.less(items[index], items[parent]) then
      break
    end
    items[index], items[parent] = items[parent], items[index]
    index = parent
  end
  return value
end

function Heap:pop()
  local items = self.items
  local count = #items
  if count == 0 then
    return nil
  end
  local root = items[1]
  items[1] = items[count]
  items[count] = nil
  count = count - 1
  local index = 1
  while true do
    local left = index * 2
    if left > count then
      break
    end
    local right = left + 1
    local child = left
    if right <= count and self.less(items[right], items[left]) then
      child = right
    end
    if not self.less(items[child], items[index]) then
      break
    end
    items[index], items[child] = items[child], items[index]
    index = child
  end
  return root
end

return Heap
