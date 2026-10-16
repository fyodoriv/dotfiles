#!/bin/bash
# Doctor checks for enterprise module
for tool in aws kubectl gradle java node docker gh jq; do
  case "$tool" in
    kubectl) brew_pkg="kubernetes-cli" ;;
    node)    brew_pkg="fnm" ;;
    docker)  brew_pkg="docker" ;;
    java)    brew_pkg="openjdk@21" ;;
    gh)      brew_pkg="gh" ;;
    *)       brew_pkg="$tool" ;;
  esac
  fix_cmd="brew install $brew_pkg"
  # AWS CLI v2 is a user-dir install; brew awscli pulls python@3.x.
  [ "$tool" = "aws" ] && fix_cmd="dotfiles-install-aws-gcloud --aws"
  check "enterprise.$tool" "$tool installed" "command -v $tool" "$fix_cmd"
done

# AWS CLI v2 and gcloud must come from the user-dir installs, not brew Python.
check "enterprise.aws_user_dir" "aws resolves under ~/.local/bin" \
  '[ "$(command -v aws)" = "$HOME/.local/bin/aws" ]' "dotfiles-install-aws-gcloud --aws"
check "enterprise.gcloud_user_dir" "gcloud resolves under ~/.local/bin" \
  '[ "$(command -v gcloud)" = "$HOME/.local/bin/gcloud" ]' "dotfiles-install-aws-gcloud --gcloud"
