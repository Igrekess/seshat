import SwiftUI

/// Detail view for a single student submission
struct SubmissionDetailView: View {
    let studentId: UUID
    let assignmentId: UUID

    @State private var dataStore = DataStore.shared
    @State private var selectedTab = 0
    @State private var isProcessingOCR = false
    @State private var isProcessingAnalysis = false

    var student: Student? {
        dataStore.getStudent(by: studentId)
    }

    var assignment: Assignment? {
        dataStore.getAssignment(by: assignmentId)
    }

    var submission: StudentSubmission? {
        dataStore.getSubmission(for: studentId, assignmentId: assignmentId)
    }

    var body: some View {
        if let student = student, let assignment = assignment {
            VStack(spacing: 0) {
                // Header
                SubmissionHeader(
                    student: student,
                    assignment: assignment,
                    submission: submission,
                    onRunOCR: runOCR,
                    onRunAnalysis: runAnalysis,
                    isProcessingOCR: isProcessingOCR,
                    isProcessingAnalysis: isProcessingAnalysis
                )

                Divider()

                if let submission = submission {
                    // Tabs
                    Picker("Vue", selection: $selectedTab) {
                        Text("Images").tag(0)
                        Text("Transcription").tag(1)
                        Text("Analyse").tag(2)
                        Text("Notation").tag(3)
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    // Tab content
                    switch selectedTab {
                    case 0:
                        SubmissionImagesView(submission: submission) { updatedSubmission in
                            dataStore.updateSubmission(updatedSubmission)
                        }
                    case 1:
                        SubmissionTranscriptionView(submission: submission) { updatedSubmission in
                            dataStore.updateSubmission(updatedSubmission)
                        }
                    case 2:
                        SubmissionAnalysisView(submission: submission) { updatedSubmission in
                            dataStore.updateSubmission(updatedSubmission)
                        }
                    case 3:
                        SubmissionGradingView(
                            submission: submission,
                            assignment: assignment,
                            onUpdate: { updatedSubmission in
                                dataStore.updateSubmission(updatedSubmission)
                            }
                        )
                    default:
                        EmptyView()
                    }
                } else {
                    ContentUnavailableView(
                        "Pas de copie",
                        systemImage: "doc.text",
                        description: Text("Importez des images pour cette copie")
                    )
                }
            }
        } else {
            ContentUnavailableView(
                "Sélectionnez un élève",
                systemImage: "person",
                description: Text("Choisissez un élève dans la liste")
            )
        }
    }

    private func runOCR() {
        guard let submission = submission else { return }
        isProcessingOCR = true

        Task {
            await BatchProcessingService.shared.runBatchOCR(submissions: [submission])
            isProcessingOCR = false
        }
    }

    private func runAnalysis() {
        guard let submission = submission else { return }
        isProcessingAnalysis = true

        Task {
            await BatchProcessingService.shared.runBatchAnalysis(
                submissions: [submission],
                assignmentId: assignmentId
            )
            isProcessingAnalysis = false
        }
    }
}

// MARK: - Submission Header

struct SubmissionHeader: View {
    let student: Student
    let assignment: Assignment
    let submission: StudentSubmission?
    let onRunOCR: () -> Void
    let onRunAnalysis: () -> Void
    let isProcessingOCR: Bool
    let isProcessingAnalysis: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(student.fullName)
                    .font(.title2)
                    .bold()

                Text(assignment.title)
                    .foregroundStyle(.secondary)

                if let submission = submission {
                    StatusBadge(status: submission.status)
                }
            }

            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                if submission != nil {
                    Button {
                        onRunOCR()
                    } label: {
                        if isProcessingOCR {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Label("OCR", systemImage: "text.viewfinder")
                        }
                    }
                    .disabled(submission?.imagePaths.isEmpty ?? true || isProcessingOCR)

                    Button {
                        onRunAnalysis()
                    } label: {
                        if isProcessingAnalysis {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Label("Analyser", systemImage: "wand.and.stars")
                        }
                    }
                    .disabled(submission?.transcription == nil || isProcessingAnalysis)
                }
            }

            // Grade display
            if let grade = submission?.finalGrade {
                GradeBadge(grade: grade, maxGrade: assignment.maxScore)
                    .font(.title)
            }
        }
        .padding()
        .background(.bar)
    }
}

// MARK: - Images View

struct SubmissionImagesView: View {
    let submission: StudentSubmission
    let onUpdate: (StudentSubmission) -> Void
    @State private var dataStore = DataStore.shared
    @State private var selectedImageIndex = 0
    @State private var draggedIndex: Int?
    @State private var showingCropEditor = false
    @State private var isCropMode = false
    @State private var cropRect: CGRect = .zero
    @State private var imageViewSize: CGSize = .zero

    // Get current crop for this image if any
    var currentCrop: CropInfo? {
        submission.cropSettings?.first { $0.imageIndex == selectedImageIndex }
    }

    var body: some View {
        if submission.imagePaths.isEmpty {
            ContentUnavailableView(
                "Pas d'images",
                systemImage: "photo",
                description: Text("Importez des images de la copie")
            )
        } else {
            VStack {
                // Image viewer with page indicator
                ZStack(alignment: .topTrailing) {
                    if selectedImageIndex < submission.imagePaths.count,
                       let image = dataStore.loadImage(relativePath: submission.imagePaths[selectedImageIndex]) {
                        GeometryReader { geometry in
                            ZStack {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(
                                        GeometryReader { imgGeo in
                                            Color.clear.onAppear {
                                                imageViewSize = imgGeo.size
                                                loadCropForCurrentImage()
                                            }
                                            .onChange(of: imgGeo.size) { _, newSize in
                                                imageViewSize = newSize
                                            }
                                        }
                                    )

                                // Crop overlay when in crop mode or when crop is defined
                                if isCropMode {
                                    ImageCropOverlay(
                                        cropRect: $cropRect,
                                        imageSize: imageViewSize,
                                        isEditing: true
                                    )
                                } else if let crop = currentCrop {
                                    // Show existing crop zone indicator
                                    let denormalizedRect = CGRect(
                                        x: crop.rect.origin.x * imageViewSize.width,
                                        y: crop.rect.origin.y * imageViewSize.height,
                                        width: crop.rect.size.width * imageViewSize.width,
                                        height: crop.rect.size.height * imageViewSize.height
                                    )
                                    Rectangle()
                                        .stroke(Color.blue, lineWidth: 2)
                                        .background(Color.blue.opacity(0.1))
                                        .frame(width: denormalizedRect.width, height: denormalizedRect.height)
                                        .position(x: denormalizedRect.midX, y: denormalizedRect.midY)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }

                    // Page indicator and actions
                    if !isCropMode {
                        HStack(spacing: 12) {
                            Text("Page \(selectedImageIndex + 1) / \(submission.imagePaths.count)")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.regularMaterial)
                                .cornerRadius(4)

                            // Crop indicator
                            if currentCrop != nil {
                                Image(systemName: "crop")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(.regularMaterial)
                                    .cornerRadius(4)
                                    .help("Zone de recadrage définie")
                            }

                            // Crop button
                            Button {
                                enterCropMode()
                            } label: {
                                Image(systemName: "crop")
                            }
                            .buttonStyle(.bordered)
                            .help("Définir la zone d'analyse")

                            // Delete current image button
                            Button(role: .destructive) {
                                deleteImage(at: selectedImageIndex)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.bordered)
                            .help("Supprimer cette image")
                        }
                        .padding(8)
                    }
                }

                // Crop mode toolbar
                if isCropMode {
                    HStack {
                        Text("Mode recadrage - Ajustez la zone à analyser")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Réinitialiser") {
                            cropRect = CGRect(origin: .zero, size: imageViewSize)
                        }
                        .buttonStyle(.bordered)

                        Button("Supprimer le recadrage") {
                            removeCrop()
                            isCropMode = false
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(.red)

                        Button("Annuler") {
                            isCropMode = false
                            loadCropForCurrentImage()
                        }
                        .buttonStyle(.bordered)

                        Button("Valider") {
                            saveCrop()
                            isCropMode = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.bar)
                }

                // Thumbnails with reorder support
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(submission.imagePaths.enumerated()), id: \.offset) { index, path in
                            ImageThumbnail(
                                path: path,
                                index: index,
                                isSelected: selectedImageIndex == index,
                                totalCount: submission.imagePaths.count,
                                hasTranscription: submission.transcription != nil,
                                hasAnalysis: submission.analysis != nil,
                                hasCrop: submission.cropSettings?.contains { $0.imageIndex == index } ?? false,
                                onSelect: {
                                    if isCropMode {
                                        // Save current crop before switching
                                        saveCrop()
                                    }
                                    selectedImageIndex = index
                                    if isCropMode {
                                        loadCropForCurrentImage()
                                    }
                                },
                                onMoveLeft: { moveImage(from: index, to: index - 1) },
                                onMoveRight: { moveImage(from: index, to: index + 1) },
                                onDelete: { deleteImage(at: index) }
                            )
                            .onDrag {
                                draggedIndex = index
                                return NSItemProvider(object: String(index) as NSString)
                            }
                            .onDrop(of: [.text], delegate: ImageDropDelegate(
                                currentIndex: index,
                                draggedIndex: $draggedIndex,
                                imagePaths: submission.imagePaths,
                                onReorder: { from, to in
                                    moveImage(from: from, to: to)
                                }
                            ))
                        }
                    }
                    .padding()
                }
                .background(.bar)

                // Help text
                Text("Glisser-déposer pour réordonner • Clic droit pour plus d'options")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
            }
        }
    }

    private func deleteImage(at index: Int) {
        guard index < submission.imagePaths.count else { return }

        var updated = submission
        updated.imagePaths.remove(at: index)

        // Reset transcription and analysis since images changed
        updated.transcription = nil
        updated.analysis = nil
        updated.grade = nil
        updated.status = updated.imagePaths.isEmpty ? .pending : .pending

        // Adjust selected index if needed
        if selectedImageIndex >= updated.imagePaths.count {
            selectedImageIndex = max(0, updated.imagePaths.count - 1)
        }

        onUpdate(updated)
    }

    private func moveImage(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < submission.imagePaths.count,
              destinationIndex >= 0, destinationIndex < submission.imagePaths.count else { return }

        var updated = submission
        let movedPath = updated.imagePaths.remove(at: sourceIndex)
        updated.imagePaths.insert(movedPath, at: destinationIndex)

        // Reset transcription since order changed
        updated.transcription = nil
        updated.analysis = nil
        updated.grade = nil
        updated.status = .pending

        // Update selection to follow the moved image
        selectedImageIndex = destinationIndex

        onUpdate(updated)
    }

    private func enterCropMode() {
        loadCropForCurrentImage()
        isCropMode = true
    }

    private func loadCropForCurrentImage() {
        if let crop = currentCrop {
            // Denormalize the crop rect
            cropRect = CGRect(
                x: crop.rect.origin.x * imageViewSize.width,
                y: crop.rect.origin.y * imageViewSize.height,
                width: crop.rect.size.width * imageViewSize.width,
                height: crop.rect.size.height * imageViewSize.height
            )
        } else {
            // Default to full image
            cropRect = CGRect(origin: .zero, size: imageViewSize)
        }
    }

    private func saveCrop() {
        // Normalize the crop rect (0-1)
        let normalizedRect = CGRect(
            x: cropRect.origin.x / max(imageViewSize.width, 1),
            y: cropRect.origin.y / max(imageViewSize.height, 1),
            width: cropRect.size.width / max(imageViewSize.width, 1),
            height: cropRect.size.height / max(imageViewSize.height, 1)
        )

        // Only save if it's different from full image
        let isFullImage = normalizedRect.origin.x < 0.01 &&
                          normalizedRect.origin.y < 0.01 &&
                          normalizedRect.size.width > 0.99 &&
                          normalizedRect.size.height > 0.99

        var updated = submission
        var crops = updated.cropSettings ?? []

        // Remove existing crop for this image
        crops.removeAll { $0.imageIndex == selectedImageIndex }

        // Add new crop if not full image
        if !isFullImage {
            crops.append(CropInfo(imageIndex: selectedImageIndex, rect: normalizedRect))
        }

        updated.cropSettings = crops.isEmpty ? nil : crops

        // Reset transcription since crop changed
        updated.transcription = nil
        updated.analysis = nil
        updated.grade = nil
        updated.status = .pending

        onUpdate(updated)
    }

    private func removeCrop() {
        var updated = submission
        var crops = updated.cropSettings ?? []
        crops.removeAll { $0.imageIndex == selectedImageIndex }
        updated.cropSettings = crops.isEmpty ? nil : crops

        // Reset transcription since crop changed
        updated.transcription = nil
        updated.analysis = nil
        updated.grade = nil
        updated.status = .pending

        onUpdate(updated)
    }
}

// MARK: - Image Crop Overlay

struct ImageCropOverlay: View {
    @Binding var cropRect: CGRect
    let imageSize: CGSize
    let isEditing: Bool

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
                path.addRect(CGRect(origin: .zero, size: imageSize))
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

            if isEditing {
                // Corner handles
                ForEach([Corner.topLeft, .topRight, .bottomLeft, .bottomRight], id: \.self) { corner in
                    CropCornerHandle(corner: corner)
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

                // Move handle (center area)
                Rectangle()
                    .fill(Color.white.opacity(0.01))
                    .frame(width: max(cropRect.width - 60, 20), height: max(cropRect.height - 60, 20))
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

struct CropCornerHandle: View {
    let corner: ImageCropOverlay.Corner

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 24, height: 24)

            Circle()
                .stroke(Color.accentColor, lineWidth: 3)
                .frame(width: 24, height: 24)
        }
        .shadow(radius: 2)
    }
}

// MARK: - Image Thumbnail

struct ImageThumbnail: View {
    let path: String
    let index: Int
    let isSelected: Bool
    let totalCount: Int
    let hasTranscription: Bool
    let hasAnalysis: Bool
    let hasCrop: Bool
    let onSelect: () -> Void
    let onMoveLeft: () -> Void
    let onMoveRight: () -> Void
    let onDelete: () -> Void

    @State private var dataStore = DataStore.shared

    var body: some View {
        VStack(spacing: 2) {
            if let image = dataStore.loadImage(relativePath: path) {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 80)
                        .clipped()
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                        )
                        .cornerRadius(4)

                    // Status indicators
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 2) {
                            if hasTranscription {
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.white)
                                    .padding(2)
                                    .background(Color.blue)
                                    .clipShape(Circle())
                            }
                            if hasAnalysis {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(2)
                                    .background(Color.green)
                                    .clipShape(Circle())
                            }
                        }

                        // Crop indicator
                        if hasCrop {
                            Image(systemName: "crop")
                                .font(.system(size: 8))
                                .foregroundStyle(.white)
                                .padding(2)
                                .background(Color.orange)
                                .clipShape(Circle())
                        }
                    }
                    .padding(2)
                }
                .onTapGesture {
                    onSelect()
                }
                .contextMenu {
                    Button {
                        onMoveLeft()
                    } label: {
                        Label("Déplacer à gauche", systemImage: "arrow.left")
                    }
                    .disabled(index == 0)

                    Button {
                        onMoveRight()
                    } label: {
                        Label("Déplacer à droite", systemImage: "arrow.right")
                    }
                    .disabled(index == totalCount - 1)

                    Divider()

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                }
            }

            Text("\(index + 1)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Drop Delegate

struct ImageDropDelegate: DropDelegate {
    let currentIndex: Int
    @Binding var draggedIndex: Int?
    let imagePaths: [String]
    let onReorder: (Int, Int) -> Void

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedIndex = draggedIndex else { return false }
        if draggedIndex != currentIndex {
            onReorder(draggedIndex, currentIndex)
        }
        self.draggedIndex = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedIndex = draggedIndex, draggedIndex != currentIndex else { return }
        // Visual feedback could be added here
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

// MARK: - Transcription View

struct SubmissionTranscriptionView: View {
    let submission: StudentSubmission
    let onUpdate: (StudentSubmission) -> Void

    @State private var isEditing = false
    @State private var editedText = ""

    var body: some View {
        if let transcription = submission.transcription {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Stats
                    HStack(spacing: 20) {
                        StatItem(label: "Paragraphes", value: "\(transcription.boundingBoxes.count)")
                        StatItem(label: "Mots", value: "\(transcription.fullText.split(separator: " ").count)")
                        StatItem(label: "Caractères", value: "\(transcription.fullText.count)")
                        StatItem(label: "Temps", value: String(format: "%.1fs", transcription.processingTime))

                        Spacer()

                        // Edit button
                        if isEditing {
                            Button {
                                saveTranscription()
                            } label: {
                                Label("Enregistrer", systemImage: "checkmark")
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Annuler") {
                                isEditing = false
                                editedText = ""
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button {
                                editedText = transcription.fullText
                                isEditing = true
                            } label: {
                                Label("Modifier", systemImage: "pencil")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)

                    // Full text
                    HStack {
                        Text("Transcription")
                            .font(.headline)

                        if transcription.editedBoxes.count > 0 {
                            Text("(modifiée)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    if isEditing {
                        TextEditor(text: $editedText)
                            .font(.body)
                            .padding(8)
                            .frame(minHeight: 300)
                            .background(Color(nsColor: .textBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.accentColor, lineWidth: 2)
                            )
                            .cornerRadius(8)

                        Text("Modifiez le texte ci-dessus puis cliquez sur Enregistrer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(transcription.fullText)
                            .font(.body)
                            .textSelection(.enabled)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(8)
                    }
                }
                .padding()
            }
        } else {
            ContentUnavailableView(
                "Pas de transcription",
                systemImage: "doc.text",
                description: Text("Lancez l'OCR pour transcrire la copie")
            )
        }
    }

    private func saveTranscription() {
        guard let transcription = submission.transcription else { return }

        var updated = submission
        updated.transcription = transcription.withFullText(editedText)
        // Reset analysis since transcription changed
        updated.analysis = nil
        updated.grade = nil
        updated.status = .transcribed

        onUpdate(updated)
        isEditing = false
    }
}

struct StatItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3)
                .bold()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Analysis View

struct SubmissionAnalysisView: View {
    let submission: StudentSubmission
    let onUpdate: (StudentSubmission) -> Void

    @State private var showingAddError = false

    var body: some View {
        if let analysis = submission.analysis {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Error summary with add button
                    HStack(spacing: 16) {
                        ForEach(ErrorCategory.allCases, id: \.self) { category in
                            let count = analysis.errorCount(for: category)
                            if count > 0 {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Color(nsColor: NSColor(hex: category.defaultColor) ?? .gray))
                                        .frame(width: 10, height: 10)
                                    Text("\(count) \(category.displayName.lowercased())")
                                        .font(.caption)
                                }
                            }
                        }

                        Spacer()

                        Button {
                            showingAddError = true
                        } label: {
                            Label("Ajouter une erreur", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)

                    // Global feedback - use calculated grade, not AI suggested
                    if let feedback = analysis.globalFeedback {
                        GlobalFeedbackCard(feedback: feedback, calculatedGrade: submission.finalGrade)
                    }

                    // Error list
                    Text("Erreurs détectées (\(analysis.totalErrors))")
                        .font(.headline)

                    ForEach(analysis.errors) { error in
                        ErrorCard(error: error, onDelete: {
                            deleteError(error)
                        })
                    }

                    if analysis.errors.isEmpty {
                        ContentUnavailableView(
                            "Aucune erreur",
                            systemImage: "checkmark.circle",
                            description: Text("Aucune erreur n'a été détectée ou ajoutée")
                        )
                        .frame(height: 200)
                    }
                }
                .padding()
            }
            .sheet(isPresented: $showingAddError) {
                AddErrorSheet(isPresented: $showingAddError) { newError in
                    addError(newError)
                }
            }
        } else {
            ContentUnavailableView(
                "Pas d'analyse",
                systemImage: "wand.and.stars",
                description: Text("Lancez l'analyse pour détecter les erreurs")
            )
        }
    }

    private func deleteError(_ error: LinguisticError) {
        guard let analysis = submission.analysis else { return }

        var updated = submission
        updated.analysis = analysis.removing(error: error)
        // Recalculate grade
        updated.grade = nil
        updated.status = .analyzed

        onUpdate(updated)
    }

    private func addError(_ error: LinguisticError) {
        guard let analysis = submission.analysis else { return }

        var updated = submission
        updated.analysis = analysis.adding(error: error)
        // Recalculate grade
        updated.grade = nil
        updated.status = .analyzed

        onUpdate(updated)
    }
}

struct GlobalFeedbackCard: View {
    let feedback: GlobalFeedback
    let calculatedGrade: Double?  // Use rubric-calculated grade for consistency
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text(feedback.overallAssessment)
                    .font(.body)

                if !feedback.strengths.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Points forts", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)

                        ForEach(feedback.strengths, id: \.self) { strength in
                            Text("• \(strength)")
                                .font(.caption)
                        }
                    }
                }

                if !feedback.areasForImprovement.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Axes d'amélioration", systemImage: "arrow.up.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)

                        ForEach(feedback.areasForImprovement, id: \.self) { area in
                            Text("• \(area)")
                                .font(.caption)
                        }
                    }
                }

                Text(feedback.encouragement)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.purple)
            }
            .padding(.vertical, 8)
        } label: {
            HStack {
                Image(systemName: "person.fill")
                    .foregroundStyle(.blue)
                Text("Appréciation du professeur")
                    .font(.headline)

                Spacer()

                // Display the rubric-calculated grade, not the AI suggested grade
                if let grade = calculatedGrade {
                    Text(String(format: "%.1f/20", grade))
                        .font(.headline)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct ErrorCard: View {
    let error: LinguisticError
    var onDelete: (() -> Void)?

    var categoryColor: Color {
        Color(nsColor: NSColor(hex: error.category.defaultColor) ?? .gray)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: error.category.icon)
                    .foregroundStyle(categoryColor)
                Text(error.category.displayName)
                    .font(.caption)
                    .foregroundStyle(categoryColor)

                Spacer()

                if let onDelete = onDelete {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Supprimer cette erreur")
                }
            }

            HStack(spacing: 8) {
                Text(error.text)
                    .strikethrough()
                    .foregroundStyle(.red)

                if let correction = error.correction {
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(correction)
                        .foregroundStyle(.green)
                        .bold()
                }
            }

            Text(error.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(categoryColor.opacity(0.05))
        .overlay(
            Rectangle()
                .fill(categoryColor)
                .frame(width: 4),
            alignment: .leading
        )
        .cornerRadius(8)
    }
}

// MARK: - Add Error Sheet

struct AddErrorSheet: View {
    @Binding var isPresented: Bool
    let onAdd: (LinguisticError) -> Void

    @State private var category: ErrorCategory = .grammar
    @State private var errorText = ""
    @State private var correction = ""
    @State private var explanation = ""

    var isValid: Bool {
        !errorText.isEmpty && !explanation.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Catégorie") {
                    Picker("Type d'erreur", selection: $category) {
                        ForEach(ErrorCategory.allCases, id: \.self) { cat in
                            HStack {
                                Image(systemName: cat.icon)
                                    .foregroundStyle(Color(nsColor: NSColor(hex: cat.defaultColor) ?? .gray))
                                Text(cat.displayName)
                            }
                            .tag(cat)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }

                Section("Erreur") {
                    TextField("Texte erroné", text: $errorText, prompt: Text("Ex: I has"))
                    TextField("Correction", text: $correction, prompt: Text("Ex: I have (optionnel)"))
                }

                Section("Explication") {
                    TextEditor(text: $explanation)
                        .frame(minHeight: 80)
                    Text("Expliquez pourquoi c'est une erreur")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Ajouter une erreur")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        let newError = LinguisticError(
                            category: category,
                            text: errorText,
                            correction: correction.isEmpty ? nil : correction,
                            explanation: explanation,
                            position: ErrorPosition(startIndex: 0, endIndex: 0, boundingBoxId: nil)
                        )
                        onAdd(newError)
                        isPresented = false
                    }
                    .disabled(!isValid)
                }
            }
        }
        .frame(minWidth: 450, minHeight: 400)
    }
}

// MARK: - Grading View

struct SubmissionGradingView: View {
    let submission: StudentSubmission
    let assignment: Assignment
    let onUpdate: (StudentSubmission) -> Void

    @State private var dataStore = DataStore.shared
    @State private var teacherGrade: Double = 0
    @State private var teacherNotes: String = ""
    @State private var useTeacherGrade = false

    var rubric: GradingRubric? {
        if let rubricId = assignment.rubricId {
            return dataStore.getRubric(by: rubricId)
        }
        return dataStore.rubrics.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Auto grade section
                if let analysis = submission.analysis {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Note automatique")
                            .font(.headline)

                        if let rubric = rubric {
                            // Show rubric breakdown
                            RubricBreakdownView(
                                rubric: rubric,
                                analysis: analysis
                            )

                            if let autoGrade = submission.grade {
                                HStack {
                                    Text("Note calculée:")
                                        .font(.headline)
                                    Spacer()
                                    Text(String(format: "%.1f / %.0f", autoGrade, assignment.maxScore))
                                        .font(.title)
                                        .bold()
                                        .foregroundStyle(GradeUtilities.color(for: autoGrade, maxGrade: assignment.maxScore))
                                }
                                .padding()
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(8)
                            }
                        } else {
                            Text("Aucun barème configuré")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                // Manual grade override
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Utiliser une note manuelle", isOn: $useTeacherGrade)

                    if useTeacherGrade {
                        HStack {
                            Text("Note:")
                            Slider(value: $teacherGrade, in: 0...assignment.maxScore, step: 0.5)
                            Text(String(format: "%.1f", teacherGrade))
                                .frame(width: 40)
                                .font(.headline)
                        }
                    }

                    Text("Commentaires du professeur")
                        .font(.headline)

                    TextEditor(text: $teacherNotes)
                        .frame(minHeight: 100)
                        .border(Color.secondary.opacity(0.3))

                    Button("Enregistrer") {
                        saveGrade()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .onAppear {
            teacherGrade = submission.teacherGrade ?? submission.grade ?? 0
            teacherNotes = submission.teacherNotes
            useTeacherGrade = submission.teacherGrade != nil
        }
    }

    private func saveGrade() {
        var updated = submission
        updated.teacherGrade = useTeacherGrade ? teacherGrade : nil
        updated.teacherNotes = teacherNotes
        updated.status = .graded
        onUpdate(updated)
    }

}

struct RubricBreakdownView: View {
    let rubric: GradingRubric
    let analysis: AnalysisResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Barème: \(rubric.name)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(rubric.criteria) { criterion in
                let errorCount = analysis.errorCount(for: criterion.category)
                let deduction = min(Double(errorCount) * criterion.pointsPerError, criterion.maxDeduction)

                HStack {
                    Circle()
                        .fill(Color(nsColor: NSColor(hex: criterion.category.defaultColor) ?? .gray))
                        .frame(width: 10, height: 10)

                    Text(criterion.category.displayName)
                        .frame(width: 100, alignment: .leading)

                    Text("\(errorCount) erreur\(errorCount > 1 ? "s" : "")")
                        .foregroundStyle(.secondary)
                        .frame(width: 80)

                    Text("× \(String(format: "%.1f", criterion.pointsPerError))")
                        .foregroundStyle(.secondary)
                        .frame(width: 50)

                    Spacer()

                    Text(String(format: "-%.1f", deduction))
                        .foregroundStyle(.red)
                        .frame(width: 50, alignment: .trailing)

                    if deduction >= criterion.maxDeduction {
                        Text("(max)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

#Preview {
    SubmissionDetailView(studentId: UUID(), assignmentId: UUID())
}
