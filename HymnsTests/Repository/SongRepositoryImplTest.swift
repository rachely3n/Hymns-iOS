import Combine
import Mockingbird
import XCTest
@testable import Hymns

class SongRepositoryImplTest: XCTestCase {

    static let resultsPage: SongResultsPage = SongResultsPage(results: [SongResult](), hasMorePages: false)

    var service: HymnalApiServiceMock!
    var target: SongResultsRepositoryImpl!

    override func setUp() {
        super.setUp()
        service = mock(HymnalApiService.self)
        target = SongResultsRepositoryImpl(service: service)
    }

    func test_search_networkError() {
        given(service.search(for: "Dan Sady", onPage: 2)) ~> { (_, _) in
            Just<SongResultsPage>(Self.resultsPage)
                .tryMap({ (_) -> SongResultsPage in
                    throw URLError(.badServerResponse)
                })
                .mapError({ (_) -> ErrorType in
                    ErrorType.data(description: "forced network error")
                }).eraseToAnyPublisher()
        }

        let valueReceived = expectation(description: "value received")
        let cancellable = target.search(searchParameter: "Dan Sady", pageNumber: 2)
            .sink(receiveValue: { resultsPage in
                valueReceived.fulfill()
                XCTAssertNil(resultsPage)
            })

        verify(service.search(for: "Dan Sady", onPage: 2)).wasCalled(exactly(1))
        wait(for: [valueReceived], timeout: testTimeout)
        cancellable.cancel()
    }

    func test_search_fromNtwork_resultsSuccessful() {
        given(service.search(for: "Dan Sady", onPage: 2)) ~> { (_, _) in
            Just<SongResultsPage>(Self.resultsPage)
                .mapError({ (_) -> ErrorType in
                    .data(description: "This will never get called")
                }).eraseToAnyPublisher()
        }

        let valueReceived = expectation(description: "value received")
        let cancellable = target.search(searchParameter: "Dan Sady", pageNumber: 2)
            .sink(receiveValue: { resultsPage in
                valueReceived.fulfill()
                XCTAssertEqual(Self.resultsPage, resultsPage!)
            })

        verify(service.search(for: "Dan Sady", onPage: 2)).wasCalled(exactly(1))
        wait(for: [valueReceived], timeout: testTimeout)
        cancellable.cancel()
    }
}
