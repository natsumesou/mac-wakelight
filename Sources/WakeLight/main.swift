import Foundation
import OSLog

let logger = Logger(subsystem: "com.indivisual.WOLFullWake", category: "WakeMonitor")

func report(_ message: String) {
    print("\(Date().formatted(date: .omitted, time: .standard))  \(message)")
    fflush(stdout)
    logger.info("\(message, privacy: .public)")
}

let timestampFormat = DateFormatter()
timestampFormat.locale = Locale(identifier: "en_US_POSIX")
timestampFormat.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
let eventPattern = /^(.{25})\s+(DarkWake|Wake|Sleep)\s+\t/

struct PowerEvent {
    let date: Date
    let isMagicPacket: Bool
    let line: String
}

@MainActor
func parseEvent(_ line: Substring) -> PowerEvent? {
    guard let match = line.prefixMatch(of: eventPattern),
          let date = timestampFormat.date(from: String(match.1)) else { return nil }
    return PowerEvent(
        date: date,
        isMagicPacket: match.2 == "DarkWake" && line.contains("Enet.MagicPacket"),
        line: String(line)
    )
}

@MainActor
func latestPowerEvent() throws -> PowerEvent? {
    let command = Process()
    let output = Pipe()
    command.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    command.arguments = ["-g", "log"]
    command.standardOutput = output
    try command.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    command.waitUntilExit()
    guard command.terminationStatus == 0 else {
        throw NSError(domain: "pmset", code: Int(command.terminationStatus))
    }
    for line in String(decoding: data, as: UTF8.self).split(separator: "\n").reversed() {
        if let event = parseEvent(line) { return event }
    }
    return nil
}

func turnOnDisplay() throws {
    let command = Process()
    command.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
    command.arguments = ["-u", "-t", "30"]
    command.terminationHandler = { finished in
        if finished.terminationStatus != 0 {
            report("caffeinate exited with status \(finished.terminationStatus)")
        }
    }
    try command.run()
}

if CommandLine.arguments.dropFirst() == ["--check-log"] {
    if let event = try latestPowerEvent() {
        report(event.line)
        report("Magic Packet dark wake: \(event.isMagicPacket)")
    } else {
        report("No power transition found")
    }
    exit(0)
}

let observeOnly = CommandLine.arguments.dropFirst() == ["--observe"]
guard observeOnly || CommandLine.arguments.count == 1 else {
    report("Usage: WakeLight [--observe | --check-log]")
    exit(2)
}

report(observeOnly ? "Watching sleep and wake (observe only)" : "Watching sleep and wake")
var previousContinuous = ContinuousClock.now
var previousAwake = SuspendingClock.now
var handledEvent: Date?

while true {
    Thread.sleep(forTimeInterval: 0.5)
    let continuous = ContinuousClock.now
    let awake = SuspendingClock.now
    let timeAsleep = previousContinuous.duration(to: continuous) - previousAwake.duration(to: awake)
    previousContinuous = continuous
    previousAwake = awake

    // Only read the power log after the hardware was actually asleep.
    guard timeAsleep >= .milliseconds(250) else { continue }
    let awakeTime = Date()
    report("Resume detected; checking power log")
    do {
        var foundRecentEvent = false
        for _ in 0..<2 {
            // pmset prints timestamps at whole-second resolution.
            if let event = try latestPowerEvent(),
               event.date >= awakeTime.addingTimeInterval(-2),
               event.date != handledEvent {
                foundRecentEvent = true
                report(event.line)
                if event.isMagicPacket {
                    handledEvent = event.date
                    if observeOnly {
                        report("Magic Packet matched; would request display wake")
                    } else {
                        try turnOnDisplay()
                        report("Magic Packet matched; requested display wake for 30 seconds")
                    }
                }
                break
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        if !foundRecentEvent { report("No new power transition found") }
    } catch {
        report("Wake check failed: \(error)")
    }
}
