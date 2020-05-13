import Combine
import Foundation
import Resolver

/**
 * Repository to fetch a list of songs results, both from local storage and from the network.
 */
protocol SongResultsRepository {
    func search(searchParameter: String, pageNumber: Int?)  -> AnyPublisher<Resource<UiSongResultsPage>, ErrorType>
}

class SongResultsRepositoryImpl: SongResultsRepository {

    private let service: HymnalApiService

    private var disposables = Set<AnyCancellable>()

    init(service: HymnalApiService) {
        self.service = service
    }

    func search(searchParameter: String, pageNumber: Int?) -> AnyPublisher<Resource<UiSongResultsPage>, ErrorType> {
        SearchNetworkBoundResource(pageNumber: pageNumber, searchParameter: searchParameter)
            .execute(disposables: &disposables)
            .eraseToAnyPublisher()
    }
}

private struct SearchNetworkBoundResource: NetworkBoundResource {

    typealias HasMorePages = Bool

    private let analytics: AnalyticsLogger
    private let converter: Converter
    private let dataStore: HymnDataStore
    private let decoder: JSONDecoder
    private let pageNumber: Int?
    private let searchParameter: String
    private let service: HymnalApiService
    private let systemUtil: SystemUtil

    fileprivate init(analytics: AnalyticsLogger = Resolver.resolve(), converter: Converter = Resolver.resolve(),
                     dataStore: HymnDataStore = Resolver.resolve(), decoder: JSONDecoder = Resolver.resolve(),
                     pageNumber: Int?, searchParameter: String, service: HymnalApiService = Resolver.resolve(),
                     systemUtil: SystemUtil = Resolver.resolve()) {
        self.analytics = analytics
        self.converter = converter
        self.dataStore = dataStore
        self.decoder = decoder
        self.pageNumber = pageNumber
        self.searchParameter = searchParameter
        self.service = service
        self.systemUtil = systemUtil
    }

    func saveToDatabase(convertedNetworkResult: ([SongResultEntity], HasMorePages)) {
        // do nothing
    }

    func shouldFetch(convertedDatabaseResult: UiSongResultsPage?) -> Bool {
        systemUtil.isNetworkAvailable()
    }

    func convertType(networkResult: SongResultsPage) throws -> ([SongResultEntity], HasMorePages) {
        converter.toSongResultEntities(songResultsPage: networkResult)
    }

    func convertType(databaseResult: ([SongResultEntity], HasMorePages)) throws -> UiSongResultsPage {
        converter.toUiSongResultsPage(songResultsEntities: databaseResult.0, hasMorePages: databaseResult.1)
    }

    func loadFromDatabase() -> AnyPublisher<([SongResultEntity], HasMorePages), ErrorType> {
        if !dataStore.databaseInitializedProperly {
            return Just<Void>(()).tryMap { _ -> ([SongResultEntity], HasMorePages) in
                throw ErrorType.data(description: "database was not intialized properly")
            }.mapError({ error -> ErrorType in
                ErrorType.data(description: error.localizedDescription)
            }).eraseToAnyPublisher()
        }

        return dataStore.searchHymn(searchParamter: searchParameter)
            .reduce(([SongResultEntity](), false)) { (_, searchResultEntities) -> ([SongResultEntity], HasMorePages) in
                let sortedSongResults = searchResultEntities.sorted { (entity1, entity2) -> Bool in
                    let rank1 = self.calculateRank(entity1.matchInfo)
                    let rank2 = self.calculateRank(entity2.matchInfo)
                    return rank2 > rank1
                }.map { searchResultEntity -> SongResultEntity in
                    return SongResultEntity(hymnType: searchResultEntity.hymnType, hymnNumber: searchResultEntity.hymnNumber, queryParams: searchResultEntity.queryParams, title: searchResultEntity.title)
                }
                return (sortedSongResults, false)
        }.eraseToAnyPublisher()
    }

    private func calculateRank(_ matchInfo: [UInt8]) -> Int {
        let titleMatch = matchInfo[0]
        let lyricsMatch = matchInfo[4]
        // Weight the match of the title twice as much as the match of the lyrics.
        return Int(titleMatch * 2 + lyricsMatch)
    }

    func createNetworkCall() -> AnyPublisher<SongResultsPage, ErrorType> {
        service.search(for: "boo", onPage: 1)
    }
}
