#!/bin/bash
# Doctor checks for enterprise module
for tool in aws kubectl gradle java node docker gh jq; do
  case "$tool" in
    aws)     brew_pkg="awscli" ;;
    kubectl) brew_pkg="kubernetes-cli" ;;
    node)    brew_pkg="fnm" ;;
    docker)  brew_pkg="docker" ;;
    java)    brew_pkg="openjdk@21" ;;
    gh)      brew_pkg="gh" ;;
    *)       brew_pkg="$tool" ;;
  esac
  check "enterprise.$tool" "$tool installed" "command -v $tool" "brew install $brew_pkg"
done
