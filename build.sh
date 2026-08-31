#!/usr/bin/env bash
set -e
export LD_LIBRARY_PATH="$HOME/.swift/lib:$LD_LIBRARY_PATH"
cd "$(dirname "$0")"
swift build
