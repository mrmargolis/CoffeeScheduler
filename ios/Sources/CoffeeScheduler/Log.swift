import os

/// The app's logs, one per area: what went wrong where nothing is shown to
/// the user. Errors are logged as public text, since the log is only read
/// from the owner's own phone (see "Logs" in the README).
enum Log {
    static let subsystem = "net.mattmargolis.CoffeeScheduler"

    /// The copies to and from iCloud Drive.
    static let sync = Logger(subsystem: subsystem, category: "sync")
    /// Handing the schedule to the widget.
    static let widget = Logger(subsystem: subsystem, category: "widget")
    static let reminders = Logger(subsystem: subsystem, category: "reminders")
    /// Reads and writes of the database.
    static let store = Logger(subsystem: subsystem, category: "store")
}
