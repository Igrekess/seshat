import SwiftUI
import AppKit

/// View for cropping images before batch processing
struct BatchCropView: View {
    let assignmentId: UUID
    let onComplete: () -> Void

    @State private var dataStore = DataStore.shared
    @State private var allImages: [ImageItem] = []
    @State private var currentIndex = 0
    @State private var cropRect: CGRect = .zero
    @State private var imageSize: CGSize = .zero
    @State private var isDragging = false
    @State private var dragStart: CGPoint = .zero
    @State private var showingApplyToAll = false

    struct ImageItem: Identifiable {
        let id = UUID()
        let submissionId: UUID
        let studentName: String
        let imagePath: String
        let imageIndex: Int
        var cropRect: CGRect? // nil = no crop (use full image)
    }

    var currentImage: ImageItem? {
        guard currentIndex < allImages.count else { return nil }
        return allImages[currentIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Préparer les images")
                        .font(.headline)
                    Text("\(currentIndex + 1) / \(allImages.count) images")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Apply to all button
                Button {
                    showingApplyToAll = true
                } label: {
                    Label("Appliquer à toutes", systemImage: "rectangle.on.rectangle")
                }
                .disabled(cropRect == .zero)
                .help("Appliquer ce recadrage à toutes les images")

                Button("Terminer") {
                    saveCropSettings()
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.bar)

            Divider()

            // Main content
            HSplitView {
                // Image editor
                VStack {
                    if let item = currentImage,
                       let nsImage = dataStore.loadImage(relativePath: item.imagePath) {
                        GeometryReader { geometry in
                            ZStack {
                                // Image
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .background(
                                        GeometryReader { imgGeo in
                                            Color.clear.onAppear {
                                                imageSize = imgGeo.size
                                                // Initialize crop rect to full image if not set
                                                if cropRect == .zero {
                                                    cropRect = CGRect(origin: .zero, size: imgGeo.size)
                                                }
                                            }
                                            .onChange(of: imgGeo.size) { _, newSize in
                                                imageSize = newSize
                                            }
                                        }
                                    )

                                // Crop overlay
                                CropOverlayView(
                                    cropRect: $cropRect,
                                    imageSize: imageSize,
                                    containerSize: geometry.size
                                )
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }

                        // Current image info
                        HStack {
                            Text(item.studentName)
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("• Image \(item.imageIndex + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button("Réinitialiser") {
                                cropRect = CGRect(origin: .zero, size: imageSize)
                            }
                            .font(.caption)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    } else {
                        ContentUnavailableView(
                            "Image non disponible",
                            systemImage: "photo"
                        )
                    }
                }
                .frame(minWidth: 400)

                // Thumbnail navigation
                VStack(spacing: 0) {
                    Text("Navigation")
                        .font(.caption)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.bar)

                    Divider()

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(Array(allImages.enumerated()), id: \.element.id) { index, item in
                                    ThumbnailRow(
                                        item: item,
                                        isSelected: index == currentIndex,
                                        hasCrop: item.cropRect != nil
                                    )
                                    .id(index)
                                    .onTapGesture {
                                        // Save current crop before switching
                                        saveCropForCurrentImage()
                                        currentIndex = index
                                        loadCropForCurrentImage()
                                    }
                                }
                            }
                            .padding()
                        }
                        .onChange(of: currentIndex) { _, newIndex in
                            withAnimation {
                                proxy.scrollTo(newIndex, anchor: .center)
                            }
                        }
                    }
                }
                .frame(width: 200)
            }

            Divider()

            // Navigation controls
            HStack {
                Button {
                    if currentIndex > 0 {
                        saveCropForCurrentImage()
                        currentIndex -= 1
                        loadCropForCurrentImage()
                    }
                } label: {
                    Label("Précédent", systemImage: "chevron.left")
                }
                .disabled(currentIndex == 0)
                .keyboardShortcut(.leftArrow, modifiers: [])

                Spacer()

                // Quick actions
                HStack(spacing: 16) {
                    Button {
                        // Skip crop for this image
                        var item = allImages[currentIndex]
                        item.cropRect = nil
                        allImages[currentIndex] = item
                        goToNext()
                    } label: {
                        Text("Passer (garder entière)")
                    }

                    Button {
                        // Validate and go to next
                        saveCropForCurrentImage()
                        goToNext()
                    } label: {
                        Label("Valider et suivant", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
                }

                Spacer()

                Button {
                    if currentIndex < allImages.count - 1 {
                        saveCropForCurrentImage()
                        currentIndex += 1
                        loadCropForCurrentImage()
                    }
                } label: {
                    Label("Suivant", systemImage: "chevron.right")
                }
                .disabled(currentIndex >= allImages.count - 1)
                .keyboardShortcut(.rightArrow, modifiers: [])
            }
            .padding()
            .background(.bar)
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            loadAllImages()
        }
        .alert("Appliquer à toutes les images ?", isPresented: $showingApplyToAll) {
            Button("Annuler", role: .cancel) { }
            Button("Appliquer") {
                applyCurrentCropToAll()
            }
        } message: {
            Text("Le recadrage actuel sera appliqué à toutes les \(allImages.count) images. Cette action ne peut pas être annulée.")
        }
    }

    private func loadAllImages() {
        let submissions = dataStore.getSubmissions(forAssignment: assignmentId)
            .filter { !$0.imagePaths.isEmpty }

        var items: [ImageItem] = []
        for submission in submissions {
            let student = dataStore.getStudent(by: submission.studentId)
            let studentName = student?.fullName ?? "Élève inconnu"

            for (index, path) in submission.imagePaths.enumerated() {
                items.append(ImageItem(
                    submissionId: submission.id,
                    studentName: studentName,
                    imagePath: path,
                    imageIndex: index,
                    cropRect: nil
                ))
            }
        }

        allImages = items
        if !items.isEmpty {
            loadCropForCurrentImage()
        }
    }

    private func saveCropForCurrentImage() {
        guard currentIndex < allImages.count else { return }
        // Only save if crop is different from full image
        if cropRect.origin != .zero || cropRect.size != imageSize {
            allImages[currentIndex].cropRect = cropRect
        }
    }

    private func loadCropForCurrentImage() {
        guard currentIndex < allImages.count else { return }
        if let savedCrop = allImages[currentIndex].cropRect {
            cropRect = savedCrop
        } else {
            // Reset to full image
            cropRect = CGRect(origin: .zero, size: imageSize)
        }
    }

    private func goToNext() {
        if currentIndex < allImages.count - 1 {
            currentIndex += 1
            loadCropForCurrentImage()
        }
    }

    private func applyCurrentCropToAll() {
        let normalizedCrop = CGRect(
            x: cropRect.origin.x / imageSize.width,
            y: cropRect.origin.y / imageSize.height,
            width: cropRect.size.width / imageSize.width,
            height: cropRect.size.height / imageSize.height
        )

        for i in allImages.indices {
            // Apply normalized crop to each image
            allImages[i].cropRect = normalizedCrop
        }
    }

    private func saveCropSettings() {
        // Save crop settings to submissions
        var submissionCrops: [UUID: [CropInfo]] = [:]

        for item in allImages {
            if let crop = item.cropRect {
                let normalizedCrop = CropInfo(
                    imageIndex: item.imageIndex,
                    rect: CGRect(
                        x: crop.origin.x / max(imageSize.width, 1),
                        y: crop.origin.y / max(imageSize.height, 1),
                        width: crop.size.width / max(imageSize.width, 1),
                        height: crop.size.height / max(imageSize.height, 1)
                    )
                )
                submissionCrops[item.submissionId, default: []].append(normalizedCrop)
            }
        }

        // Update submissions with crop info
        for (submissionId, crops) in submissionCrops {
            if var submission = dataStore.getSubmission(by: submissionId) {
                submission.cropSettings = crops
                dataStore.updateSubmission(submission)
            }
        }
    }
}

// MARK: - Crop Overlay

struct CropOverlayView: View {
    @Binding var cropRect: CGRect
    let imageSize: CGSize
    let containerSize: CGSize

    @State private var dragCorner: Corner?
    @State private var dragStart: CGPoint = .zero
    @State private var initialRect: CGRect = .zero

    enum Corner {
        case topLeft, topRight, bottomLeft, bottomRight, move
    }

    var body: some View {
        ZStack {
            // Dimmed overlay outside crop area
            Path { path in
                path.addRect(CGRect(origin: .zero, size: containerSize))
                path.addRect(cropRect)
            }
            .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))

            // Crop rectangle
            Rectangle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)

            // Grid lines (rule of thirds)
            Path { path in
                let thirdW = cropRect.width / 3
                let thirdH = cropRect.height / 3

                // Vertical lines
                path.move(to: CGPoint(x: cropRect.minX + thirdW, y: cropRect.minY))
                path.addLine(to: CGPoint(x: cropRect.minX + thirdW, y: cropRect.maxY))
                path.move(to: CGPoint(x: cropRect.minX + 2 * thirdW, y: cropRect.minY))
                path.addLine(to: CGPoint(x: cropRect.minX + 2 * thirdW, y: cropRect.maxY))

                // Horizontal lines
                path.move(to: CGPoint(x: cropRect.minX, y: cropRect.minY + thirdH))
                path.addLine(to: CGPoint(x: cropRect.maxX, y: cropRect.minY + thirdH))
                path.move(to: CGPoint(x: cropRect.minX, y: cropRect.minY + 2 * thirdH))
                path.addLine(to: CGPoint(x: cropRect.maxX, y: cropRect.minY + 2 * thirdH))
            }
            .stroke(Color.white.opacity(0.5), lineWidth: 1)

            // Corner handles
            ForEach([Corner.topLeft, .topRight, .bottomLeft, .bottomRight], id: \.self) { corner in
                CornerHandle(corner: corner)
                    .position(cornerPosition(corner))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if dragCorner == nil {
                                    dragCorner = corner
                                    dragStart = value.startLocation
                                    initialRect = cropRect
                                }
                                updateCrop(for: corner, with: value.location)
                            }
                            .onEnded { _ in
                                dragCorner = nil
                            }
                    )
            }

            // Move handle (center)
            Circle()
                .fill(Color.white.opacity(0.01)) // Nearly invisible but captures gestures
                .frame(width: max(cropRect.width - 40, 20), height: max(cropRect.height - 40, 20))
                .position(x: cropRect.midX, y: cropRect.midY)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if dragCorner == nil {
                                dragCorner = .move
                                dragStart = value.startLocation
                                initialRect = cropRect
                            }
                            let delta = CGSize(
                                width: value.location.x - dragStart.x,
                                height: value.location.y - dragStart.y
                            )
                            var newRect = initialRect.offsetBy(dx: delta.width, dy: delta.height)
                            // Clamp to image bounds
                            newRect.origin.x = max(0, min(newRect.origin.x, imageSize.width - newRect.width))
                            newRect.origin.y = max(0, min(newRect.origin.y, imageSize.height - newRect.height))
                            cropRect = newRect
                        }
                        .onEnded { _ in
                            dragCorner = nil
                        }
                )
        }
    }

    private func cornerPosition(_ corner: Corner) -> CGPoint {
        switch corner {
        case .topLeft: return CGPoint(x: cropRect.minX, y: cropRect.minY)
        case .topRight: return CGPoint(x: cropRect.maxX, y: cropRect.minY)
        case .bottomLeft: return CGPoint(x: cropRect.minX, y: cropRect.maxY)
        case .bottomRight: return CGPoint(x: cropRect.maxX, y: cropRect.maxY)
        case .move: return CGPoint(x: cropRect.midX, y: cropRect.midY)
        }
    }

    private func updateCrop(for corner: Corner, with location: CGPoint) {
        let minSize: CGFloat = 50

        switch corner {
        case .topLeft:
            let newX = min(location.x, cropRect.maxX - minSize)
            let newY = min(location.y, cropRect.maxY - minSize)
            cropRect = CGRect(
                x: max(0, newX),
                y: max(0, newY),
                width: cropRect.maxX - max(0, newX),
                height: cropRect.maxY - max(0, newY)
            )
        case .topRight:
            let newWidth = max(minSize, location.x - cropRect.minX)
            let newY = min(location.y, cropRect.maxY - minSize)
            cropRect = CGRect(
                x: cropRect.minX,
                y: max(0, newY),
                width: min(newWidth, imageSize.width - cropRect.minX),
                height: cropRect.maxY - max(0, newY)
            )
        case .bottomLeft:
            let newX = min(location.x, cropRect.maxX - minSize)
            let newHeight = max(minSize, location.y - cropRect.minY)
            cropRect = CGRect(
                x: max(0, newX),
                y: cropRect.minY,
                width: cropRect.maxX - max(0, newX),
                height: min(newHeight, imageSize.height - cropRect.minY)
            )
        case .bottomRight:
            let newWidth = max(minSize, location.x - cropRect.minX)
            let newHeight = max(minSize, location.y - cropRect.minY)
            cropRect = CGRect(
                x: cropRect.minX,
                y: cropRect.minY,
                width: min(newWidth, imageSize.width - cropRect.minX),
                height: min(newHeight, imageSize.height - cropRect.minY)
            )
        case .move:
            break
        }
    }
}

struct CornerHandle: View {
    let corner: CropOverlayView.Corner

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 20, height: 20)

            Circle()
                .stroke(Color.accentColor, lineWidth: 2)
                .frame(width: 20, height: 20)
        }
        .shadow(radius: 2)
    }
}

// MARK: - Thumbnail Row

struct ThumbnailRow: View {
    let item: BatchCropView.ImageItem
    let isSelected: Bool
    let hasCrop: Bool

    @State private var dataStore = DataStore.shared

    var body: some View {
        HStack(spacing: 8) {
            if let image = dataStore.loadImage(relativePath: item.imagePath) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 50)
                    .clipped()
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.studentName)
                    .font(.caption)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text("Image \(item.imageIndex + 1)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if hasCrop {
                        Image(systemName: "crop")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
            }

            Spacer()
        }
        .padding(6)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(6)
    }
}

// CropInfo is defined in SchoolModels.swift

#Preview {
    BatchCropView(assignmentId: UUID()) { }
}
