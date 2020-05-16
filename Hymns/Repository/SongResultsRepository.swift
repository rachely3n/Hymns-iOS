import Combine
import Foundation
import Resolver

/**
 * Repository to fetch a list of songs results, both from local storage and from the network.
 */
protocol SongResultsRepository {
    func search(searchParameter: String, pageNumber: Int)  -> AnyPublisher<UiSongResultsPage, ErrorType>
}

class SongResultsRepositoryImpl: SongResultsRepository {

    private let converter: Converter
    private let dataStore: HymnDataStore
    private let mainQueue: DispatchQueue
    private let service: HymnalApiService
    private let systemUtil: SystemUtil

    private var disposables = Set<AnyCancellable>()

    init(converter: Converter = Resolver.resolve(),
         dataStore: HymnDataStore = Resolver.resolve(),
         mainQueue: DispatchQueue = Resolver.resolve(name: "main"),
         service: HymnalApiService = Resolver.resolve(),
         systemUtil: SystemUtil = Resolver.resolve()) {
        self.converter = converter
        self.dataStore = dataStore
        self.mainQueue = mainQueue
        self.service = service
        self.systemUtil = systemUtil
    }

    func search(searchParameter: String, pageNumber: Int) -> AnyPublisher<UiSongResultsPage, ErrorType> {
        SearchPublisher(pageNumber: pageNumber, searchParameter: searchParameter, converter: converter,
                        dataStore: dataStore, disposables: &disposables, service: service, systemUtil: systemUtil)
        .eraseToAnyPublisher()
    }
}

private class SearchPublisher: NetworkBoundPublisher {

    typealias UIResultType = UiSongResultsPage
    typealias Output = UiSongResultsPage

    private var disposables: Set<AnyCancellable>
    private let converter: Converter
    private let dataStore: HymnDataStore
    private let pageNumber: Int
    private let searchParameter: String
    private let service: HymnalApiService
    private let systemUtil: SystemUtil

    fileprivate init(pageNumber: Int, searchParameter: String, converter: Converter, dataStore: HymnDataStore,
                     disposables: inout Set<AnyCancellable>, service: HymnalApiService, systemUtil: SystemUtil) {
        self.converter = converter
        self.dataStore = dataStore
        self.disposables = disposables
        self.pageNumber = pageNumber
        self.searchParameter = searchParameter
        self.service = service
        self.systemUtil = systemUtil
    }

    func createSubscription<S>(_ subscriber: S) -> Subscription where S: Subscriber, S.Failure == ErrorType, S.Input == UIResultType {
        SearchSubscription(pageNumber: pageNumber, searchParameter: searchParameter, converter: converter, dataStore: dataStore,
                           disposables: &disposables, service: service, subscriber: subscriber, systemUtil: systemUtil)
    }
}

private class SearchSubscription<SubscriberType: Subscriber>: NetworkBoundSubscription where SubscriberType.Input == UiSongResultsPage, SubscriberType.Failure == ErrorType {

    private let analytics: AnalyticsLogger
    private let converter: Converter
    private let dataStore: HymnDataStore
    private let pageNumber: Int
    private let searchParameter: String
    private let service: HymnalApiService
    private let systemUtil: SystemUtil

    var subscriber: SubscriberType?
    var disposables: Set<AnyCancellable>

    fileprivate init(pageNumber: Int, searchParameter: String, analytics: AnalyticsLogger = Resolver.resolve(),
                     converter: Converter, dataStore: HymnDataStore, disposables: inout Set<AnyCancellable>,
                     service: HymnalApiService, subscriber: SubscriberType, systemUtil: SystemUtil) {
        // okay to inject analytics because wse aren't mocking it in the unit tests
        self.analytics = analytics
        self.converter = converter
        self.dataStore = dataStore
        self.disposables = disposables
        self.pageNumber = pageNumber
        self.searchParameter = searchParameter
        self.service = service
        self.subscriber = subscriber
        self.systemUtil = systemUtil
    }

    func saveToDatabase(convertedNetworkResult: ([SongResultEntity], Bool)) {
        // do nothing
    }

    func shouldFetch(convertedDatabaseResult: UiSongResultsPage?) -> Bool {
        systemUtil.isNetworkAvailable()
    }

    func convertType(networkResult: SongResultsPage) throws -> ([SongResultEntity], Bool) {
        converter.toSongResultEntities(songResultsPage: networkResult)
    }

    func convertType(databaseResult: ([SongResultEntity], Bool)) throws -> UiSongResultsPage {
        converter.toUiSongResultsPage(songResultsEntities: databaseResult.0, hasMorePages: databaseResult.1)
    }

    func loadFromDatabase() -> AnyPublisher<([SongResultEntity], Bool), ErrorType> {
        if !dataStore.databaseInitializedProperly {
            return Just<Void>(()).tryMap { _ -> ([SongResultEntity], Bool) in
                throw ErrorType.data(description: "database was not intialized properly")
            }.mapError({ error -> ErrorType in
                ErrorType.data(description: error.localizedDescription)
            }).eraseToAnyPublisher()
        }

        return dataStore.searchHymn(searchParamter: searchParameter)
            .reduce(([SongResultEntity](), false)) { (_, searchResultEntities) -> ([SongResultEntity], Bool) in
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
