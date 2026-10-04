import Foundation
import HomeKit
import Observation

@MainActor
@Observable
final class HomeKitStore: NSObject, HMHomeManagerDelegate {
    struct Light: Identifiable {
        let id: UUID
        let name: String
        let room: String
        let characteristic: HMCharacteristic
        let brightnessCharacteristic: HMCharacteristic?
        let hueCharacteristic: HMCharacteristic?
        let saturationCharacteristic: HMCharacteristic?
        let colorTemperatureCharacteristic: HMCharacteristic?
        let brightness: Int?
        var isOn: Bool
    }

    struct Scene: Identifiable {
        let id: UUID
        let name: String
        let actionSet: HMActionSet
    }

    private let manager = HMHomeManager()
    private(set) var lights: [Light] = []
    private(set) var scenes: [Scene] = []
    private(set) var statusText = "CONNECT TO APPLE HOME"

    override init() {
        super.init()
        manager.delegate = self
    }

    nonisolated func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        Task { @MainActor in self.loadHome() }
    }

    func loadHome() {
        guard let home = manager.primaryHome ?? manager.homes.first else {
            statusText = "NO APPLE HOME FOUND"
            return
        }

        statusText = home.name.uppercased()
        scenes = home.actionSets.map { Scene(id: $0.uniqueIdentifier, name: $0.name, actionSet: $0) }
        lights = home.accessories.flatMap { accessory in
            accessory.services.compactMap { service in
                guard let characteristic = service.characteristics.first(where: { $0.characteristicType == HMCharacteristicTypePowerState }) else { return nil }
                let brightnessCharacteristic = service.characteristics.first(where: { $0.characteristicType == HMCharacteristicTypeBrightness })
                let hueCharacteristic = service.characteristics.first(where: { $0.characteristicType == HMCharacteristicTypeHue })
                let saturationCharacteristic = service.characteristics.first(where: { $0.characteristicType == HMCharacteristicTypeSaturation })
                let colorTemperatureCharacteristic = service.characteristics.first(where: { $0.characteristicType == HMCharacteristicTypeColorTemperature })
                let state = (characteristic.value as? NSNumber)?.boolValue ?? false
                let brightness = (brightnessCharacteristic?.value as? NSNumber)?.intValue
                return Light(id: characteristic.uniqueIdentifier, name: accessory.name, room: accessory.room?.name ?? "HOME", characteristic: characteristic, brightnessCharacteristic: brightnessCharacteristic, hueCharacteristic: hueCharacteristic, saturationCharacteristic: saturationCharacteristic, colorTemperatureCharacteristic: colorTemperatureCharacteristic, brightness: brightness, isOn: state)
            }
        }
        for light in lights {
            refresh(light)
        }
    }

    func toggle(_ light: Light) {
        setLocalState(for: light.id, isOn: !light.isOn)
        light.characteristic.writeValue(!light.isOn) { [weak self] _ in
            Task { @MainActor in self?.refresh(light) }
        }
    }

    func setAllLights(on: Bool) {
        for light in lights {
            light.characteristic.writeValue(on) { _ in }
        }
        lights = lights.map { light in
            var updated = light
            updated.isOn = on
            return updated
        }
        Task {
            try? await Task.sleep(for: .seconds(1))
            for light in lights { refresh(light) }
        }
    }

    func movieTime() {
        for light in lights where light.isOn {
            light.brightnessCharacteristic?.writeValue(10 as NSNumber) { _ in }
        }
    }

    func goodMorning() {
        // Do this directly instead of relying on a user-created scene with the
        // same name. Changing only power and brightness lets a light that has
        // Adaptive Lighting enabled in Apple Home retain its adaptive colour.
        for light in lights {
            light.characteristic.writeValue(true) { _ in
                light.brightnessCharacteristic?.writeValue(70 as NSNumber) { _ in }
            }
        }
        Task {
            try? await Task.sleep(for: .seconds(1))
            refreshAll()
        }
    }

    func setBrightness(_ brightness: Int, for light: Light) {
        guard let characteristic = light.brightnessCharacteristic else { return }
        characteristic.writeValue(brightness as NSNumber) { [weak self] _ in
            Task { @MainActor in self?.refresh(light) }
        }
    }

    func setColorTemperature(_ mired: Int, for light: Light) {
        guard let characteristic = light.colorTemperatureCharacteristic else { return }
        characteristic.writeValue(mired as NSNumber) { [weak self] _ in
            if !light.isOn { light.characteristic.writeValue(true) { _ in } }
            Task { @MainActor in self?.refresh(light) }
        }
    }

    func setColor(for light: Light, hue: Int, saturation: Int) {
        light.hueCharacteristic?.writeValue(hue as NSNumber) { _ in }
        light.saturationCharacteristic?.writeValue(saturation as NSNumber) { _ in }
        if !light.isOn { light.characteristic.writeValue(true) { _ in } }
    }

    func activate(_ scene: Scene) {
        guard let home = manager.primaryHome ?? manager.homes.first else { return }
        home.executeActionSet(scene.actionSet) { [weak self] _ in
            Task { @MainActor in self?.loadHome() }
        }
    }

    func refreshAll() {
        for light in lights { refresh(light) }
    }

    private func refresh(_ light: Light) {
        light.characteristic.readValue { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let isOn = (light.characteristic.value as? NSNumber)?.boolValue ?? light.isOn
                let brightness = (light.brightnessCharacteristic?.value as? NSNumber)?.intValue
                self.setLocalState(for: light.id, isOn: isOn, brightness: brightness)
            }
        }
    }

    private func setLocalState(for id: UUID, isOn: Bool, brightness: Int? = nil) {
        guard let index = lights.firstIndex(where: { $0.id == id }) else { return }
        lights[index].isOn = isOn
        if let brightness { lights[index] = Light(id: lights[index].id, name: lights[index].name, room: lights[index].room, characteristic: lights[index].characteristic, brightnessCharacteristic: lights[index].brightnessCharacteristic, hueCharacteristic: lights[index].hueCharacteristic, saturationCharacteristic: lights[index].saturationCharacteristic, colorTemperatureCharacteristic: lights[index].colorTemperatureCharacteristic, brightness: brightness, isOn: isOn) }
    }
}
