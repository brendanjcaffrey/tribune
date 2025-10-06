protocol LibraryProtocol {
    func hasAnyNewsletters() async throws -> Bool
    func getAllNewsletters() async throws -> [Newsletter]
    func getNewestNewsletter() async throws -> Newsletter?
    func putNewsletter(_ n: Newsletter) async throws
    func findById(_ id: Int) async throws -> Newsletter?
}
