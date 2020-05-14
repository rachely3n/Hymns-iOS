import Combine
import FirebaseCrashlytics
import Foundation
import Resolver

/**
 * Repository that stores all hymns that have been searched during this session in memory.
 */
protocol HymnsRepository {
    func getHymn(_ hymnIdentifier: HymnIdentifier)  -> AnyPublisher<UiHymn?, Never>
}

class HymnsRepositoryImpl: HymnsRepository {

    private let converter: Converter
    private let dataStore: HymnDataStore
    private let decoder: JSONDecoder
    private let mainQueue: DispatchQueue
    private let service: HymnalApiService
    private let systemUtil: SystemUtil

    private var disposables = Set<AnyCancellable>()
    private var hymns: [HymnIdentifier: UiHymn] = [HymnIdentifier: UiHymn]()

    init(converter: Converter = Resolver.resolve(),
         dataStore: HymnDataStore = Resolver.resolve(),
         decoder: JSONDecoder = Resolver.resolve(),
         mainQueue: DispatchQueue = Resolver.resolve(name: "main"),
         service: HymnalApiService = Resolver.resolve(),
         systemUtil: SystemUtil = Resolver.resolve()) {
        self.converter = converter
        self.dataStore = dataStore
        self.decoder = decoder
        self.mainQueue = mainQueue
        self.service = service
        self.systemUtil = systemUtil
    }

    func getHymn(_ hymnIdentifier: HymnIdentifier)  -> AnyPublisher<UiHymn?, Never> {
        if let hymn = hymns[hymnIdentifier] {
            return Just(hymn).eraseToAnyPublisher()
        }

        return HymnNetworkBoundResource(hymnIdentifier: hymnIdentifier)
            .execute(disposables: &disposables)
            // Don't pass through any values while hymn is still loading.
            .drop(while: { resource -> Bool in
                resource.status == .loading
            })
            .map { [weak self] resource -> UiHymn? in
                guard let self = self, let hymn = resource.data else {
                    return nil
                }
                self.mainQueue.async {
                    self.hymns[hymnIdentifier] = hymn
                }
                return hymn
        }
        .replaceError(with: nil)
        .eraseToAnyPublisher()
    }

    fileprivate struct HymnNetworkBoundResource: NetworkBoundResource {

        private let analytics: AnalyticsLogger
        private let converter: Converter
        private let dataStore: HymnDataStore
        private let decoder: JSONDecoder
        private let hymnIdentifier: HymnIdentifier
        private let service: HymnalApiService
        private let systemUtil: SystemUtil


        fileprivate init(analytics: AnalyticsLogger = Resolver.resolve(), converter: Converter = Resolver.resolve(),
                         dataStore: HymnDataStore = Resolver.resolve(), decoder: JSONDecoder = Resolver.resolve(),
                         hymnIdentifier: HymnIdentifier, service: HymnalApiService = Resolver.resolve(),
                         systemUtil: SystemUtil = Resolver.resolve()) {
            self.analytics = analytics
            self.converter = converter
            self.dataStore = dataStore
            self.decoder = decoder
            self.hymnIdentifier = hymnIdentifier
            self.service = service
            self.systemUtil = systemUtil
        }

        func saveToDatabase(convertedNetworkResult: HymnEntity?) {
            if !dataStore.databaseInitializedProperly {
                return
            }
            guard let hymnEntity = convertedNetworkResult else {
                return
            }
            dataStore.saveHymn(hymnEntity)
        }

        func shouldFetch(convertedDatabaseResult uiResult: UiHymn??) -> Bool {
            let flattened = uiResult?.flatMap({ uiHymn -> UiHymn? in
                return uiHymn
            })
            return systemUtil.isNetworkAvailable() && flattened == nil
        }

        func convertType(networkResult: Hymn) throws -> HymnEntity? {
            do {
                return try converter.toHymnEntity(hymnIdentifier: hymnIdentifier, hymn: networkResult)
            } catch {
                analytics.logError(message: "error orccured when converting Hymn to HymnEntity", error: error, extraParameters: ["hymnIdentifier": String(describing: hymnIdentifier)])
                throw TypeConversionError(triggeringError: error)
            }
        }

        /**
         * Converts the network result to the database result type and combines them together.
         */
        func convertType(databaseResult: HymnEntity?) throws -> UiHymn? {
            do {
                return try converter.toUiHymn(hymnIdentifier: hymnIdentifier, hymnEntity: databaseResult)
            } catch {
                analytics.logError(message: "error orccured when converting HymnEntity to UiHymn", error: error, extraParameters: ["hymnIdentifier": String(describing: hymnIdentifier)])
                throw TypeConversionError(triggeringError: error)
            }
        }

        func loadFromDatabase() -> AnyPublisher<HymnEntity?, ErrorType> {
            if !dataStore.databaseInitializedProperly {
                return Just<HymnEntity?>(nil).tryMap { _ -> HymnEntity? in
                    throw ErrorType.data(description: "database was not intialized properly")
                }.mapError({ error -> ErrorType in
                    ErrorType.data(description: error.localizedDescription)
                }).eraseToAnyPublisher()
            }
            return dataStore.getHymn(hymnIdentifier)
        }

        func createNetworkCall() -> AnyPublisher<Hymn, ErrorType> {
            service.getHymn(hymnIdentifier)
        }
    }
}
