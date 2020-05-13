import Foundation

struct SongResultEntity {
    let hymnType: HymnType
    let hymnNumber: String
    let queryParams: [String: String]?
    let title: String
}
