import os

/// Event-only logging (KTD6): no transcribed text, no request URLs,
/// no raw response bodies may ever be interpolated into a log message.
enum Log {
    static let app = Logger(subsystem: AppIdentity.logSubsystem, category: "app")
    static let audio = Logger(subsystem: AppIdentity.logSubsystem, category: "audio")
    static let stt = Logger(subsystem: AppIdentity.logSubsystem, category: "stt")
    static let hotkey = Logger(subsystem: AppIdentity.logSubsystem, category: "hotkey")
    static let insertion = Logger(subsystem: AppIdentity.logSubsystem, category: "insertion")
}
