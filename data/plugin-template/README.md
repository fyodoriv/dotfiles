# @NAME@ (dotfiles plugin)

A company plugin for [dotfiles](https://github.com/fyodoriv/dotfiles).
The contract is in dotfiles `docs/plugin-system.md`.

- Install: `DOTFILES_PLUGINS_V2=1 dotfiles plugin add <git-url>@<signed-tag>`
- Release: create an SSH-signed annotated tag (`git tag -s vX.Y.Z -m vX.Y.Z`).
- Check: `dotfiles plugin lint @NAME@` and the CI workflow below.
