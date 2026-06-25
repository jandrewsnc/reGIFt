import Foundation

// MARK: - Models
// Actual API shape: { id: Int, title: String, file: { hd/md/sm: { gif: { url } } } }

struct KlipyGIF: Identifiable {
    let id: String
    let title: String
    let thumbURL: URL?
    let thumbAspectRatio: CGFloat  // width/height of the sm gif
    let gifURL: URL?
    let klipyPageURL: URL?
}

extension KlipyGIF: Decodable {
    private struct File: Decodable {
        struct Size: Decodable {
            struct Format: Decodable {
                let url: String
                let width: Int?
                let height: Int?
            }
            let gif: Format?
        }
        let hd: Size?
        let md: Size?
        let sm: Size?
    }

    enum CodingKeys: String, CodingKey { case id, title, file, slug }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = String(try c.decode(Int.self, forKey: .id))
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        let file = try? c.decode(File.self, forKey: .file)
        let thumb = file?.sm?.gif ?? file?.md?.gif
        thumbURL = (thumb?.url).flatMap { URL(string: $0) }
        gifURL   = (file?.md?.gif?.url ?? file?.hd?.gif?.url).flatMap { URL(string: $0) }
        // Fall back to 16:9 if dimensions are missing
        if let w = thumb?.width, let h = thumb?.height, h > 0 {
            thumbAspectRatio = CGFloat(w) / CGFloat(h)
        } else {
            thumbAspectRatio = 16.0 / 9.0
        }
        // Use API-provided slug if present, otherwise derive from title
        let slug = (try? c.decode(String.self, forKey: .slug)) ?? Self.slugify(title)
        klipyPageURL = slug.isEmpty ? nil : URL(string: "https://klipy.com/gifs/\(slug)")
    }

    private static func slugify(_ string: String) -> String {
        string.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}

private struct KlipyResponse: Decodable {
    struct Outer: Decodable {
        let data: [KlipyGIF]
    }
    let result: Bool
    let data: Outer
}

// MARK: - Service

@MainActor
class KlipyService: ObservableObject {
    static let shared = KlipyService()

    private var apiKey: String {
        // Production: always read from Keychain (nothing bundled in the binary).
        // Debug: fall back to Config so the dev workflow still works without onboarding.
        if let key = KeychainHelper.load() { return key }
        #if DEBUG
        return Config.klipyAPIKey
        #else
        return ""
        #endif
    }
    private let base = "https://api.klipy.com/api/v1"
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    func trending(count: Int = 50) async throws -> [KlipyGIF] {
        let url = URL(string: "\(base)/\(apiKey)/gifs/trending?per_page=\(count)")!
        return try await fetch(url)
    }

    func search(query: String, count: Int = 50) async throws -> [KlipyGIF] {
        #if DEBUG
        if simulateTimeout {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            throw URLError(.timedOut)
        }
        #endif
        var components = URLComponents(string: "\(base)/\(apiKey)/gifs/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "per_page", value: "\(count)"),
        ]
        return try await fetch(components.url!)
    }

    #if DEBUG
    var simulateTimeout = false
    #endif

    private func fetch(_ url: URL) async throws -> [KlipyGIF] {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            // Print raw response to help debug field names on first run
            if let body = String(data: data, encoding: .utf8) {
                print("[KlipyService] Unexpected response:\n\(body)")
            }
            throw URLError(.badServerResponse)
        }
        // Uncomment to inspect the real JSON structure when setting up your API key:
        // print("[KlipyService] Raw JSON:\n\(String(data: data, encoding: .utf8) ?? "")")
        return try JSONDecoder().decode(KlipyResponse.self, from: data).data.data
    }
}
