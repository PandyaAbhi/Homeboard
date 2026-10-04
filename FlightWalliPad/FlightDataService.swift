import Foundation

protocol FlightDataProvider {
    func fetchAircraft(latitude: Double, longitude: Double, radiusNM: Int) async throws -> [Aircraft]
}

struct AirplanesLiveProvider: FlightDataProvider {
    func fetchAircraft(latitude: Double, longitude: Double, radiusNM: Int) async throws -> [Aircraft] {
        // Both community feeds use the same readsb-compatible response shape.
        // Try ADS-B.lol first because Airplanes.live may require an API key on
        // some networks; retain Airplanes.live as a compatible fallback.
        let radius = max(1, min(radiusNM, 250))
        let endpoints = [
            "https://api.adsb.lol/v2/point/\(latitude)/\(longitude)/\(radius)",
            "https://api.airplanes.live/v2/point/\(latitude)/\(longitude)/\(radius)"
        ]

        var lastError: Error = FlightError.badResponse
        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue("Homeboard/1.0", forHTTPHeaderField: "User-Agent")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    lastError = FlightError.badResponse
                    continue
                }
                if (200..<300).contains(http.statusCode) {
                    return try JSONDecoder().decode(AircraftResponse.self, from: data).aircraft
                }
                if http.statusCode == 429 {
                    let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                    lastError = FlightError.rateLimited(retryAfter: retryAfter)
                    continue
                }
                lastError = FlightError.http(http.statusCode)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}

enum FlightError: LocalizedError {
    case badResponse
    case http(Int)
    case rateLimited(retryAfter: TimeInterval?)
    var errorDescription: String? {
        switch self {
        case .badResponse:
            return "The flight service returned an invalid response."
        case .http(let code):
            return "Flight service returned HTTP \(code)."
        case .rateLimited:
            return "Live flight data is busy. Keeping the last update and retrying automatically."
        }
    }
}
