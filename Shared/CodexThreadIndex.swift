import Foundation

struct CodexThreadSummary: Codable, Equatable, Sendable {
    let id: String
    let threadName: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case threadName = "thread_name"
        case updatedAt = "updated_at"
    }
}

enum CodexThreadIndex {
    static func recentThreads(from data: Data, limit: Int = 6) -> [CodexThreadSummary] {
        let decoder = JSONDecoder()
        var newestByID: [String: CodexThreadSummary] = [:]

        for line in data.split(separator: 0x0A) {
            guard
                let thread = try? decoder.decode(CodexThreadSummary.self, from: Data(line)),
                UUID(uuidString: thread.id) != nil
            else { continue }

            if let existing = newestByID[thread.id], existing.updatedAt >= thread.updatedAt {
                continue
            }
            newestByID[thread.id] = thread
        }

        return newestByID.values
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(max(0, limit))
            .map(\.self)
    }
}
