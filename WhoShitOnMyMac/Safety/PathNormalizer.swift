import Foundation

enum PathNormalizer {
    static func resolve(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
