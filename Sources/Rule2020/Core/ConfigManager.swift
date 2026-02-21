import Foundation

final class ConfigManager {
    private let appName = "2020Rule"
    private let fileName = "config.json"
    private(set) var config: AppConfig
    let configPath: URL

    init() throws {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "ConfigManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No application support directory found"])
        }

        let dir = appSupport.appendingPathComponent(appName, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        configPath = dir.appendingPathComponent(fileName)

        if fm.fileExists(atPath: configPath.path) {
            let data = try Data(contentsOf: configPath)
            let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
            config = try decoded.validated()
        } else {
            config = AppConfig.defaults()
            try save()
        }
    }

    func update(_ newConfig: AppConfig) throws {
        config = try newConfig.validated()
        try save()
    }

    func save() throws {
        let data = try JSONEncoder.prettyPrinted.encode(config)
        try data.write(to: configPath, options: .atomic)
    }
}

private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
