#!/bin/bash
# Railway volumes are mounted root-owned and OpenSearch refuses to run as root.
set -euo pipefail

OS_HOME=/usr/share/opensearch
DATA_DIR="$OS_HOME/data"
mkdir -p "$DATA_DIR"
rm -rf "$DATA_DIR/lost+found"
chown -R 1000:1000 "$DATA_DIR"

exec chroot --userspec=1000:1000 / env HOME="$OS_HOME" \
  bash -c 'cd /usr/share/opensearch && exec ./opensearch-docker-entrypoint.sh "$@"' opensearch-start "$@"
