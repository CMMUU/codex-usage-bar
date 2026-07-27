import Foundation

enum CodexExecutableLocatorError: LocalizedError {
  case notFound

  var errorDescription: String? {
    "未找到 Codex CLI。请安装 Codex，或通过 CODEX_BINARY_PATH 指定可执行文件。"
  }
}

public enum CodexExecutableLocator {
  public static func resolve(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    homeDirectory: String = NSHomeDirectory(),
    fileManager: FileManager = .default
  ) throws -> URL {
    var candidates: [String] = []

    if let override = environment["CODEX_BINARY_PATH"], !override.isEmpty {
      candidates.append(override)
    }

    candidates.append(contentsOf: [
      "/Applications/ChatGPT.app/Contents/Resources/codex",
      "/opt/homebrew/bin/codex",
      "/usr/local/bin/codex",
      "\(homeDirectory)/.local/bin/codex",
      "\(homeDirectory)/.npm-global/bin/codex",
    ])

    if let path = environment["PATH"] {
      candidates.append(
        contentsOf: path.split(separator: ":").map {
          "\($0)/codex"
        })
    }

    var visited = Set<String>()
    for candidate in candidates where visited.insert(candidate).inserted {
      if fileManager.isExecutableFile(atPath: candidate) {
        return URL(fileURLWithPath: candidate)
      }
    }

    throw CodexExecutableLocatorError.notFound
  }
}
