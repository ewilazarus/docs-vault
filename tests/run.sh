#!/usr/bin/env bash
# Run every test script, with the bash that runs this one. Needs jq.
#
#   bash tests/run.sh          # or /bin/bash tests/run.sh, to check bash 3.2 on macOS

set -u
status=0
for test in "$(dirname "$0")"/*.test.sh; do
  "$BASH" "$test" || status=1
  echo
done
[ "$status" -eq 0 ] && echo "All tests passed." || echo "Some tests failed."
exit "$status"
