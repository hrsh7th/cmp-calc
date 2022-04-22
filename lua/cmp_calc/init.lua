local math_keys = {}
for key in pairs(math) do
  table.insert(math_keys, key)
end

local source = {}

source.new = function()
  return setmetatable({}, { __index = source })
end

source.get_trigger_characters = function()
  return { '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ' ', '+', '-', '/', '*', ')' }
end

source.get_keyword_pattern = function()
  return ([[\s*\zs\%(\d\+\%(\.\d\+\)\?\|+\|\-\|/\|\*\|%\|\^\|(\|)\|\s\|%PAT%\)\+]]):gsub(vim.pesc('%PAT%'), table.concat(math_keys, '\\|'))
end

source.complete = function(self, request, callback)
  local input = self:_trim_right(string.sub(request.context.cursor_before_line, request.offset))

  -- Resolve math_keys
  for _, key in ipairs(math_keys) do
    input = string.gsub(input, vim.pesc(key), 'math.' .. key)
  end

  -- Analyze column count and program script.
  local program, delta = self:_analyze(input)
  if not program then
    return callback()
  end

  -- Ignore if input has no math operators.
  if string.match(program, '^[%s%d%.]*$') ~= nil then
    return callback()
  end

  -- Ignore if failed to interpret to Lua.
  local m = load(('return (%s)'):format(program))
  if type(m) ~= 'function' then
    return callback()
  end
  local status, value = pcall(function()
    return '' .. m()
  end)

  -- Ignore if return values is not a number.
  if not status then
    return callback()
  end

  callback({
    items = {
      {
        word = value,
        label = value,
        filterText = input .. string.rep(table.concat(self:get_trigger_characters(), ''), 2), -- keep completion menu after operator or whitespace.
        textEdit = {
          range = {
            start = {
              line = request.context.cursor.row - 1,
              character = delta + request.offset - 1,
            },
            ['end'] = {
              line = request.context.cursor.row - 1,
              character = request.context.cursor.col - 1,
            },
          },
          newText = value,
        },
      },
      {
        word = input .. ' = ' .. value,
        label = program .. ' = ' .. value,
        filterText = input .. string.rep(table.concat(self:get_trigger_characters(), ''), 2), -- keep completion menu after operator or whitespace.
        textEdit = {
          range = {
            start = {
              line = request.context.cursor.row - 1,
              character = delta + request.offset - 1,
            },
            ['end'] = {
              line = request.context.cursor.row - 1,
              character = request.context.cursor.col - 1,
            },
          },
          newText = input .. ' = ' .. value,
        },
      }
    },
    isIncomplete = true,
  })
end

source._analyze = function(_, input)
  local stack = {}
  local unmatched_paren_count = 0
  local o = string.byte('(')
  local c = string.byte(')')
  for i = #input, 1, -1 do
    if string.byte(input, i) == c then
      table.insert(stack, ')')
    elseif string.byte(input, i) == o then
      if #stack > 0 then
        table.remove(stack, #stack)
      else
        unmatched_paren_count = unmatched_paren_count + 1
      end
    end
  end

  local program = input
  while true do
    local fixed_program = string.gsub(program, '^%s*%(', '')
    if fixed_program ~= program then
      unmatched_paren_count = unmatched_paren_count - 1
      program = fixed_program
    else
      break
    end
  end

  -- invalid math expression.
  if unmatched_paren_count > 0 then
    return nil, nil
  end

  return program, #input - #program
end

source._trim_right = function(_, text)
  return string.gsub(text, '[^%d%)]*$', '')
end

return source
