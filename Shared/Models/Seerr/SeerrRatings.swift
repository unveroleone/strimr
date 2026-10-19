import Foundation

struct SeerrRottenTomatoesRating: Hashable, Decodable {
    let title: String?
    let url: String?
    let criticsRating: String?
    let criticsScore: Int?
    let audienceRating: String?
    let audienceScore: Int?
    let year: Int?

    var isCertifiedFresh: Bool {
        criticsRating == "Certified Fresh"
    }

    var isCriticsFresh: Bool {
        guard let criticsScore else { return false }
        return criticsScore >= 60
    }

    var isAudienceUpright: Bool {
        guard let audienceScore else { return false }
        return audienceScore >= 60
    }
}

struct SeerrImdbRating: Hashable, Decodable {
    let title: String?
    let url: String?
    let criticsScore: Double?
    let criticsScoreCount: Int?
}

struct SeerrMediaRatings: Hashable, Decodable {
    let rt: SeerrRottenTomatoesRating?
    let imdb: SeerrImdbRating?
}
