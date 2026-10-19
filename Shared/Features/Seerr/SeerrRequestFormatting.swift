import Foundation

enum SeerrRequestFormatting {
    static func displayName(for user: SeerrUser?) -> String {
        if let name = user?.displayName, !name.isEmpty {
            return name
        }
        if let id = user?.id {
            return String(localized: "seerr.manageRequests.userId \(id)")
        }
        return String(localized: "seerr.manageRequests.unknownUser")
    }

    static func avatarURL(for user: SeerrUser?, baseURL: URL?) -> URL? {
        guard let avatar = user?.avatar, !avatar.isEmpty else { return nil }
        if let url = URL(string: avatar), url.scheme != nil {
            return url
        }
        guard let baseURL else { return nil }
        let path = avatar.hasPrefix("/") ? String(avatar.dropFirst()) : avatar
        return baseURL.appendingPathComponent(path)
    }

    static func parsedDate(from value: String?) -> Date? {
        guard let value else { return nil }
        if let date = isoFormatterWithFractional.date(from: value) {
            return date
        }
        return isoFormatter.date(from: value)
    }

    static func mediumDateTimeText(for date: Date) -> String {
        mediumDateTimeFormatter.string(from: date)
    }

    static func relativeText(for date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let isoFormatterWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let mediumDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}
