# Resolve Agentbrew from the checkout in managed agent shells

**Hypothesis:** The managed session can prefer the existing Agentbrew shim
while preserving fnm's Node precedence. Today the fnm bin directory can
put an older Agentbrew executable before the checkout shim.

**Measurement:** Run the session environment fixtures in hosted CI.
Give a disposable shell both a fake fnm Agentbrew and the checkout shim.
Check the paths of `agentbrew` and `node`. Verify direct use of the
pinned fixture and fallback when the checkout shim is absent.

**Success:** In 1 conflicting PATH case, Agentbrew resolves to the checkout
shim. Node still resolves to fnm. The old executable still runs when called
by absolute path, and 0 owner runtime files change.

**Pivot:** If 1 case changes Node selection or requires replacing the
pinned runtime, keep the current PATH order and inspect the routing.

**Anchor:** [Current managed PATH function](https://github.com/fyodoriv/dotfiles/blob/06f775667093b26c682bf55465a17ed1dc3132f0/lib/dotfiles-endpoint-paths.sh)
and [Agentbrew packaged hook drift](https://github.com/fyodoriv/agentbrew/pull/1347).
