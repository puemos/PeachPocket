#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p build/module-cache
/usr/bin/swiftc -swift-version 5 -parse-as-library -module-cache-path build/module-cache Sources/SessionPolicy.swift Tests/PolicyTests.swift -o build/policy-tests
build/policy-tests
/usr/bin/swiftc -swift-version 5 -parse-as-library -module-cache-path build/module-cache Sources/VibrationPattern.swift Tests/PatternTests.swift -o build/pattern-tests
build/pattern-tests
/usr/bin/clang -Wall -Wextra -Werror -mmacosx-version-min=14.0 Native/Haptic.c -o build/haptic-validation -framework CoreFoundation -framework IOKit
/usr/bin/ruby Tests/ActuatorArguments.rb build/haptic-validation
