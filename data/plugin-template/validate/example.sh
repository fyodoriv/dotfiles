# Validate scripts call pass, fail, or audit_warn.
if [ -f dotfiles-plugin.yaml ]; then pass "manifest present"; else fail "manifest missing"; fi
