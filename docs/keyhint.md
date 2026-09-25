# Key hints (`lua/pure/keyhint.lua`)

A home-made which-key. Press `<Space>` (the leader) and wait: a window at the
bottom lists every key that can come next, with what it does, and names the
groups (`f → +Find`, `g → +Git`). Keep typing and it narrows down.

- Typed quickly, nothing is shown and nothing waits: `<Space>ff` runs at once.
- Works in visual mode too, with the mappings that exist there.
- A count or register typed before the leader still reaches the mapping
  (`3<Space>…`, `"a<Space>…`).

While the window is up:

| Key | What |
|---|---|
| `<BS>` | one key back |
| `<Esc>` | cancel |
| `<CR>` | run the mapping typed so far, when a longer one shares its keys |

In the list, `key → description` is a mapping; `key → +Name` is a group (the
name from `vim.g.pure_keyhint_groups`, or the only mapping's description, or
"N keymaps").

## Settings

```lua
vim.g.pure_keyhint_delay = 1000          -- ms before the window shows
vim.g.pure_keyhint_groups = {            -- in configs/keymaps.lua
  ['<leader>f'] = 'Find',
  ...
}
vim.g.pure_keyhint_triggers = { { 'n', '<leader>' }, { 'x', '<leader>' } }
vim.g.pure_keyhint = false               -- off
```

When you add a new group of mappings, give it a name in
`vim.g.pure_keyhint_groups` (top of `keymaps.lua`).

Colours: `PureHintKey`, `PureHintGroup`, `PureHintDesc`, `PureHintSep` (linked
to theme groups).

## How it works

`<leader>` becomes a buffer-local `<nowait>` mapping that reads the next keys
itself (`getcharstr()`), opening the window if nothing is typed for the
delay. Once the keys name exactly one mapping, the trigger is removed for a
moment and the keys are typed again, so the real mapping runs exactly as if
typed directly. That is why `timeoutlen` no longer matters after the leader.
