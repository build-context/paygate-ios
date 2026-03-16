import Foundation
import UIKit

/// Main entry point for the Paygate SDK.
/// Use `Paygate.initialize(apiKey:)` to set up, then `Paygate.launch(flowId:from:)` to present flows.
public final class Paygate {

    // MARK: - Configuration

    private static var apiKey: String?
    private static var baseURL: String = "http://localhost:4000"

    /// Initialize the Paygate SDK with your API key.
    /// - Parameters:
    ///   - apiKey: Your Paygate API key (found in the dashboard under API Keys).
    ///   - baseURL: Optional custom base URL for the Paygate API. Defaults to production.
    public static func initialize(apiKey: String, baseURL: String? = nil) {
        self.apiKey = apiKey
        if let baseURL = baseURL {
            self.baseURL = baseURL
        }
    }

    /// Launch a flow by presenting it as a full-screen modal.
    /// - Parameters:
    ///   - flowId: The ID of the flow to present.
    ///   - viewController: The view controller to present from.
    ///   - completion: Optional completion handler called when the flow is dismissed.
    public static func launch(
        flowId: String,
        from viewController: UIViewController,
        completion: ((PaygateResult) -> Void)? = nil
    ) {
        guard let apiKey = apiKey else {
            print("[Paygate] Error: SDK not initialized. Call Paygate.initialize(apiKey:) first.")
            completion?(.error(PaygateError.notInitialized))
            return
        }

        // Fetch flow content from API
        fetchFlow(flowId: flowId, apiKey: apiKey) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let flowData):
                    let paygateVC = PaygateViewController(
                        flowData: flowData,
                        apiKey: apiKey,
                        baseURL: baseURL,
                        completion: completion
                    )
                    paygateVC.modalPresentationStyle = .fullScreen
                    paygateVC.modalTransitionStyle = .coverVertical
                    viewController.present(paygateVC, animated: true)

                case .failure(let error):
                    print("[Paygate] Error loading flow: \(error.localizedDescription)")
                    completion?(.error(error))
                }
            }
        }
    }

    // MARK: - Private

    private static func fetchFlow(
        flowId: String,
        apiKey: String,
        completion: @escaping (Result<FlowData, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/api/sdk/flows/\(flowId)") else {
            completion(.failure(PaygateError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.httpMethod = "GET"

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(PaygateError.noData))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                completion(.failure(PaygateError.serverError))
                return
            }

            do {
                let flowData = try JSONDecoder().decode(FlowData.self, from: data)
                completion(.success(flowData))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

// MARK: - Models

public struct FlowData: Codable {
    public let id: String
    public let name: String
    public let htmlContent: String
    public let productIds: [String]
}

public enum PaygateResult {
    case dismissed
    case purchased(productId: String)
    case error(Error)
}

public enum PaygateError: LocalizedError {
    case notInitialized
    case invalidURL
    case noData
    case serverError

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Paygate SDK not initialized. Call Paygate.initialize(apiKey:) first."
        case .invalidURL:
            return "Invalid API URL."
        case .noData:
            return "No data received from server."
        case .serverError:
            return "Server returned an error."
        }
    }
}
