import Foundation

enum GatewayAPIError: LocalizedError {
    case invalidURL
    case unauthorized
    case httpStatus(Int)
    case emptyResponse
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Could not build the gateway URL."
        case .unauthorized:
            return "Unauthorized (401). Check the bearer token in Preferences."
        case .httpStatus(let code):
            return "Gateway returned HTTP \(code)."
        case .emptyResponse:
            return "Gateway returned an empty response."
        case .decoding(let error):
            return "Could not parse device list: \(error.localizedDescription)"
        case .transport(let error):
            return "Could not reach the gateway: \(error.localizedDescription)"
        }
    }
}

struct DevicesFetchResult {
    let envelope: DevicesEnvelope
    /// Raw HTTP body (compact JSON from the server).
    let rawData: Data
}

enum GatewayAPIClient {
    static func fetchDevices(settings: GatewaySettings = .load()) async throws -> DevicesFetchResult {
        guard let url = URL(string: "http://\(settings.bindHost):\(settings.port)/v1/devices") else {
            throw GatewayAPIError.invalidURL
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 5)
        request.httpMethod = "GET"
        if let token = settings.bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw GatewayAPIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GatewayAPIError.emptyResponse
        }
        if http.statusCode == 401 {
            throw GatewayAPIError.unauthorized
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw GatewayAPIError.httpStatus(http.statusCode)
        }
        guard !data.isEmpty else {
            throw GatewayAPIError.emptyResponse
        }

        do {
            let envelope = try JSONDecoder().decode(DevicesEnvelope.self, from: data)
            return DevicesFetchResult(envelope: envelope, rawData: data)
        } catch {
            throw GatewayAPIError.decoding(error)
        }
    }

    /// Pretty-printed JSON matching the `/v1/devices` envelope schema.
    static func prettyPrintedDevicesJSON(from rawData: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: rawData, options: [])
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }
}
