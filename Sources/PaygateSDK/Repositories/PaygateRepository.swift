import Foundation

class PaygateRepository {
    let baseURL: String
    let apiKey: String
    let session: URLSession
    let decoder: JSONDecoder

    init(baseURL: String, apiKey: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
        self.decoder = JSONDecoder()
    }

    func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw PaygateError.invalidURL
        }

        var request = URLRequest(url: url)
        PaygateHTTP.applyDefaultHeaders(to: &request, apiKey: apiKey)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw PaygateError.serverError()
        }

        guard http.statusCode == 200 else {
            let detail = parseErrorDetail(from: data)
            throw PaygateError.serverError(detail: detail)
        }

        return try decoder.decode(T.self, from: data)
    }

    private func parseErrorDetail(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["detail"] as? String ?? json["error"] as? String
    }
}
