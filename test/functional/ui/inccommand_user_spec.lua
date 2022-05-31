local helpers = require('test.functional.helpers')(after_each)
local Screen = require('test.functional.ui.screen')
local clear = helpers.clear
local exec_lua = helpers.exec_lua
local insert = helpers.insert
local feed = helpers.feed
local command = helpers.command

-- Implements a :Replace command that works like :substitute.
local setup_replace_cmd = [[
  local function show_replace_preview(buf, use_preview_win, preview_ns, preview_buf, matches)
    -- Find the width taken by the largest line number, used for padding the line numbers
    local highest_lnum = math.max(matches[#matches][1], 1)
    local highest_lnum_width = math.floor(math.log10(highest_lnum))
    local preview_buf_line = 0

    vim.g.prevns = preview_ns
    vim.g.prevbuf = preview_buf

    for _, match in ipairs(matches) do
      local lnum = match[1]
      local line_matches = match[2]
      local prefix

      if use_preview_win then
        prefix = string.format(
          '|%s%d| ',
          string.rep(' ', highest_lnum_width - math.floor(math.log10(lnum))),
          lnum
        )

        vim.api.nvim_buf_set_lines(
          preview_buf,
          preview_buf_line,
          preview_buf_line,
          0,
          { prefix .. vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] }
        )
      end

      for _, line_match in ipairs(line_matches) do
        vim.api.nvim_buf_add_highlight(
          buf,
          preview_ns,
          'Substitute',
          lnum - 1,
          line_match[1],
          line_match[2]
        )

        if use_preview_win then
          vim.api.nvim_buf_add_highlight(
            preview_buf,
            preview_ns,
            'Substitute',
            preview_buf_line,
            #prefix + line_match[1],
            #prefix + line_match[2]
          )
        end
      end

      preview_buf_line = preview_buf_line + 1
    end

    if use_preview_win then
      return 2
    else
      return 1
    end
  end

  local function do_replace(opts, preview, preview_ns, preview_buf)
    local pat1 = opts.fargs[1] or ''
    local pat2 = opts.fargs[2] or ''
    local line1 = opts.line1
    local line2 = opts.line2

    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, line1 - 1, line2, 0)
    local matches = {}

    for i, line in ipairs(lines) do
      local startidx, endidx = 0, 0
      local line_matches = {}
      local num = 1

      while startidx ~= -1 do
        local match = vim.fn.matchstrpos(line, pat1, 0, num)
        startidx, endidx = match[2], match[3]

        if startidx ~= -1 then
          line_matches[#line_matches+1] = { startidx, endidx }
        end

        num = num + 1
      end

      if #line_matches > 0 then
        matches[#matches+1] = { line1 + i - 1, line_matches }
      end
    end

    local new_lines = {}

    for _, match in ipairs(matches) do
      local lnum = match[1]
      local line_matches = match[2]
      local line = lines[lnum - line1 + 1]
      local pat_width_differences = {}

      -- If previewing, only replace the text in current buffer if pat2 isn't empty
      -- Otherwise, always replace the text
      if pat2 ~= '' or not preview then
        if preview then
          for _, line_match in ipairs(line_matches) do
            local startidx, endidx = unpack(line_match)
            local pat_match = line:sub(startidx + 1, endidx)

            pat_width_differences[#pat_width_differences+1] =
              #vim.fn.substitute(pat_match, pat1, pat2, 'g') - #pat_match
          end
        end

        new_lines[lnum] = vim.fn.substitute(line, pat1, pat2, 'g')
      end

      -- Highlight the matches if previewing
      if preview then
        local idx_offset = 0
        for i, line_match in ipairs(line_matches) do
          local startidx, endidx = unpack(line_match)
          -- Starting index of replacement text
          local repl_startidx = startidx + idx_offset
          -- Ending index of the replacement text (if pat2 isn't empty)
          local repl_endidx

          if pat2 ~= '' then
            repl_endidx = endidx + idx_offset + pat_width_differences[i]
          else
            repl_endidx = endidx + idx_offset
          end

          if pat2 ~= '' then
            idx_offset = idx_offset + pat_width_differences[i]
          end

          line_matches[i] = { repl_startidx, repl_endidx }
        end
      end
    end

    for lnum, line in pairs(new_lines) do
      vim.api.nvim_buf_set_lines(buf, lnum - 1, lnum, false, { line })
    end

    if preview then
      local lnum = vim.api.nvim_win_get_cursor(0)[1]
      -- Use preview window only if preview buffer is provided and range isn't just the current line
      local use_preview_win = (preview_buf ~= nil) and (line1 ~= lnum or line2 ~= lnum)
      return show_replace_preview(buf, use_preview_win, preview_ns, preview_buf, matches)
    end
  end

  local function replace(opts)
    do_replace(opts, false)
  end

  local function replace_preview(opts, preview_ns, preview_buf)
    return do_replace(opts, true, preview_ns, preview_buf)
  end

  -- ":<range>Replace <pat1> <pat2>"
  -- Replaces all occurences of <pat1> in <range> with <pat2>
  vim.api.nvim_create_user_command(
    'Replace',
    replace,
    { nargs = '*', range = '%', addr = 'lines',
      preview = replace_preview }
  )
]]

describe("'inccommand' for user commands", function()
  local screen

  before_each(function()
    clear()
    screen = Screen.new(40, 17)
    screen:set_default_attr_ids({
      [1] = {background = Screen.colors.Yellow1},
      [2] = {foreground = Screen.colors.Blue1, bold = true},
      [3] = {reverse = true},
      [4] = {reverse = true, bold = true}
    })
    screen:attach()
    exec_lua(setup_replace_cmd)
    command('set cmdwinheight=5')
    insert[[
      text on line 1
      more text on line 2
      oh no, even more text
      will the text ever stop
      oh well
      did the text stop
      why won't it stop
      make the text stop
    ]]
  end)

  it('works with inccommand=nosplit', function()
    command('set inccommand=nosplit')
    feed(':Replace text cats')
    screen:expect([[
        {1:cats} on line 1                        |
        more {1:cats} on line 2                   |
        oh no, even more {1:cats}                 |
        will the {1:cats} ever stop               |
        oh well                               |
        did the {1:cats} stop                     |
        why won't it stop                     |
        make the {1:cats} stop                    |
                                              |
      {2:~                                       }|
      {2:~                                       }|
      {2:~                                       }|
      {2:~                                       }|
      {2:~                                       }|
      {2:~                                       }|
      {2:~                                       }|
      :Replace text cats^                      |
    ]])
  end)

  it('works with inccommand=split', function()
    command('set inccommand=split')
    feed(':Replace text cats')
    screen:expect([[
        {1:cats} on line 1                        |
        more {1:cats} on line 2                   |
        oh no, even more {1:cats}                 |
        will the {1:cats} ever stop               |
        oh well                               |
        did the {1:cats} stop                     |
        why won't it stop                     |
        make the {1:cats} stop                    |
                                              |
      {4:[No Name] [+]                           }|
      |1|   {1:cats} on line 1                    |
      |2|   more {1:cats} on line 2               |
      |3|   oh no, even more {1:cats}             |
      |4|   will the {1:cats} ever stop           |
      |6|   did the {1:cats} stop                 |
      {3:[Preview]                               }|
      :Replace text cats^                      |
    ]])
  end)

  it('properly closes preview when inccommand=split', function()
    command('set inccommand=split')
    feed(':Replace text cats<Esc>')
    screen:expect([[
        text on line 1                        |
        more text on line 2                   |
        oh no, even more text                 |
        will the text ever stop               |
        oh well                               |
        did the text stop                     |
        why won't it stop                     |
        make the text stop                    |
      ^                                        |
      {2:~                                       }|
      {2:~                                       }|
      {2:~                                       }|
      {2:~                                       }|
      {2:~                                       }|
      {2:~                                       }|
      {2:~                                       }|
                                              |
    ]])
  end)

  it('properly executes command when inccommand=split', function()
    command('set inccommand=split')
    feed(':Replace text cats<CR>')
    screen:expect([[
        cats on line 1                        |
        more cats on line 2                   |
        oh no, even more cats                 |
        will the cats ever stop               |
        oh well                               |
        did the cats stop                     |
        why won't it stop                     |
        make the cats stop                    |
      ^                                        |
      {2:~                                       }|
      {2:~                                       }|
      {2:~                                       }|
      {2:~                                       }|
      {2:~                                       }|
      {2:~                                       }|
      {2:~                                       }|
      :Replace text cats                      |
    ]])
  end)

  it('shows preview window only when range is not current line', function()
    command('set inccommand=split')
    feed('gg:.Replace text cats')
    screen:expect([[
        {1:cats} on line 1                        |
        more text on line 2                   |
        oh no, even more text                 |
        will the text ever stop               |
        oh well                               |
        did the text stop                     |
        why won't it stop                     |
        make the text stop                    |
                                              |
      {2:~                                       }|
      {2:~                                       }|
      {2:~                                       }|
      {2:~                                       }|
      {2:~                                       }|
      {2:~                                       }|
      {2:~                                       }|
      :.Replace text cats^                     |
    ]])
  end)
end)
