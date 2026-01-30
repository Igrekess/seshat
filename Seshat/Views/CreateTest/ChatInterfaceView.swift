import SwiftUI

/// Chat interface for interacting with the AI to generate questions
struct ChatInterfaceView: View {
    @Bindable var service: TestCreationService
    @State private var inputText = ""
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if let session = service.currentSession {
                            ForEach(session.conversationHistory.filter { $0.role != .system }) { message in
                                ChatMessageRow(message: message, onAddQuestions: addQuestions)
                                    .id(message.id)
                            }
                        }

                        // Empty state
                        if service.currentSession?.conversationHistory.filter({ $0.role != .system }).isEmpty ?? true {
                            EmptyStateView()
                                .padding(.top, 60)
                        }
                    }
                    .padding()
                }
                .onChange(of: service.currentSession?.conversationHistory.count) { _, _ in
                    if let lastMessage = service.currentSession?.conversationHistory.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: service.streamingContent) { _, _ in
                    if let lastMessage = service.currentSession?.conversationHistory.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            // Input area
            InputArea(
                inputText: $inputText,
                isGenerating: service.isGenerating,
                onSend: sendMessage
            )
            .focused($isInputFocused)
        }
        .alert("Erreur", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .onAppear {
            isInputFocused = true
        }
    }

    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let message = inputText
        inputText = ""

        Task {
            do {
                try await service.sendMessage(message)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func addQuestions(_ questions: [Question]) {
        for question in questions {
            service.addQuestion(question)
        }
    }
}

// MARK: - Chat Message Row

struct ChatMessageRow: View {
    let message: ChatMessage
    var onAddQuestions: (([Question]) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(message.role == .user ? Color.blue : Color.purple)
                    .frame(width: 32, height: 32)

                Image(systemName: message.role == .user ? "person.fill" : "brain.head.profile")
                    .foregroundColor(.white)
                    .font(.system(size: 14))
            }

            // Content
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack {
                    Text(message.role == .user ? "Vous" : "Assistant IA")
                        .font(.headline)
                        .foregroundColor(.primary)

                    if message.isStreaming {
                        ProgressView()
                            .scaleEffect(0.6)
                    }

                    Spacer()

                    Text(message.timestamp, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Message content
                Text(message.content)
                    .textSelection(.enabled)
                    .foregroundColor(.primary)

                // Parsed questions indicator
                if let questions = message.parsedQuestions, !questions.isEmpty {
                    ParsedQuestionsIndicator(questions: questions, onAddQuestions: onAddQuestions)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(message.role == .user ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.1))
        )
    }
}

// MARK: - Parsed Questions Indicator

struct ParsedQuestionsIndicator: View {
    let questions: [Question]
    var onAddQuestions: (([Question]) -> Void)?

    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)

            Text("\(questions.count) question(s) générée(s)")
                .font(.callout)
                .foregroundColor(.secondary)

            Spacer()

            if let onAddQuestions = onAddQuestions {
                Button {
                    onAddQuestions(questions)
                } label: {
                    Label("Ajouter au test", systemImage: "plus.circle.fill")
                        .font(.callout)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(0.1))
        )
    }
}

// MARK: - Input Area

struct InputArea: View {
    @Binding var inputText: String
    let isGenerating: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Text input
            TextField("Décrivez les questions à générer...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.1))
                )
                .onSubmit {
                    if !isGenerating {
                        onSend()
                    }
                }
                .disabled(isGenerating)

            // Send button
            Button {
                onSend()
            } label: {
                Image(systemName: isGenerating ? "stop.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(canSend ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding()
    }

    private var canSend: Bool {
        !isGenerating && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Commencez à créer votre test")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Décrivez les questions que vous souhaitez générer.\nPar exemple:")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                ExamplePrompt("Génère 5 QCM sur les verbes irréguliers en anglais")
                ExamplePrompt("Crée 3 questions ouvertes sur la Révolution française")
                ExamplePrompt("Fais un quiz vrai/faux sur les capitales européennes")
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.1))
            )
        }
        .padding()
    }
}

struct ExamplePrompt: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack {
            Image(systemName: "quote.opening")
                .foregroundColor(.secondary)
                .font(.caption)
            Text(text)
                .font(.callout)
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    ChatInterfaceView(service: TestCreationService.shared)
}
