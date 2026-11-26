#!/bin/bash
# Provision the pinned compiler in the App Priority install scope.
app_priority_toolchain_prepare() {
  local scope="$1" target digest installer
  local release=1.100.0
  case "$(uname -m)" in
    arm64)
      target=aarch64-apple-darwin
      digest=63752a1919a3a4793173ec70f8f212621a7ce38ba6a246095984482f4de20f9f
      ;;
    x86_64)
      target=x86_64-apple-darwin
      digest=bc107f1fb0228de7fa32413c89c1b305cea9cd256e94b01150cd054128145429
      ;;
    *) return 2 ;;
  esac

  export CARGO_HOME="$scope/cargo" RUSTUP_HOME="$scope/rustup"
  export RUSTUP_TOOLCHAIN="$release-$target"
  local compiler_bin="$RUSTUP_HOME/toolchains/$RUSTUP_TOOLCHAIN/bin"
  if [ ! -x "$compiler_bin/cargo" ] || [ ! -x "$compiler_bin/rustc" ]; then
    (umask 077; mkdir -p "$scope")
    installer="$(mktemp "$scope/.rustup-init.XXXXXXXX")"
    (
      trap 'rm -f "$installer"' EXIT
      curl --fail --silent --show-error --proto '=https' --connect-timeout 15 --max-time 90 \
        "https://static.rust-lang.org/rustup/archive/1.29.3/$target/rustup-init" --output "$installer"
      printf '%s  %s\n' "$digest" "$installer" | shasum -a 256 --check
      chmod 700 "$installer"
      unset RUSTUP_DIST_SERVER RUSTUP_UPDATE_ROOT RUSTUP_OVERRIDE_HOST
      PATH=/usr/bin:/bin:/usr/sbin:/sbin "$installer" -y --no-modify-path --profile minimal \
        --default-host "$target" --default-toolchain "$release"
    )
  fi
  "$compiler_bin/rustc" --version | grep -F "rustc $release "
  export PATH="$compiler_bin:$PATH" RUSTC="$compiler_bin/rustc"
  export MACOSX_DEPLOYMENT_TARGET=13.0
  unset RUSTC_WRAPPER RUSTC_WORKSPACE_WRAPPER
}
