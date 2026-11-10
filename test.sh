#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p build
swiftc Sources/Policy.swift Tests/main.swift -o build/policy-tests
build/policy-tests
swiftc Sources/Policy.swift Sources/Protocol.swift Tests/Protocol/main.swift -o build/protocol-tests
build/protocol-tests
swiftc Sources/MainRunLoop.swift Tests/ModalRunLoop/main.swift -o build/modal-tests
build/modal-tests
swiftc Sources/TrustedLoginwindow.swift Tests/TrustedLoginwindow/main.swift -o build/trust-tests -framework AppKit -framework Security
build/trust-tests
if [[ "${1:-}" == "--live-display" ]]; then
    swiftc Sources/Policy.swift Sources/MainRunLoop.swift Sources/DisplayWake.swift Tests/DisplayWakeRunLoop/main.swift -o build/display-wake-appkit-test -framework AppKit -framework IOKit
    build/display-wake-appkit-test
fi
