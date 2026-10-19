import Foundation

enum SeerrRequestDisplayStatus: Hashable {
    case pending
    case declined
    case failed
    case requested
    case processing(progress: Double?)
    case partiallyAvailable
    case available
    case blacklisted
    case deleted

    init(request: SeerrRequest) {
        switch request.status {
        case .pending:
            self = .pending
            return
        case .declined:
            self = .declined
            return
        case .failed:
            self = .failed
            return
        case .approved, .completed, .none:
            break
        }

        let is4k = request.is4k ?? false
        let mediaStatus = is4k ? request.media?.status4k : request.media?.status
        let downloads = (is4k ? request.media?.downloadStatus4k : request.media?.downloadStatus) ?? []

        switch mediaStatus {
        case .available:
            self = .available
        case .partiallyAvailable:
            self = .partiallyAvailable
        case .processing:
            self = Self.processing(downloads: downloads)
        case .blacklisted:
            self = .blacklisted
        case .deleted:
            self = .deleted
        case .pending, .unknown, .none:
            self = .requested
        }
    }

    static func processing(downloads: [SeerrDownloadItem]) -> SeerrRequestDisplayStatus {
        guard !downloads.isEmpty else { return .requested }
        let progresses = downloads.compactMap(\.progress)
        guard !progresses.isEmpty else { return .processing(progress: nil) }
        return .processing(progress: progresses.reduce(0, +) / Double(progresses.count))
    }

    var labelKey: String {
        switch self {
        case .pending:
            "seerr.media.availability.pending"
        case .declined:
            "seerr.request.status.declined"
        case .failed:
            "seerr.request.status.failed"
        case .requested:
            "seerr.media.availability.requested"
        case .processing:
            "seerr.media.availability.processing"
        case .partiallyAvailable:
            "seerr.media.availability.partiallyAvailable"
        case .available:
            "seerr.media.availability.available"
        case .blacklisted:
            "seerr.media.availability.blacklisted"
        case .deleted:
            "seerr.request.status.deleted"
        }
    }
}
