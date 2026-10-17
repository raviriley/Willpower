import Foundation
import Darwin

extension Process {
    /// Bound system commands and avoid filling a pipe while waiting for exit.
    @discardableResult
    func runWithTimeout(_ timeout: TimeInterval = 5) throws -> Data {
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var output: FileHandle?
        if standardOutput is Pipe {
            FileManager.default.createFile(atPath: outputURL.path, contents: nil,
                                           attributes: [.posixPermissions: 0o600])
            output = try FileHandle(forWritingTo: outputURL)
            standardOutput = output
        }
        defer {
            try? output?.close()
            if output != nil { try? FileManager.default.removeItem(at: outputURL) }
        }
        try run() // Never wait on a process whose launch failed.
        let watchdog = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        watchdog.schedule(deadline: .now() + timeout)
        watchdog.setEventHandler { [self] in
            if isRunning { kill(processIdentifier, SIGKILL) }
        }
        watchdog.resume()
        defer { watchdog.cancel() }
        waitUntilExit()
        guard terminationReason == .exit && terminationStatus == 0 else {
            throw NSError(domain: "Willpower.SystemCommand", code: Int(terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey:
                            "\(executableURL?.lastPathComponent ?? "Command") failed or timed out (status \(terminationStatus))."])
        }
        return output == nil ? Data() : try Data(contentsOf: outputURL)
    }
}
