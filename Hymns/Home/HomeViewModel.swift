import Combine
import FirebaseCrashlytics
import Foundation
import Resolver

class HomeViewModel: ObservableObject {

    @Published var searchActive: Bool = false
    @Published var searchParameter = ""
    @Published var songResults: [SongResultViewModel] = [SongResultViewModel]()
    @Published var label: String?
    @Published var state: HomeResultState = .results

    private var currentPage = 1
    private var hasMorePages = false
    private var isLoading = false
    private var recentSongsNotification: Notification?

    private var disposables = Set<AnyCancellable>()
    private let analytics: AnalyticsLogger
    private let backgroundQueue: DispatchQueue
    private let historyStore: HistoryStore
    private let mainQueue: DispatchQueue
    private let repository: SongResultsRepository

    init(analytics: AnalyticsLogger = Resolver.resolve(),
         backgroundQueue: DispatchQueue = Resolver.resolve(name: "background"),
         historyStore: HistoryStore = Resolver.resolve(),
         mainQueue: DispatchQueue = Resolver.resolve(name: "main"),
         repository: SongResultsRepository = Resolver.resolve()) {
        self.analytics = analytics
        self.backgroundQueue = backgroundQueue
        self.historyStore = historyStore
        self.mainQueue = mainQueue
        self.repository = repository

        // Initialize HymnDataStore early and start doing the heavy copying work on the background.
        backgroundQueue.async {
            let _: HymnDataStore = Resolver.resolve()
        }

        $searchActive
            .receive(on: mainQueue)
            .sink { searchActive in
                self.analytics.logSearchActive(isActive: searchActive)
                if !searchActive {
                    self.resetState()
                    self.fetchRecentSongs()
                    return
                }
        }.store(in: &disposables)

        $searchParameter
            // Ignore the first call with an empty string since it's take care of already by $searchActive
            .dropFirst()
            // Debounce works by waiting a bit until the user stops typing and before sending a value
            .debounce(for: .seconds(0.3), scheduler: mainQueue)
            .sink { searchParameter in
                self.analytics.logQueryChanged(queryText: searchParameter)
                self.refreshSearchResults()
        }.store(in: &disposables)
    }

    deinit {
        recentSongsNotification?.invalidate()
    }

    private func resetState() {
        currentPage = 1
        hasMorePages = false
        songResults = [SongResultViewModel]()
        state = .loading
    }

    private func refreshSearchResults() {
        // Changes in searchActive are taken care of already by $searchActive
        if !self.searchActive {
            return
        }

        resetState()

        if self.searchParameter.isEmpty {
            self.fetchRecentSongs()
            return
        }

        if searchParameter.trim().isPositiveInteger {
            self.fetchByNumber(hymnNumber: searchParameter.trim())
            return
        }
        self.performSearch(page: currentPage)
    }

    private func fetchRecentSongs() {
        label = "Recent hymns"
        state = .loading
        recentSongsNotification?.invalidate() // invalidate old notification because we're about to create a new one
        recentSongsNotification = historyStore.recentSongs { recentSongs in
            if self.searchActive && !self.searchParameter.isEmpty {
                // If the recent songs db changes while recent songs shouldn't be shown (there's an active search going on),
                // we don't want to randomly replace the search results with updated db results.
                return
            }
            self.state = .results
            self.songResults = recentSongs.map { recentSong in
                let identifier = HymnIdentifier(recentSong.hymnIdentifierEntity)
                return SongResultViewModel(title: recentSong.songTitle, destinationView: DisplayHymnView(viewModel: DisplayHymnViewModel(hymnToDisplay: identifier)).eraseToAnyView())
            }
        }
    }

    private func fetchByNumber(hymnNumber: String) {
        label = nil
        let matchingNumbers = HymnNumberUtil.matchHymnNumbers(hymnNumber: hymnNumber)
        songResults = matchingNumbers.map({ number -> SongResultViewModel in
            let identifier = HymnIdentifier(hymnType: .classic, hymnNumber: number)
            return SongResultViewModel(title: "Hymn \(number)", destinationView: DisplayHymnView(viewModel: DisplayHymnViewModel(hymnToDisplay: identifier)).eraseToAnyView())
        })
        state = songResults.isEmpty ? .empty : .results
    }

    func loadMore(at songResult: SongResultViewModel) {
        if !shouldLoadMore(songResult) {
            return
        }

        currentPage += 1
        performSearch(page: currentPage)
    }

    private func shouldLoadMore(_ songResult: SongResultViewModel) -> Bool {
        let thresholdMet = songResults.firstIndex(of: songResult) ?? 0 > songResults.count - 5
        return hasMorePages && !isLoading && thresholdMet
    }

    private func performSearch(page: Int) {
        label = nil

        let searchInput = self.searchParameter
        if searchInput.isEmpty {
            Crashlytics.crashlytics().record(error: ErrorType.data(description: "search parameter should never be empty during a song fetch"))
            return
        }

        isLoading = true
        repository
            .search(searchParameter: searchParameter.trim(), pageNumber: page)
            .map({ songResultsPage -> ([SongResultViewModel], Bool) in
                let hasMorePages = songResultsPage.hasMorePages ?? false
                let songResults = songResultsPage.results.compactMap { songResult -> SongResultViewModel? in
                    return SongResultViewModel(title: songResult.name, destinationView: DisplayHymnView(viewModel: DisplayHymnViewModel(hymnToDisplay: songResult.identifier)).eraseToAnyView())
                }
                return (songResults, hasMorePages)
            })
            .subscribe(on: backgroundQueue)
            .receive(on: mainQueue)
            .sink(
                receiveCompletion: { [weak self] _ in
                    guard let self = self else { return }
                    // Call is completed, so we should stop loading any more pages
                    self.isLoading = false
                    self.hasMorePages = false

                    // If there are no results and there's aren't any more results coming,
                    // then we should show the no results state. Otherwise, just keep the results that we have.
                    if self.songResults.isEmpty {
                        self.state = .empty
                    } else {
                        self.state = .results
                    }
                },
                receiveValue: { [weak self] (songResults, hasMorePages) in
                    guard let self = self else { return }
                    if searchInput != self.searchParameter {
                        // search parameter has changed by the time results came back, so just drop this.
                        return
                    }

                    self.state = .results
                    self.songResults.append(contentsOf: songResults)
                    self.hasMorePages = hasMorePages
                    self.isLoading = false

                    if self.songResults.isEmpty && !self.hasMorePages {
                        // If there are no results and no more pages to load, show the empty state
                        self.state = .empty
                    }
            }).store(in: &disposables)
    }
}

/**
 * Encapsulates the different state the home screen results page can take.
 */
enum HomeResultState {
    /**
     * Currently displaying results.
     */
    case results

    /**
     * Currently displaying the loading state.
     */
    case loading

    /**
     * Currently displaying an no-results state.
     */
    case empty
}

extension Resolver {
    public static func registerHomeViewModel() {
        register {HomeViewModel()}.scope(graph)
    }
}
