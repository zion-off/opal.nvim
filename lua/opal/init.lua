local M = {}

M.config = {
  prefix = "<leader>O",
  watch = false,
}

local cached_services = {}
local watch_job_id = nil
local unhealthy_set = {}

local function setup_highlights()
  local defaults = {
    OpalTitle = { link = "Title" },
    OpalBorder = { link = "FloatBorder" },
    OpalFooter = { link = "Comment" },
    OpalNormal = { link = "NormalFloat" },
  }
  for name, hl in pairs(defaults) do
    hl.default = true
    vim.api.nvim_set_hl(0, name, hl)
  end
end

local compact_commands = { status = true, down = true, up = true, restart = true, heal = true }
local interactive_commands = { tui = true }

local function run_in_float(cmd, title, opts)
  opts = opts or {}
  local cmd_name = opts.cmd_name

  local compact = cmd_name and compact_commands[cmd_name]
  local auto_close = cmd_name and interactive_commands[cmd_name]
  local w_ratio = compact and 0.7 or 0.9
  local h_ratio = compact and 0.5 or 0.9

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  local width = math.floor(vim.o.columns * w_ratio)
  local height = math.floor(vim.o.lines * h_ratio)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = title and { { " " .. title .. " ", "OpalTitle" } } or nil,
    title_pos = title and "center" or nil,
    footer = auto_close
        and { { " Ctrl-q  close ", "OpalFooter" } }
      or { { " Esc  close ", "OpalFooter" } },
    footer_pos = "center",
    noautocmd = true,
    zindex = 50,
  })
  vim.wo[win].winblend = 5
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].winhighlight = "Normal:OpalNormal,FloatBorder:OpalBorder"

  local job_id = vim.fn.jobstart(cmd, {
    term = true,
    on_exit = function(_, code)
      vim.schedule(function()
        if not vim.api.nvim_win_is_valid(win) then
          return
        end
        if auto_close and code == 0 then
          vim.api.nvim_win_close(win, true)
          return
        end
        if code == 0 then
          vim.api.nvim_win_set_config(win, {
            footer = { { "  Done │ q/Esc  close ", "DiagnosticOk" } },
            footer_pos = "center",
          })
        else
          vim.api.nvim_win_set_config(win, {
            footer = { { "  Exit " .. code .. " │ q/Esc  close ", "DiagnosticError" } },
            footer_pos = "center",
          })
        end
      end)
    end,
  })

  local function close()
    vim.fn.jobstop(job_id)
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.keymap.set("n", "q", close, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true })
  vim.keymap.set("t", "<C-q>", close, { buffer = buf, nowait = true })

  if auto_close then -- interactive (TUI): enter terminal mode, Esc passes through to the app
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) then
        vim.cmd("startinsert")
      end
    end)
  end
end

local function refresh_service_cache()
  vim.fn.jobstart("opal-cli service-list", {
    stdout_buffered = true,
    on_stdout = function(_, data)
      local services = {}
      for _, line in ipairs(data) do
        if line ~= "" and not line:match("^📋") then
          table.insert(services, line)
        end
      end
      table.sort(services)
      cached_services = services
    end,
  })
end

local function get_services(callback)
  vim.notify("Fetching services...", vim.log.levels.INFO)
  vim.fn.jobstart("opal-cli service-list", {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      local services = {}
      for _, line in ipairs(data) do
        if line ~= "" and not line:match("^📋") then
          table.insert(services, line)
        end
      end
      table.sort(services)
      cached_services = services
      vim.schedule(function()
        if #services == 0 then
          vim.notify("No services found", vim.log.levels.WARN)
          return
        end
        callback(services)
      end)
    end,
    on_stderr = function(_, data)
      local err = table.concat(data, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
      if err ~= "" then
        vim.schedule(function()
          vim.notify("opal-cli error: " .. err, vim.log.levels.ERROR)
        end)
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        vim.schedule(function()
          vim.notify("opal-cli exited with code " .. code, vim.log.levels.ERROR)
        end)
      end
    end,
  })
end

local function pick_service_and_run(cmd_name)
  get_services(function(services)
    local has_telescope, pickers = pcall(require, "telescope.pickers")
    if has_telescope then
      local finders = require("telescope.finders")
      local conf = require("telescope.config").values
      local actions = require("telescope.actions")
      local action_state = require("telescope.actions.state")
      local entry_display = require("telescope.pickers.entry_display")

      local displayer = entry_display.create({
        separator = " ",
        items = {
          { width = 2 },
          { remaining = true },
        },
      })

      local function make_display(entry)
        return displayer({
          { "󰡨", "Special" },
          entry.value,
        })
      end

      pickers
        .new({}, {
          prompt_title = "Opal: " .. cmd_name,
          finder = finders.new_table({
            results = services,
            entry_maker = function(service)
              return {
                value = service,
                display = make_display,
                ordinal = service,
              }
            end,
          }),
          sorter = conf.generic_sorter({}),
          attach_mappings = function(prompt_bufnr)
            actions.select_default:replace(function()
              local selection = action_state.get_selected_entry()
              actions.close(prompt_bufnr)
              if selection then
                run_in_float(
                  "opal-cli " .. cmd_name .. " " .. vim.fn.shellescape(selection.value),
                  cmd_name .. ": " .. selection.value,
                  { cmd_name = cmd_name }
                )
              end
            end)
            return true
          end,
        })
        :find()
    else
      vim.ui.select(services, {
        prompt = "Select service for " .. cmd_name .. ":",
        format_item = function(item)
          return "󰡨 " .. item
        end,
      }, function(choice)
        if choice then
          run_in_float(
            "opal-cli " .. cmd_name .. " " .. vim.fn.shellescape(choice),
            cmd_name .. ": " .. choice,
            { cmd_name = cmd_name }
          )
        end
      end)
    end
  end)
end

local function restart_unhealthy()
  vim.notify("Checking for unhealthy containers...", vim.log.levels.INFO)
  vim.fn.jobstart("docker ps --filter health=unhealthy --format '{{.Names}}'", {
    stdout_buffered = true,
    on_stdout = function(_, data)
      local containers = {}
      for _, line in ipairs(data) do
        if line ~= "" then
          table.insert(containers, line)
        end
      end
      vim.schedule(function()
        if #containers == 0 then
          vim.notify("No unhealthy containers found", vim.log.levels.INFO)
        else
          local escaped = vim.tbl_map(vim.fn.shellescape, containers)
          local cmd = "opal-cli restart " .. table.concat(escaped, " ")
          run_in_float(cmd, "heal: " .. table.concat(containers, ", "), { cmd_name = "heal" })
        end
      end)
    end,
  })
end

-- Health watcher ------------------------------------------------------------

local function watch_start()
  if watch_job_id then
    vim.notify("Opal: health watcher already running", vim.log.levels.WARN)
    return
  end

  -- Scan for already-unhealthy containers
  vim.fn.jobstart("docker ps --filter health=unhealthy --format '{{.Names}}'", {
    stdout_buffered = true,
    on_stdout = function(_, data)
      local names = {}
      for _, line in ipairs(data) do
        if line ~= "" then
          unhealthy_set[line] = true
          table.insert(names, line)
        end
      end
      if #names > 0 then
        vim.schedule(function()
          vim.notify("Opal: " .. #names .. " unhealthy container(s): " .. table.concat(names, ", "), vim.log.levels.WARN)
        end)
      end
    end,
  })

  -- Stream health events
  watch_job_id = vim.fn.jobstart(
    "docker events --filter event=health_status --format '{{.Actor.Attributes.name}}|{{.Status}}'",
    {
      on_stdout = function(_, data)
        for _, line in ipairs(data) do
          if line ~= "" then
            local name, status = line:match("^(.+)|health_status: (.+)$")
            if name and status then
              vim.schedule(function()
                if status == "unhealthy" then
                  unhealthy_set[name] = true
                  vim.notify("Container unhealthy: " .. name, vim.log.levels.WARN)
                elseif status == "healthy" then
                  if unhealthy_set[name] then
                    unhealthy_set[name] = nil
                    vim.notify("Container recovered: " .. name, vim.log.levels.INFO)
                  end
                end
              end)
            end
          end
        end
      end,
      on_exit = function(_, code)
        vim.schedule(function()
          watch_job_id = nil
          if code ~= 0 and code ~= 143 then -- 143 = SIGTERM (normal stop)
            vim.notify("Opal: health watcher exited (" .. code .. ")", vim.log.levels.WARN)
          end
        end)
      end,
    }
  )

  if watch_job_id <= 0 then
    watch_job_id = nil
    vim.notify("Opal: failed to start health watcher", vim.log.levels.ERROR)
  else
    vim.notify("Opal: health watcher started", vim.log.levels.INFO)
  end
end

local function watch_stop()
  if not watch_job_id then
    vim.notify("Opal: health watcher not running", vim.log.levels.WARN)
    return
  end
  vim.fn.jobstop(watch_job_id)
  watch_job_id = nil
  unhealthy_set = {}
  vim.notify("Opal: health watcher stopped", vim.log.levels.INFO)
end

local function watch_toggle()
  if watch_job_id then
    watch_stop()
  else
    watch_start()
  end
end

-- Public API ----------------------------------------------------------------

local function make_service_command(cmd_name)
  return function(service)
    if service then
      run_in_float(
        "opal-cli " .. cmd_name .. " " .. vim.fn.shellescape(service),
        cmd_name .. ": " .. service,
        { cmd_name = cmd_name }
      )
    else
      run_in_float("opal-cli " .. cmd_name, cmd_name .. ": all", { cmd_name = cmd_name })
    end
  end
end

M.tui = function()
  run_in_float("opal-cli tui", "Opal TUI", { cmd_name = "tui" })
end

M.build = make_service_command("build")
M.up = make_service_command("up")
M.down = make_service_command("down")
M.logs = make_service_command("logs")
M.status = make_service_command("status")
M.restart = make_service_command("restart")

M.pull = function()
  run_in_float("opal-cli pull", "pull", { cmd_name = "pull" })
end

M.heal = function()
  restart_unhealthy()
end

M.update = function()
  run_in_float("opal-cli update", "update", { cmd_name = "update" })
end

M.watch_start = watch_start
M.watch_stop = watch_stop
M.watch_toggle = watch_toggle

-- Pickers (interactive service selection)
M.pick_build = function()
  pick_service_and_run("build")
end

M.pick_up = function()
  pick_service_and_run("up")
end

M.pick_down = function()
  pick_service_and_run("down")
end

M.pick_logs = function()
  pick_service_and_run("logs")
end

M.pick_restart = function()
  pick_service_and_run("restart")
end

local service_taking_commands = { build = true, up = true, down = true, logs = true, status = true, restart = true }

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  setup_highlights()

  local subcommands = {
    tui = M.tui,
    build = M.build,
    up = M.up,
    down = M.down,
    pull = M.pull,
    logs = M.logs,
    status = M.status,
    restart = M.restart,
    heal = M.heal,
    update = M.update,
    watch = M.watch_toggle,
  }

  vim.api.nvim_create_user_command("Opal", function(args)
    local sub = args.fargs[1]
    local service = args.fargs[2]
    if not sub then
      M.tui()
      return
    end
    local fn = subcommands[sub]
    if not fn then
      vim.notify("Unknown Opal command: " .. sub, vim.log.levels.ERROR)
      return
    end
    fn(service)
  end, {
    nargs = "*",
    complete = function(_, line)
      local parts = vim.split(line, "%s+")
      if #parts == 2 then
        return vim.tbl_keys(subcommands)
      elseif #parts == 3 and service_taking_commands[parts[2]] then
        return cached_services
      end
    end,
  })

  -- Register with which-key if available
  local ok, wk = pcall(require, "which-key")
  if ok then
    local prefix = M.config.prefix
    wk.add({
      { prefix, group = "Opal", icon = { icon = "󰗀", color = "purple" } },

      -- TUI
      { prefix .. "c", M.tui, desc = "Launch TUI" },

      -- Global commands (uppercase)
      { prefix .. "B", M.build, desc = "Build all services", icon = { icon = "󰣖", color = "orange" } },
      { prefix .. "U", M.up, desc = "Up all services", icon = { icon = "󰐊", color = "green" } },
      { prefix .. "D", M.down, desc = "Down all services", icon = { icon = "󰓛", color = "red" } },
      { prefix .. "P", M.pull, desc = "Pull all services", icon = { icon = "󰇚", color = "cyan" } },
      { prefix .. "L", M.logs, desc = "Logs all services", icon = { icon = "󰷐", color = "yellow" } },
      { prefix .. "s", M.status, desc = "Status", icon = { icon = "󰋽", color = "blue" } },
      { prefix .. "R", M.restart, desc = "Restart all services", icon = { icon = "󰑓", color = "orange" } },
      { prefix .. "H", M.heal, desc = "Heal (restart unhealthy)", icon = { icon = "󰣐", color = "red" } },

      -- Service-specific commands (lowercase, opens picker)
      { prefix .. "b", M.pick_build, desc = "Build service...", icon = { icon = "󰣖", color = "orange" } },
      { prefix .. "u", M.pick_up, desc = "Up service...", icon = { icon = "󰐊", color = "green" } },
      { prefix .. "d", M.pick_down, desc = "Down service...", icon = { icon = "󰓛", color = "red" } },
      { prefix .. "l", M.pick_logs, desc = "Logs service...", icon = { icon = "󰷐", color = "yellow" } },
      { prefix .. "r", M.pick_restart, desc = "Restart service...", icon = { icon = "󰑓", color = "orange" } },

      -- Git
      { prefix .. "g", M.update, desc = "Git update repos", icon = { cat = "filetype", name = "git" } },

      -- Watch
      { prefix .. "w", M.watch_toggle, desc = "Toggle health watcher", icon = { icon = "󰗈", color = "green" } },
    })
  end

  refresh_service_cache()

  if M.config.watch then
    watch_start()
  end

  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      if watch_job_id then
        vim.fn.jobstop(watch_job_id)
        watch_job_id = nil
      end
    end,
  })
end

return M
