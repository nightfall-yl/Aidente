#!/bin/zsh
set -euo pipefail
project_dir=${0:A:h:h}
cd "$project_dir"
# Match build_app.sh: prefer the active xcode-select SDK so the freshly
# built AidenteShared.swiftmodule (built with that same SDK) can be loaded.
# The hardcoded 15.5 path stays as a fallback for machines without Xcode.
sdk=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)
if [[ -z "$sdk" || ! -d "$sdk" ]]; then
    sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk"
fi
swiftc -parse-as-library BuildSupport/tests/ChargingRegressionTests.swift \
    -sdk "$sdk" -target arm64-apple-macosx14.0 \
    -I Build/Modules -I Vendor/SMCKit/Sources/SMC/include \
    -L Build -lAidenteShared -lsmc_power -lSMCKit Build/Objects/smc.o \
    -framework IOKit -o Build/ChargingRegressionTests
Build/ChargingRegressionTests
