#!/bin/sh
# Builds the dev flavour the harness runs: build.noindex/Bridge Dev.app and build.noindex/bridge-dev.
cd "$(dirname "$0")/.."
exec ./build.sh --dev "$@"
