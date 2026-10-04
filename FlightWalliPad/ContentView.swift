import SwiftUI
import Combine
import CoreImage.CIFilterBuiltins
import UIKit

struct ContentView: View {
    private enum DisplayMode: String, CaseIterable {
        case home = "HOME", sky = "WEATHER & SKY", pulse = "NEARBY FLIGHTS", homeControl = "HOME CONTROL"
        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .sky: return "moon.stars.fill"
            case .pulse: return "airplane.departure"
            case .homeControl: return "lightbulb.fill"
            }
        }
    }
    @State private var vm = FlightWallViewModel()
    @State private var showSettings = false
    @State private var now = Date()
    @State private var displayMode: DisplayMode = .home
    @State private var homeStore: HomeKitStore?
    @State private var showMoment = false
    @State private var systemChromeVisible = false
    @State private var lastInteraction = Date()
    @State private var ambientAudio = AmbientAudioController()
    @AppStorage("autoCycle") private var autoCycle = true
    @AppStorage("ambientMuted") private var ambientMuted = true
    @AppStorage("worldCityIDs") private var worldCityIDs = "Europe/London,Asia/Tokyo"
    @AppStorage("welcomeMessage") private var welcomeMessage = "WELCOME HOME"
    @AppStorage("temperatureUnit") private var temperatureUnit = "F"
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color(red: 0.008, green: 0.016, blue: 0.035).ignoresSafeArea()
            WeatherBackground(condition: vm.weatherCondition, date: now).ignoresSafeArea()
            // Keep the interface readable without hiding the animated weather scene.
            Color.black.opacity(0.025).ignoresSafeArea()
            StarField().opacity(WeatherBackground.starOpacity(condition: vm.weatherCondition, date: now)).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                modeBar
                ZStack {
                    if displayMode == .home {
                        HomeView(now: now, clocks: selectedClocks, headlines: vm.headlines, greeting: welcomeMessage, weather: vm.weatherCondition, forecast: vm.hourlyForecast, aircraft: vm.aircraft, lightsOn: homeStore?.lights.filter(\.isOn).count ?? 0, distanceMode: isDistanceMode)
                            .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    }
                    if displayMode == .sky {
                        SkySpaceView(now: now, weatherSummary: skyWeatherSummary, forecast: vm.hourlyForecast, temperatureUnit: temperatureUnit, moonrise: vm.moonrise)
                            .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    }
                    if displayMode == .pulse {
                        AirportPulseView(aircraft: vm.aircraft, isLoading: vm.isLoading, errorMessage: vm.errorMessage)
                            .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    }
                    if displayMode == .homeControl {
                        HomeControlView(store: homeStore, connect: { homeStore = HomeKitStore() }, movieModeSelected: {
                            ambientMuted = true
                            ambientAudio.setMuted(true)
                        })
                            .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    }
                }
                .animation(.easeInOut(duration: 0.42), value: displayMode)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            ambientAudio.setMuted(ambientMuted)
            ambientAudio.update(condition: vm.weatherCondition)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .statusBarHidden(!systemChromeVisible)
        .overlay(alignment: .top) {
            Color.clear
                .frame(height: 28)
                .contentShape(Rectangle())
                .onTapGesture { revealSystemChrome() }
        }
        .onReceive(timer) { date in
            now = date
            if autoCycle, Calendar.current.component(.second, from: date) == 0 {
                let index = DisplayMode.allCases.firstIndex(of: displayMode) ?? 0
                displayMode = DisplayMode.allCases[(index + 1) % DisplayMode.allCases.count]
            }
        }
        .onChange(of: vm.weatherCondition) { _, condition in ambientAudio.update(condition: condition) }
        .onChange(of: ambientMuted) { _, muted in ambientAudio.setMuted(muted) }
        .simultaneousGesture(TapGesture().onEnded { lastInteraction = Date() })
        .task {
            vm.start()
            if homeStore == nil { homeStore = HomeKitStore() }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSettings) { SettingsView(vm: vm) }
        .fullScreenCover(isPresented: $showMoment) { ImmersiveMomentView(now: now, weather: vm.weatherSummary) { showMoment = false } }
    }

    private var selectedClocks: [WorldClock] {
        let selected = Set(worldCityIDs.split(separator: ",").map(String.init))
        return WorldCities.all.filter { selected.contains($0.timeZone) }
    }

    private var isDistanceMode: Bool {
        displayMode == .home && now.timeIntervalSince(lastInteraction) > 90
    }

    private var skyWeatherSummary: String {
        guard let celsius = vm.weatherTemperatureC else { return vm.weatherSummary }
        let temperature: Int
        let suffix: String
        if temperatureUnit == "C" {
            temperature = Int(celsius.rounded())
            suffix = "°C"
        } else {
            temperature = Int((celsius * 9 / 5 + 32).rounded())
            suffix = "°F"
        }
        return "BOS \(temperature)\(suffix)  •  \(vm.weatherWind)"
    }

    private var header: some View {
        HStack(alignment: .center) {
            if displayMode != .home {
                FlipBoardText(text: now.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()), fontSize: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(welcomeMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "WELCOME HOME" : welcomeMessage.uppercased())
                    Text(now.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                }
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.72))
            }
            Spacer()
        }
        .padding(.horizontal, 24).padding(.vertical, displayMode == .home ? 10 : 16)
    }

    private func revealSystemChrome() {
        systemChromeVisible = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            systemChromeVisible = false
        }
    }

    private var modeBar: some View {
        HStack(spacing: 18) {
            ForEach(DisplayMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.38)) { displayMode = mode }
                } label: {
                    Image(systemName: mode.icon)
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(displayMode == mode ? Color(red: 0.72, green: 0.94, blue: 1.0) : .white.opacity(0.52))
                        .overlay {
                            if displayMode == mode {
                                Circle().stroke(Color.cyan.opacity(0.9), lineWidth: 1.5)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.rawValue)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 42, height: 36)
                    .foregroundStyle(.white.opacity(0.78))
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            Button {
                ambientMuted.toggle()
                lastInteraction = Date()
            } label: {
                Image(systemName: ambientMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 38, height: 36)
                    .foregroundStyle(.white.opacity(0.78))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ambientMuted ? "Unmute ambient sound" : "Mute ambient sound")
        }
        .padding(.horizontal, 24).padding(.vertical, 9)
    }

    private var footer: some View {
        HStack {
            Text("HOMEBOARD • LIVING ROOM EDITION")
            Spacer()
            if let last = vm.lastUpdated { Text("FLIGHT UPDATE \(last.formatted(date: .omitted, time: .shortened))") }
        }
        .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.7))
        .padding(14).background(.black.opacity(0.28))
    }
}

private struct HomeView: View {
    let now: Date
    let clocks: [WorldClock]
    let headlines: [String]
    let greeting: String
    let weather: String
    let forecast: [HourlyWeather]
    let aircraft: [Aircraft]
    let lightsOn: Int
    let distanceMode: Bool
    var body: some View {
        ViewThatFits(in: .vertical) {
            fullLayout
            compactLayout
        }
        .animation(.easeInOut(duration: 0.8), value: distanceMode)
    }

    private var fullLayout: some View {
        VStack(spacing: distanceMode ? 10 : 16) {
            Spacer()
            Text(greeting.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "WELCOME HOME" : greeting.uppercased())
                .font(.system(size: distanceMode ? 16 : 21, weight: .medium, design: .serif))
                .tracking(3.2)
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.32), radius: 5, y: 2)
                .accessibilityLabel("Dashboard greeting")
            FlipBoardText(text: now.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute().second()), fontSize: distanceMode ? 112 : 98)
                .minimumScaleFactor(0.5)
            Text(now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.system(size: 25, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.75))

            if !distanceMode, !clocks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(clocks) { clock in
                            WorldClockTile(clock: clock, now: now).frame(width: 130)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
            NowInsightCard(now: now, weather: weather, forecast: forecast, aircraft: aircraft, lightsOn: lightsOn)
                .padding(.horizontal, 24)
            if !distanceMode {
                NewsHeadlineCard(now: now, headlines: headlines).padding(.horizontal, 24)
            }
            Spacer()
        }
    }

    private var compactLayout: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(greeting.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "WELCOME HOME" : greeting.uppercased())
                    .font(.system(size: 15, weight: .medium, design: .serif)).tracking(2)
                FlipBoardText(text: now.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()), fontSize: 50)
                    .minimumScaleFactor(0.45)
                Text(now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                NowInsightCard(now: now, weather: weather, forecast: forecast, aircraft: aircraft, lightsOn: lightsOn)
                NewsHeadlineCard(now: now, headlines: headlines)
            }
            .padding(16)
        }
    }
}

private struct NowInsightCard: View {
    let now: Date
    let weather: String
    let forecast: [HourlyWeather]
    let aircraft: [Aircraft]
    let lightsOn: Int

    private var insight: (icon: String, eyebrow: String, title: String, detail: String, color: Color) {
        if let rain = forecast.first(where: { $0.time > now && ($0.summary.lowercased().contains("rain") || $0.summary.lowercased().contains("storm")) }) {
            return ("cloud.rain.fill", "WEATHER AHEAD", "Rain around \(rain.time.formatted(date: .omitted, time: .shortened))", "Take an umbrella if you're heading out.", .cyan)
        }
        let sun = BostonSunTimes(date: now)
        if now < sun.sunset, sun.sunset.timeIntervalSince(now) < 2 * 3600 {
            return ("sunset.fill", "COMING UP", "Sunset in \(max(1, Int(sun.sunset.timeIntervalSince(now) / 60))) minutes", "The background will ease into its night scene.", .orange)
        }
        if lightsOn > 0 && Calendar.current.component(.hour, from: now) >= 22 {
            return ("lightbulb.fill", "HOME CHECK", "\(lightsOn) light\(lightsOn == 1 ? " is" : "s are") still on", "Open Home Control to turn them off.", .yellow)
        }
        if let flight = aircraft.filter({ $0.flight?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false && $0.distance != nil }).min(by: { ($0.distance ?? 999) < ($1.distance ?? 999) }) {
            return ("airplane", "PASSING NEARBY", flight.callsign, flight.proximityText, .orange)
        }
        let hour = Calendar.current.component(.hour, from: now)
        if hour < 11 { return ("sun.max.fill", "GOOD MORNING", "A calm start to the day", "Weather, home and headlines are ready.", .yellow) }
        if hour >= 18 { return ("moon.stars.fill", "THIS EVENING", "Home is settling in", "Your night scene will update automatically.", .cyan) }
        return ("sparkles", "RIGHT NOW", "Everything looks steady", weather.isEmpty ? "Homeboard is keeping watch." : weather, .cyan)
    }

    var body: some View {
        let item = insight
        HStack(spacing: 15) {
            Image(systemName: item.icon).font(.system(size: 28, weight: .semibold)).foregroundStyle(item.color).frame(width: 38)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.eyebrow).font(.system(size: 10, weight: .black, design: .monospaced)).foregroundStyle(item.color)
                Text(item.title).font(.system(size: 18, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.72)
                Text(item.detail).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
            }
            Spacer()
        }
        .padding(16).background(.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct WorldClock: Identifiable {
    let city: String
    let timeZone: String
    var id: String { city }
}

private enum WorldCities {
    static let all = [
        WorldClock(city: "ANCHORAGE", timeZone: "America/Anchorage"), WorldClock(city: "LOS ANGELES", timeZone: "America/Los_Angeles"),
        WorldClock(city: "DENVER", timeZone: "America/Denver"), WorldClock(city: "CHICAGO", timeZone: "America/Chicago"),
        WorldClock(city: "NEW YORK", timeZone: "America/New_York"), WorldClock(city: "SÃO PAULO", timeZone: "America/Sao_Paulo"),
        WorldClock(city: "LONDON", timeZone: "Europe/London"), WorldClock(city: "PARIS", timeZone: "Europe/Paris"),
        WorldClock(city: "ROME", timeZone: "Europe/Rome"), WorldClock(city: "AMSTERDAM", timeZone: "Europe/Amsterdam"),
        WorldClock(city: "CAPE TOWN", timeZone: "Africa/Johannesburg"), WorldClock(city: "CAIRO", timeZone: "Africa/Cairo"),
        WorldClock(city: "DUBAI", timeZone: "Asia/Dubai"), WorldClock(city: "MUMBAI", timeZone: "Asia/Kolkata"),
        WorldClock(city: "SINGAPORE", timeZone: "Asia/Singapore"), WorldClock(city: "HONG KONG", timeZone: "Asia/Hong_Kong"),
        WorldClock(city: "SHANGHAI", timeZone: "Asia/Shanghai"), WorldClock(city: "TOKYO", timeZone: "Asia/Tokyo"),
        WorldClock(city: "SEOUL", timeZone: "Asia/Seoul"), WorldClock(city: "SYDNEY", timeZone: "Australia/Sydney"),
        WorldClock(city: "AUCKLAND", timeZone: "Pacific/Auckland")
    ]
}

private struct WorldClockTile: View {
    let clock: WorldClock
    let now: Date
    var body: some View {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: clock.timeZone)
        formatter.dateFormat = "HH:mm"
        return VStack(spacing: 5) {
            Text(clock.city).font(.system(size: 10, weight: .black, design: .monospaced)).foregroundStyle(.white.opacity(0.58))
            Text(formatter.string(from: now)).font(.system(size: 22, weight: .bold, design: .monospaced))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct AmbientMomentCard: View {
    let now: Date
    private var message: String {
        let hour = Calendar.current.component(.hour, from: now)
        let moon = MoonInfo(date: now)
        if moon.illumination > 95 { return "FULL MOON TONIGHT" }
        if hour >= 17 && hour < 20 { return "GOLDEN HOUR IS HERE" }
        if hour >= 5 && hour < 7 { return "A NEW DAY IS TAKING OFF" }
        if hour >= 20 || hour < 5 { return "LOOK UP • THE SKY IS OPEN" }
        return "CLEAR SKIES, BIG PLANS" }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("SKY MOMENT", systemImage: "sparkles").font(.system(size: 10, weight: .black, design: .monospaced)).foregroundStyle(.cyan)
            Text(message).font(.system(size: 15, weight: .bold, design: .rounded)).lineLimit(2)
            Text("A small reason to look outside.").font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.58))
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading).padding(13)
        .background(.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct DailyAviationFactCard: View {
    let now: Date
    private let facts = [
        "The Boeing 747's distinctive upper deck began as a lounge concept.",
        "Airport code BOS is Boston Logan's three-letter identity.",
        "Contrails form when warm jet exhaust meets very cold air.",
        "Aviation uses UTC so pilots worldwide share one clock.",
        "The first commercial jet service began in 1952.",
        "A flight number can be reused every day for the same route."
    ]
    var body: some View {
        let index = (Calendar.current.ordinality(of: .day, in: .year, for: now) ?? 0) % facts.count
        return VStack(alignment: .leading, spacing: 8) {
            Label("TODAY'S AVIATION FACT", systemImage: "airplane").font(.system(size: 10, weight: .black, design: .monospaced)).foregroundStyle(.orange)
            Text(facts[index]).font(.system(size: 13, weight: .semibold, design: .rounded)).lineLimit(3)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading).padding(13)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct HomeMomentCard: View {
    let now: Date
    let aircraft: [Aircraft]
    let action: () -> Void

    private var kind: Int { (Calendar.current.component(.minute, from: now) / 2) % 3 }
    private var featured: Aircraft? { aircraft.first(where: \.isInteresting) ?? aircraft.first }

    var body: some View {
        Button(action: action) {
            Group {
            switch kind {
            case 0:
                moment(icon: "moon.stars.fill", eyebrow: "SKY & SPACE", title: MoonInfo(date: now).shortDescription, detail: "Sunset around \(DaylightSummary.sunsetText(for: now))", color: .cyan)
            case 1:
                if let featured {
                    moment(icon: "airplane", eyebrow: "AIRPORT PULSE", title: "\(featured.callsign) • \(featured.movementText)", detail: "\(featured.distanceText) from Boston Logan • \(featured.altitudeText)", color: .orange)
                } else {
                    moment(icon: "antenna.radiowaves.left.and.right", eyebrow: "AIRPORT PULSE", title: "Checking the airspace", detail: "Live flight stories appear when data arrives.", color: .orange)
                }
            default:
                moment(icon: "lightbulb.fill", eyebrow: "AVIATION FACT", title: "Aviation uses UTC so pilots worldwide share one clock.", detail: "A shared time standard keeps global travel coordinated.", color: .yellow)
            }
            }
        }
        .buttonStyle(.plain)
    }

    private func moment(icon: String, eyebrow: String, title: String, detail: String, color: Color) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 27, weight: .semibold)).foregroundStyle(color).frame(width: 38)
            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow).font(.system(size: 10, weight: .black, design: .monospaced)).foregroundStyle(color)
                Text(title).font(.system(size: 16, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                Text(detail).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
            }
            Spacer()
        }
        .padding(16).background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct NewsHeadlineCard: View {
    let now: Date
    let headlines: [String]

    var body: some View {
        let index = headlines.isEmpty ? 0 : Calendar.current.component(.minute, from: now) % headlines.count
        let headline = headlines.isEmpty ? "Loading current headlines…" : headlines[index]
        let next = headlines.count > 1 ? headlines[(index + 1) % headlines.count] : nil
        return VStack(alignment: .leading, spacing: 10) {
            Label("LIVE HEADLINES", systemImage: "newspaper.fill")
                .font(.system(size: 10, weight: .black, design: .monospaced)).foregroundStyle(.red)
            Text(headline).font(.system(size: 19, weight: .bold, design: .rounded)).lineLimit(2)
            if let next {
                Text("UP NEXT  •  \(next)").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.60)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(17)
        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct ImmersiveMomentView: View {
    let now: Date
    let weather: String
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            WeatherBackground(condition: weather, date: now).ignoresSafeArea()
            StarField().opacity(0.45).ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "moon.stars.fill").font(.system(size: 80)).foregroundStyle(.cyan)
                Text(MoonInfo(date: now).name.uppercased()).font(.system(size: 42, weight: .bold, design: .rounded))
                Text(MoonInfo(date: now).shortDescription).font(.system(size: 21, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.78))
                Text("Sunset around \(DaylightSummary.sunsetText(for: now)) • \(weather)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced)).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.66))
                Spacer()
                Button("RETURN TO HOME") { dismiss() }.buttonStyle(.borderedProminent).tint(.cyan)
            }
            .padding(30)
        }
    }
}

private struct HomeTile: View {
    let icon: String; let title: String; let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.title2).foregroundStyle(.cyan)
            Text(title).font(.system(size: 11, weight: .black, design: .monospaced)).foregroundStyle(.white.opacity(0.58))
            Text(value).font(.system(size: 15, weight: .bold, design: .rounded)).lineLimit(2).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading).padding(16)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct SkySpaceView: View {
    let now: Date
    let weatherSummary: String
    let forecast: [HourlyWeather]
    let temperatureUnit: String
    let moonrise: Date?
    private var moon: MoonInfo { MoonInfo(date: now) }
    var body: some View {
        VStack(spacing: 12) {
            Text("WEATHER & SKY").font(.system(size: 16, weight: .black, design: .monospaced)).foregroundStyle(.cyan)
            Text("RIGHT NOW AND WHAT'S NEXT").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
            WeatherHero(summary: weatherSummary, forecast: forecast, temperatureUnit: temperatureUnit, now: now)
            HStack(spacing: 10) {
                SolarEventTile(now: now)
                MoonSummaryTile(now: now, moonrise: moonrise, moon: moon)
                SpaceTile(icon: "globe.americas.fill", title: "LOCATION", value: "BOSTON, MA")
            }
            .padding(.horizontal, 24)
            RestOfDayForecast(forecast: forecast, temperatureUnit: temperatureUnit, now: now)
            Link("Moonrise data: sunrise-sunset.org", destination: URL(string: "https://sunrise-sunset.org")!)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.42))
        }
        .padding(.top, 10).padding(.bottom, 10)
    }
}

private struct SolarEventTile: View {
    let now: Date

    private var sun: BostonSunTimes { BostonSunTimes(date: now) }

    var body: some View {
        let event = nextEvent
        VStack(spacing: 9) {
            Image(systemName: event.icon).font(.title2).foregroundStyle(.yellow)
            Text(event.title).font(.system(size: 10, weight: .black, design: .monospaced)).foregroundStyle(.white.opacity(0.58))
            Text(event.value).font(.system(size: 15, weight: .bold, design: .rounded)).multilineTextAlignment(.center).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 112).padding(10)
        .background(.indigo.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
    }

    private var nextEvent: (title: String, icon: String, value: String) {
        if now < sun.sunrise {
            return ("SUNRISE", "sunrise.fill", sun.sunrise.formatted(date: .omitted, time: .shortened))
        }
        if now < sun.sunset {
            return ("SUNSET", "sunset.fill", sun.sunset.formatted(date: .omitted, time: .shortened))
        }
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        let sunrise = BostonSunTimes(date: tomorrow).sunrise
        return ("SUNRISE TOMORROW", "sunrise.fill", sunrise.formatted(date: .omitted, time: .shortened))
    }
}

private struct MoonSummaryTile: View {
    let now: Date
    let moonrise: Date?
    let moon: MoonInfo

    var body: some View {
        HStack(spacing: 12) {
            Image("MoonTexture")
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .mask(MoonPhaseMask(offset: moon.shadowOffset * 52 / 158))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(moon.name.uppercased())
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                Text("\(moon.illumination)% illuminated")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Text("Moonrise \(moonrise?.formatted(date: .omitted, time: .shortened) ?? "—")")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.66))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 112).padding(10)
        .background(.indigo.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct WeatherHero: View {
    let summary: String
    let forecast: [HourlyWeather]
    let temperatureUnit: String
    let now: Date

    private var current: HourlyWeather? { forecast.first(where: { $0.time >= now }) ?? forecast.first }
    private var summaryParts: [String] { summary.components(separatedBy: "  •  ") }
    private var temperature: String { summaryParts.first?.replacingOccurrences(of: "BOS ", with: "") ?? "—" }
    private var wind: String { summaryParts.dropFirst().first?.replacingOccurrences(of: "WIND ", with: "") ?? current?.wind ?? "—" }
    private var today: [HourlyWeather] { forecast.filter { Calendar.current.isDate($0.time, inSameDayAs: now) } }
    private var range: String {
        let values = today.map(convertedTemperature)
        guard let low = values.min(), let high = values.max() else { return "H —  L —" }
        return "H \(high)°  L \(low)°"
    }

    var body: some View {
        HStack(spacing: 24) {
            Image(systemName: current?.symbol ?? "cloud.sun.fill")
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 62, weight: .medium))
            VStack(alignment: .leading, spacing: 3) {
                Text(temperature)
                    .font(.system(size: 70, weight: .light, design: .rounded))
                    .monospacedDigit()
                Text((current?.summary ?? "CURRENT CONDITIONS").uppercased())
                    .font(.system(size: 15, weight: .black, design: .monospaced))
                Text("\(range)  •  WIND \(wind)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .padding(.horizontal, 22)
        .padding(.horizontal, 24)
    }

    private func convertedTemperature(_ hour: HourlyWeather) -> Int {
        let sourceF = hour.unit.uppercased().hasPrefix("F")
        if (temperatureUnit == "F") == sourceF { return hour.temperature }
        if temperatureUnit == "C" { return Int(((Double(hour.temperature) - 32) * 5 / 9).rounded()) }
        return Int((Double(hour.temperature) * 9 / 5 + 32).rounded())
    }
}

private struct MoonPhaseMask: View {
    let offset: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(.white)
            Circle()
                .fill(.black)
                .offset(x: offset)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
    }
}

private struct WeatherSpaceTile: View {
    let summary: String
    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: "thermometer.medium").font(.system(size: 25, weight: .semibold)).foregroundStyle(.cyan)
            Text("WEATHER").font(.system(size: 12, weight: .black, design: .monospaced)).foregroundStyle(.white.opacity(0.58))
            Text(summary.replacingOccurrences(of: "BOS ", with: "").replacingOccurrences(of: "  •  WIND ", with: "\n"))
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, minHeight: 112).padding(10)
        .background(.indigo.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct RestOfDayForecast: View {
    let forecast: [HourlyWeather]
    let temperatureUnit: String
    let now: Date

    private var upcomingForecast: [HourlyWeather] {
        Array(forecast.filter { $0.time >= now }.prefix(24))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("NEXT 24 HOURS", systemImage: "clock")
                .font(.system(size: 12, weight: .black, design: .monospaced)).foregroundStyle(.cyan)
            if upcomingForecast.isEmpty {
                Text("Fetching Boston’s hourly forecast…")
                    .font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.55))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(upcomingForecast) { hour in
                            VStack(spacing: 7) {
                                Text(hour.time.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated))))
                                Image(systemName: hour.symbol).foregroundStyle(hour.symbol == "sun.max.fill" ? .yellow : .cyan)
                                Text(formattedTemperature(for: hour))
                                Text(hour.wind.uppercased())
                                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.6)
                            }
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.82))
                            .frame(width: 74)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 13)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 24)
    }

    private func formattedTemperature(for hour: HourlyWeather) -> String {
        let sourceIsFahrenheit = hour.unit.uppercased().hasPrefix("F")
        let requestedCelsius = temperatureUnit == "C"
        let value: Double
        if requestedCelsius == sourceIsFahrenheit {
            value = sourceIsFahrenheit ? (Double(hour.temperature) - 32) * 5 / 9 : Double(hour.temperature) * 9 / 5 + 32
        } else {
            value = Double(hour.temperature)
        }
        return "\(Int(value.rounded()))°"
    }
}

private struct SpaceTile: View {
    let icon: String; let title: String; let value: String
    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 25, weight: .semibold)).foregroundStyle(.yellow)
            Text(title).font(.system(size: 12, weight: .black, design: .monospaced)).foregroundStyle(.white.opacity(0.58))
            Text(value).font(.system(size: 16, weight: .bold, design: .rounded)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 112).padding(10)
        .background(.indigo.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct HomeControlView: View {
    let store: HomeKitStore?
    let connect: () -> Void
    let movieModeSelected: () -> Void
    @State private var selectedLight: HomeKitStore.Light?
    @State private var showWiFiQR = false

    var body: some View {
        VStack(spacing: 18) {
            Text("HOME CONTROL").font(.system(size: 16, weight: .black, design: .monospaced)).foregroundStyle(.cyan)
            Text("YOUR APPLE HOME, ON THE WALL").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
            Button { showWiFiQR = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "wifi").font(.system(size: 18, weight: .bold)).foregroundStyle(.cyan)
                    Text("WIFI CONNECT").font(.system(size: 11, weight: .black, design: .monospaced))
                    Spacer()
                    Image(systemName: "qrcode").foregroundStyle(.white.opacity(0.62))
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)

            if let store {
                Text(store.statusText).font(.system(size: 11, weight: .black, design: .monospaced)).foregroundStyle(.cyan)
                HStack(spacing: 14) {
                    RitualButton(icon: "sun.max.fill", title: "GOOD MORNING", color: .yellow) { store.goodMorning() }
                    RitualButton(icon: "moon.fill", title: "GOOD NIGHT", color: .indigo) { store.setAllLights(on: false) }
                    RitualButton(icon: "film.fill", title: "MOVIE TIME", color: .orange) {
                        movieModeSelected()
                        store.movieTime()
                    }
                }
                .padding(.horizontal, 24)

                if !store.lights.isEmpty {
                    let onCount = store.lights.filter(\.isOn).count
                    Text(onCount == 0 ? "ALL LIGHTS ARE OFF" : "\(onCount) OF \(store.lights.count) LIGHTS ON")
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundStyle(onCount == 0 ? .green : .yellow)
                }

                if store.lights.isEmpty {
                    HomeEmptyState(text: "No controllable lights found. Add lights or scenes in Apple Home, then return here.")
                } else {
                    Text("LIGHTS").font(.system(size: 11, weight: .black, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(store.lights.prefix(9)) { light in
                            Button { store.toggle(light) } label: {
                                VStack(spacing: 7) {
                                    Image(systemName: light.isOn ? "lightbulb.fill" : "lightbulb").font(.title2).foregroundStyle(light.isOn ? .yellow : .white.opacity(0.45))
                                    Text(light.name).font(.system(size: 11, weight: .bold, design: .rounded)).lineLimit(1)
                                    Text(light.room.uppercased()).font(.system(size: 8, weight: .black, design: .monospaced)).foregroundStyle(.white.opacity(0.48)).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, minHeight: 90).padding(8)
                                .background(light.isOn ? .yellow.opacity(0.16) : .black.opacity(0.20), in: RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                            .highPriorityGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in selectedLight = light })
                        }
                    }
                    .padding(.horizontal, 24)
                }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "house.and.flag.fill").font(.system(size: 52)).foregroundStyle(.cyan)
                    Text("CONNECT APPLE HOME").font(.system(size: 21, weight: .bold, design: .rounded))
                    Text("Use your existing Apple Home lights and scenes from this display.").font(.system(size: 14, weight: .medium, design: .rounded)).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.65))
                    Button("CONNECT") { connect() }.buttonStyle(.borderedProminent).tint(.cyan)
                }.padding(28)
            }
            Spacer()
        }.padding(.top, 16)
        .task(id: store?.statusText ?? "NO_HOME") {
            guard let store else { return }
            while !Task.isCancelled {
                store.refreshAll()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .sheet(item: $selectedLight) { light in
            if let store {
                LightControlSheet(store: store, light: light)
            }
        }
        .sheet(isPresented: $showWiFiQR) { WiFiQRCodeSheet() }
    }
}

private struct WiFiQRCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("guestWiFiSSID") private var ssid = ""
    @AppStorage("guestWiFiPassword") private var password = ""
    @State private var draftSSID = ""
    @State private var draftPassword = ""
    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    private var hasNetwork: Bool { !ssid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var qrImage: UIImage? {
        let payload = "WIFI:T:WPA;S:\(escaped(ssid));P:\(escaped(password));;"
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)), let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                if hasNetwork, let qrImage {
                    Image(uiImage: qrImage).interpolation(.none).resizable().scaledToFit().frame(width: 240, height: 240)
                        .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 18))
                    Text(ssid).font(.title3.bold())
                    Text("Tap the Wi‑Fi logo again to edit this guest network.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("EDIT WIFI") { draftSSID = ssid; draftPassword = password; ssid = "" }
                        .buttonStyle(.bordered)
                } else {
                    Image(systemName: "wifi").font(.system(size: 48)).foregroundStyle(.cyan)
                    Text("GUEST WIFI").font(.title2.bold())
                    Text("Enter the network once. Guests can scan this code with their phone camera.")
                        .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    TextField("Network name", text: $draftSSID).textInputAutocapitalization(.never).textFieldStyle(.roundedBorder)
                    SecureField("Password", text: $draftPassword).textFieldStyle(.roundedBorder)
                    Button("SAVE & SHOW QR") {
                        ssid = draftSSID.trimmingCharacters(in: .whitespacesAndNewlines)
                        password = draftPassword
                    }
                    .buttonStyle(.borderedProminent).tint(.cyan).disabled(draftSSID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Spacer()
            }
            .padding(28)
            .onAppear { draftSSID = ssid; draftPassword = password }
            .navigationTitle("Wi‑Fi Connect")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ":", with: "\\:")
    }
}

private struct LightControlSheet: View {
    let store: HomeKitStore
    let light: HomeKitStore.Light
    @Environment(\.dismiss) private var dismiss
    @State private var brightness: Double
    @State private var selectedColor = Color.red

    init(store: HomeKitStore, light: HomeKitStore.Light) {
        self.store = store
        self.light = light
        _brightness = State(initialValue: Double(light.brightness ?? 100))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: light.isOn ? "lightbulb.fill" : "lightbulb").font(.system(size: 60)).foregroundStyle(light.isOn ? .yellow : .secondary)
                Text(light.name).font(.title.bold())
                Text(light.room.uppercased()).font(.system(size: 11, weight: .black, design: .monospaced)).foregroundStyle(.secondary)

                if light.brightnessCharacteristic != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("BRIGHTNESS \(Int(brightness))% ").font(.system(size: 12, weight: .black, design: .monospaced))
                        Slider(value: $brightness, in: 1...100, step: 1) { editing in
                            if !editing { store.setBrightness(Int(brightness), for: light) }
                        }
                    }.padding(.horizontal, 28)
                }

                if light.colorTemperatureCharacteristic != nil {
                    VStack(spacing: 10) {
                        Text("WHITE TONE").font(.system(size: 12, weight: .black, design: .monospaced))
                        HStack(spacing: 10) {
                            WhiteToneButton(title: "WARM", color: Color(red: 1, green: 0.63, blue: 0.25)) { store.setColorTemperature(370, for: light) }
                            WhiteToneButton(title: "SOFT", color: Color(red: 1, green: 0.80, blue: 0.52)) { store.setColorTemperature(333, for: light) }
                            WhiteToneButton(title: "NEUTRAL", color: Color(red: 1, green: 0.94, blue: 0.80)) { store.setColorTemperature(250, for: light) }
                            WhiteToneButton(title: "COOL", color: Color(red: 0.80, green: 0.90, blue: 1)) { store.setColorTemperature(200, for: light) }
                        }
                    }
                }

                if light.hueCharacteristic != nil, light.saturationCharacteristic != nil {
                    VStack(spacing: 10) {
                        Text("CUSTOM COLOR").font(.system(size: 12, weight: .black, design: .monospaced))
                        ColorPicker("Choose a color", selection: $selectedColor, supportsOpacity: false)
                            .labelsHidden()
                            .scaleEffect(1.35)
                            .padding(.vertical, 8)
                            .onChange(of: selectedColor) { _, color in
                                let uiColor = UIColor(color)
                                var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
                                guard uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return }
                                store.setColor(for: light, hue: Int((hue * 360).rounded()), saturation: Int((saturation * 100).rounded()))
                            }
                    }
                }
                Button(light.isOn ? "TURN OFF" : "TURN ON") { store.toggle(light); dismiss() }
                    .buttonStyle(.borderedProminent).tint(light.isOn ? .gray : .yellow)
                Spacer()
            }
            .padding(.top, 32)
            .navigationTitle("Light Control")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct WhiteToneButton: View {
    let title: String
    let color: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Circle().fill(color).frame(width: 28, height: 28).overlay(Circle().stroke(.white.opacity(0.45), lineWidth: 1))
                Text(title).font(.system(size: 8, weight: .black, design: .monospaced))
            }
            .frame(width: 52)
        }
        .buttonStyle(.plain)
    }
}

private struct ColorPreset: View {
    let color: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) { Circle().fill(color).frame(width: 34, height: 34).overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1)) }.buttonStyle(.plain)
    }
}

private struct RitualButton: View {
    let icon: String; let title: String; let color: Color; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title2).foregroundStyle(color)
                Text(title).font(.system(size: 9, weight: .black, design: .monospaced)).lineLimit(1)
            }.frame(maxWidth: .infinity, minHeight: 76).background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain)
    }
}

private struct HomeEmptyState: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 13, weight: .medium, design: .rounded)).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.64)).padding(.horizontal, 32) }
}

private struct AirportPulseView: View {
    let aircraft: [Aircraft]; let isLoading: Bool; let errorMessage: String?
    private var nearbyFlights: [Aircraft] {
        Array(aircraft
            .filter { plane in
                let callsign = plane.flight?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return !callsign.isEmpty && plane.distance != nil && plane.altitude?.doubleValue != nil
            }
            .sorted { ($0.distance ?? .greatestFiniteMagnitude) < ($1.distance ?? .greatestFiniteMagnitude) }
            .prefix(5))
    }

    var body: some View {
        VStack(spacing: 14) {
            Text("NEARBY FLIGHTS").font(.system(size: 16, weight: .black, design: .monospaced)).foregroundStyle(.orange)
            Text("THE CLOSEST IDENTIFIED AIRCRAFT AROUND BOSTON LOGAN")
                .font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
            if !nearbyFlights.isEmpty {
                VStack(spacing: 10) {
                    ForEach(nearbyFlights) { flight in
                        NearbyFlightCard(flight: flight)
                    }
                }
                .padding(.horizontal, 24)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 44)).foregroundStyle(.cyan)
                    Text(isLoading ? "CHECKING THE AIRSPACE" : "NO COMPLETE FLIGHTS NEARBY").font(.system(size: 18, weight: .bold, design: .monospaced))
                    Text(errorMessage ?? "Only identified flights with useful live information are shown.")
                        .font(.system(size: 13, weight: .medium, design: .rounded)).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.65))
                }.padding(24)
            }
            Spacer()
        }.padding(.top, 16)
    }
}

private struct NearbyFlightCard: View {
    let flight: Aircraft

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "airplane")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.orange)
                .rotationEffect(.degrees(flight.track ?? 0))
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 9) {
                    Text(flight.callsign).font(.system(size: 19, weight: .black, design: .monospaced))
                    if let operatorName = flight.operatorName, !operatorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(operatorName.uppercased())
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72)).lineLimit(1)
                    }
                }
                if let route = flight.routeText {
                    Text(route).font(.system(size: 14, weight: .black, design: .monospaced)).foregroundStyle(.cyan)
                }
                Text(flight.proximityText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(flight.distanceText).foregroundStyle(.orange)
                Text(flight.altitudeText)
                Text(flight.movementText)
            }
            .font(.system(size: 12, weight: .bold, design: .monospaced))
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 17))
    }
}

private struct TrafficStory: View {
    let icon: String; let title: String; let plane: Aircraft; let detail: String; let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon).foregroundStyle(color)
            Text(title).font(.system(size: 9, weight: .black, design: .monospaced)).foregroundStyle(.white.opacity(0.56))
            Text(plane.callsign).font(.system(size: 15, weight: .bold, design: .monospaced)).lineLimit(1)
            Text(detail).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(color).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(13)
        .background(.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 15))
    }
}

private struct PulseMetric: View {
    let value: String; let label: String; let color: Color
    var body: some View {
        VStack(spacing: 5) {
            Text(value).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(color)
            Text(label).font(.system(size: 10, weight: .black, design: .monospaced)).foregroundStyle(.white.opacity(0.6))
        }.frame(maxWidth: .infinity).padding(.vertical, 16).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }
}

private enum DaylightSummary {
    static func text(for date: Date) -> String {
        let sun = BostonSunTimes(date: date)
        if date < sun.sunrise || date >= sun.sunset { return "NIGHT SKY" }
        if date.timeIntervalSince(sun.sunrise) < 75 * 60 { return "MORNING LIGHT" }
        if sun.sunset.timeIntervalSince(date) < 75 * 60 { return "GOLDEN HOUR" }
        return "DAYLIGHT"
    }
    static func sunsetText(for date: Date) -> String {
        BostonSunTimes(date: date).sunset.formatted(date: .omitted, time: .shortened)
    }
}

private struct BostonSunTimes {
    let sunrise: Date
    let sunset: Date

    init(date: Date) {
        let latitude = 42.3656 * Double.pi / 180
        let longitude = -71.0096
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let day = Double(localCalendar.ordinality(of: .day, in: .year, for: date) ?? 1)
        let gamma = 2 * Double.pi / 365 * (day - 1)
        let equationOfTime = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma) - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma))
        let declination = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma) - 0.006758 * cos(2 * gamma) + 0.000907 * sin(2 * gamma) - 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma)
        let hourAngle = acos(cos(90.833 * Double.pi / 180) / (cos(latitude) * cos(declination)) - tan(latitude) * tan(declination)) * 180 / Double.pi
        let sunriseMinutes = 720 - 4 * (longitude + hourAngle) - equationOfTime
        let sunsetMinutes = 720 - 4 * (longitude - hourAngle) - equationOfTime

        let components = localCalendar.dateComponents([.year, .month, .day], from: date)
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let utcStart = utcCalendar.date(from: components) ?? date
        sunrise = utcStart.addingTimeInterval(sunriseMinutes * 60)
        sunset = utcStart.addingTimeInterval(sunsetMinutes * 60)
    }
}

private struct MoonInfo {
    let day: Int; let illumination: Int; let name: String; let shadowOpacity: Double; let shadowOffset: CGFloat; let phase: Double
    init(date: Date) {
        let reference = Date(timeIntervalSince1970: 947182440)
        let lunarAge = date.timeIntervalSince(reference) / 86_400.0 / 29.53058867
        phase = lunarAge - floor(lunarAge)
        day = Int(phase * 29.53) + 1
        illumination = Int(((1 - cos(phase * 2 * .pi)) / 2 * 100).rounded())
        switch phase {
        case 0..<0.035, 0.965...: name = "New Moon"
        case 0.035..<0.22: name = "Waxing Crescent"
        case 0.22..<0.28: name = "First Quarter"
        case 0.28..<0.47: name = "Waxing Gibbous"
        case 0.47..<0.53: name = "Full Moon"
        case 0.53..<0.72: name = "Waning Gibbous"
        case 0.72..<0.78: name = "Last Quarter"
        default: name = "Waning Crescent"
        }
        let fullness = phase <= 0.5 ? phase / 0.5 : (1 - phase) / 0.5
        shadowOpacity = 0.96
        shadowOffset = (phase <= 0.5 ? -1 : 1) * CGFloat(fullness * 158)
    }
    var shortDescription: String { "\(name) • \(illumination)% lit" }
    var nextFullMoonText: String {
        let days = (phase <= 0.5 ? 0.5 - phase : 1.5 - phase) * 29.53058867
        let rounded = Int(days.rounded())
        return rounded == 0 ? "TONIGHT" : "IN \(rounded) DAYS"
    }
}

private struct WeatherBackground: View {
    let condition: String
    let date: Date

    private var sunTimes: BostonSunTimes { BostonSunTimes(date: date) }
    private var isDaytime: Bool { date >= sunTimes.sunrise && date < sunTimes.sunset }
    private var isGoldenHour: Bool {
        isDaytime && (date.timeIntervalSince(sunTimes.sunrise) < 75 * 60 || sunTimes.sunset.timeIntervalSince(date) < 75 * 60)
    }
    private var isSnowy: Bool { condition.contains("SN") }
    private var isStormy: Bool { condition.contains("TS") || condition.contains("RA") || condition.contains("SH") || condition.contains("DZ") }
    private var isCloudy: Bool { condition.contains("OVC") || condition.contains("BKN") || condition.contains("FG") || condition.contains("BR") || isSnowy }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                LinearGradient(colors: backgroundColors, startPoint: .top, endPoint: .bottom)
                if isDaytime {
                    DaylightAtmosphere(phase: phase, cloudCover: cloudCover, isStormy: isStormy)
                } else {
                    BackgroundMoon(phase: phase, date: date, obscured: isCloudy || isStormy || isSnowy)
                    NightAtmosphere(phase: phase, cloudCover: cloudCover, isStormy: isStormy)
                }
                if isCloudy || isStormy || isSnowy {
                    CloudBank(phase: phase, opacity: isStormy ? 0.48 : (isSnowy ? 0.34 : 0.24), isDark: isStormy, band: 0)
                    CloudBank(phase: phase + 19, opacity: isStormy ? 0.34 : 0.16, isDark: isStormy, band: 1)
                } else {
                    // Even a clear sky gets slow, high-altitude cloud movement.
                    CloudBank(phase: phase, opacity: isDaytime ? 0.10 : 0.06, isDark: false, band: 0)
                }
                if isStormy {
                    RainLayer(phase: phase).opacity(0.72)
                    LightningFlash(phase: phase)
                }
                if isSnowy {
                    SnowLayer(phase: phase).opacity(0.92)
                }
            }
        }
        .animation(.easeInOut(duration: 1.2), value: condition)
    }

    private var backgroundColors: [Color] {
        if isSnowy { return [Color(red: 0.31, green: 0.46, blue: 0.59), Color(red: 0.055, green: 0.14, blue: 0.24)] }
        if isStormy { return [Color(red: 0.12, green: 0.22, blue: 0.36), Color(red: 0.012, green: 0.035, blue: 0.10)] }
        if isCloudy { return [Color(red: 0.22, green: 0.38, blue: 0.55), Color(red: 0.025, green: 0.12, blue: 0.25)] }
        if isGoldenHour { return [Color(red: 0.43, green: 0.42, blue: 0.64), Color(red: 0.045, green: 0.10, blue: 0.27)] }
        if isDaytime { return [Color(red: 0.07, green: 0.48, blue: 0.84), Color(red: 0.015, green: 0.19, blue: 0.48)] }
        return [Color(red: 0.035, green: 0.07, blue: 0.20), Color(red: 0.002, green: 0.012, blue: 0.07)]
    }

    private var cloudCover: Double {
        if isStormy { return 0.95 }
        if isSnowy { return 0.80 }
        if isCloudy { return 0.68 }
        return 0.20
    }

    static func starOpacity(condition: String, date: Date) -> Double {
        let sun = BostonSunTimes(date: date)
        guard date < sun.sunrise || date >= sun.sunset else { return 0.04 }
        if condition.contains("OVC") || condition.contains("BKN") || condition.contains("RA") || condition.contains("SN") { return 0.08 }
        return 0.42
    }
}

private struct DaylightAtmosphere: View {
    let phase: TimeInterval
    let cloudCover: Double
    let isStormy: Bool

    var body: some View {
        GeometryReader { proxy in
            let sunX = proxy.size.width * (0.74 + CGFloat(sin(phase / 80)) * 0.035)
            let sunY = -proxy.size.height * 0.10 + CGFloat(cos(phase / 65)) * 12
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(isStormy ? 0.15 : 0.95), Color.yellow.opacity(isStormy ? 0.05 : 0.35), .clear], center: .center, startRadius: 4, endRadius: 310))
                    .frame(width: 620, height: 620)
                    .position(x: sunX, y: sunY)
                    .blur(radius: 12)
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(LinearGradient(colors: [.white.opacity((1 - cloudCover) * 0.16), .clear], startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * 1.35, height: 110)
                        .rotationEffect(.degrees(-11 + Double(index) * 6))
                        .offset(x: CGFloat(sin(phase / (10 + Double(index) * 3)) * 90), y: CGFloat(index - 1) * 180)
                        .blur(radius: 32)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }
}

private struct NightAtmosphere: View {
    let phase: TimeInterval
    let cloudCover: Double
    let isStormy: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Ellipse()
                    .fill(LinearGradient(colors: [.indigo.opacity(isStormy ? 0.12 : 0.34), .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(width: proxy.size.width * 1.45, height: 180)
                    .rotationEffect(.degrees(-10))
                    .offset(x: CGFloat(sin(phase / 16) * 85), y: -proxy.size.height * 0.20)
                    .blur(radius: 54)
                Circle()
                    .fill(RadialGradient(colors: [.cyan.opacity((1 - cloudCover) * 0.16), .clear], center: .center, startRadius: 4, endRadius: 250))
                    .frame(width: 500, height: 500)
                    .offset(x: CGFloat(cos(phase / 52) * 50), y: proxy.size.height * 0.22)
                    .blur(radius: 30)
            }
        }
    }
}

private struct BackgroundMoon: View {
    let phase: TimeInterval
    let date: Date
    let obscured: Bool

    var body: some View {
        GeometryReader { proxy in
            let moon = MoonInfo(date: date)
            let size = min(max(proxy.size.width * 0.16, 112), 220)
            Image("MoonTexture")
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .mask(MoonPhaseMask(offset: moon.shadowOffset * size / 158))
                // The moon belongs to the atmosphere rather than sitting above it.
                .shadow(color: .white.opacity(obscured ? 0.06 : 0.22), radius: obscured ? 8 : 22)
                .blur(radius: obscured ? 2.5 : 0.8)
                .opacity(obscured ? 0.25 : 0.58)
                .position(
                    x: proxy.size.width * 0.79 + CGFloat(sin(phase / 75) * 14),
                    y: proxy.size.height * 0.24 + CGFloat(cos(phase / 70) * 8)
                )
        }
    }
}

private struct CloudBank: View {
    let phase: TimeInterval
    let opacity: Double
    let isDark: Bool
    let band: Int

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let clusterWidth = max(width * 0.42, 270)
            let travel = wrapped(CGFloat(phase * (band == 0 ? 7 : -4)), width: clusterWidth * 2)
            ForEach(0..<5, id: \.self) { index in
                let y = proxy.size.height * (band == 0 ? 0.22 : 0.58) + CGFloat((index % 2) * 54 - 27)
                CloudPuff(tint: isDark ? Color(red: 0.14, green: 0.20, blue: 0.31) : .white, opacity: opacity)
                    .frame(width: clusterWidth, height: 150)
                    .position(x: -clusterWidth + travel + CGFloat(index) * clusterWidth * 0.76, y: y)
            }
        }
    }
}

private struct CloudPuff: View {
    let tint: Color
    let opacity: Double

    var body: some View {
        ZStack(alignment: .bottom) {
            Capsule().fill(tint.opacity(opacity * 0.76)).frame(width: 250, height: 58)
            Circle().fill(tint.opacity(opacity)).frame(width: 100, height: 100).offset(x: -58, y: -17)
            Circle().fill(tint.opacity(opacity * 0.94)).frame(width: 124, height: 124).offset(x: 10, y: -30)
            Circle().fill(tint.opacity(opacity * 0.82)).frame(width: 82, height: 82).offset(x: 78, y: -12)
        }
        .blur(radius: 13)
        .compositingGroup()
    }
}

private struct LightningFlash: View {
    let phase: TimeInterval

    var body: some View {
        let pulse = sin(phase * 2.4) > 0.992 ? 0.42 : 0
        return Color.white.opacity(pulse).blendMode(.screen)
    }
}

private struct ClearSkyTexture: View {
    let phase: TimeInterval

    var body: some View {
        GeometryReader { proxy in
            let driftX = CGFloat(sin(phase / 35) * 14)
            let driftY = CGFloat(cos(phase / 42) * 8)
            Image("ClearSky")
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width + 36, height: proxy.size.height + 36)
                .offset(x: driftX - 18, y: driftY - 18)
                .overlay(Color(red: 0.02, green: 0.19, blue: 0.43).opacity(0.12))
                .clipped()
        }
    }
}

private struct SunlitSky: View {
    let phase: TimeInterval
    let clouded: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(clouded ? 0.18 : 0.82), Color(red: 0.58, green: 0.83, blue: 1).opacity(clouded ? 0.10 : 0.38), .clear], center: .center, startRadius: 6, endRadius: 260))
                    .frame(width: 560, height: 560)
                    .offset(x: proxy.size.width * 0.30, y: -proxy.size.height * 0.44)
                    .blur(radius: 14)

                Ellipse()
                    .fill(LinearGradient(colors: [.white.opacity(clouded ? 0.10 : 0.20), .clear], startPoint: .top, endPoint: .bottom))
                    .frame(width: proxy.size.width * 1.45, height: proxy.size.height * 0.38)
                    .rotationEffect(.degrees(-12))
                    .offset(x: CGFloat(sin(phase / 18) * 35), y: -proxy.size.height * 0.30)
                    .blur(radius: 58)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }
}

private struct LivingSkyFlow: View {
    let phase: TimeInterval
    let isDaytime: Bool
    let muted: Bool

    var body: some View {
        GeometryReader { proxy in
            let travel = CGFloat(sin(phase / 5.5) * 130)
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(LinearGradient(
                            colors: [isDaytime ? .cyan.opacity(muted ? 0.11 : 0.28) : .blue.opacity(0.20), .clear, .blue.opacity(0.08)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: proxy.size.width * 1.55, height: 150)
                        .rotationEffect(.degrees(-12 + Double(index) * 4))
                        .offset(x: travel + CGFloat(index - 1) * 105, y: CGFloat(index - 1) * 180)
                        .blur(radius: 36)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }
}

private struct AtmosphericLight: View {
    let phase: TimeInterval
    let isDaytime: Bool
    let isCloudy: Bool
    var body: some View {
        let drift = CGFloat(0.22 + sin(phase / 12) * 0.12)
        return LinearGradient(
            colors: isDaytime ? [Color.cyan.opacity(isCloudy ? 0.12 : 0.26), .clear, Color.blue.opacity(0.16)] : [Color.indigo.opacity(0.22), .clear, Color.cyan.opacity(0.12)],
            startPoint: UnitPoint(x: drift, y: 0),
            endPoint: UnitPoint(x: 1 - drift, y: 1)
        )
        .blendMode(.screen)
    }
}

private struct CloudLayer: View {
    let opacity: Double
    let phase: TimeInterval
    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let drift = CGFloat(phase.truncatingRemainder(dividingBy: 90)) * 4
            ForEach(0..<6, id: \.self) { index in
                Ellipse().fill(.white.opacity(opacity))
                    .frame(width: 280, height: 80)
                    .blur(radius: 24)
                    .position(x: wrapped(CGFloat(index * 213) + drift, width: width + 260) - 130, y: CGFloat(60 + (index * 131) % Int(max(proxy.size.height, 1))))
            }
        }
    }
}

private struct RainLayer: View {
    let phase: TimeInterval
    var body: some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height, 1)
            ForEach(0..<42, id: \.self) { index in
                Capsule().fill(.cyan.opacity(0.42)).frame(width: 1.5, height: 22)
                    .rotationEffect(.degrees(18))
                    .position(x: CGFloat((index * 97) % Int(max(proxy.size.width, 1))), y: wrapped(CGFloat(index * 163) + CGFloat(phase * 260), width: height + 80) - 40)
            }
        }
    }
}

private struct SnowLayer: View {
    let phase: TimeInterval
    var body: some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height, 1)
            ForEach(0..<48, id: \.self) { index in
                Circle().fill(.white.opacity(index.isMultiple(of: 3) ? 0.82 : 0.48))
                    .frame(width: index.isMultiple(of: 3) ? 4 : 2, height: index.isMultiple(of: 3) ? 4 : 2)
                    .position(x: CGFloat((index * 71) % Int(max(proxy.size.width, 1))) + CGFloat(sin(phase + Double(index)) * 12), y: wrapped(CGFloat(index * 119) + CGFloat(phase * 38), width: height + 30) - 15)
            }
        }
    }
}

private func wrapped(_ value: CGFloat, width: CGFloat) -> CGFloat {
    let remainder = value.truncatingRemainder(dividingBy: width)
    return remainder >= 0 ? remainder : remainder + width
}

private struct StarField: View {
    var body: some View {
        GeometryReader { proxy in
            ForEach(0..<55, id: \.self) { index in
                Circle().fill(.white.opacity(Double((index * 17) % 7 + 2) / 20)).frame(width: index.isMultiple(of: 11) ? 3 : 1.5, height: index.isMultiple(of: 11) ? 3 : 1.5)
                    .position(x: CGFloat((index * 79) % Int(max(proxy.size.width, 1))), y: CGFloat((index * 47) % Int(max(proxy.size.height, 1))))
            }
        }
    }
}

struct SettingsView: View {
    @Bindable var vm: FlightWallViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("autoCycle") private var autoCycle = true
    @AppStorage("worldCityIDs") private var worldCityIDs = "Europe/London,Asia/Tokyo"
    @AppStorage("welcomeMessage") private var welcomeMessage = "WELCOME HOME"
    @AppStorage("temperatureUnit") private var temperatureUnit = "F"
    @AppStorage("dreamDestination") private var dreamDestination = "Tokyo"
    var body: some View {
        NavigationStack {
            Form {
                Section("LOCATION") {
                    TextField("Latitude", value: $vm.latitude, format: .number)
                    TextField("Longitude", value: $vm.longitude, format: .number)
                    Stepper("Flight range: \(vm.radiusNM) NM", value: $vm.radiusNM, in: 5...100, step: 5)
                }
                Section("LIVING ROOM") { Toggle("Auto-cycle Home, Sky & Space, Airport Pulse", isOn: $autoCycle) }
                Section("PERSONALIZE") {
                    TextField("Welcome message", text: $welcomeMessage)
                    Text("Shown above the main clock. For example: WELCOME HOME or THE SMITH HOME.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("WEATHER") {
                    Picker("Temperature", selection: $temperatureUnit) {
                        Text("Fahrenheit (°F)").tag("F")
                        Text("Celsius (°C)").tag("C")
                    }
                }
                Section("WORLD CLOCKS") {
                    NavigationLink("Choose cities") {
                        CityPicker(selectedIDs: Binding(
                            get: { Set(worldCityIDs.split(separator: ",").map(String.init)) },
                            set: { worldCityIDs = $0.sorted().joined(separator: ",") }
                        ))
                    }
                }
                Section("TRAVEL WISH LIST") {
                    Picker("Next escape", selection: $dreamDestination) {
                        Text("Tokyo").tag("Tokyo")
                        Text("Paris").tag("Paris")
                        Text("Dubai").tag("Dubai")
                        Text("Reykjavík").tag("Reykjavík")
                        Text("Sydney").tag("Sydney")
                    }
                }
                Section { Text("Home and Sky & Space work without a network. Airport Pulse uses community ADS-B data when it is available.").font(.footnote) }
            }
            .navigationTitle("Flight Wall Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct CityPicker: View {
    @Binding var selectedIDs: Set<String>
    @State private var searchText = ""

    private var cities: [WorldClock] {
        guard !searchText.isEmpty else { return WorldCities.all }
        return WorldCities.all.filter { $0.city.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List(cities) { city in
            Button {
                if selectedIDs.contains(city.timeZone) { selectedIDs.remove(city.timeZone) }
                else { selectedIDs.insert(city.timeZone) }
            } label: {
                HStack {
                    Text(city.city)
                    Spacer()
                    if selectedIDs.contains(city.timeZone) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                }
            }
            .foregroundStyle(.primary)
        }
        .navigationTitle("World Clocks")
        .searchable(text: $searchText, prompt: "Search cities")
    }
}
