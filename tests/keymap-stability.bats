#!/usr/bin/env bats
# Tests for the WebStorm keymap + editor-font stability invariants.
#
# WHY: WebStorm rewrites jetbrains/keymap.xml whenever the user touches the IDE
# Keymap preferences UI (alphabetises actions, drops comments, occasionally
# nukes user-added bindings). These tests pin the file's structural invariants
# so a silent IDE rewrite that loses a user-added action surfaces as a failing
# test instead of an unnoticed dotfiles drift.

load test_helper

KEYMAP="$BATS_TEST_DIRNAME/../jetbrains/keymap.xml"
EDITOR_FONT="$BATS_TEST_DIRNAME/../jetbrains/editor-font.xml"

@test "keymap: file exists and is non-empty" {
  [ -f "$KEYMAP" ]
  [ -s "$KEYMAP" ]
}

@test "keymap: well-formed XML" {
  xmllint --noout "$KEYMAP"
}

@test "keymap: every <action> has a unique id (no IDE-duplicated entries)" {
  # WebStorm sometimes appends a second copy of an action when imports clash.
  # Catch the duplicate before it ships.
  local ids
  ids=$(grep -oE '<action id="[^"]+"' "$KEYMAP" | sort)
  local uniq
  uniq=$(printf '%s\n' "$ids" | sort -u)
  [ "$(printf '%s\n' "$ids" | wc -l)" = "$(printf '%s\n' "$uniq" | wc -l)" ]
}

@test "keymap: keeps the user-configured Codeium chat binding" {
  # com.codeium.intellij.command.CommandAction must stay bound to BOTH
  # 'shift meta i' and 'meta back_slash'. If WebStorm strips either, fail.
  grep -q 'id="com.codeium.intellij.command.CommandAction"' "$KEYMAP"
  grep -q 'first-keystroke="shift meta i"' "$KEYMAP"
  grep -q 'first-keystroke="meta back_slash"' "$KEYMAP"
}

@test "keymap: force-push binding survives (triple-modifier intentional friction)" {
  grep -q 'id="Vcs.Push.Force"' "$KEYMAP"
  grep -q 'first-keystroke="shift ctrl meta k"' "$KEYMAP"
}

@test "keymap: split-editor + move-tab bindings survive" {
  for id in SplitHorizontally SplitVertically Unsplit MoveTabDown MoveTabRight; do
    grep -q "id=\"$id\"" "$KEYMAP" || { echo "missing action id: $id"; return 1; }
  done
}

@test "keymap: parent shortcuts for GotoTypeDeclaration restored (no dropped ctrl+shift+b / mouse)" {
  # The child keymap deliberately re-declares all parent bindings so a child
  # definition doesn't silently drop them. If the mouse-shortcut disappears,
  # ctrl-click navigation breaks.
  awk '/id="GotoTypeDeclaration"/,/<\/action>/' "$KEYMAP" \
    | grep -q 'mouse-shortcut'
  awk '/id="GotoTypeDeclaration"/,/<\/action>/' "$KEYMAP" \
    | grep -qE 'first-keystroke="shift (meta|ctrl) b"'
}

@test "keymap: cleared bindings stay empty (no shortcut re-added by import)" {
  # These actions were intentionally cleared (no shortcut) to prevent the
  # parent's binding from firing. If a shortcut sneaks back in, fail.
  for id in EmmetNextEditPoint WD.UploadCurrentRemoteFileAction copilot.disposeInlays; do
    # The action must exist but have ZERO child <keyboard-shortcut> or
    # <mouse-shortcut> elements.
    local block
    block=$(awk -v id="$id" '
      $0 ~ "id=\""id"\"" {found=1}
      found {print}
      found && /<\/action>/ {exit}
      found && /\/>/ {exit}
    ' "$KEYMAP")
    if echo "$block" | grep -qE '(keyboard-shortcut|mouse-shortcut)'; then
      echo "expected cleared binding for $id, but found a shortcut:"
      echo "$block"
      return 1
    fi
  done
}

@test "editor-font: keeps only VERSION (IDE defaults win for everything else)" {
  # The user deliberately removed FONT_SIZE / FONT_FAMILY / LINE_SPACING /
  # USE_LIGATURES so the IDE's own font defaults apply. Make sure they don't
  # quietly re-appear on the next IDE-driven rewrite.
  xmllint --noout "$EDITOR_FONT"
  ! grep -qE 'name="(FONT_SIZE|FONT_SIZE_2D|FONT_FAMILY|LINE_SPACING|USE_LIGATURES)"' "$EDITOR_FONT"
  grep -q 'name="VERSION"' "$EDITOR_FONT"
}
