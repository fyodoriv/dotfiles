#!/usr/bin/env bats
# gh_admin_scopes: false keeps the git doctor from requiring the workflow,
# admin:public_key and delete_repo gh scopes.

load test_helper

DOCTOR="$BATS_TEST_DIRNAME/../modules/git/doctor.sh"

scopes_for() {
  GH_ADMIN_SCOPES="$1"
  eval "$(sed -n '/^  _scopes="repo gist read:org"$/,/admin:public_key delete_repo"$/p' "$DOCTOR")"
  echo "$_scopes"
}

@test "gh_admin_scopes=false requires only repo, gist and read:org" {
  [ "$(scopes_for false)" = "repo gist read:org" ]
}

@test "gh_admin_scopes=true also requires workflow, admin:public_key and delete_repo" {
  [ "$(scopes_for true)" = "repo gist read:org workflow admin:public_key delete_repo" ]
}

@test "doctor and chezmoi config default gh_admin_scopes to false" {
  grep -q '{{ dig "gh_admin_scopes" false . }}' "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor"
  grep -q '{{- $ghAdminScopes := false -}}' "$BATS_TEST_DIRNAME/../.chezmoi.yaml.tmpl"
  grep -q 'hasKey . "gh_admin_scopes"' "$BATS_TEST_DIRNAME/../.chezmoi.yaml.tmpl"
  grep -q '^  gh_admin_scopes: {{ \$ghAdminScopes }}' "$BATS_TEST_DIRNAME/../.chezmoi.yaml.tmpl"
}

@test "doctor fails closed: unknown gh_admin_scopes means no admin scopes" {
  grep -q "dig \"gh_admin_scopes\" false . }}' 2>/dev/null || echo \"false\")" "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor"
  [ "$(scopes_for "")" = "repo gist read:org" ]
  ! grep -q 'gh auth refresh -h github.com -s delete_repo' "$DOCTOR"
}
