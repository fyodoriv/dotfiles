# Runs in a child process with a cleaned env, the plugin root as cwd, and a
# timeout. Report only; the core never runs fix commands for plugins.
check "example.readme" "plugin README exists" "[ -f README.md ]" ""
