#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
if [[ ! -x "build/气间 AirPause.app/Contents/MacOS/AirPause" ]]; then
  ./build.command
fi
open "build/气间 AirPause.app"
