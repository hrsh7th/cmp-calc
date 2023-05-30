local math_keys = {}
for key in pairs(math) do
  table.insert(math_keys, key)
end

local source = {}

source.new = function()
  return setmetatable({}, { __index = source })
end

source.get_position_encoding_kind = function()
  return 'utf-8'
end

source.get_trigger_characters = function()
  local chars = ',0123456789)'
  for _, key in ipairs(math_keys) do
    chars = chars .. key
  end
  return vim.fn.split(chars, [[\zs]])
end

source.get_keyword_pattern = function(self)
  return self._keyptn
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
    return callback({ isIncomplete = true })
  end

  -- Ignore if input has no math operators.
  if string.match(program, '^[%s%d%.]*$') ~= nil then
    return callback({ isIncomplete = true })
  end

  -- Ignore if failed to interpret to Lua.
  local m = load('return ' .. program)
  if type(m) ~= 'function' then
    return callback({ isIncomplete = true })
  end
  local status, value = pcall(m)

	-- Ignore if failed or not a number.
  if not status or type(value) ~= "number" then
    return callback({ isIncomplete = true })
	else
		value = tostring(value)
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
  local unmatched_parens = 0
  local o = string.byte('(')
  local c = string.byte(')')
  for i = #input, 1, -1 do
    if string.byte(input, i) == c then
      unmatched_parens=unmatched_parens-1
    elseif string.byte(input, i) == o then
      unmatched_parens=unmatched_parens+1
    end
  end

  -- invalid math expression.
  if unmatched_parens ~= 0 then
    return nil, nil
  end

  return input, 0
end

source._trim_right = function(_, text)
  return string.gsub(text, '%s*$', '')
end

-- Keyword matching pattern (vim regex)
source._keyptn = [[\s*\zs\(\d\+\(\.\d\+\)\?\|[,+/*%^()-]\|\s\|]] ..
  table.concat(math_keys, '\\|') .. '\\)\\+'

return source
