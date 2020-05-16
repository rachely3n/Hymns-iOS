import Foundation
import GRDB

struct SearchResultEntity: Decodable {
    let hymnType: HymnType
    let hymnNumber: String
    let queryParams: [String: String]?
    let title: String
    let matchInfo: [UInt8]

    enum CodingKeys: String, CodingKey {
        case hymnType = "HYMN_TYPE"
        case hymnNumber = "HYMN_NUMBER"
        case queryParams = "QUERY_PARAMS"
        case title = "SONG_TITLE"
        case matchInfo = "matchinfo(SEARCH_VIRTUAL_SONG_DATA, 's')"
    }
}

extension SearchResultEntity: FetchableRecord {
}
