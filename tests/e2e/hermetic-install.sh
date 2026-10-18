#!/bin/bash
# Hermetic end-to-end run of bin/dotfiles-install on this Mac.
#
# Real: chezmoi init/apply of this working tree, every lifecycle script, the
# doctor, chezmoi verify, a zsh start, and the backup/restore.
# Not real: commands that change the OS outside $HOME. Two layers keep them
# away from the real Mac:
#   1. PATH shims log and succeed for brew, defaults, launchctl, killall,
#      sudo, pmset, mas, osascript, and similar tools.
#   2. sandbox-exec denies running the real binaries, denies the cfprefsd
#      IPC that `defaults` uses (it ignores $HOME), and denies file writes
#      outside the scratch folder. A script that escapes the shims fails
#      loudly instead of changing the Mac.
#
# Usage: tests/e2e/hermetic-install.sh <scratch-dir> [dotfiles-install args...]
# Leaves: <scratch>/home (the fake HOME), <scratch>/run.log, <scratch>/os-calls.log
#
# Environment:
#   E2E_BREAK=1   add a late failing chezmoi script, so apply fails after it
#                 has written files (tests the real auto-restore)
#   E2E_FULL=1    heal with the whole doctor (about 90 s); the default heals
#                 with a few core modules to keep the gate fast
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
SCRATCH="$(mkdir -p "$1" && cd "$1" && pwd -P)"
shift

OS_TOOLS=(brew defaults launchctl killall sudo pmset mas osascript softwareupdate
  mdutil tccutil open codesign xattr chflags scutil systemsetup networksetup spctl
  osacompile lsregister)

rm -rf "$SCRATCH/home" "$SCRATCH/shims" "$SCRATCH/tmp" "$SCRATCH/doctor"
mkdir -p "$SCRATCH/home/apps" "$SCRATCH/shims" "$SCRATCH/tmp"
: > "$SCRATCH/os-calls.log"

# The user's clone: this working tree, including uncommitted edits.
(cd "$REPO" && git ls-files -co --exclude-standard -z | rsync -a --from0 --files-from=- ./ "$SCRATCH/home/apps/dotfiles/")

# A Mac that already has a shell and git config the install will replace.
printf '# e2e original zshrc\n' > "$SCRATCH/home/.zshrc"
printf '[user]\n\tname = Original\n' > "$SCRATCH/home/.gitconfig"

if [ "${E2E_BREAK:-}" = "1" ]; then
  printf '#!/bin/bash\necho "e2e: injected failure after files were written" >&2\nexit 1\n' \
    > "$SCRATCH/home/apps/dotfiles/.chezmoiscripts/run_after_zz-e2e-injected-failure.sh"
fi

# Heal with the real doctor; scope it to the git, shell, and sync modules
# unless E2E_FULL=1. The doctor takes one --module, so run each in turn and
# fail when any of them fails.
if [ "${E2E_FULL:-}" = "1" ]; then
  printf '#!/bin/bash\nexec bash "%s/home/apps/dotfiles/bin/dotfiles-doctor" --fix "$@"\n' "$SCRATCH" > "$SCRATCH/doctor"
else
  printf '#!/bin/bash\nrc=0\nfor m in git shell sync; do\n  bash "%s/home/apps/dotfiles/bin/dotfiles-doctor" --fix --module "$m" "$@" || rc=1\ndone\nexit "$rc"\n' "$SCRATCH" > "$SCRATCH/doctor"
fi
chmod +x "$SCRATCH/doctor"

for tool in "${OS_TOOLS[@]}"; do
  cat > "$SCRATCH/shims/$tool" <<SHIM
#!/bin/bash
echo "$tool \$*" >> "$SCRATCH/os-calls.log"
case "$tool \${1:-}" in
  "brew --prefix") echo "$SCRATCH/fakebrew" ;;
  "osacompile -o")
    # Callers edit the bundle next, so leave a minimal app behind.
    mkdir -p "\$2/Contents/MacOS" "\$2/Contents/Resources"
    printf '<?xml version="1.0" encoding="UTF-8"?>\\n<plist version="1.0"><dict><key>CFBundleName</key><string>App</string></dict></plist>\\n' > "\$2/Contents/Info.plist" ;;
esac
exit 0
SHIM
  chmod +x "$SCRATCH/shims/$tool"
done

deny_exec=""
for tool in "${OS_TOOLS[@]}"; do
  for dir in /usr/bin /bin /usr/sbin /sbin /opt/homebrew/bin /usr/local/bin; do
    deny_exec+=" (literal \"$dir/$tool\")"
  done
done
cat > "$SCRATCH/profile.sb" <<PROFILE
(version 1)
(allow default)
(deny file-write* (subpath "/"))
(allow file-write* (subpath "$SCRATCH") (subpath "/dev") (subpath "/private/var/folders") (subpath "/var/folders"))
(deny process-exec$deny_exec)
(deny mach-lookup (global-name "com.apple.cfprefsd.daemon") (global-name "com.apple.cfprefsd.agent"))
PROFILE

cd "$SCRATCH/home/apps/dotfiles" || exit 1
env -i HOME="$SCRATCH/home" USER="${USER:-e2e}" LOGNAME="${USER:-e2e}" SHELL=/bin/zsh TERM=dumb \
  TMPDIR="$SCRATCH/tmp" LANG=en_US.UTF-8 \
  PATH="$SCRATCH/shims:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  DOTFILES_INSTALL_SKIP_XCODE_CHECK=1 \
  DOTFILES_INSTALL_DOCTOR="$SCRATCH/doctor" \
  sandbox-exec -f "$SCRATCH/profile.sb" bash bin/dotfiles-install "$@" > "$SCRATCH/run.log" 2>&1
