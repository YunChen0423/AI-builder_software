#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
xcrun swiftc -swift-version 5 -module-cache-path /tmp/airpause-swift-cache Sources/Session.swift Sources/Geometry.swift Sources/Interaction.swift Sources/MusicResponse.swift Tests/SessionTests.swift -o /tmp/airpause-session-tests
/tmp/airpause-session-tests
