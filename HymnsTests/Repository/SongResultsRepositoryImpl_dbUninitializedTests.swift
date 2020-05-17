import Combine
import Mockingbird
import XCTest
@testable import Hymns

class SongResultsRepositoryImpl_dbUninitializedTests: XCTestCase {

    let databaseResult = HymnEntity(hymnIdentifier: cebuano123,
                                    id: 0,
                                    title: "song title",
                                    lyricsJson: "[{\"verse_type\":\"verse\",\"verse_content\":[\"line 1\",\"line 2\"]}]")
    let networkResult = Hymn(title: "song title", metaData: [MetaDatum](), lyrics: [Verse(verseType: .verse, verseContent: ["line 1", "line 2"])])
    let expected = UiHymn(hymnIdentifier: cebuano123, title: "song title", lyrics: [Verse(verseType: .verse, verseContent: ["line 1", "line 2"])])

    var backgroundQueue = DispatchQueue.init(label: "background test queue")
    var converter: ConverterMock!
    var dataStore: HymnDataStoreMock!
    var service: HymnalApiServiceMock!
    var systemUtil: SystemUtilMock!
    var target: SongResultsRepository!

    override func setUp() {
        super.setUp()
        converter = mock(Converter.self)
        dataStore = mock(HymnDataStore.self)
        service = mock(HymnalApiService.self)
        systemUtil = mock(SystemUtil.self)
        target = SongResultsRepositoryImpl(converter: converter, dataStore: dataStore, mainQueue: backgroundQueue, service: service, systemUtil: systemUtil)
        given(dataStore.getDatabaseInitializedProperly()) ~> false
    }

    func test_searchHymn_databaseError_noNetwork() {
        given(systemUtil.isNetworkAvailable()) ~> false
        given(converter.toUiHymn(hymnIdentifier: cebuano123, hymnEntity: nil)) ~> nil

        let completion = expectation(description: "completion received")
        let value = expectation(description: "value received")
        value.isInverted = true
        let cancellable = target.search(searchParameter: "param", pageNumber: 1)
            .print(self.description)
            .sink(receiveCompletion: { state in
                completion.fulfill()
                XCTAssertEqual(state, .failure(.data(description: "database was not intialized properly")))
            }, receiveValue: { hymn in
                value.fulfill()
                XCTAssertNil(hymn)
            })

        verify(dataStore.getDatabaseInitializedProperly()).wasCalled(exactly(1))
        verify(service.getHymn(any())).wasNeverCalled()
        verify(dataStore.saveHymn(any())).wasNeverCalled()
        wait(for: [completion, value], timeout: testTimeout)
        cancellable.cancel()
    }

//    func test_getHymn_databaseError_networkAvailable_networkError() {
//        given(systemUtil.isNetworkAvailable()) ~> true
//        given(service.getHymn(cebuano123)) ~> { _ in
//            Just(self.networkResult)
//                .tryMap({ (_) -> Hymn in
//                    throw URLError(.badServerResponse)
//                })
//                .mapError({ (_) -> ErrorType in
//                    ErrorType.data(description: "forced network error")
//                }).eraseToAnyPublisher()
//        }
//
//        let completion = expectation(description: "completion received")
//        let value = expectation(description: "value received")
//        let cancellable = target.getHymn(cebuano123)
//            .print(self.description)
//            .sink(receiveCompletion: { state in
//                completion.fulfill()
//                XCTAssertEqual(state, .finished)
//            }, receiveValue: { hymn in
//                value.fulfill()
//                XCTAssertNil(hymn)
//            })
//
//        verify(dataStore.getDatabaseInitializedProperly()).wasCalled(exactly(1))
//        verify(service.getHymn(cebuano123)).wasCalled(exactly(1))
//        verify(dataStore.saveHymn(any())).wasNeverCalled()
//        wait(for: [completion, value], timeout: testTimeout)
//        cancellable.cancel()
//    }
//
//    func test_getHymn_databaseError_networkAvailable_resultsSuccessful() {
//        given(systemUtil.isNetworkAvailable()) ~> true
//        given(service.getHymn(cebuano123)) ~> {  _ in
//            return Just(self.networkResult).mapError({ (_) -> ErrorType in
//                .data(description: "This will never get called")
//            }).eraseToAnyPublisher()
//        }
//        given(converter.toHymnEntity(hymnIdentifier: cebuano123, hymn: self.networkResult)) ~> self.databaseResult
//        given(converter.toUiHymn(hymnIdentifier: cebuano123, hymnEntity: self.databaseResult)) ~> self.expected
//
//        let completion = expectation(description: "completion received")
//        let value = expectation(description: "value received")
//        let cancellable = target.getHymn(cebuano123)
//            .print(self.description)
//            .sink(receiveCompletion: { state in
//                completion.fulfill()
//                XCTAssertEqual(state, .finished)
//            }, receiveValue: { hymn in
//                value.fulfill()
//                XCTAssertEqual(self.expected, hymn!)
//            })
//
//        verify(dataStore.getDatabaseInitializedProperly()).wasCalled(exactly(2))
//        verify(service.getHymn(cebuano123)).wasCalled(exactly(1))
//        verify(dataStore.saveHymn(any())).wasNeverCalled()
//        wait(for: [completion, value], timeout: testTimeout)
//        cancellable.cancel()
//    }
//
//    func test_getHymn_databaseError_networkConversionError() {
//        given(systemUtil.isNetworkAvailable()) ~> true
//        given(service.getHymn(cebuano123)) ~> {  _ in
//            Just(self.networkResult).mapError({ (_) -> ErrorType in
//                .data(description: "This will never get called")
//            }).eraseToAnyPublisher()
//        }
//        given(converter.toHymnEntity(hymnIdentifier: cebuano123, hymn: self.networkResult)) ~> {_, _ in
//            throw TypeConversionError.init(triggeringError: ErrorType.parsing(description: "failed to convert!"))
//        }
//
//        let completion = expectation(description: "completion received")
//        let value = expectation(description: "value received")
//        let cancellable = target.getHymn(cebuano123)
//            .print(self.description)
//            .sink(receiveCompletion: { state in
//                completion.fulfill()
//                XCTAssertEqual(state, .finished)
//            }, receiveValue: { hymn in
//                value.fulfill()
//                XCTAssertNil(hymn)
//            })
//
//        verify(dataStore.getDatabaseInitializedProperly()).wasCalled(exactly(1))
//        verify(service.getHymn(cebuano123)).wasCalled(exactly(1))
//        verify(dataStore.saveHymn(any())).wasNeverCalled()
//        wait(for: [completion, value], timeout: testTimeout)
//        cancellable.cancel()
//    }
}
