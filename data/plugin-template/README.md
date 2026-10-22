# @NAME@ (dotfiles plugin)

A company plugin for [dotfiles](https://github.com/fyodoriv/dotfiles).
The contract is in dotfiles `docs/plugins.md`.

- Install: `dotfiles plugin add <git-url>@<signed-tag>`
- Update to the newest signed tag: `dotfiles plugin update @NAME@`
- Release: create an SSH-signed annotated tag (`git tag -s vX.Y.Z -m vX.Y.Z`).
- Check: `dotfiles plugin lint @NAME@` and the CI workflow below.
