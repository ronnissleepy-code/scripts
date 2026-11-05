#!/bin/sh
# throwaway: local hashes for comparison with the box
cd "$(dirname "$0")" || exit 1
sha256sum shodan.sh hunt.sh worker.env
