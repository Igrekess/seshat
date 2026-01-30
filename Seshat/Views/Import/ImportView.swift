import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(AppState.self) private var appState
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 0) {
            if let copy = appState.currentCopy {
                ImportedImageView(copy: copy)
            } else {
                DropZoneView(isDragging: $isDragging)
            }
        }
        .onDrop(of: [.image, .pdf, .fileURL], isTargeted: $isDragging) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                    if let data = data {
                        DispatchQueue.main.async {
                            appState.importImage(data, filename: "imported_image.png")
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        DispatchQueue.main.async {
                            handleFileURL(url)
                        }
                    }
                }
            }
        }
    }

    private func handleFileURL(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            appState.importImage(data, filename: url.lastPathComponent)
        } catch {
            // Handle error
        }
    }
}

// MARK: - Drop Zone View
struct DropZoneView: View {
    @Binding var isDragging: Bool
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 64))
                .foregroundColor(isDragging ? .accentColor : .secondary)

            Text("Glissez une copie ici")
                .font(.title2)
                .fontWeight(.medium)

            Text("ou")
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                Button(action: openFilePicker) {
                    Label("Ouvrir un fichier", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                Button(action: openContinuityCamera) {
                    Label("Scanner avec iPhone", systemImage: "camera")
                }
                .buttonStyle(.bordered)
            }

            Text("Formats supportés: JPEG, PNG, HEIC, PDF")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isDragging ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
                .background(isDragging ? Color.accentColor.opacity(0.05) : Color.clear)
        )
        .padding(32)
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .pdf]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                appState.importImage(data, filename: url.lastPathComponent)
            } catch {
                // Handle error
            }
        }
    }

    private func openContinuityCamera() {
        // Continuity Camera would be triggered via NSMenuItemValidation
    }
}

// MARK: - Imported Image View
struct ImportedImageView: View {
    let copy: StudentCopy
    @Environment(AppState.self) private var appState
    @State private var zoomScale: CGFloat = 1.0
    @State private var isCropMode = false
    @State private var containerSize: CGSize = .zero

    /// Calculate actual displayed image size (accounting for aspect ratio fit)
    private func displayedImageSize(in containerSize: CGSize) -> CGSize {
        guard let imageSize = copy.imageSize, containerSize.width > 0, containerSize.height > 0 else {
            return containerSize
        }

        // Account for image rotation
        let effectiveSize: CGSize
        if appState.imageRotation == 90 || appState.imageRotation == 270 {
            effectiveSize = CGSize(width: imageSize.height, height: imageSize.width)
        } else {
            effectiveSize = imageSize
        }

        let imageAspect = effectiveSize.width / effectiveSize.height
        let containerAspect = containerSize.width / containerSize.height

        if imageAspect > containerAspect {
            // Image is wider than container - fit to width
            let width = containerSize.width
            let height = width / imageAspect
            return CGSize(width: width, height: height)
        } else {
            // Image is taller than container - fit to height
            let height = containerSize.height
            let width = height * imageAspect
            return CGSize(width: width, height: height)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main Toolbar
            HStack {
                Text(copy.originalFilename)
                    .font(.headline)

                Spacer()

                HStack(spacing: 8) {
                    // Rotation buttons (90° increments)
                    Button(action: { appState.rotateImageLeft() }) {
                        Image(systemName: "rotate.left")
                    }
                    .buttonStyle(.borderless)
                    .help("Rotation gauche 90° (⌘←)")
                    .keyboardShortcut(.leftArrow, modifiers: .command)

                    Button(action: { appState.rotateImageRight() }) {
                        Image(systemName: "rotate.right")
                    }
                    .buttonStyle(.borderless)
                    .help("Rotation droite 90° (⌘→)")
                    .keyboardShortcut(.rightArrow, modifiers: .command)

                    if appState.imageRotation != 0 {
                        Text("\(appState.imageRotation)°")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 35)
                    }

                    Divider().frame(height: 20)

                    // Crop mode toggle
                    Toggle(isOn: $isCropMode) {
                        Label("Recadrer", systemImage: "crop")
                    }
                    .toggleStyle(.button)
                    .tint(isCropMode ? .accentColor : nil)
                    .help("Mode recadrage (C)")

                    if appState.cropRegion != nil {
                        Button(action: {
                            appState.cropRegion = nil
                            appState.cropRotation = 0
                        }) {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.orange)
                        .help("Supprimer le recadrage")
                    }

                    Divider().frame(height: 20)

                    // Zoom controls
                    Button(action: { zoomScale = max(0.25, zoomScale - 0.25) }) {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("-", modifiers: .command)

                    Text("\(Int(zoomScale * 100))%")
                        .monospacedDigit()
                        .frame(width: 45)

                    Button(action: { zoomScale = min(4.0, zoomScale + 0.25) }) {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("=", modifiers: .command)

                    Button(action: { zoomScale = 1.0 }) {
                        Text("1:1")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Divider().frame(height: 20)

                    Button("Transcrire", systemImage: "text.viewfinder") {
                        Task {
                            await appState.startTranscription()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(.bar)

            Divider()

            // Main content
            HSplitView {
                // Image View with crop overlay
                GeometryReader { geometry in
                    let imgSize = displayedImageSize(in: geometry.size)

                    ScrollView([.horizontal, .vertical]) {
                        ZStack {
                            if let nsImage = copy.nsImage {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .rotationEffect(.degrees(Double(appState.imageRotation)))
                                    .frame(
                                        width: imgSize.width * zoomScale,
                                        height: imgSize.height * zoomScale
                                    )

                                // Crop overlay
                                if isCropMode || appState.cropRegion != nil {
                                    RotatableCropOverlay(
                                        cropRect: Binding(
                                            get: { appState.cropRegion ?? CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8) },
                                            set: { appState.cropRegion = $0 }
                                        ),
                                        cropRotation: Binding(
                                            get: { appState.cropRotation },
                                            set: { appState.cropRotation = $0 }
                                        ),
                                        displaySize: CGSize(
                                            width: imgSize.width * zoomScale,
                                            height: imgSize.height * zoomScale
                                        ),
                                        isActive: isCropMode,
                                        onActivate: {
                                            if appState.cropRegion == nil {
                                                appState.cropRegion = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
                                            }
                                        }
                                    )
                                }
                            }
                        }
                        .frame(
                            minWidth: max(geometry.size.width, imgSize.width * zoomScale),
                            minHeight: max(geometry.size.height, imgSize.height * zoomScale)
                        )
                    }
                    .background(Color(nsColor: .controlBackgroundColor))
                    .onAppear { containerSize = geometry.size }
                    .onChange(of: geometry.size) { _, newSize in containerSize = newSize }
                }

                // Crop control panel (when in crop mode)
                if isCropMode {
                    CropControlPanel(
                        cropRect: Binding(
                            get: { appState.cropRegion ?? CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8) },
                            set: { appState.cropRegion = $0 }
                        ),
                        cropRotation: Binding(
                            get: { appState.cropRotation },
                            set: { appState.cropRotation = $0 }
                        ),
                        imageRotation: Binding(
                            get: { appState.imageRotation },
                            set: { appState.imageRotation = $0 }
                        ),
                        onDone: { isCropMode = false }
                    )
                    .frame(width: 240)
                }
            }

            // Status bar
            HStack {
                if let crop = appState.cropRegion {
                    Image(systemName: "crop")
                        .foregroundColor(.accentColor)
                    Text("Zone: \(Int(crop.width * 100))% × \(Int(crop.height * 100))%")
                        .font(.caption)
                        .foregroundColor(.accentColor)

                    if abs(appState.cropRotation) > 0.1 {
                        Text("• Rotation: \(String(format: "%.1f", appState.cropRotation))°")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                } else if isCropMode {
                    Image(systemName: "hand.draw")
                        .foregroundColor(.secondary)
                    Text("Ajustez la zone avec les poignées • Utilisez les coins extérieurs pour pivoter")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let size = copy.imageSize {
                    Text("\(Int(size.width)) × \(Int(size.height)) px")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(.bar)
        }
        .onKeyPress("c") {
            isCropMode.toggle()
            return .handled
        }
    }
}

// MARK: - Rotatable Crop Overlay
struct RotatableCropOverlay: View {
    @Binding var cropRect: CGRect
    @Binding var cropRotation: Double
    let displaySize: CGSize
    let isActive: Bool
    let onActivate: () -> Void

    @State private var activeHandle: CropHandle?
    @State private var initialRect: CGRect = .zero
    @State private var initialRotation: Double = 0
    @State private var initialAngle: Double = 0
    @State private var dragStartLocation: CGPoint = .zero

    private let handleSize: CGFloat = 16
    private let handleHitArea: CGFloat = 40
    private let rotationHandleOffset: CGFloat = 30
    private let minCropSize: CGFloat = 0.05

    enum CropHandle: Equatable {
        case topLeft, top, topRight
        case left, center, right
        case bottomLeft, bottom, bottomRight
        case rotate  // Single rotation handle at top center
    }

    private var cropCenter: CGPoint {
        CGPoint(
            x: (cropRect.minX + cropRect.width / 2) * displaySize.width,
            y: (cropRect.minY + cropRect.height / 2) * displaySize.height
        )
    }

    var body: some View {
        let displayRect = CGRect(
            x: cropRect.origin.x * displaySize.width,
            y: cropRect.origin.y * displaySize.height,
            width: cropRect.width * displaySize.width,
            height: cropRect.height * displaySize.height
        )

        ZStack {
            // Dimmed overlay outside crop area (with rotation)
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.5)))
                context.blendMode = .destinationOut

                // Create rotated rect path
                var path = Path()
                path.addRect(CGRect(origin: .zero, size: CGSize(width: displayRect.width, height: displayRect.height)))

                let transform = CGAffineTransform(translationX: displayRect.midX, y: displayRect.midY)
                    .rotated(by: cropRotation * .pi / 180)
                    .translatedBy(x: -displayRect.width / 2, y: -displayRect.height / 2)

                context.fill(path.applying(transform), with: .color(.white))
            }
            .allowsHitTesting(false)

            // Rotated crop frame group
            Group {
                // Main crop rectangle
                ZStack {
                    // White border
                    Rectangle()
                        .strokeBorder(Color.white, lineWidth: 2)
                        .shadow(color: .black.opacity(0.5), radius: 2)

                    // Rule of thirds grid
                    GridOverlay()
                        .stroke(Color.white.opacity(0.4), lineWidth: 1)

                    // Resize handles (corners)
                    ForEach([CropHandle.topLeft, .topRight, .bottomLeft, .bottomRight], id: \.self) { handle in
                        resizeHandle(handle, rectSize: displayRect.size)
                    }

                    // Resize handles (edges)
                    ForEach([CropHandle.top, .bottom, .left, .right], id: \.self) { handle in
                        edgeHandle(handle, rectSize: displayRect.size)
                    }
                }
                .frame(width: displayRect.width, height: displayRect.height)
                .gesture(moveGesture())

                // Single rotation handle at top center
                rotationHandle(rectSize: displayRect.size)
            }
            .rotationEffect(.degrees(cropRotation))
            .position(x: displayRect.midX, y: displayRect.midY)
        }
        .frame(width: displaySize.width, height: displaySize.height)
        .contentShape(Rectangle())
        .onTapGesture {
            onActivate()
        }
    }

    // MARK: - Handle Views

    private func resizeHandle(_ handle: CropHandle, rectSize: CGSize) -> some View {
        let position = handlePosition(handle, in: rectSize)

        return ZStack {
            Circle()
                .fill(Color.clear)
                .frame(width: handleHitArea, height: handleHitArea)

            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white)
                .frame(width: handleSize, height: handleSize)
                .shadow(color: .black.opacity(0.3), radius: 2)
        }
        .position(position)
        .gesture(resizeGesture(handle))
        .onHover { hovering in
            if hovering {
                NSCursor.crosshair.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private func edgeHandle(_ handle: CropHandle, rectSize: CGSize) -> some View {
        let position = handlePosition(handle, in: rectSize)
        let isVertical = handle == .left || handle == .right

        return ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(
                    width: isVertical ? handleHitArea : handleHitArea * 1.5,
                    height: isVertical ? handleHitArea * 1.5 : handleHitArea
                )

            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white)
                .frame(
                    width: isVertical ? 6 : 28,
                    height: isVertical ? 28 : 6
                )
                .shadow(color: .black.opacity(0.3), radius: 2)
        }
        .position(position)
        .gesture(resizeGesture(handle))
        .onHover { hovering in
            if hovering {
                if isVertical {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.resizeUpDown.push()
                }
            } else {
                NSCursor.pop()
            }
        }
    }

    private func rotationHandle(rectSize: CGSize) -> some View {
        let handleY: CGFloat = -rotationHandleOffset - 10

        return ZStack {
            // Connection line from frame to handle
            Path { path in
                path.move(to: CGPoint(x: rectSize.width / 2, y: 0))
                path.addLine(to: CGPoint(x: rectSize.width / 2, y: handleY + 12))
            }
            .stroke(Color.white, lineWidth: 2)

            // Handle circle with rotation icon
            ZStack {
                Circle()
                    .fill(Color.clear)
                    .frame(width: handleHitArea, height: handleHitArea)

                Circle()
                    .fill(Color.white)
                    .frame(width: 28, height: 28)
                    .shadow(color: .black.opacity(0.4), radius: 3)

                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.orange)
            }
            .position(x: rectSize.width / 2, y: handleY)
            .gesture(singleRotationGesture(rectSize: rectSize))
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
    }

    // MARK: - Position Calculations

    private func handlePosition(_ handle: CropHandle, in size: CGSize) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: 0, y: 0)
        case .top: return CGPoint(x: size.width / 2, y: 0)
        case .topRight: return CGPoint(x: size.width, y: 0)
        case .left: return CGPoint(x: 0, y: size.height / 2)
        case .center: return CGPoint(x: size.width / 2, y: size.height / 2)
        case .right: return CGPoint(x: size.width, y: size.height / 2)
        case .bottomLeft: return CGPoint(x: 0, y: size.height)
        case .bottom: return CGPoint(x: size.width / 2, y: size.height)
        case .bottomRight: return CGPoint(x: size.width, y: size.height)
        default: return .zero
        }
    }


    // MARK: - Gestures

    private func moveGesture() -> some Gesture {
        DragGesture()
            .onChanged { value in
                if activeHandle == nil {
                    activeHandle = .center
                    initialRect = cropRect
                    dragStartLocation = value.startLocation
                }

                guard activeHandle == .center else { return }

                let deltaX = (value.location.x - dragStartLocation.x) / displaySize.width
                let deltaY = (value.location.y - dragStartLocation.y) / displaySize.height

                var newRect = initialRect
                newRect.origin.x = max(0, min(1 - initialRect.width, initialRect.origin.x + deltaX))
                newRect.origin.y = max(0, min(1 - initialRect.height, initialRect.origin.y + deltaY))

                cropRect = newRect
            }
            .onEnded { _ in
                activeHandle = nil
            }
    }

    private func resizeGesture(_ handle: CropHandle) -> some Gesture {
        DragGesture()
            .onChanged { value in
                handleResizeDrag(handle: handle, value: value)
            }
            .onEnded { _ in
                activeHandle = nil
            }
    }

    private func handleResizeDrag(handle: CropHandle, value: DragGesture.Value) {
        if activeHandle == nil {
            activeHandle = handle
            initialRect = cropRect
            dragStartLocation = value.startLocation
        }

        guard activeHandle == handle else { return }

        // Account for rotation when calculating delta
        let rotRad: CGFloat = -cropRotation * .pi / 180
        let rawDeltaX: CGFloat = value.location.x - dragStartLocation.x
        let rawDeltaY: CGFloat = value.location.y - dragStartLocation.y
        let cosRot: CGFloat = cos(rotRad)
        let sinRot: CGFloat = sin(rotRad)
        let deltaX: CGFloat = (rawDeltaX * cosRot - rawDeltaY * sinRot) / displaySize.width
        let deltaY: CGFloat = (rawDeltaX * sinRot + rawDeltaY * cosRot) / displaySize.height

        let newRect = computeResizedRect(handle: handle, deltaX: deltaX, deltaY: deltaY)
        cropRect = newRect
    }

    private func computeResizedRect(handle: CropHandle, deltaX: CGFloat, deltaY: CGFloat) -> CGRect {
        switch handle {
        case .topLeft:
            let newX = min(initialRect.maxX - minCropSize, max(0, initialRect.minX + deltaX))
            let newY = min(initialRect.maxY - minCropSize, max(0, initialRect.minY + deltaY))
            return CGRect(x: newX, y: newY, width: initialRect.maxX - newX, height: initialRect.maxY - newY)

        case .top:
            let newY = min(initialRect.maxY - minCropSize, max(0, initialRect.minY + deltaY))
            return CGRect(x: initialRect.minX, y: newY, width: initialRect.width, height: initialRect.maxY - newY)

        case .topRight:
            let newY = min(initialRect.maxY - minCropSize, max(0, initialRect.minY + deltaY))
            let newWidth = max(minCropSize, min(1 - initialRect.minX, initialRect.width + deltaX))
            return CGRect(x: initialRect.minX, y: newY, width: newWidth, height: initialRect.maxY - newY)

        case .left:
            let newX = min(initialRect.maxX - minCropSize, max(0, initialRect.minX + deltaX))
            return CGRect(x: newX, y: initialRect.minY, width: initialRect.maxX - newX, height: initialRect.height)

        case .right:
            let newWidth = max(minCropSize, min(1 - initialRect.minX, initialRect.width + deltaX))
            return CGRect(x: initialRect.minX, y: initialRect.minY, width: newWidth, height: initialRect.height)

        case .bottomLeft:
            let newX = min(initialRect.maxX - minCropSize, max(0, initialRect.minX + deltaX))
            let newHeight = max(minCropSize, min(1 - initialRect.minY, initialRect.height + deltaY))
            return CGRect(x: newX, y: initialRect.minY, width: initialRect.maxX - newX, height: newHeight)

        case .bottom:
            let newHeight = max(minCropSize, min(1 - initialRect.minY, initialRect.height + deltaY))
            return CGRect(x: initialRect.minX, y: initialRect.minY, width: initialRect.width, height: newHeight)

        case .bottomRight:
            let newWidth = max(minCropSize, min(1 - initialRect.minX, initialRect.width + deltaX))
            let newHeight = max(minCropSize, min(1 - initialRect.minY, initialRect.height + deltaY))
            return CGRect(x: initialRect.minX, y: initialRect.minY, width: newWidth, height: newHeight)

        default:
            return initialRect
        }
    }

    private func singleRotationGesture(rectSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if activeHandle == nil {
                    activeHandle = .rotate
                    initialRotation = cropRotation
                    dragStartLocation = value.startLocation
                }

                guard activeHandle == .rotate else { return }

                // Horizontal drag controls rotation
                // Moving right = clockwise, moving left = counter-clockwise
                let deltaX: CGFloat = value.location.x - dragStartLocation.x

                // Sensitivity: 200 pixels = 45 degrees
                let rotationDelta: CGFloat = deltaX * 45.0 / 200.0

                // Clamp rotation to ±45°
                let newRotation = max(-45, min(45, initialRotation + rotationDelta))
                cropRotation = newRotation
            }
            .onEnded { _ in
                activeHandle = nil
            }
    }
}

// MARK: - Grid Overlay
struct GridOverlay: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Vertical lines (rule of thirds)
        path.move(to: CGPoint(x: rect.width / 3, y: 0))
        path.addLine(to: CGPoint(x: rect.width / 3, y: rect.height))
        path.move(to: CGPoint(x: rect.width * 2 / 3, y: 0))
        path.addLine(to: CGPoint(x: rect.width * 2 / 3, y: rect.height))

        // Horizontal lines
        path.move(to: CGPoint(x: 0, y: rect.height / 3))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height / 3))
        path.move(to: CGPoint(x: 0, y: rect.height * 2 / 3))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height * 2 / 3))

        return path
    }
}

// MARK: - Crop Control Panel
struct CropControlPanel: View {
    @Binding var cropRect: CGRect
    @Binding var cropRotation: Double
    @Binding var imageRotation: Int
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Recadrage")
                    .font(.headline)
                Spacer()
                Button("Terminé") {
                    onDone()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()
            .background(.bar)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Crop rotation section (for straightening text)
                    GroupBox("Redresser le texte") {
                        VStack(spacing: 12) {
                            HStack {
                                Text("\(String(format: "%.1f", cropRotation))°")
                                    .font(.title3)
                                    .monospacedDigit()
                                    .frame(width: 60)

                                Slider(value: $cropRotation, in: -45...45, step: 0.1)

                                Button(action: { cropRotation = 0 }) {
                                    Image(systemName: "arrow.counterclockwise")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(abs(cropRotation) < 0.1)
                            }

                            // Fine adjustment buttons
                            HStack(spacing: 8) {
                                Button("-1°") { cropRotation = max(-45, cropRotation - 1) }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                Button("-0.1°") { cropRotation = max(-45, cropRotation - 0.1) }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                Spacer()

                                Button("+0.1°") { cropRotation = min(45, cropRotation + 0.1) }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                Button("+1°") { cropRotation = min(45, cropRotation + 1) }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // Image rotation section (90° increments)
                    GroupBox("Rotation image") {
                        VStack(spacing: 12) {
                            HStack {
                                Button(action: { imageRotation = (imageRotation - 90 + 360) % 360 }) {
                                    Image(systemName: "rotate.left")
                                        .frame(width: 32, height: 32)
                                }
                                .buttonStyle(.bordered)

                                Spacer()

                                Text("\(imageRotation)°")
                                    .font(.title2)
                                    .monospacedDigit()
                                    .frame(width: 60)

                                Spacer()

                                Button(action: { imageRotation = (imageRotation + 90) % 360 }) {
                                    Image(systemName: "rotate.right")
                                        .frame(width: 32, height: 32)
                                }
                                .buttonStyle(.bordered)
                            }

                            // Quick rotation buttons
                            HStack(spacing: 8) {
                                ForEach([0, 90, 180, 270], id: \.self) { angle in
                                    Button("\(angle)°") {
                                        imageRotation = angle
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(imageRotation == angle ? .accentColor : nil)
                                    .controlSize(.small)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // Position section
                    GroupBox("Position") {
                        VStack(spacing: 8) {
                            HStack {
                                Text("X:")
                                    .frame(width: 20)
                                Slider(value: Binding(
                                    get: { cropRect.origin.x },
                                    set: { newX in
                                        cropRect.origin.x = min(max(0, newX), 1 - cropRect.width)
                                    }
                                ), in: 0...max(0.01, 1 - cropRect.width))
                                Text("\(Int(cropRect.origin.x * 100))%")
                                    .monospacedDigit()
                                    .frame(width: 40)
                            }

                            HStack {
                                Text("Y:")
                                    .frame(width: 20)
                                Slider(value: Binding(
                                    get: { cropRect.origin.y },
                                    set: { newY in
                                        cropRect.origin.y = min(max(0, newY), 1 - cropRect.height)
                                    }
                                ), in: 0...max(0.01, 1 - cropRect.height))
                                Text("\(Int(cropRect.origin.y * 100))%")
                                    .monospacedDigit()
                                    .frame(width: 40)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // Size section
                    GroupBox("Taille") {
                        VStack(spacing: 8) {
                            HStack {
                                Text("L:")
                                    .frame(width: 20)
                                Slider(value: Binding(
                                    get: { cropRect.width },
                                    set: { newW in
                                        cropRect.size.width = min(max(0.05, newW), 1 - cropRect.origin.x)
                                    }
                                ), in: 0.05...max(0.06, 1 - cropRect.origin.x))
                                Text("\(Int(cropRect.width * 100))%")
                                    .monospacedDigit()
                                    .frame(width: 40)
                            }

                            HStack {
                                Text("H:")
                                    .frame(width: 20)
                                Slider(value: Binding(
                                    get: { cropRect.height },
                                    set: { newH in
                                        cropRect.size.height = min(max(0.05, newH), 1 - cropRect.origin.y)
                                    }
                                ), in: 0.05...max(0.06, 1 - cropRect.origin.y))
                                Text("\(Int(cropRect.height * 100))%")
                                    .monospacedDigit()
                                    .frame(width: 40)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // Presets
                    GroupBox("Préréglages") {
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                Button("Pleine page") {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button("Centre 80%") {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        cropRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            HStack(spacing: 8) {
                                Button("Moitié haute") {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        cropRect = CGRect(x: 0, y: 0, width: 1, height: 0.5)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button("Moitié basse") {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        cropRect = CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // Reset button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            cropRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
                            cropRotation = 0
                            imageRotation = 0
                        }
                    }) {
                        Label("Tout réinitialiser", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Import Dialog View
struct ImportDialogView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Importer une copie")
                .font(.headline)

            DropZoneView(isDragging: .constant(false))
                .frame(height: 200)

            HStack {
                Button("Annuler") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
        }
        .padding()
        .frame(width: 500, height: 350)
    }
}

#Preview {
    ImportView()
        .environment(AppState())
}
