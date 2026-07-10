// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "LLMEcosystemDemo",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .executable(name: "LLMEcosystemDemo", targets: ["LLMEcosystemDemo"])
    ],
    dependencies: [
        .package(url: "https://github.com/rajatslakhina/foundation-model-provider-gateway.git", from: "1.0.0"),
        .package(url: "https://github.com/rajatslakhina/token-meter-kit.git", from: "1.0.0"),
        .package(url: "https://github.com/rajatslakhina/structured-output-kit.git", from: "1.0.0"),
        .package(url: "https://github.com/rajatslakhina/response-cache-kit.git", from: "1.0.0"),
        .package(url: "https://github.com/rajatslakhina/tool-registry-kit.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "LLMEcosystemDemo",
            dependencies: [
                .product(name: "ProviderGatewayKit", package: "foundation-model-provider-gateway"),
                .product(name: "TokenMeterKit", package: "token-meter-kit"),
                .product(name: "StructuredOutputKit", package: "structured-output-kit"),
                .product(name: "ResponseCacheKit", package: "response-cache-kit"),
                .product(name: "ToolRegistryKit", package: "tool-registry-kit")
            ]
        )
    ]
)
