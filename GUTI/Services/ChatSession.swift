import Foundation
import Combine

// MARK: - Chat Message

struct ChatMessage: Identifiable, Equatable {

    let id = UUID()
    let text: String
    let isUser: Bool
    let date: Date
    /// Agente que respondió según el orquestador ("financial", "secretary", "multi-agent"...).
    let agent: String?
    let fromVoice: Bool
    let isError: Bool

    init(
        text: String,
        isUser: Bool,
        agent: String? = nil,
        fromVoice: Bool = false,
        isError: Bool = false,
        date: Date = Date()
    ) {
        self.text = text
        self.isUser = isUser
        self.agent = agent
        self.fromVoice = fromVoice
        self.isError = isError
        self.date = date
    }
}

// MARK: - Chat Session

/// Estado de la conversación con GUTI. Vive a nivel de app (ContentView) para que
/// el historial y la voz no se pierdan al cambiar de pestaña.
@MainActor
final class ChatSession: ObservableObject {

    enum Phase: Equatable {
        case idle
        case listening
        case thinking
        case speaking
    }

    @Published var messages: [ChatMessage] = []
    @Published var draft = ""
    @Published private(set) var isSending = false
    /// Últimos niveles del micrófono (0...1) para dibujar la onda en vivo.
    @Published private(set) var levelHistory: [Float] = Array(repeating: 0, count: 28)

    let voice = VoiceService()

    /// Se llama después de cada respuesta para refrescar finanzas, tareas y agenda.
    var onResponse: (() async -> Void)?

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Reenviar cambios del VoiceService para que la UI reaccione a
        // isRecording / isSpeaking / recognizedText.
        voice.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        voice.$audioLevel
            .sink { [weak self] level in
                guard let self, self.voice.isRecording else { return }
                self.levelHistory.removeFirst()
                self.levelHistory.append(level)
            }
            .store(in: &cancellables)

        voice.$recognizedText
            .sink { [weak self] text in
                guard let self, self.voice.isRecording, !text.isEmpty else { return }
                self.draft = text
            }
            .store(in: &cancellables)
    }

    var phase: Phase {
        if voice.isRecording { return .listening }
        if isSending { return .thinking }
        if voice.isSpeaking { return .speaking }
        return .idle
    }

    // MARK: - Send

    func send(_ text: String, fromVoice: Bool = false) {

        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty, !isSending else { return }

        draft = ""
        voice.stopSpeaking()
        messages.append(ChatMessage(text: cleanText, isUser: true, fromVoice: fromVoice))
        isSending = true

        Task {
            do {
                let result = try await APIService.shared.sendCommand(cleanText)
                messages.append(
                    ChatMessage(text: result.response, isUser: false, agent: result.agent)
                )
                isSending = false
                voice.speak(result.response)
                await onResponse?()
            } catch {
                print("❌ Error enviando comando: \(error)")
                isSending = false
                messages.append(
                    ChatMessage(
                        text: "No pude conectarme con el servidor. Verifica que el backend esté encendido y que Tailscale esté activo.",
                        isUser: false,
                        isError: true
                    )
                )
            }
        }
    }

    // MARK: - Voice

    func toggleRecording() {
        if voice.isRecording {
            finishRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard !isSending else { return }
        voice.stopSpeaking()
        draft = ""
        levelHistory = Array(repeating: 0, count: levelHistory.count)
        Task { await voice.startRecording() }
    }

    /// Detiene la grabación y envía la transcripción automáticamente.
    func finishRecording() {
        Task {
            let text = await voice.stopRecordingAndGetText()
            send(text, fromVoice: true)
        }
    }

    /// Detiene la grabación descartando lo dicho.
    func cancelRecording() {
        Task {
            _ = await voice.stopRecordingAndGetText()
            draft = ""
        }
    }

    func replay(_ message: ChatMessage) {
        voice.speak(message.text)
    }

    func clear() {
        voice.stopSpeaking()
        messages.removeAll()
        draft = ""
    }
}
