import Foundation

struct SeerrCollection: Identifiable, Hashable, Decodable {
    let id: Int
    let name: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let parts: [SeerrMedia]?
}
