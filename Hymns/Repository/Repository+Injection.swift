import Resolver

/**
 * Registers repositories to the dependency injection framework.
 */
extension Resolver {
    public static func registerRepositories() {
        register {HymnsRepositoryImpl() as HymnsRepository}.scope(application)
        register {SongResultsRepositoryImpl(service: resolve()) as SongResultsRepository}.scope(application)
    }
}
