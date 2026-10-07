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

        static let persistedValueNames = [
            islandYOffset,
            notchHeightAdjustment,
            expandedHeightAdjustment,
            expandedTopControlsTopOffset,
            leftControlsXOffset,
            leftControlsYOffset,
            rightControlsXOffset,
            rightControlsYOffset,
            expandedContentTopGap
        ]
    }

    private enum Default {
        // Extend the top-level panel by half a point above the physical screen
        // edge so WindowServer does not leave a one-pixel menu-bar seam.
        static let islandYOffset = -0.5
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

    func useDisplay(
        name: String,
        identity: String,
        legacyIdentities: [String] = [],
        legacyIdentityPrefixes: [String] = []
    ) {
        let nextDisplayKey = Self.safeDisplayKey(identity)
        let nextDisplayName = name.isEmpty ? "当前屏幕" : name
        guard nextDisplayKey != currentDisplayKey else {
            if currentDisplayName != nextDisplayName {
                currentDisplayName = nextDisplayName
            }
            return
        }

        currentDisplayName = nextDisplayName
        migrateLegacyValuesIfNeeded(
            from: legacyIdentities,
            matching: legacyIdentityPrefixes,
            to: nextDisplayKey
        )

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

    private func migrateLegacyValuesIfNeeded(
        from legacyIdentities: [String],
        matching legacyIdentityPrefixes: [String],
        to displayKey: String
    ) {
        let legacyDisplayKeys = legacyIdentities
            .map(Self.safeDisplayKey)
            .filter { $0 != displayKey }
        let legacyStoragePrefixes = legacyIdentityPrefixes.map {
            "\(Key.prefix)\(Self.safeDisplayKey($0))"
        }
        guard !legacyDisplayKeys.isEmpty || !legacyStoragePrefixes.isEmpty else { return }
        let availableKeys = defaults.dictionaryRepresentation().keys.sorted()

        for valueName in Key.persistedValueNames {
            let destinationKey = Self.storageKey(valueName, displayKey: displayKey)
            guard defaults.object(forKey: destinationKey) == nil else { continue }
            let explicitSourceKeys = legacyDisplayKeys.map {
                Self.storageKey(valueName, displayKey: $0)
            }
            let matchingSourceKeys = availableKeys.filter { key in
                key.hasSuffix(".\(valueName)")
                    && legacyStoragePrefixes.contains(where: key.hasPrefix)
            }
            for sourceKey in explicitSourceKeys + matchingSourceKeys {
                guard let value = defaults.object(forKey: sourceKey) else { continue }
                defaults.set(value, forKey: destinationKey)
                break
            }
        }
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
    @State private var isShowingSketch = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                CalibrationSlider(
                    title: "顶屿整体垂直位置",
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

                Button {
                    isShowingSketch = true
                } label: {
                    Label("打开摄像头布局草图", systemImage: "pencil.and.ruler")
                }
                .buttonStyle(.borderedProminent)

                Text("草图画布会显示真实摄像头安全区、当前紧凑外框和展开外框。你可以直接用鼠标画出封面、曲名、控制键和歌词的大概分布，再把画布截图发回。草图不会修改当前布局。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                footer
            }
            .padding(20)
        }
        .frame(width: 440, height: 620)
        .sheet(isPresented: $isShowingSketch) {
            LayoutSketchEditor(model: model)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("布局校准")
                .font(.system(size: 20, weight: .semibold))
            Text(displayGeometrySummary)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var displayGeometrySummary: String {
        if model.hasCameraHousing {
            return "\(settings.currentDisplayName)：系统识别到约 \(Int(model.notchWidth)) x \(Int(model.topBandHeight)) pt 的摄像头区域。调整会实时生效，并在重启后保留。"
        }
        return "\(settings.currentDisplayName)：未检测到摄像头刘海，顶屿使用屏幕顶部居中胶囊布局。"
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

/// A reversible, screenshot-first layout board. It deliberately does not
/// write calibration values: the user can sketch the desired information
/// hierarchy over the real camera-safe reference and send the result back
/// before we change the product layout.
private struct LayoutSketchCanvas: View {
    @ObservedObject var model: IslandModel
    @Environment(\.dismiss) private var dismiss
    @State private var strokes: [[CGPoint]] = []
    @State private var activeStroke: [CGPoint] = []

    private let referenceScreenSize = CGSize(width: 1440, height: 900)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("摄像头布局草图")
                        .font(.system(size: 20, weight: .semibold))
                    Text("参考层不会修改顶屿；请在画布上标出你希望的封面、曲名、控制键和歌词区域。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            GeometryReader { proxy in
                let board = boardGeometry(for: proxy.size)
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        }

                    Canvas { context, size in
                        drawReference(in: &context, board: board)
                        drawStrokes(in: &context)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                activeStroke.append(value.location)
                            }
                            .onEnded { _ in
                                guard !activeStroke.isEmpty else { return }
                                strokes.append(activeStroke)
                                activeStroke.removeAll(keepingCapacity: true)
                            }
                    )
                }
            }

            HStack(spacing: 10) {
                Label("灰色：摄像头模组", systemImage: "camera.fill")
                Label("蓝色虚线：紧凑态", systemImage: "rectangle")
                Label("绿色虚线：展开态", systemImage: "rectangle.expand.vertical")
                Spacer()
                Button("清空手绘") {
                    strokes.removeAll()
                    activeStroke.removeAll()
                }
                .disabled(strokes.isEmpty && activeStroke.isEmpty)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 960, height: 700)
    }

    private func boardGeometry(for size: CGSize) -> SketchBoardGeometry {
        let scale = min(
            max((size.width - 44) / referenceScreenSize.width, 0.1),
            max((size.height - 44) / referenceScreenSize.height, 0.1)
        )
        let screenSize = CGSize(
            width: referenceScreenSize.width * scale,
            height: referenceScreenSize.height * scale
        )
        let screenOrigin = CGPoint(
            x: (size.width - screenSize.width) / 2,
            y: (size.height - screenSize.height) / 2
        )
        let screen = CGRect(origin: screenOrigin, size: screenSize)
        let centerX = screen.midX
        let camera = CGRect(
            x: centerX - model.notchWidth * scale / 2,
            y: screen.minY,
            width: model.notchWidth * scale,
            height: model.topBandHeight * scale
        )
        let compact = CGRect(
            x: centerX - model.compactWidth * scale / 2,
            y: screen.minY,
            width: model.compactWidth * scale,
            height: model.topBandHeight * scale
        )
        let expanded = CGRect(
            x: centerX - model.expandedWidth * scale / 2,
            y: screen.minY,
            width: model.expandedWidth * scale,
            height: model.expandedHeight * scale
        )
        return SketchBoardGeometry(screen: screen, camera: camera, compact: compact, expanded: expanded)
    }

    private func drawReference(in context: inout GraphicsContext, board: SketchBoardGeometry) {
        context.fill(
            Path(board.screen),
            with: .color(Color.black.opacity(0.08))
        )
        context.stroke(
            Path(board.screen),
            with: .color(Color.primary.opacity(0.16)),
            style: StrokeStyle(lineWidth: 1)
        )

        let gridStep: CGFloat = 80
        var x = board.screen.minX + gridStep
        while x < board.screen.maxX {
            var path = Path()
            path.move(to: CGPoint(x: x, y: board.screen.minY))
            path.addLine(to: CGPoint(x: x, y: board.screen.maxY))
            context.stroke(path, with: .color(Color.primary.opacity(0.045)), style: StrokeStyle(lineWidth: 1))
            x += gridStep
        }
        var y = board.screen.minY + gridStep
        while y < board.screen.maxY {
            var path = Path()
            path.move(to: CGPoint(x: board.screen.minX, y: y))
            path.addLine(to: CGPoint(x: board.screen.maxX, y: y))
            context.stroke(path, with: .color(Color.primary.opacity(0.045)), style: StrokeStyle(lineWidth: 1))
            y += gridStep
        }

        context.fill(
            Path(board.camera),
            with: .color(Color.black.opacity(0.30))
        )
        context.stroke(
            Path(board.camera),
            with: .color(Color.primary.opacity(0.38)),
            style: StrokeStyle(lineWidth: 1)
        )
        context.stroke(
            Path(board.compact),
            with: .color(Color.blue.opacity(0.70)),
            style: StrokeStyle(lineWidth: 2, dash: [7, 5])
        )
        context.stroke(
            Path(board.expanded),
            with: .color(Color.green.opacity(0.70)),
            style: StrokeStyle(lineWidth: 2, dash: [7, 5])
        )

        drawLabel("摄像头模组 (Int(model.notchWidth)) × (Int(model.topBandHeight)) pt", at: board.camera, in: &context, color: .secondary)
        drawLabel("紧凑态外框", at: board.compact, in: &context, color: .blue)
        drawLabel("展开态外框", at: board.expanded, in: &context, color: .green)
    }

    private func drawLabel(
        _ text: String,
        at rect: CGRect,
        in context: inout GraphicsContext,
        color: Color
    ) {
        context.draw(
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color),
            at: CGPoint(x: rect.minX + 6, y: rect.minY + 14),
            anchor: .topLeading
        )
    }

    private func drawStrokes(in context: inout GraphicsContext) {
        for stroke in strokes + (activeStroke.isEmpty ? [] : [activeStroke]) {
            guard stroke.count > 1 else { continue }
            var path = Path()
            path.move(to: stroke[0])
            path.addLines(Array(stroke.dropFirst()))
            context.stroke(
                path,
                with: .color(Color.orange.opacity(0.92)),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

private struct SketchBoardGeometry {
    let screen: CGRect
    let camera: CGRect
    let compact: CGRect
    let expanded: CGRect
}

private enum EditorComponent: String, CaseIterable, Identifiable {
    case artwork
    case metadata
    case controls
    case lyrics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .artwork: return "专辑封面"
        case .metadata: return "歌名 / 歌手"
        case .controls: return "播放控制"
        case .lyrics: return "歌词区域"
        }
    }

    var color: Color {
        switch self {
        case .artwork: return .orange
        case .metadata: return .purple
        case .controls: return .blue
        case .lyrics: return .green
        }
    }
}

private struct EditorFrame {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
}

private struct EditorBoardGeometry {
    let screen: CGRect
    let camera: CGRect
    let compact: CGRect
    let expanded: CGRect
    let scale: CGFloat
    let workOriginX: CGFloat
    let topInset: CGFloat
}

/// Lightweight layout editor for the user's information hierarchy sketch.
/// The reference layer is fixed; editing these boxes never changes live layout
/// calibration values.
private struct LayoutSketchEditor: View {
    @ObservedObject var model: IslandModel
    @Environment(\.dismiss) private var dismiss
    @State private var frames: [EditorComponent: EditorFrame]
    @State private var selectedComponent: EditorComponent = .artwork
    @State private var strokes: [[CGPoint]] = []
    @State private var activeStroke: [CGPoint] = []
    @State private var interactionOrigin: EditorFrame?
    @State private var isDrawing = false
    @State private var showGrid = true
    @State private var zoom: CGFloat = 1

    private let referenceScreenWidth: CGFloat = 1440
    private let workTopInset: CGFloat = 60

    init(model: IslandModel) {
        self.model = model
        _frames = State(initialValue: Self.initialFrames(for: model))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("摄像头布局草图")
                        .font(.system(size: 20, weight: .semibold))
                    Text("先在右侧锁定部件，再在中央拖动或调整尺寸。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 14) {
                GeometryReader { proxy in
                    let board = boardGeometry(for: proxy.size)
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(nsColor: .windowBackgroundColor))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.primary.opacity(0.14), lineWidth: 1)
                            }

                        Canvas { context, _ in
                            drawReference(in: &context, board: board)
                            drawComponentFrames(in: &context, board: board)
                            drawStrokes(in: &context)
                        }

                        if !isDrawing {
                            let selectedRect = canvasRect(
                                for: frames[selectedComponent] ?? defaultFrame,
                                board: board
                            )
                            Rectangle()
                                .fill(.clear)
                                .frame(width: max(selectedRect.width, 20), height: max(selectedRect.height, 20))
                                .position(x: selectedRect.midX, y: selectedRect.midY)
                                .contentShape(Rectangle())
                                .gesture(moveGesture(for: selectedComponent, board: board))
                            Circle()
                                .fill(selectedComponent.color)
                                .frame(width: 13, height: 13)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                                .position(x: selectedRect.maxX, y: selectedRect.maxY)
                                .gesture(resizeGesture(for: selectedComponent, board: board))
                        } else {
                            Color.clear
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in activeStroke.append(value.location) }
                                        .onEnded { _ in
                                            guard !activeStroke.isEmpty else { return }
                                            strokes.append(activeStroke)
                                            activeStroke.removeAll(keepingCapacity: true)
                                        }
                                )
                        }
                    }
                    .clipped()
                }

                propertyPanel
                    .frame(width: 248)
            }
            .frame(minHeight: 560)

            toolbar
        }
        .padding(18)
        .frame(width: 1_280, height: 830)
    }

    private var propertyPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("锁定要编辑的部件")
                .font(.system(size: 13, weight: .semibold))

            ForEach(EditorComponent.allCases) { component in
                Button {
                    selectedComponent = component
                    isDrawing = false
                } label: {
                    HStack(spacing: 8) {
                        Circle().fill(component.color).frame(width: 8, height: 8)
                        Text(component.title)
                        Spacer()
                        if selectedComponent == component {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }

            Divider()

            Text("位置与尺寸")
                .font(.system(size: 13, weight: .semibold))
            HStack(spacing: 6) {
                numericField("X", keyPath: \.x)
                numericField("Y", keyPath: \.y)
            }
            HStack(spacing: 6) {
                numericField("宽", keyPath: \.width)
                numericField("高", keyPath: \.height)
            }
            Text("单位：pt。拖动框体移动，右下角圆点调整宽高。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
            Text("灰色：摄像头 · 蓝色：紧凑外框 · 绿色：展开外框")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Toggle("显示网格", isOn: $showGrid)
                .font(.system(size: 12))
            Toggle("手绘标注模式", isOn: $isDrawing)
                .font(.system(size: 12))
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button { zoom = max(0.75, zoom - 0.1) } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            Slider(value: $zoom, in: 0.75...1.35, step: 0.05)
                .frame(width: 150)
            Button { zoom = min(1.35, zoom + 0.1) } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            Text("\(Int(zoom * 100))%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Button("清空手绘") {
                strokes.removeAll()
                activeStroke.removeAll()
            }
            .disabled(strokes.isEmpty && activeStroke.isEmpty)
            Button("恢复部件初始位置") {
                frames = Self.initialFrames(for: model)
            }
        }
        .font(.system(size: 12))
    }

    private func numericField(
        _ title: String,
        keyPath: WritableKeyPath<EditorFrame, CGFloat>
    ) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("", text: numericBinding(keyPath: keyPath))
                .textFieldStyle(.roundedBorder)
                .frame(width: 82)
        }
    }

    private func numericBinding(
        keyPath: WritableKeyPath<EditorFrame, CGFloat>
    ) -> Binding<String> {
        Binding(
            get: {
                let frame = frames[selectedComponent] ?? defaultFrame
                return String(Int(frame[keyPath: keyPath].rounded()))
            },
            set: { value in
                guard let number = Double(value) else { return }
                var frame = frames[selectedComponent] ?? defaultFrame
                frame[keyPath: keyPath] = max(0, CGFloat(number))
                frames[selectedComponent] = frame
            }
        )
    }

    private func boardGeometry(for size: CGSize) -> EditorBoardGeometry {
        // Fit the island work area, not an entire 1440 × 900 desktop. The
        // physical camera housing and the two island outlines remain in the
        // same coordinate system, but fill the useful editor space.
        let workWidth = max(model.expandedWidth, model.compactWidth) + 180
        let workHeight = max(model.expandedHeight + 120, 300)
        let baseScale = min(
            (size.width - 32) / workWidth,
            (size.height - 32) / workHeight
        )
        let scale = baseScale * zoom
        let workOriginX = (referenceScreenWidth - workWidth) / 2
        let screenSize = CGSize(width: workWidth * scale, height: workHeight * scale)
        let screen = CGRect(
            x: (size.width - screenSize.width) / 2,
            y: (size.height - screenSize.height) / 2,
            width: screenSize.width,
            height: screenSize.height
        )
        let centerX = screen.minX + (referenceScreenWidth / 2 - workOriginX) * scale
        let camera = CGRect(
            x: centerX - model.notchWidth * scale / 2,
            y: screen.minY + workTopInset * scale,
            width: model.notchWidth * scale,
            height: model.topBandHeight * scale
        )
        let compact = CGRect(
            x: centerX - model.compactWidth * scale / 2,
            y: screen.minY + workTopInset * scale,
            width: model.compactWidth * scale,
            height: model.topBandHeight * scale
        )
        let expanded = CGRect(
            x: centerX - model.expandedWidth * scale / 2,
            y: screen.minY + workTopInset * scale,
            width: model.expandedWidth * scale,
            height: model.expandedHeight * scale
        )
        return EditorBoardGeometry(screen: screen, camera: camera, compact: compact, expanded: expanded, scale: scale, workOriginX: workOriginX, topInset: workTopInset)
    }

    private func canvasRect(for frame: EditorFrame, board: EditorBoardGeometry) -> CGRect {
        CGRect(
            x: board.screen.minX + (frame.x - board.workOriginX) * board.scale,
            y: board.screen.minY + (board.topInset + frame.y) * board.scale,
            width: frame.width * board.scale,
            height: frame.height * board.scale
        )
    }

    private func drawReference(in context: inout GraphicsContext, board: EditorBoardGeometry) {
        context.fill(Path(board.screen), with: .color(Color.black.opacity(0.08)))
        context.stroke(Path(board.screen), with: .color(Color.primary.opacity(0.16)), style: StrokeStyle(lineWidth: 1))
        if showGrid {
            let gridStep = 80 * board.scale
            var x = board.screen.minX + gridStep
            while x < board.screen.maxX {
                var path = Path()
                path.move(to: CGPoint(x: x, y: board.screen.minY))
                path.addLine(to: CGPoint(x: x, y: board.screen.maxY))
                context.stroke(path, with: .color(Color.primary.opacity(0.045)), style: StrokeStyle(lineWidth: 1))
                x += gridStep
            }
            var y = board.screen.minY + gridStep
            while y < board.screen.maxY {
                var path = Path()
                path.move(to: CGPoint(x: board.screen.minX, y: y))
                path.addLine(to: CGPoint(x: board.screen.maxX, y: y))
                context.stroke(path, with: .color(Color.primary.opacity(0.045)), style: StrokeStyle(lineWidth: 1))
                y += gridStep
            }
        }
        context.fill(Path(board.camera), with: .color(Color.black.opacity(0.30)))
        context.stroke(Path(board.camera), with: .color(Color.primary.opacity(0.38)), style: StrokeStyle(lineWidth: 1))
        context.stroke(Path(board.compact), with: .color(Color.blue.opacity(0.70)), style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
        context.stroke(Path(board.expanded), with: .color(Color.green.opacity(0.70)), style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
    }

    private func drawComponentFrames(in context: inout GraphicsContext, board: EditorBoardGeometry) {
        for component in EditorComponent.allCases {
            let rect = canvasRect(for: frames[component] ?? defaultFrame, board: board)
            let selected = component == selectedComponent
            context.fill(Path(roundedRect: rect, cornerRadius: 8), with: .color(component.color.opacity(selected ? 0.16 : 0.08)))
            context.stroke(
                Path(roundedRect: rect, cornerRadius: 8),
                with: .color(component.color.opacity(selected ? 0.95 : 0.62)),
                style: StrokeStyle(lineWidth: selected ? 2 : 1.5, dash: selected ? [] : [5, 4])
            )
            drawLabel(component.title, at: rect, in: &context, color: component.color)
        }
    }

    private func drawLabel(_ text: String, at rect: CGRect, in context: inout GraphicsContext, color: Color) {
        context.draw(
            Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(color),
            at: CGPoint(x: rect.minX + 6, y: rect.minY + 5),
            anchor: .topLeading
        )
    }

    private func drawStrokes(in context: inout GraphicsContext) {
        for stroke in strokes + (activeStroke.isEmpty ? [] : [activeStroke]) {
            guard stroke.count > 1 else { continue }
            var path = Path()
            path.move(to: stroke[0])
            path.addLines(Array(stroke.dropFirst()))
            context.stroke(path, with: .color(Color.orange.opacity(0.92)), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
    }

    private func moveGesture(for component: EditorComponent, board: EditorBoardGeometry) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if interactionOrigin == nil { interactionOrigin = frames[component] ?? defaultFrame }
                guard var frame = interactionOrigin else { return }
                frame.x += value.translation.width / board.scale
                frame.y += value.translation.height / board.scale
                frames[component] = frame
                selectedComponent = component
            }
            .onEnded { _ in interactionOrigin = nil }
    }

    private func resizeGesture(for component: EditorComponent, board: EditorBoardGeometry) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if interactionOrigin == nil { interactionOrigin = frames[component] ?? defaultFrame }
                guard var frame = interactionOrigin else { return }
                frame.width = max(24, frame.width + value.translation.width / board.scale)
                frame.height = max(24, frame.height + value.translation.height / board.scale)
                frames[component] = frame
                selectedComponent = component
            }
            .onEnded { _ in interactionOrigin = nil }
    }

    private var defaultFrame: EditorFrame {
        EditorFrame(x: 0, y: 0, width: 120, height: 60)
    }

    private static func initialFrames(for model: IslandModel) -> [EditorComponent: EditorFrame] {
        let expandedX = (1440 - model.expandedWidth) / 2
        let contentY = model.topBandHeight
        return [
            .artwork: EditorFrame(x: expandedX + 16, y: contentY + 5, width: 76, height: 76),
            .metadata: EditorFrame(x: expandedX + 102, y: contentY - 11, width: 118, height: 54),
            .controls: EditorFrame(x: expandedX + 102, y: contentY + 55, width: 118, height: 42),
            .lyrics: EditorFrame(
                x: expandedX + 232,
                y: contentY + 8,
                width: max(220, model.expandedWidth - 248),
                height: max(80, model.expandedBodyHeight - contentY - 16)
            )
        ]
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
