import SwiftUI

struct GutiChatView: View {

    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var chat: ChatSession

    @FocusState private var isTextFieldFocused: Bool

    private let suggestions: [(text: String, agent: String)] = [
        ("¿Cuánto dinero me queda disponible para salir este fin de semana?", "financial"),
        ("Revisa si el decano me respondió el correo", "secretary"),
        ("¿Cuánto me queda para el fin de semana y qué tareas tengo pendientes?", "multi-agent"),
        ("¿Cómo están mis tarjetas de crédito?", "financial")
    ]

    var body: some View {

        VStack(spacing: 0) {

            header

            if chat.messages.isEmpty {
                welcomeView
            } else {
                messagesView
            }

            inputArea
        }
        .background(Color.appBackground)
        .task {
            await chat.voice.requestPermissions()
        }
        .sensoryFeedback(trigger: chat.phase) { old, new in
            switch (old, new) {
            case (_, .listening): return .start
            case (.listening, _): return .stop
            case (.thinking, .speaking), (.thinking, .idle): return .success
            default: return nil
            }
        }
    }

    // MARK: - Header

    private var header: some View {

        HStack(spacing: 12) {

            GutiOrb(phase: chat.phase, level: chat.voice.audioLevel, size: 46)

            VStack(alignment: .leading, spacing: 3) {

                Text("GUTI")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.white)

                Text(phaseSubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(chat.phase == .idle ? Color.grayGuti : phaseColor)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: chat.phase)
            }

            Spacer()

            ConnectionBadge(state: appStore.connection)

            if !chat.messages.isEmpty {

                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        chat.clear()
                    }
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.grayGuti)
                        .frame(width: 38, height: 38)
                        .background(Color.cardGuti)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Nueva conversación")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var phaseSubtitle: String {
        switch chat.phase {
        case .idle: return "Asistente personal"
        case .listening: return "Escuchando…"
        case .thinking: return "Consultando a los agentes…"
        case .speaking: return "Respondiendo en voz alta"
        }
    }

    private var phaseColor: Color {
        switch chat.phase {
        case .listening: return .pinkGuti
        case .thinking: return .purpleGuti
        default: return .cyanGuti
        }
    }

    // MARK: - Welcome

    private var welcomeView: some View {

        ScrollView {

            VStack(spacing: 26) {

                Spacer(minLength: 16)

                Button {
                    chat.toggleRecording()
                } label: {
                    GutiOrb(phase: chat.phase, level: chat.voice.audioLevel, size: 128)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hablar con GUTI")

                VStack(spacing: 8) {

                    Text("Hola, soy GUTI")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Toca el micrófono y pregúntame por tus finanzas, correos, tareas o agenda.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.grayGuti)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }

                VStack(alignment: .leading, spacing: 10) {

                    Text("PRUEBA DECIR")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.grayGuti)
                        .padding(.leading, 4)

                    ForEach(suggestions, id: \.text) { suggestion in
                        suggestionButton(suggestion.text, agent: suggestion.agent)
                    }
                }

                Spacer(minLength: 20)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func suggestionButton(_ text: String, agent: String) -> some View {

        Button {
            chat.send(text)
        } label: {

            HStack(alignment: .center, spacing: 12) {

                AgentStyle(agent).icon
                    .frame(width: 30, height: 30)
                    .background(AgentStyle(agent).color.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 9))

                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 4)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.cyanGuti)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.cardGuti)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(chat.phase == .thinking || chat.phase == .listening)
    }

    // MARK: - Messages

    private var messagesView: some View {

        ScrollViewReader { proxy in

            ScrollView {

                LazyVStack(spacing: 16) {

                    ForEach(chat.messages) { message in
                        MessageRow(message: message) {
                            chat.replay(message)
                        }
                        .id(message.id)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if chat.phase == .thinking {
                        ThinkingIndicator()
                            .id("thinking")
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .animation(.easeOut(duration: 0.25), value: chat.messages)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.messages.count) { _, _ in
                if let last = chat.messages.last {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: chat.phase) { _, phase in
                if phase == .thinking {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo("thinking", anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Input

    private var inputArea: some View {

        VStack(spacing: 10) {

            if chat.phase == .listening {
                listeningPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 10) {

                HStack(spacing: 8) {

                    TextField("Escribe o habla con GUTI…", text: $chat.draft, axis: .vertical)
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .lineLimit(1...4)
                        .focused($isTextFieldFocused)
                        .submitLabel(.send)
                        .disabled(chat.phase == .listening)
                        .onSubmit { chat.send(chat.draft) }

                    if canSendText {
                        Button {
                            chat.send(chat.draft)
                            isTextFieldFocused = false
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.appBackground)
                                .frame(width: 32, height: 32)
                                .background(Color.cyanGuti)
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Enviar")
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, 7)
                .padding(.vertical, 7)
                .frame(minHeight: 50)
                .background(Color.cardGuti)
                .overlay(
                    RoundedRectangle(cornerRadius: 25)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 25))

                micButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.appBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 1)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: chat.phase)
    }

    private var canSendText: Bool {
        chat.phase != .listening
            && chat.phase != .thinking
            && !chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var listeningPanel: some View {

        VStack(alignment: .leading, spacing: 12) {

            HStack(spacing: 8) {

                Circle()
                    .fill(Color.pinkGuti)
                    .frame(width: 8, height: 8)
                    .shadow(color: Color.pinkGuti.opacity(0.8), radius: 4)

                Text("ESCUCHANDO")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.pinkGuti)

                Spacer()

                Button("Cancelar") {
                    chat.cancelRecording()
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.grayGuti)
            }

            Text(chat.draft.isEmpty ? "Habla ahora…" : chat.draft)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(chat.draft.isEmpty ? Color.grayGuti : .white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: 0.15), value: chat.draft)

            WaveformView(levels: chat.levelHistory)
                .frame(height: 34)

            Text("Toca el botón rojo para enviar")
                .font(.system(size: 11))
                .foregroundStyle(Color.grayGuti.opacity(0.8))
        }
        .padding(16)
        .background(Color.cardGuti)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.pinkGuti.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var micButton: some View {

        Button {
            switch chat.phase {
            case .speaking: chat.voice.stopSpeaking()
            default: chat.toggleRecording()
            }
        } label: {

            ZStack {

                if chat.phase == .listening {
                    Circle()
                        .fill(Color.pinkGuti.opacity(0.25))
                        .frame(width: 50, height: 50)
                        .scaleEffect(1 + CGFloat(chat.voice.audioLevel) * 0.45)
                        .animation(.easeOut(duration: 0.12), value: chat.voice.audioLevel)
                }

                Circle()
                    .fill(micBackground)
                    .frame(width: 50, height: 50)
                    .shadow(color: micShadow, radius: 10)

                if chat.phase == .thinking {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: micIcon)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(chat.phase == .thinking)
        .accessibilityLabel(micAccessibilityLabel)
    }

    private var micIcon: String {
        switch chat.phase {
        case .listening: return "stop.fill"
        case .speaking: return "speaker.slash.fill"
        default: return "mic.fill"
        }
    }

    private var micBackground: AnyShapeStyle {
        switch chat.phase {
        case .listening:
            return AnyShapeStyle(Color.pinkGuti)
        case .speaking:
            return AnyShapeStyle(Color.purpleGuti)
        default:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.cyanGuti, Color.purpleGuti],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    private var micShadow: Color {
        switch chat.phase {
        case .listening: return Color.pinkGuti.opacity(0.5)
        case .thinking: return .clear
        default: return Color.cyanGuti.opacity(0.35)
        }
    }

    private var micAccessibilityLabel: String {
        switch chat.phase {
        case .listening: return "Terminar y enviar"
        case .speaking: return "Silenciar a GUTI"
        default: return "Hablar con GUTI"
        }
    }
}

// MARK: - Agent Style

/// Presentación de cada agente del orquestador (color, icono y nombre).
struct AgentStyle {

    let name: String
    let symbol: String
    let color: Color

    init(_ agent: String?) {
        switch agent {
        case "financial":
            (name, symbol, color) = ("Finanzas", "wallet.pass.fill", .cyanGuti)
        case "secretary":
            (name, symbol, color) = ("Secretaría", "tray.full.fill", .purpleGuti)
        case "agenda":
            (name, symbol, color) = ("Agenda", "calendar", .purpleGuti)
        case "multi-agent":
            (name, symbol, color) = ("Multi-agente", "point.3.connected.trianglepath.dotted", .pinkGuti)
        default:
            (name, symbol, color) = ("GUTI", "sparkles", .grayGuti)
        }
    }

    var icon: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(color)
    }
}

// MARK: - Message Row

private struct MessageRow: View {

    let message: ChatMessage
    let onReplay: () -> Void

    var body: some View {

        HStack(alignment: .bottom) {

            if message.isUser { Spacer(minLength: 50) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 6) {

                if !message.isUser && !message.isError {
                    agentChip
                }

                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .background(bubbleColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(borderColor, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                HStack(spacing: 8) {

                    if message.fromVoice {
                        Image(systemName: "waveform")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.cyanGuti.opacity(0.8))
                    }

                    Text(message.date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "es_CO"))))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.grayGuti.opacity(0.7))

                    if !message.isUser && !message.isError {
                        Button(action: onReplay) {
                            Label("Escuchar", systemImage: "speaker.wave.2.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.grayGuti)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
            }

            if !message.isUser { Spacer(minLength: 50) }
        }
    }

    private var agentChip: some View {
        let style = AgentStyle(message.agent)
        return HStack(spacing: 5) {
            Image(systemName: style.symbol)
                .font(.system(size: 10, weight: .bold))
            Text(style.name.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(style.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(style.color.opacity(0.12))
        .clipShape(Capsule())
    }

    private var bubbleColor: Color {
        if message.isUser { return Color.cyanGuti.opacity(0.18) }
        if message.isError { return Color.pinkGuti.opacity(0.12) }
        return Color.cardGuti
    }

    private var borderColor: Color {
        if message.isUser { return Color.cyanGuti.opacity(0.25) }
        if message.isError { return Color.pinkGuti.opacity(0.3) }
        return Color.white.opacity(0.05)
    }
}

// MARK: - Thinking Indicator

private struct ThinkingIndicator: View {

    var body: some View {

        HStack {

            HStack(spacing: 10) {

                TimelineView(.animation(minimumInterval: 0.2)) { context in
                    let step = Int(context.date.timeIntervalSinceReferenceDate * 3) % 3
                    HStack(spacing: 5) {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .fill(Color.purpleGuti)
                                .frame(width: 7, height: 7)
                                .opacity(index == step ? 1 : 0.3)
                        }
                    }
                }

                Text("Consultando a los agentes")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.grayGuti)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(Color.cardGuti)
            .clipShape(RoundedRectangle(cornerRadius: 18))

            Spacer()
        }
    }
}

// MARK: - Waveform

private struct WaveformView: View {

    let levels: [Float]

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 3) {
                ForEach(levels.indices, id: \.self) { index in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.pinkGuti, Color.purpleGuti],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: max(4, geometry.size.height * CGFloat(levels[index])))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
            .animation(.easeOut(duration: 0.1), value: levels)
        }
    }
}

// MARK: - Orb

/// Avatar de GUTI que refleja el estado de la conversación.
struct GutiOrb: View {

    let phase: ChatSession.Phase
    let level: Float
    let size: CGFloat

    @State private var breathe = false

    var body: some View {

        ZStack {

            Circle()
                .fill(glowColor.opacity(0.18))
                .scaleEffect(phase == .listening ? 1 + CGFloat(level) * 0.35 : (breathe ? 1.08 : 0.96))
                .animation(.easeOut(duration: 0.12), value: level)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.purpleGuti.opacity(0.35), Color.cyanGuti.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(size * 0.1)
                .overlay(
                    Circle()
                        .stroke(glowColor.opacity(0.4), lineWidth: 1)
                        .padding(size * 0.1)
                )

            Image(systemName: symbol)
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundStyle(glowColor)
                .symbolEffect(.variableColor.iterative, isActive: phase == .speaking || phase == .thinking)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }

    private var symbol: String {
        switch phase {
        case .idle: return "sparkles"
        case .listening: return "mic.fill"
        case .thinking: return "ellipsis"
        case .speaking: return "waveform"
        }
    }

    private var glowColor: Color {
        switch phase {
        case .idle: return .purpleGuti
        case .listening: return .pinkGuti
        case .thinking: return .purpleGuti
        case .speaking: return .cyanGuti
        }
    }
}

// MARK: - Connection Badge

/// Estado de conexión con el backend (vía Tailscale).
struct ConnectionBadge: View {

    let state: AppStore.ConnectionState

    var body: some View {

        HStack(spacing: 6) {

            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.7), radius: 4)

            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch state {
        case .checking: return .grayGuti
        case .online: return .cyanGuti
        case .offline: return .pinkGuti
        }
    }

    private var label: String {
        switch state {
        case .checking: return "…"
        case .online: return "ONLINE"
        case .offline: return "OFFLINE"
        }
    }
}

// MARK: - Preview

#Preview {
    GutiChatView()
        .environmentObject(AppStore())
        .environmentObject(ChatSession())
        .preferredColorScheme(.dark)
}
