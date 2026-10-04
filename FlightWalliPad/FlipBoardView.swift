import SwiftUI

struct FlipBoardText: View {
    let text: String
    var fontSize: CGFloat = 34

    var body: some View {
        HStack(spacing: fontSize * 0.055) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                SplitFlapCharacter(character: character, fontSize: fontSize)
            }
        }
    }
}

private struct SplitFlapCharacter: View {
    let character: Character
    let fontSize: CGFloat
    @State private var previousCharacter: Character = " "
    @State private var displayedCharacter: Character = " "
    @State private var isFlipping = false
    @State private var outgoingAngle = 0.0
    @State private var incomingAngle = 88.0

    var body: some View {
        if character == ":" {
            Text(":")
                .font(.system(size: fontSize * 0.88, weight: .black, design: .monospaced))
                .foregroundStyle(Color(red: 0.93, green: 0.90, blue: 0.80))
                .frame(width: fontSize * 0.42, height: fontSize * 1.24, alignment: .center)
                .offset(y: fontSize * 0.01)
                .zIndex(2)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: fontSize * 0.055)
                    .fill(Color(red: 0.075, green: 0.078, blue: 0.082).opacity(0.90))
                RoundedRectangle(cornerRadius: fontSize * 0.055)
                    .stroke(Color.white.opacity(0.075), lineWidth: 0.65)
                if isFlipping {
                    halfDigit(previousCharacter, half: .top)
                    halfDigit(displayedCharacter, half: .bottom)
                    movingHalf(previousCharacter, half: .top, shade: [.clear, .black.opacity(0.58)])
                        .rotation3DEffect(.degrees(outgoingAngle), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.55)
                        .shadow(color: .black.opacity(0.65), radius: 6, y: 4)
                    movingHalf(displayedCharacter, half: .bottom, shade: [.black.opacity(0.58), .clear])
                        .rotation3DEffect(.degrees(incomingAngle), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.55)
                        .shadow(color: .black.opacity(0.55), radius: 6, y: -3)
                } else {
                    digit(displayedCharacter)
                }
                LinearGradient(colors: [.black.opacity(0.14), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(width: fontSize * 0.67, height: fontSize * 0.62)
                    .frame(height: fontSize * 1.24, alignment: .top)
                LinearGradient(colors: [.clear, .black.opacity(0.20)], startPoint: .top, endPoint: .bottom)
                    .frame(width: fontSize * 0.67, height: fontSize * 0.62)
                    .frame(height: fontSize * 1.24, alignment: .bottom)
                Rectangle().fill(.black.opacity(0.56)).frame(height: 1)
                HStack {
                    Circle().fill(.black.opacity(0.62)).frame(width: fontSize * 0.07, height: fontSize * 0.07)
                    Spacer()
                    Circle().fill(.black.opacity(0.62)).frame(width: fontSize * 0.07, height: fontSize * 0.07)
                }.padding(.horizontal, fontSize * 0.035)
            }
            .frame(width: fontSize * 0.67, height: fontSize * 1.24)
            .shadow(color: .black.opacity(0.38), radius: 2, y: 1)
            .onAppear { previousCharacter = character; displayedCharacter = character }
            .onChange(of: character) { oldCharacter, newCharacter in
                previousCharacter = oldCharacter
                displayedCharacter = newCharacter
                isFlipping = true
                outgoingAngle = 0
                incomingAngle = 88
                withAnimation(.linear(duration: 0.12)) { outgoingAngle = -88 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
                    withAnimation(.linear(duration: 0.13)) { incomingAngle = 0 }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    isFlipping = false
                }
            }
        }
    }

    private func digit(_ value: Character) -> some View {
        Text(String(value))
            .font(.system(size: fontSize, weight: .black, design: .monospaced))
            .foregroundStyle(Color(red: 0.95, green: 0.92, blue: 0.81))
            .frame(width: fontSize * 0.67, height: fontSize * 1.24)
    }

    private func halfDigit(_ value: Character, half: FlapHalf) -> some View {
        digit(value)
            .mask(alignment: half == .top ? .top : .bottom) {
                Rectangle().frame(width: fontSize * 0.67, height: fontSize * 0.62)
            }
    }

    private func movingHalf(_ value: Character, half: FlapHalf, shade: [Color]) -> some View {
        ZStack {
            digit(value)
            LinearGradient(colors: shade, startPoint: .top, endPoint: .bottom)
        }
        .mask(alignment: half == .top ? .top : .bottom) {
            Rectangle().frame(width: fontSize * 0.67, height: fontSize * 0.62)
        }
    }
}

private enum FlapHalf { case top, bottom }

struct FlightRow: View {
    let aircraft: Aircraft
    let index: Int

    var body: some View {
        HStack(spacing: 12) {
            FlipBoardText(text: aircraft.callsign, fontSize: 24)
                .frame(width: 205, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                if aircraft.operatorName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    Text(aircraft.airlineText)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                }
                Text(aircraft.typeText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .opacity(0.65)
            }
            .frame(width: 170, alignment: .leading)
            Spacer()
            Text(aircraft.altitudeText)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .frame(width: 105, alignment: .trailing)
            Text(aircraft.distanceText)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .frame(width: 105, alignment: .trailing)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 8)
        .background(Color.white.opacity(index.isMultiple(of: 2) ? 0.035 : 0.015))
    }
}
