import Foundation
import Observation

@MainActor
@Observable
final class SeerrRequestsViewModel {
    @ObservationIgnored private let store: SeerrStore
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let permissionService = SeerrPermissionService()
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var pendingNextPage = false

    var query: SeerrRequestQuery
    var requests: [SeerrRequest] = []
    var mediaDetails: [SeerrRequestMediaKey: SeerrMedia] = [:]
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    var isShowingError = false
    var busyRequestIDs: Set<Int> = []
    var hasLoaded = false
    var unavailableMediaKeys: Set<SeerrRequestMediaKey> = []

    private var totalResults = 0
    private let pageSize = 20

    init(store: SeerrStore, query: SeerrRequestQuery = SeerrRequestQuery(), session: URLSession = .shared) {
        self.store = store
        self.query = query
        self.session = session
    }

    var canManageRequests: Bool {
        permissionService.hasPermission(.manageRequests, user: store.user)
    }

    var totalCount: Int {
        totalResults
    }

    func canEdit(_ request: SeerrRequest) -> Bool {
        guard request.status == .pending else { return false }
        return canManageRequests || isOwnRequest(request)
    }

    func canDelete(_ request: SeerrRequest) -> Bool {
        if canManageRequests {
            return true
        }
        return request.status == .pending && isOwnRequest(request)
    }

    func canModerate(_ request: SeerrRequest) -> Bool {
        canManageRequests && request.status == .pending
    }

    func canRetry(_ request: SeerrRequest) -> Bool {
        canManageRequests && request.status == .failed
    }

    func isBusy(_ request: SeerrRequest) -> Bool {
        busyRequestIDs.contains(request.id)
    }

    func displayStatus(for request: SeerrRequest) -> SeerrRequestDisplayStatus {
        SeerrRequestDisplayStatus(request: request)
    }

    func reload() async {
        loadGeneration += 1
        let generation = loadGeneration
        pendingNextPage = false

        guard let requestRepository else {
            presentError(SeerrAPIError.invalidURL)
            hasLoaded = true
            return
        }

        isLoading = true
        errorMessage = nil
        defer {
            if generation == loadGeneration {
                isLoading = false
                hasLoaded = true
            }
        }

        do {
            let response = try await fetchPage(repository: requestRepository, skip: 0)
            guard generation == loadGeneration, !Task.isCancelled else { return }
            requests = response.results
            totalResults = response.pageInfo.results
            isLoading = false
            hasLoaded = true
            await loadMediaDetails(for: response.results, generation: generation)
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration, !Task.isCancelled else { return }
            requests = []
            totalResults = 0
            presentError(error)
            return
        }

        await continuePagingIfRequested(generation: generation)
    }

    func loadMoreIfNeeded(current request: SeerrRequest) async {
        guard request.id == requests.last?.id, requests.count < totalResults else { return }
        guard !isLoadingMore, !isLoading else {
            pendingNextPage = true
            return
        }
        guard let requestRepository else { return }

        pendingNextPage = false
        let generation = loadGeneration
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let response = try await fetchPage(repository: requestRepository, skip: requests.count)
            guard generation == loadGeneration, !Task.isCancelled else { return }
            let knownIDs = Set(requests.map(\.id))
            let newRequests = response.results.filter { !knownIDs.contains($0.id) }
            requests.append(contentsOf: newRequests)
            totalResults = max(totalResults, response.pageInfo.results)
            isLoadingMore = false
            await loadMediaDetails(for: newRequests, generation: generation)
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration, !Task.isCancelled else { return }
            presentError(error)
            return
        }

        await continuePagingIfRequested(generation: generation)
    }

    private func continuePagingIfRequested(generation: Int) async {
        guard pendingNextPage, generation == loadGeneration, let last = requests.last else { return }
        await loadMoreIfNeeded(current: last)
    }

    func approve(_ request: SeerrRequest) async {
        await perform(on: request) { repository in
            try await repository.updateRequestStatus(id: request.id, status: .approved)
        }
    }

    func decline(_ request: SeerrRequest) async {
        await perform(on: request) { repository in
            try await repository.updateRequestStatus(id: request.id, status: .declined)
        }
    }

    func retry(_ request: SeerrRequest) async {
        await perform(on: request) { repository in
            try await repository.retryRequest(id: request.id)
        }
    }

    func delete(_ request: SeerrRequest) async {
        guard let requestRepository, !busyRequestIDs.contains(request.id) else { return }

        busyRequestIDs.insert(request.id)
        defer { busyRequestIDs.remove(request.id) }

        do {
            try await requestRepository.cancelRequest(id: request.id)
            requests.removeAll { $0.id == request.id }
            totalResults = max(0, totalResults - 1)
        } catch {
            presentError(error)
        }
    }

    func mediaDetail(for request: SeerrRequest) -> SeerrMedia? {
        guard let key = mediaKey(for: request) else { return nil }
        return mediaDetails[key]
    }

    func makeEditViewModel(for request: SeerrRequest) async -> SeerrMediaRequestViewModel? {
        guard canEdit(request), let key = mediaKey(for: request), let mediaRepository else { return nil }

        busyRequestIDs.insert(request.id)
        defer { busyRequestIDs.remove(request.id) }

        do {
            var media = try await fetchMedia(for: key, repository: mediaRepository)
            media.mediaType = key.mediaType
            return SeerrMediaRequestViewModel(media: media, store: store, editing: request, session: session)
        } catch {
            presentError(error)
            return nil
        }
    }

    func mediaTitle(for request: SeerrRequest) -> String {
        guard let media = mediaDetail(for: request) else {
            if let key = mediaKey(for: request), unavailableMediaKeys.contains(key) {
                return String(localized: "seerr.requests.unavailableTitle")
            }
            return String(localized: "loading")
        }
        switch media.mediaType {
        case .movie:
            return media.title ?? media.name ?? ""
        case .tv, .person, .none:
            return media.name ?? media.title ?? ""
        }
    }

    func openableMedia(for request: SeerrRequest) -> SeerrMedia? {
        if let media = mediaDetail(for: request) {
            return media
        }
        guard let key = mediaKey(for: request), unavailableMediaKeys.contains(key) else { return nil }
        return SeerrMedia(placeholderID: key.tmdbId, mediaType: key.mediaType)
    }

    func mediaYear(for request: SeerrRequest) -> String? {
        guard let media = mediaDetail(for: request) else { return nil }
        let dateString: String? = switch media.mediaType {
        case .movie:
            media.releaseDate
        case .tv:
            media.firstAirDate
        case .person, .none:
            nil
        }
        guard let dateString, dateString.count >= 4 else { return nil }
        return String(dateString.prefix(4))
    }

    func isTV(_ request: SeerrRequest) -> Bool {
        (request.media?.mediaType ?? request.type) == .tv
    }

    func seasonSummary(for request: SeerrRequest) -> String? {
        guard isTV(request) else { return nil }
        let numbers = Set(request.seasons?.compactMap(\.seasonNumber) ?? []).sorted()
        guard !numbers.isEmpty else { return String(localized: "seerr.manageRequests.seasons.all") }
        return SeerrSeasonSummary.text(for: numbers, totalSeasons: mediaDetail(for: request)?.numberOfSeasons)
    }

    func displayName(for user: SeerrUser?) -> String {
        SeerrRequestFormatting.displayName(for: user)
    }

    func avatarURL(for user: SeerrUser?) -> URL? {
        SeerrRequestFormatting.avatarURL(for: user, baseURL: baseURL)
    }

    func relativeDateText(from value: String?) -> String? {
        guard let date = SeerrRequestFormatting.parsedDate(from: value) else { return nil }
        return SeerrRequestFormatting.relativeText(for: date)
    }

    func showsModified(_ request: SeerrRequest) -> Bool {
        guard request.modifiedBy != nil else { return false }
        return request.updatedAt != nil && request.updatedAt != request.createdAt
    }

    private func perform(
        on request: SeerrRequest,
        action: (SeerrRequestRepository) async throws -> Void,
    ) async {
        guard let requestRepository, !busyRequestIDs.contains(request.id) else { return }

        busyRequestIDs.insert(request.id)
        defer { busyRequestIDs.remove(request.id) }

        do {
            try await action(requestRepository)
            await refreshRequest(repository: requestRepository)
        } catch {
            presentError(error)
        }
    }

    private func refreshRequest(repository: SeerrRequestRepository) async {
        // Re-fetch the current page window so statuses and active filters stay accurate.
        let generation = loadGeneration
        let take = max(pageSize, requests.count)
        do {
            let response = try await repository.getRequests(
                take: take,
                skip: 0,
                filter: query.status.rawValue,
                mediaType: query.mediaType.rawValue,
                sort: query.sort.rawValue,
                sortDirection: query.isAscending ? "asc" : "desc",
            )
            guard generation == loadGeneration else { return }
            requests = response.results
            totalResults = response.pageInfo.results
            await loadMediaDetails(for: response.results, generation: generation)
        } catch {
            // The action succeeded; keep the current rows and let the next reload correct them.
        }
    }

    private func fetchPage(repository: SeerrRequestRepository, skip: Int) async throws -> SeerrRequestPageResponse {
        try await repository.getRequests(
            take: pageSize,
            skip: skip,
            filter: query.status.rawValue,
            mediaType: query.mediaType.rawValue,
            sort: query.sort.rawValue,
            sortDirection: query.isAscending ? "asc" : "desc",
        )
    }

    private func loadMediaDetails(for requests: [SeerrRequest], generation: Int) async {
        guard let mediaRepository else { return }

        var keys: [SeerrRequestMediaKey] = []
        for request in requests {
            guard let key = mediaKey(for: request), mediaDetails[key] == nil, !keys.contains(key) else { continue }
            keys.append(key)
        }
        guard !keys.isEmpty else { return }

        await withTaskGroup(of: (SeerrRequestMediaKey, SeerrMedia?).self) { group in
            for key in keys {
                group.addTask { @MainActor in
                    var media = try? await self.fetchMedia(for: key, repository: mediaRepository)
                    media?.mediaType = key.mediaType
                    return (key, media)
                }
            }
            for await (key, media) in group {
                guard generation == loadGeneration else { continue }
                if let media {
                    mediaDetails[key] = media
                    unavailableMediaKeys.remove(key)
                } else {
                    unavailableMediaKeys.insert(key)
                }
            }
        }
    }

    private func fetchMedia(
        for key: SeerrRequestMediaKey,
        repository: SeerrMediaRepository,
    ) async throws -> SeerrMedia {
        switch key.mediaType {
        case .movie:
            try await repository.getMovie(id: key.tmdbId)
        case .tv, .person:
            try await repository.getTV(id: key.tmdbId)
        }
    }

    private func mediaKey(for request: SeerrRequest) -> SeerrRequestMediaKey? {
        guard let media = request.media, let tmdbId = media.tmdbId, let mediaType = media.mediaType ?? request.type,
              mediaType != .person else { return nil }
        return SeerrRequestMediaKey(tmdbId: tmdbId, mediaType: mediaType)
    }

    private func isOwnRequest(_ request: SeerrRequest) -> Bool {
        guard let userID = store.user?.id else { return false }
        return request.requestedBy?.id == userID
    }

    private var mediaRepository: SeerrMediaRepository? {
        guard let baseURL else { return nil }
        return SeerrMediaRepository(baseURL: baseURL, session: session)
    }

    private var requestRepository: SeerrRequestRepository? {
        guard let baseURL else { return nil }
        return SeerrRequestRepository(baseURL: baseURL, session: session)
    }

    private var baseURL: URL? {
        guard let baseURLString = store.baseURLString else { return nil }
        return URL(string: baseURLString)
    }

    private func presentError(_ error: Error) {
        let key = switch error {
        case SeerrAPIError.invalidURL:
            "integrations.seerr.error.invalidURL"
        case SeerrAPIError.requestFailed:
            "integrations.seerr.error.connection"
        default:
            "common.errors.tryAgainLater"
        }
        errorMessage = String(localized: .init(key))
        isShowingError = true
    }
}

struct SeerrRequestMediaKey: Hashable {
    let tmdbId: Int
    let mediaType: SeerrMediaType
}

enum SeerrSeasonSummary {
    static func text(for numbers: [Int], totalSeasons: Int?) -> String {
        if let totalSeasons, totalSeasons > 0, Set(numbers).isSuperset(of: Set(1 ... totalSeasons)) {
            return String(localized: "seerr.manageRequests.seasons.all")
        }
        var ranges: [String] = []
        var start = numbers[0]
        var previous = numbers[0]
        for number in numbers.dropFirst() {
            if number == previous + 1 {
                previous = number
                continue
            }
            ranges.append(rangeText(start, previous))
            start = number
            previous = number
        }
        ranges.append(rangeText(start, previous))
        let joined = ranges.joined(separator: ", ")
        return String(localized: "seerr.requests.seasons.summary \(joined)")
    }

    private static func rangeText(_ start: Int, _ end: Int) -> String {
        start == end ? "\(start)" : "\(start)-\(end)"
    }
}
