#!/bin/bash
# Parse a version string like "10.45.1c" and export IB_GATEWAY_MAJOR / _MINOR.
# Must be SOURCED (uses caller-scope variables and BASH_REMATCH); a child
# process invocation will set the variables only in the child.
#
# Usage:  source scripts/extract_ib_gateway_major_minor.sh "10.45.1c"
if [[ $1 =~ ([0-9]+)\.([0-9]+) ]]; then
    IB_GATEWAY_MAJOR=${BASH_REMATCH[1]}
    IB_GATEWAY_MINOR=${BASH_REMATCH[2]}
fi
