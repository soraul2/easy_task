import SwiftUI

struct FocusDurationControl: View {
    let title: String
    let identifier: String
    @Binding var minutes: Int
    let range: ClosedRange<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
            HStack(spacing: 6) {
                adjustment("minus", label: "\(title) 1분 줄이기", disabled: minutes <= range.lowerBound) {
                    minutes = max(range.lowerBound, minutes - 1)
                }
                Text("\(minutes)분")
                    .font(.title3.monospacedDigit().weight(.bold))
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(identifier)-value")
                adjustment("plus", label: "\(title) 1분 늘리기", disabled: minutes >= range.upperBound) {
                    minutes = min(range.upperBound, minutes + 1)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(AppTheme.border, lineWidth: 1) }
    }

    private func adjustment(_ icon: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).frame(minWidth: 20, minHeight: 20)
        }
        .buttonStyle(PlanBaseButtonStyle(.secondary))
        .disabled(disabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier("\(identifier)-\(icon)")
    }
}

struct FocusTimerDial: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let seconds: TimeInterval
    let progress: Double
    let paused: Bool
    let isBreak: Bool

    private var clock: String {
        let value = max(0, Int(seconds.rounded(.up)))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                digits
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
            } else {
                ZStack {
                    Circle().fill(AppTheme.panel)
                    Circle().stroke(AppTheme.border.opacity(0.65), lineWidth: 8)
                    Circle().trim(from: 0, to: min(1, max(0, progress)))
                        .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(reduceMotion || paused ? nil : .linear(duration: 1), value: progress)
                    digits.padding(24)
                }
                .frame(width: 248, height: 248)
                .padding(6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isBreak ? "휴식 남은 시간" : "집중 남은 시간")
        .accessibilityValue("\(clock), \(paused ? "일시정지" : "진행 중")")
        .accessibilityIdentifier("focus-timer")
    }

    private var digits: some View {
        VStack(spacing: 10) {
            Text(paused ? "잠시 멈춤" : "남은 시간")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.secondaryText)
            Text(clock)
                .font(dynamicTypeSize.isAccessibilitySize ? .largeTitle.bold() : .system(size: 52, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Label(paused ? "준비되면 이어가세요" : (isBreak ? "잠깐 쉬어가세요" : "한 가지에 집중하는 중"),
                  systemImage: paused ? "pause.fill" : (isBreak ? "leaf" : "scope"))
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
    }
}
