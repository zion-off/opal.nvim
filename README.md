# opal.nvim

neovim plugin for opal-cli. manage docker compose services from inside neovim — build, deploy, tail logs, check status, and monitor container health without leaving your editor.

## how it works

1. run any opal command — output appears in a floating terminal window
2. use uppercase keys for all services, lowercase to pick a specific service via telescope
3. press `Esc` or `q` to close the float when done
4. optionally enable the health watcher to get notified when containers go unhealthy

## requirements

- neovim >= 0.10
- opal-cli
- [which-key.nvim](https://github.com/folke/which-key.nvim)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (optional, for service picker)

## installation

### lazy.nvim

```lua
{
  "zion-off/opal.nvim",
  dependencies = { "folke/which-key.nvim" },
  opts = {},
}
```

### packer.nvim

```lua
use {
  "zion-off/opal.nvim",
  requires = { "folke/which-key.nvim" },
  config = function()
    require("opal").setup({})
  end,
}
```

### manual

clone the repo into your neovim packages directory:

```sh
git clone https://github.com/zion-off/opal.nvim \
  ~/.local/share/nvim/site/pack/plugins/start/opal.nvim
```

then add `require("opal").setup({})` to your config. make sure [which-key.nvim](https://github.com/folke/which-key.nvim) is also installed.

## configuration

these are the defaults — pass any overrides to `setup()`:

```lua
require("opal").setup({
  -- key prefix for all opal bindings
  prefix = "<leader>O",

  -- auto-start the container health watcher on setup
  watch = false,
})
```

## commands & keybindings

### commands

| command                   | description                                   |
| ------------------------- | --------------------------------------------- |
| `:Opal`                   | launch the opal TUI                           |
| `:Opal build [service]`   | build all services, or a specific one         |
| `:Opal up [service]`      | start all services, or a specific one         |
| `:Opal down [service]`    | stop all services, or a specific one          |
| `:Opal restart [service]` | restart all services, or a specific one       |
| `:Opal logs [service]`    | tail logs for all services, or a specific one |
| `:Opal status`            | show status of all services                   |
| `:Opal pull`              | pull latest images                            |
| `:Opal update`            | git update repos                              |
| `:Opal heal`              | restart any unhealthy containers              |
| `:Opal watch`             | toggle the health watcher                     |

### keybindings

all keybindings are under the configured prefix (default `<leader>O`).

| key | description                 |
| --- | --------------------------- |
| `c` | launch TUI                  |
| `s` | status                      |
| `B` | build all                   |
| `U` | up all                      |
| `D` | down all                    |
| `R` | restart all                 |
| `L` | logs all                    |
| `P` | pull                        |
| `H` | heal (restart unhealthy)    |
| `b` | build service... (picker)   |
| `u` | up service... (picker)      |
| `d` | down service... (picker)    |
| `r` | restart service... (picker) |
| `l` | logs service... (picker)    |
| `g` | git update repos            |
| `w` | toggle health watcher       |

### floating terminal

| key         | mode     | description           |
| ----------- | -------- | --------------------- |
| `q` / `Esc` | normal   | close the float       |
| `Ctrl-q`    | terminal | close the float (TUI) |

the footer updates to show exit status when the command finishes.

## health watcher

the health watcher uses `docker events` to listen for container health status changes in real time. it's essentially zero-cost — just a persistent connection to the docker daemon that fires only when something changes.

when enabled, you get `vim.notify` messages for:

- containers becoming unhealthy
- containers recovering to healthy

enable it on startup with `watch = true` in your config, or toggle it on demand with `<leader>Ow` / `:Opal watch`.

## highlight groups

customize the floating window appearance by overriding these highlight groups:

| group        | default link  | description             |
| ------------ | ------------- | ----------------------- |
| `OpalTitle`  | `Title`       | float window title      |
| `OpalBorder` | `FloatBorder` | float window border     |
| `OpalFooter` | `Comment`     | float window footer     |
| `OpalNormal` | `NormalFloat` | float window background |

## license

BSD 2-Clause
