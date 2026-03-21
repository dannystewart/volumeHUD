//
//  Logger.swift
//  by Danny Stewart (2026)
//  MIT License
//  https://github.com/dannystewart/volumeHUD
//

import Foundation

#if canImport(os)
    import os
#endif

// MARK: - Logger

public final class Logger: @unchecked Sendable {
    private enum LogLevel {
        case debug
        case info
        case warning
        case error
        case fault

        nonisolated var label: String {
            switch self {
            case .debug: "🛠️"
            case .info: "✅"
            case .warning: "⚠️"
            case .error: "❌"
            case .fault: "🔥"
            }
        }
    }

    private nonisolated static let timestampLock: NSLock = .init()
    private nonisolated static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    #if canImport(os)
        private let osLogger: os.Logger
    #endif

    private let category: String

    public nonisolated init(category: String = "volumeHUD") {
        self.category = category

        #if canImport(os)
            let subsystem = Bundle.main.bundleIdentifier ?? "com.dannystewart.volumeHUD"
            osLogger = os.Logger(subsystem: subsystem, category: category)
        #endif
    }

    private nonisolated static func formatTimestamp(_ date: Date) -> String {
        timestampLock.lock()
        defer { Self.timestampLock.unlock() }
        return timestampFormatter.string(from: date)
    }

    public nonisolated func debug(_ message: @autoclosure () -> String) {
        log(.debug, message())
    }

    public nonisolated func info(_ message: @autoclosure () -> String) {
        log(.info, message())
    }

    public nonisolated func warning(_ message: @autoclosure () -> String) {
        log(.warning, message())
    }

    public nonisolated func error(_ message: @autoclosure () -> String) {
        log(.error, message())
    }

    public nonisolated func fault(_ message: @autoclosure () -> String) {
        log(.fault, message())
    }

    private nonisolated func log(_ level: LogLevel, _ message: String) {
        let timestamp = Self.formatTimestamp(Date())
        let formatted = "\(timestamp) \(level.label) \(message)"

        #if canImport(os)
            switch level {
            case .debug:
                self.osLogger.debug("\(formatted, privacy: .public)")
            case .info:
                self.osLogger.info("\(formatted, privacy: .public)")
            case .warning:
                self.osLogger.notice("\(formatted, privacy: .public)")
            case .error:
                self.osLogger.error("\(formatted, privacy: .public)")
            case .fault:
                self.osLogger.fault("\(formatted, privacy: .public)")
            }
        #else
            print(formatted)
        #endif
    }
}
