# estyxq Hub

A NextUI menu with Overview, Playground, ESP, and Settings tabs. The ESP module handles skeletons and rings for R6 and R15 characters.

## Load from GitHub

Upload `menu.luau` and `esp.luau` to the same folder in a public GitHub repository. In `menu.luau`, set:

```lua
ScriptBaseURL = "https://raw.githubusercontent.com/USERNAME/REPOSITORY/main/",
```

Replace `USERNAME` and `REPOSITORY` with your values. If the scripts are in a subfolder, include it after `main/`. Use the files' exact names and capitalization.

Then run only this launcher, with your own menu URL:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/USERNAME/REPOSITORY/main/menu.luau"))()
```

The menu downloads NextUI from its official source. Enabling ESP downloads `esp.luau` from `ScriptBaseURL`, creates its controller, and applies the menu's settings. Disabling ESP releases its drawings and listeners. The controller is reused when you enable it again; a new menu session fetches the configured ESP source again.

For an ESP file hosted elsewhere, set `ESPSourceURL` to its full raw URL. That override takes priority over `ScriptBaseURL`.

To copy a raw URL, open a file on GitHub and click **Raw**. It should display Lua source text. A `github.com/.../blob/...` page is the file viewer rather than the raw source.

This simple loader uses public URLs without authentication. Private repositories need authenticated access. A branch such as `main` follows your uploaded changes; using a tag or commit in place of `main` selects a specific version.

## Run the two files separately

With both URL settings empty, execute `esp.luau` first to register its module, then execute `menu.luau` and enable ESP in its tab.

## Menu behavior

- **RightShift** shows or hides the hub. Settings can change the shortcut.
- Minimizing shows the draggable **estyxq Hub** pill on desktop and touch devices.
- Minimizing keeps ESP active.
- Closing, unloading, or reloading the menu stops its ESP and cleans up the interface.
- Appearance and ESP values are session-only.

The branding, versions, theme, and source URLs are together in `CONFIG` at the top of `menu.luau`.

NextUI documentation: https://diser.me/nextui/