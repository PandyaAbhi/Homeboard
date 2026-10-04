import Foundation
import Observation

@MainActor
@Observable
final class FlightWallViewModel {
    var aircraft: [Aircraft] = []
    var isRunning = false
    var isLoading = false
    var lastUpdated: Date?
    var nextUpdate: Date?
    var errorMessage: String?
    var weatherSummary = "BOS WEATHER • LOADING"
    var weatherCondition = "unknown"
    var weatherTemperatureC: Double?
    var weatherWind = "CALM"
    var hourlyForecast: [HourlyWeather] = []
    var moonrise: Date?
    var headlines: [String] = []
    var trails: [String: [FlightTrailPoint]] = [:]
    var radiusNM = 50
    var latitude = 42.3656
    var longitude = -71.0096

    private var loopTask: Task<Void, Never>?
    private let provider: FlightDataProvider
    private var retryDelay: TimeInterval = 0
    private var flightDetailsCache: [String: FlightDetails] = [:]
    private var attemptedOperatorLookups = Set<String>()

    init(provider: FlightDataProvider = AirplanesLiveProvider()) {
        self.provider = provider
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        errorMessage = nil
        Task { [weak self] in await self?.updateWeather() }
        Task { [weak self] in await self?.updateHourlyForecast() }
        Task { [weak self] in await self?.updateMoonrise() }
        Task { [weak self] in await self?.updateNews() }
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled && self.isRunning {
                await self.refresh()
                guard self.isRunning else { break }
                let delay = self.retryDelay > 0 ? self.retryDelay : 300
                self.nextUpdate = Date().addingTimeInterval(delay)
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    func stop() {
        isRunning = false
        loopTask?.cancel()
        loopTask = nil
        nextUpdate = nil
    }

    func refreshNow() {
        guard isRunning else { return }
        Task { await refresh() }
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let results = try await provider.fetchAircraft(latitude: latitude, longitude: longitude, radiusNM: radiusNM)
            let sortedResults = results.sorted { ($0.distance ?? .greatestFiniteMagnitude) < ($1.distance ?? .greatestFiniteMagnitude) }
            aircraft = sortedResults
            recordTrails(for: sortedResults)
            lastUpdated = Date()
            errorMessage = nil
            retryDelay = 0
            Task { [weak self] in await self?.updateWeather() }
            Task { [weak self] in await self?.updateHourlyForecast() }
            Task { [weak self] in await self?.updateMoonrise() }
            Task { [weak self] in await self?.updateNews() }
            Task { [weak self] in
                guard let self else { return }
                self.aircraft = await self.enrichOperators(in: sortedResults)
            }
        } catch {
            if case let FlightError.rateLimited(retryAfter) = error {
                retryDelay = max(300, retryAfter ?? 300)
            }
            errorMessage = error.localizedDescription
        }
    }

    private func recordTrails(for aircraft: [Aircraft]) {
        let activeHexes = Set(aircraft.map(\.hex))
        trails = trails.filter { activeHexes.contains($0.key) }
        for plane in aircraft {
            guard let latitude = plane.latitude, let longitude = plane.longitude else { continue }
            var points = trails[plane.hex] ?? []
            points.append(FlightTrailPoint(latitude: latitude, longitude: longitude))
            trails[plane.hex] = Array(points.suffix(12))
        }
    }

    private func enrichOperators(in aircraft: [Aircraft]) async -> [Aircraft] {
        var enriched = aircraft

        for index in enriched.indices.prefix(18) {
            guard enriched[index].operatorName?.isEmpty != false || enriched[index].routeText == nil else { continue }
            let lookupKey = "\(enriched[index].hex.uppercased())|\(enriched[index].callsign.uppercased())"

            if let cachedDetails = flightDetailsCache[lookupKey] {
                enriched[index].operatorName = cachedDetails.operatorName
                enriched[index].originCode = cachedDetails.originCode
                enriched[index].destinationCode = cachedDetails.destinationCode
                continue
            }
            guard attemptedOperatorLookups.insert(lookupKey).inserted else { continue }

            if let details = try? await fetchFlightDetails(for: enriched[index]) {
                flightDetailsCache[lookupKey] = details
                enriched[index].operatorName = details.operatorName
                enriched[index].originCode = details.originCode
                enriched[index].destinationCode = details.destinationCode
            }
        }
        return enriched
    }

    private func fetchFlightDetails(for aircraft: Aircraft) async throws -> FlightDetails? {
        let callsign = aircraft.callsign.trimmingCharacters(in: .whitespacesAndNewlines)
        guard callsign.count >= 3 else { return nil }

        var components = URLComponents(string: "https://api.adsbdb.com/v0/aircraft/\(aircraft.hex)")!
        components.queryItems = [URLQueryItem(name: "callsign", value: callsign)]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 8
        request.setValue("Homeboard/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        let result = try JSONDecoder().decode(ADSBDBLookup.self, from: data)
        let route = result.response?.flightroute
        let airline = route?.airline?.name ?? result.response?.aircraft?.registeredOwner
        let origin = route?.origin?.iataCode ?? route?.origin?.icaoCode
        let destination = route?.destination?.iataCode ?? route?.destination?.icaoCode
        guard airline != nil || origin != nil || destination != nil else { return nil }
        return FlightDetails(operatorName: airline, originCode: origin, destinationCode: destination)
    }

    private func updateWeather() async {
        guard let url = URL(string: "https://aviationweather.gov/api/data/metar?ids=KBOS&format=json&taf=false") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let reports = try JSONDecoder().decode([METARReport].self, from: data)
            guard let report = reports.first else { return }
            let wind = report.windSpeed.map { plainWind(direction: report.windDirection, knots: $0) } ?? "CALM"
            let temperature = report.temperature.map { "\(Int($0.rounded()))°C" } ?? "—"
            weatherTemperatureC = report.temperature
            weatherWind = wind
            weatherSummary = "BOS WX \(temperature) • \(wind)"
            weatherCondition = report.weatherDescription?.uppercased() ?? report.rawObservation?.uppercased() ?? "CLEAR"
        } catch {
            weatherSummary = "BOS WEATHER • UNAVAILABLE"
        }
    }

    private func updateNews() async {
        if let fetched = try? await NewsService.fetchHeadlines(), !fetched.isEmpty {
            headlines = fetched
        }
    }

    private func plainWind(direction: Int?, knots: Double) -> String {
        let mph = Int((knots * 1.15078).rounded())
        guard mph >= 3 else { return "CALM" }
        let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let bearing = direction ?? 0
        let cardinal = points[Int((Double(bearing) / 22.5).rounded()) % points.count]
        let description: String
        switch mph {
        case 0..<9: description = "LIGHT WIND"
        case 9..<19: description = "BREEZE"
        case 19..<31: description = "WINDY"
        default: description = "STRONG WIND"
        }
        return "\(description) FROM \(cardinal) • \(mph) MPH"
    }

    private func updateHourlyForecast() async {
        guard let pointURL = URL(string: "https://api.weather.gov/points/42.3656,-71.0096") else { return }
        var pointRequest = URLRequest(url: pointURL)
        pointRequest.setValue("Homeboard/1.0 (Living Room Dashboard)", forHTTPHeaderField: "User-Agent")
        pointRequest.setValue("application/geo+json", forHTTPHeaderField: "Accept")

        do {
            let (pointData, _) = try await URLSession.shared.data(for: pointRequest)
            let point = try JSONDecoder().decode(NWSPoint.self, from: pointData)
            guard let hourlyURL = URL(string: point.properties.forecastHourly) else { return }
            var hourlyRequest = URLRequest(url: hourlyURL)
            hourlyRequest.setValue("Homeboard/1.0 (Living Room Dashboard)", forHTTPHeaderField: "User-Agent")
            hourlyRequest.setValue("application/geo+json", forHTTPHeaderField: "Accept")

            let (forecastData, _) = try await URLSession.shared.data(for: hourlyRequest)
            let forecast = try JSONDecoder().decode(NWSHourlyForecast.self, from: forecastData)
            let formatter = ISO8601DateFormatter()
            hourlyForecast = forecast.properties.periods.compactMap { period in
                guard let time = formatter.date(from: period.startTime) else { return nil }
                return HourlyWeather(time: time, temperature: period.temperature, unit: period.temperatureUnit, summary: period.shortForecast, wind: "\(period.windDirection) WIND • \(period.windSpeed)")
            }.filter { $0.time >= Date() }.prefix(24).map { $0 }
        } catch {
            hourlyForecast = []
        }
    }

    private func updateMoonrise() async {
        let candidates = [Date(), Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()]
        for candidate in candidates {
            guard let moonrise = try? await fetchMoonrise(for: candidate) else { continue }
            if moonrise > Date() {
                self.moonrise = moonrise
                return
            }
        }
    }

    private func fetchMoonrise(for date: Date) async throws -> Date? {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let key = dateFormatter.string(from: date)
        var components = URLComponents(string: "https://api.sunrise-sunset.org/v2")!
        components.queryItems = [
            URLQueryItem(name: "lat", value: "42.3656"),
            URLQueryItem(name: "lng", value: "-71.0096"),
            URLQueryItem(name: "date", value: key),
            URLQueryItem(name: "tz", value: "America/New_York")
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let response = try JSONDecoder().decode(SunMoonResponse.self, from: data)
        guard let value = response.moonrise else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }
}

private struct FlightDetails {
    let operatorName: String?
    let originCode: String?
    let destinationCode: String?
}

struct HourlyWeather: Identifiable {
    let time: Date
    let temperature: Int
    let unit: String
    let summary: String
    let wind: String
    var id: Date { time }

    var symbol: String {
        let text = summary.lowercased()
        if text.contains("thunder") { return "cloud.bolt.rain.fill" }
        if text.contains("snow") || text.contains("sleet") { return "snowflake" }
        if text.contains("rain") || text.contains("shower") { return "cloud.rain.fill" }
        if text.contains("cloud") { return "cloud.fill" }
        if text.contains("night") { return "moon.stars.fill" }
        return "sun.max.fill"
    }
}

private struct METARReport: Decodable {
    let temperature: Double?
    let windDirection: Int?
    let windSpeed: Double?
    let weatherDescription: String?
    let rawObservation: String?

    enum CodingKeys: String, CodingKey {
        case temperature = "temp"
        case windDirection = "wdir"
        case windSpeed = "wspd"
        case weatherDescription = "wxString"
        case rawObservation = "rawOb"
    }
}

private struct NWSPoint: Decodable {
    let properties: Properties
    struct Properties: Decodable { let forecastHourly: String }
}

private struct NWSHourlyForecast: Decodable {
    let properties: Properties
    struct Properties: Decodable { let periods: [Period] }
    struct Period: Decodable {
        let startTime: String
        let temperature: Int
        let temperatureUnit: String
        let shortForecast: String
        let windSpeed: String
        let windDirection: String
    }
}

private struct SunMoonResponse: Decodable {
    let moonrise: String?
}

private struct ADSBDBLookup: Decodable {
    let response: LookupResponse?

    struct LookupResponse: Decodable {
        let aircraft: LookupAircraft?
        let flightroute: FlightRoute?
    }

    struct LookupAircraft: Decodable {
        let registeredOwner: String?

        enum CodingKeys: String, CodingKey {
            case registeredOwner = "registered_owner"
        }
    }

    struct FlightRoute: Decodable {
        let airline: Airline?
        let origin: Airport?
        let destination: Airport?
    }

    struct Airport: Decodable {
        let iataCode: String?
        let icaoCode: String?
        enum CodingKeys: String, CodingKey {
            case iataCode = "iata_code"
            case icaoCode = "icao_code"
        }
    }

    struct Airline: Decodable {
        let name: String?
    }
}
