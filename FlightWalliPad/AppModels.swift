import Foundation

struct Aircraft: Identifiable, Decodable, Equatable {
    let hex: String
    let flight: String?
    let registration: String?
    let type: String?
    var operatorName: String?
    var originCode: String?
    var destinationCode: String?
    let latitude: Double?
    let longitude: Double?
    let altitude: AltitudeValue?
    let groundSpeed: Double?
    let track: Double?
    let distance: Double?
    let direction: Double?
    let verticalRate: Double?

    var id: String { hex }
    var callsign: String { (flight ?? hex).trimmingCharacters(in: .whitespacesAndNewlines) }
    var altitudeText: String {
        guard let altitude else { return "—" }
        if let feet = altitude.doubleValue { return "\(Int(feet.rounded()))'" }
        return altitude.stringValue ?? "—"
    }
    var distanceText: String {
        guard let distance else { return "—" }
        return String(format: "%.1f NM", distance)
    }
    var speedText: String {
        guard let groundSpeed else { return "—" }
        return "\(Int(groundSpeed.rounded())) kt"
    }
    var typeText: String { type ?? "AIRCRAFT" }
    var operatorText: String {
        if let operatorName, !operatorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return operatorName
        }
        return callsign
    }

    var airlineText: String {
        guard let operatorName, !operatorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "AIRLINE UNAVAILABLE"
        }
        return operatorName.uppercased()
    }
    var routeText: String? {
        guard let originCode, let destinationCode, !originCode.isEmpty, !destinationCode.isEmpty else { return nil }
        return "\(originCode.uppercased())  →  \(destinationCode.uppercased())"
    }
    var movementText: String {
        guard let verticalRate else { return "TRACKING" }
        if verticalRate < -300 { return "DESCENDING" }
        if verticalRate > 300 { return "CLIMBING" }
        return "LEVEL"
    }
    var headingText: String {
        guard let track else { return "—" }
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return directions[Int(((track + 22.5) / 45).rounded(.down)) % directions.count]
    }
    var proximityText: String {
        "Passing \(distanceText) \(headingText) of Boston Logan"
    }
    var isInteresting: Bool {
        let code = (type ?? "").uppercased()
        return code.hasPrefix("A35") || code.hasPrefix("A38") || code.hasPrefix("B74") || code.hasPrefix("B77") || code.hasPrefix("B78") || code.hasPrefix("C17")
    }

    enum CodingKeys: String, CodingKey {
        case hex, flight, registration = "r", type = "t", operatorName = "ownOp"
        case latitude = "lat", longitude = "lon", altitude = "alt_baro", groundSpeed = "gs"
        case track, distance = "dst", direction = "dir", verticalRate = "baro_rate"
    }
}

struct FlightTrailPoint: Identifiable, Equatable {
    let id = UUID()
    let latitude: Double
    let longitude: Double
}

enum AltitudeValue: Decodable, Equatable {
    case number(Double)
    case text(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { self = .number(d); return }
        if let i = try? c.decode(Int.self) { self = .number(Double(i)); return }
        self = .text((try? c.decode(String.self)) ?? "—")
    }

    var doubleValue: Double? {
        switch self { case .number(let v): return v; case .text: return nil }
    }
    var stringValue: String? {
        switch self { case .number: return nil; case .text(let v): return v }
    }
}

struct AircraftResponse: Decodable {
    let aircraft: [Aircraft]
    enum CodingKeys: String, CodingKey { case aircraft = "ac" }
}
