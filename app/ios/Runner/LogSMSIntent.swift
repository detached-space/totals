import AppIntents
import Foundation

/// "Log SMS Entry" — invoked by the user's Messages automation Shortcut to hand
/// a bank SMS straight to Totals, with no Files action and no folder-permission
/// prompt. Appends to Documents/sms_queue.txt; the Dart side drains the queue on
/// launch/resume (MessageIngestService). Pure Swift — never touches Flutter.
///
/// Queue entry format (matched by MessageIngestService.parseQueueEntries):
///   <ISO8601 timestamp>\n---\n<raw SMS text>\n===\n
@available(iOS 16.0, *)
struct LogSMSIntent: AppIntent {
    static var title: LocalizedStringResource = "Log SMS Entry"
    static var description =
        IntentDescription("Queues a bank SMS for Totals to import on next open.")
    // Run in the background — no UI, works even if Totals isn't running.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Text")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$text) to Totals")
    }

    func perform() async throws -> some IntentResult {
        let docs = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let url = docs.appendingPathComponent("sms_queue.txt")
        let stamp = ISO8601DateFormatter().string(from: Date())
        let entry = "\(stamp)\n---\n\(text)\n===\n"
        guard let data = entry.data(using: .utf8) else { return .result() }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        return .result()
    }
}
