import SwiftUI

struct GutiChatView: View {

    @EnvironmentObject private var appStore: AppStore
    @StateObject private var voiceService = VoiceService()

    @State private var messageText = ""
    @State private var messages: [ChatMessage] = []
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {

        VStack(spacing: 0) {

            header

            if messages.isEmpty {

                welcomeView

            } else {

                messagesView
            }

            if let errorMessage {

                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
            }

            inputArea
        }
        .background(Color.appBackground)
        .onAppear {

            Task {
                await voiceService.requestPermissions()
            }
        }
        .onChange(
            of: voiceService.recognizedText
        ) { _, newValue in

            guard !newValue.isEmpty else {
                return
            }

            messageText = newValue
        }
    }

    // MARK: - Header

    private var header: some View {

        HStack(spacing: 12) {

            ZStack {

                Circle()
                    .fill(
                        Color.purpleGuti.opacity(0.18)
                    )
                    .frame(
                        width: 46,
                        height: 46
                    )

                Image(systemName: "sparkles")
                    .font(
                        .system(
                            size: 21,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        Color.purpleGuti
                    )
            }

            VStack(
                alignment: .leading,
                spacing: 3
            ) {

                Text("GUTI")
                    .font(
                        .system(
                            size: 21,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(.white)

                Text("Asistente personal")
                    .font(
                        .system(size: 13)
                    )
                    .foregroundStyle(
                        Color.grayGuti
                    )
            }

            Spacer()

            Circle()
                .fill(
                    Color.cyanGuti
                )
                .frame(
                    width: 9,
                    height: 9
                )
                .shadow(
                    color: Color.cyanGuti.opacity(0.7),
                    radius: 5
                )
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    // MARK: - Welcome

    private var welcomeView: some View {

        ScrollView {

            VStack(spacing: 24) {

                Spacer(
                    minLength: 30
                )

                ZStack {

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.purpleGuti.opacity(0.22),
                                    Color.cyanGuti.opacity(0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(
                            width: 110,
                            height: 110
                        )

                    Image(systemName: "sparkles")
                        .font(
                            .system(
                                size: 45,
                                weight: .medium
                            )
                        )
                        .foregroundStyle(
                            Color.purpleGuti
                        )
                }

                VStack(spacing: 8) {

                    Text("Hola, soy GUTI")
                        .font(
                            .system(
                                size: 28,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(.white)

                    Text(
                        "Tu asistente personal inteligente"
                    )
                    .font(
                        .system(size: 16)
                    )
                    .foregroundStyle(
                        Color.grayGuti
                    )
                    .multilineTextAlignment(.center)
                }

                VStack(spacing: 10) {

                    suggestionButton(
                        "¿Cuánto he gastado este mes?"
                    )

                    suggestionButton(
                        "¿Qué tareas tengo pendientes?"
                    )

                    suggestionButton(
                        "¿Qué tengo en mi agenda?"
                    )
                }

                Spacer(
                    minLength: 30
                )
            }
            .frame(
                maxWidth: .infinity
            )
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Messages

    private var messagesView: some View {

        ScrollViewReader { proxy in

            ScrollView {

                LazyVStack(spacing: 14) {

                    ForEach(messages) { message in

                        messageBubble(message)
                            .id(message.id)
                    }

                    if isSending {

                        typingIndicator
                            .id("typing")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .onChange(
                of: messages.count
            ) { _, _ in

                if let lastMessage =
                    messages.last {

                    withAnimation(
                        .easeOut(
                            duration: 0.25
                        )
                    ) {

                        proxy.scrollTo(
                            lastMessage.id,
                            anchor: .bottom
                        )
                    }
                }
            }
            .onChange(
                of: isSending
            ) { _, sending in

                if sending {

                    withAnimation(
                        .easeOut(
                            duration: 0.25
                        )
                    ) {

                        proxy.scrollTo(
                            "typing",
                            anchor: .bottom
                        )
                    }
                }
            }
        }
    }

    // MARK: - Message Bubble

    private func messageBubble(
        _ message: ChatMessage
    ) -> some View {

        HStack {

            if message.isUser {

                Spacer(
                    minLength: 50
                )
            }

            VStack(
                alignment:
                    message.isUser
                    ? .trailing
                    : .leading,
                spacing: 5
            ) {

                Text(message.text)
                    .font(
                        .system(size: 15)
                    )
                    .foregroundStyle(.white)
                    .padding(
                        .horizontal,
                        15
                    )
                    .padding(
                        .vertical,
                        11
                    )
                    .background(
                        message.isUser
                        ? Color.cyanGuti.opacity(0.18)
                        : Color.cardGuti
                    )
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: 18
                        )
                        .stroke(
                            message.isUser
                            ? Color.cyanGuti.opacity(0.25)
                            : Color.white.opacity(0.05),
                            lineWidth: 1
                        )
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 18
                        )
                    )

                Text(
                    message.date.formattedTime
                )
                .font(
                    .system(size: 10)
                )
                .foregroundStyle(
                    Color.grayGuti.opacity(0.7)
                )
            }

            if !message.isUser {

                Spacer(
                    minLength: 50
                )
            }
        }
    }

    // MARK: - Typing

    private var typingIndicator: some View {

        HStack {

            HStack(spacing: 5) {

                Circle()
                    .frame(
                        width: 7,
                        height: 7
                    )

                Circle()
                    .frame(
                        width: 7,
                        height: 7
                    )

                Circle()
                    .frame(
                        width: 7,
                        height: 7
                    )
            }
            .foregroundStyle(
                Color.grayGuti
            )
            .padding(
                .horizontal,
                17
            )
            .padding(
                .vertical,
                14
            )
            .background(
                Color.cardGuti
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 18
                )
            )

            Spacer()
        }
    }

    // MARK: - Suggestion

    private func suggestionButton(
        _ text: String
    ) -> some View {

        Button {

            messageText = text

            sendMessage(
                text: text
            )

        } label: {

            HStack {

                Text(text)
                    .font(
                        .system(size: 14)
                    )
                    .foregroundStyle(.white)

                Spacer()

                Image(
                    systemName: "arrow.up.right"
                )
                .font(
                    .system(
                        size: 13,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    Color.cyanGuti
                )
            }
            .padding(
                .horizontal,
                16
            )
            .padding(
                .vertical,
                13
            )
            .background(
                Color.cardGuti
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: 14
                )
                .stroke(
                    Color.white.opacity(0.06),
                    lineWidth: 1
                )
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 14
                )
            )
        }
        .disabled(isSending)
    }

    // MARK: - Input

    private var inputArea: some View {

        VStack(spacing: 6) {

            if voiceService.isRecording {

                HStack(spacing: 7) {

                    Circle()
                        .fill(
                            Color.pinkGuti
                        )
                        .frame(
                            width: 8,
                            height: 8
                        )

                    Text(
                        "Escuchando... habla con GUTI"
                    )
                    .font(
                        .system(
                            size: 12,
                            weight: .medium
                        )
                    )
                    .foregroundStyle(
                        Color.pinkGuti
                    )

                    Spacer()

                    Text(
                        "Toca el micrófono para terminar"
                    )
                    .font(
                        .system(size: 10)
                    )
                    .foregroundStyle(
                        Color.grayGuti
                    )
                }
                .padding(
                    .horizontal,
                    16
                )
            }

            HStack(spacing: 10) {

                // MARK: Microphone

                Button {

                    toggleRecording()

                } label: {

                    ZStack {

                        Circle()
                            .fill(
                                voiceService.isRecording
                                ? Color.pinkGuti.opacity(0.18)
                                : Color.cardGuti
                            )
                            .frame(
                                width: 46,
                                height: 46
                            )

                        Image(
                            systemName:
                                voiceService.isRecording
                                ? "stop.fill"
                                : "mic.fill"
                        )
                        .font(
                            .system(
                                size: 18,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            voiceService.isRecording
                            ? Color.pinkGuti
                            : Color.cyanGuti
                        )
                    }
                }
                .disabled(isSending)

                // MARK: Text Field

                HStack(spacing: 8) {

                    TextField(
                        "Habla con GUTI...",
                        text: $messageText
                    )
                    .font(
                        .system(size: 15)
                    )
                    .foregroundStyle(.white)
                    .submitLabel(.send)
                    .onSubmit {

                        sendMessage(
                            text: messageText
                        )
                    }

                    if !messageText.isEmpty {

                        Button {

                            messageText = ""

                        } label: {

                            Image(
                                systemName:
                                    "xmark.circle.fill"
                            )
                            .foregroundStyle(
                                Color.grayGuti
                            )
                        }
                    }
                }
                .padding(
                    .horizontal,
                    14
                )
                .frame(
                    minHeight: 46
                )
                .background(
                    Color.cardGuti
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 16
                    )
                )

                // MARK: Send

                Button {

                    sendMessage(
                        text: messageText
                    )

                } label: {

                    ZStack {

                        Circle()
                            .fill(
                                messageText
                                    .trimmingCharacters(
                                        in: .whitespacesAndNewlines
                                    )
                                    .isEmpty
                                ? Color.cardGuti
                                : Color.cyanGuti
                            )
                            .frame(
                                width: 46,
                                height: 46
                            )

                        Image(
                            systemName: "arrow.up"
                        )
                        .font(
                            .system(
                                size: 18,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(
                            messageText
                                .trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                                .isEmpty
                            ? Color.grayGuti
                            : Color.appBackground
                        )
                    }
                }
                .disabled(
                    messageText
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        .isEmpty
                    || isSending
                    || voiceService.isRecording
                )
            }
        }
        .padding(
            .horizontal,
            14
        )
        .padding(
            .top,
            10
        )
        .padding(
            .bottom,
            10
        )
        .background(
            Color.appBackground
        )
        .overlay(
            alignment: .top
        ) {

            Rectangle()
                .fill(
                    Color.white.opacity(0.05)
                )
                .frame(
                    height: 1
                )
        }
    }

    // MARK: - Send Message

    private func sendMessage(
        text: String
    ) {

        let cleanText =
            text.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !cleanText.isEmpty else {
            return
        }

        guard !isSending else {
            return
        }

        messageText = ""
        errorMessage = nil

        let userMessage =
            ChatMessage(
                text: cleanText,
                isUser: true
            )

        messages.append(
            userMessage
        )

        isSending = true

        Task {

            do {

                print(
                    "📡 Enviando comando a GUTI: \(cleanText)"
                )

                let result =
                    try await APIService.shared.sendCommand(
                        cleanText
                    )

                print(
                    "🤖 Respuesta de GUTI: \(result.response)"
                )

                await MainActor.run {

                    let assistantMessage =
                        ChatMessage(
                            text: result.response,
                            isUser: false
                        )

                    messages.append(
                        assistantMessage
                    )

                    isSending = false

                    // GUTI habla automáticamente.

                    voiceService.speak(
                        result.response
                    )

                    // Refrescar datos en segundo plano
                    Task {
                        await appStore.refreshAll()
                    }
                }

            } catch {

                print(
                    "❌ Error enviando comando: \(error)"
                )

                await MainActor.run {

                    isSending = false

                    errorMessage =
                        error.localizedDescription

                    let errorChat =
                        ChatMessage(
                            text:
                                "No pude conectarme con el servidor. Verifica que el backend de GUTI esté funcionando.",
                            isUser: false
                        )

                    messages.append(
                        errorChat
                    )
                }
            }
        }
    }

    // MARK: - Voice

    private func toggleRecording() {

        if voiceService.isRecording {

            // -----------------------------------------------------
            // TERMINAR GRABACIÓN Y ENVIAR AUTOMÁTICAMENTE
            // -----------------------------------------------------

            Task {

                let text =
                    await voiceService
                    .stopRecordingAndGetText()

                let cleanText =
                    text.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )

                guard !cleanText.isEmpty else {

                    print(
                        "⚠️ No se obtuvo texto de la grabación."
                    )

                    return
                }

                print(
                    "🎤 Comando de voz terminado: \(cleanText)"
                )

                await MainActor.run {

                    sendMessage(
                        text: cleanText
                    )
                }
            }

        } else {

            // -----------------------------------------------------
            // INICIAR GRABACIÓN
            // -----------------------------------------------------

            messageText = ""

            errorMessage = nil

            Task {

                await voiceService.startRecording()
            }
        }
    }
}

// MARK: - Chat Message

private struct ChatMessage: Identifiable {

    let id = UUID()

    let text: String
    let isUser: Bool
    let date: Date

    init(
        text: String,
        isUser: Bool,
        date: Date = Date()
    ) {

        self.text = text
        self.isUser = isUser
        self.date = date
    }
}

// MARK: - Date Extension

private extension Date {

    var formattedTime: String {

        let formatter =
            DateFormatter()

        formatter.locale =
            Locale(
                identifier: "es_CO"
            )

        formatter.dateFormat =
            "HH:mm"

        return formatter.string(
            from: self
        )
    }
}

// MARK: - Preview

#Preview {

    GutiChatView()
        .environmentObject(
            AppStore()
        )
        .preferredColorScheme(
            .dark
        )
}
