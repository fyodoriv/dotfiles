#!/bin/bash
# Print one fixed category; never repeat command output.
category=unknown
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    *'HTTP 401'*|*'HTTP 403'*|*unauthorized*) category=http-auth ;;
    *'HTTP 500'*|*'HTTP 503'*) category=http-server ;;
    *'permission denied'*|*'Permission denied'*|*'operation not permitted'*|*'Operation not permitted'*) category=permission ;;
    *'connection refused'*|*'Connection refused'*|*ECONNREFUSED*|*'timed out'*) category=connection ;;
  esac
done
printf '%s\n' "$category"
