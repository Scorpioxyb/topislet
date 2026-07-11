import Foundation
import SwiftUI

@MainActor
final class LayoutCalibrationSettings: ObservableObject {
    private enum Key {
        static let prefix = "MacBookIsland.LayoutCalibration."
        static let islandYOffset = "islandYOffset"
        static let notchHeightAdjustment = "notchHeightAdjustment"
        static let expandedHeightAdjustment = "expandedHeightAdjustment"
        static let expandedTopControlsTopOffset = "expandedTopControlsTopOffset"
        static let leftControlsXOffset = "leftControlsXOffset"
        static let leftControlsYOffset = "leftControlsYOffset"
        static let rightControlsXOffset = "rightControlsXOffset"
        static let rightControlsYOffset = "rightControlsYOffset"
        static let expandedContentTopGap = "expandedContentTopGap"
    }

    private enum Default {
        static let islandYOffset = 0.0
        static let notchHeightAdjustment = 1.0
        static let expandedHeightAdjustment = 0.0
        static let expandedTopControlsTopOffset = 4.0
        static let leftControlsXOffset = 22.0
        static let leftControlsYOffset = 0.0
        static let rightControlsXOffset = 22.0
        static let rightControlsYOffset = -1.0
        static let expandedContentTopGap = 46.0
    }

    private let defaults: UserDefaults
    private var isLoading = false
    private var currentDisplayKey: String

    @Published private(set) var currentDisplayName: String

    @Published var islandYOffset: Double {
        didSet { persist(Key.islandYOffset, islandYOffset) }
    }

    @Published var notchHeightAdjustment: Double {
        didSet { persist(Key.notchHeightAdjustment, notchHeightAdjustment) }
    }

    @Published var expandedHeightAdjustment: Double {
        didSet { persist(Key.expandedHeightAdjustment, expandedHeightAdjustment) }
    }

    @Published var expandedTopControlsTopOffset: Double {
        didSet { persist(Key.expandedTopControlsTopOffset, expandedTopControlsTopOffset) }
    }

    @Published var leftControlsXOffset: Double {
        didSet { persist(Key.leftControlsXOffset, leftControlsXOffset) }
    }

    @Published var leftControlsYOffset: Double {
        didSet { persist(Key.leftControlsYOffset, leftControlsYOffset) }
    }

    @Published var rightControlsXOffset: Double {
        didSet { persist(Key.rightControlsXOffset, rightControlsXOffset) }
    }

    @Published var rightControlsYOffset: Double {
        didSet { persist(Key.rightControlsYOffset, rightControlsYOffset) }
    }

    @Published var expandedContentTopGap: Double {
        didSet { persist(Key.expandedContentTopGap, expandedContentTopGap) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        currentDisplayKey = "default"
        currentDisplayName = "当前屏幕"
        islandYOffset = Self.double(
            named: Key.islandYOffset,
            displayKey: currentDisplayKey,
            in: defaults,
            fallback: Default.islandYOffset
        )
        notchHeightAdjustment = Self.double(
            named: Key.notchHeightAdjustment,
            displayKey: currentDisplayKey,
            in: defaults,
            fallback: Default.notchHeightAdjustment
        )
        expandedHeightAdjustment = Self.double(
            named: Key.expandedHeightAdjustment,
            displayKey: currentDisplayKey,
            in: defaults,
            fallback: Default.expandedHeightAdjustment
        )
        expandedTopControlsTopOffset = Self.double(
            named: Key.expandedTopControlsTopOffset,
            displayKey: currentDisplayKey,
            in: defaults,
            fallback: Default.expandedTopControlsTopOffset
        )
        leftControlsXOffset = Self.double(
            named: Key.leftControlsXOffset,
            displayKey: currentDisplayKey,
            in: defaults,
            fallback: Default.leftControlsXOffset
        )
        leftControlsYOffset = Self.double(
            named: Key.leftControlsYOffset,
            displayKey: currentDisplayKey,
            in: defaults,
            fallback: Default.leftControlsYOffset
        )
        rightControlsXOffset = Self.double(
            named: Key.rightControlsXOffset,
            displayKey: currentDisplayKey,
            in: defaults,
            fallback: Default.rightControlsXOffset
        )
        rightControlsYOffset = Self.double(
            named: Key.rightControlsYOffset,
            displayKey: currentDisplayKey,
            in: defaults,
            fallback: Default.rightControlsYOffset
        )
        expandedContentTopGap = Self.double(
            named: Key.expandedContentTopGap,
            displayKey: currentDisplayKey,
            in: defaults,
            fallback: Default.expandedContentTopGap
        )
    }

    func useDisplay(name: String, identity: String) {
        let nextDisplayKey = Self.safeDisplayKey(identity)
        let nextDisplayName = name.isEmpty ? "当前屏幕" : name
        guard nextDisplayKey != currentDisplayKey else {
            if currentDisplayName != nextDisplayName {
                currentDisplayName = nextDisplayName
            }
            return
        }

        currentDisplayName = nextDisplayName

        isLoading = true
        currentDisplayKey = nextDisplayKey
        islandYOffset = Self.double(
            named: Key.islandYOffset,
            displayKey: currentDisplayKey,
            in: defaults,
            fallback: Default.islandYOffset
        )
        notchHeightAdjustment = Self.double(
            named: Key.notchHeightAdjustment,
            displayKey: currentDisplayKey,
            in: defaults,
            fallback: Default.notchHeightAdjustment
        )
        expandedHeightAdjustment = Self.double(
            named: Key.expandedHeightAdjustment,
            displayKey: currentDisplayKey,
            in: defaults,
            fallback: Default.expandedHeightAdjustment
        )
        expandedTopControlsTopOffset = Self.double(
            named: Key.expandedTopControlsTopOffset,
            displayKey: currentDisplayKey,
            in: defaults,
            fallback: Default.expandedTopControlsTopOffset
        )
        leftControlsXOffset = Self.double(
            named: Key.leftControlsXOffset,
            displayKey: currentDisplayKey,
            in: defaults,
            fallback: Default.leftControlsXOffset
        )
        leftControlsYOffset = Self.double(
            named: Key.leftControlsYOffset,
            displayKey: currentDisplayKey,
            in: defaults,
            fallback: Default.leftControlsYOffset
        )
        rightControlsXOffset = Self.double(
            named: Key.rightControlsXOffset,
            displayKey: currentDisplayKey,
            in: defaults,
            fallback: Default.rightControlsXOffset
        )
        rightControlsYOffset = Self.double(
            named: Key.rightControlsYOffset,
            displayKey: currentDisplayKey,
            in: defaults,
            fallback: Default.rightControlsYOffset
        )
        expandedContentTopGap = Self.double(
            named: Key.expandedContentTopGap,
            displayKey: currentDisplayKey,
            in: defaults,
            fallback: Default.expandedContentTopGap
        )
        isLoading = false
    }

    func resetToDefaults() {
        islandYOffset = Default.islandYOffset
        notchHeightAdjustment = Default.notchHeightAdjustment
        expandedHeightAdjustment = Default.expandedHeightAdjustment
        expandedTopControlsTopOffset = Default.expandedTopControlsTopOffset
        leftControlsXOffset = Default.leftControlsXOffset
        leftControlsYOffset = Default.leftControlsYOffset
        rightControlsXOffset = Default.rightControlsXOffset
        rightControlsYOffset = Default.rightControlsYOffset
        expandedContentTopGap = Default.expandedContentTopGap
    }

    private func persist(_ name: String, _ value: Double) {
        guard !isLoading else { return }
        defaults.set(value, forKey: Self.storageKey(name, displayKey: currentDisplayKey))
    }

    private static func double(
        named name: String,
        displayKey: String,
        in defaults: UserDefaults,
        fallback: Double
    ) -> Double {
        let key = storageKey(name, displayKey: displayKey)
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.double(forKey: key)
    }

    private static func storageKey(_ name: String, displayKey: String) -> String {
        "\(Key.prefix)\(displayKey).\(name)"
    }

    private static func safeDisplayKey(_ identity: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = identity.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        return String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
}

struct LayoutCalibrationView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var settings: LayoutCalibrationSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                CalibrationSlider(
                    title: "灵动岛整体垂直",
                    value: $settings.islandYOffset,
                    range: -8...28,
                    helper: "正数向下；截图不显示物理刘海，以屏幕实物为准。"
                )

                CalibrationSlider(
                    title: "摄像头遮挡高度",
                    value: $settings.notchHeightAdjustment,
                    range: -2...8,
                    helper: "默认向下多覆盖 1 pt，让胶囊底部贴合物理摄像头模组并落在完整像素边界。"
                )

                CalibrationSlider(
                    title: "展开高度",
                    value: $settings.expandedHeightAdjustment,
                    range: -36...96,
                    helper: "只影响当前活动的展开内容。"
                )

                footer
            }
            .padding(20)
        }
        .frame(width: 440, height: 620)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("布局校准")
                .font(.system(size: 20, weight: .semibold))
            Text("\(settings.currentDisplayName)：刘海区域约 \(Int(model.notchWidth)) x \(Int(model.topBandHeight)) pt。调整会实时生效，并在重启后保留。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("恢复默认") {
                settings.resetToDefaults()
            }

            Spacer()

            Button("折叠") {
                model.mode = .compact
            }

            Button("展开预览") {
                model.isVisible = true
                model.mode = .expanded
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 4)
    }
}

private struct CalibrationSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let helper: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(value.rounded())) pt")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 54, alignment: .trailing)
            }

            HStack(spacing: 10) {
                Slider(value: $value, in: range, step: 1)
                Stepper("", value: $value, in: range, step: 1)
                    .labelsHidden()
            }

            Text(helper)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
