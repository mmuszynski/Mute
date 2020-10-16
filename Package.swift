// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "Mute",
    platforms: [.iOS(.v9)],
    products: [.library(name: "Mute", targets: ["Mute"])],
    targets: [.target(name: "Mute", resources: [.process("Resources/mute.aiff")])]
)
