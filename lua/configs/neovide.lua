if vim.g.neovide then
  vim.g.neovide_floating_blur_amount_x = 5.0
  vim.g.neovide_floating_blur_amount_y = 5.0
  vim.g.neovide_floating_corner_radius = 0.6

  vim.g.neovide_window_blurred = false -- Disable blur when window is unfocused
  vim.g.neovide_floating_shadow = false
  -- Opaque on startup; <leader>oxc goes to vim.g.transparencyAmount (configs/functions.lua).
  vim.g.neovide_opacity = 1.0
  vim.g.neovide_normal_opacity = 1.0
end

