import Foundation
import Combine
import AVFoundation
import Speech

@MainActor
final class VoiceService: NSObject, ObservableObject {

    // MARK: - Published

    @Published var isRecording = false
    @Published var recognizedText = ""
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var speechAvailable = false

    // MARK: - Audio

    private let audioEngine = AVAudioEngine()
    private let speechSynthesizer = AVSpeechSynthesizer()

    private var audioConverter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?

    // MARK: - Speech

    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?

    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var inputStream: AsyncStream<AnalyzerInput>?

    private var resultsTask: Task<Void, Never>?
    private var analyzerTask: Task<Void, Never>?

    // MARK: - Text

    private var finalizedText = ""
    private var volatileText = ""

    // MARK: - Init

    override init() {
        super.init()

        speechSynthesizer.delegate = self

        authorizationStatus = SFSpeechRecognizer.authorizationStatus()

        print("🎤 GUTI VoiceService iniciado.")
        print("🎤 Autorización de voz: \(authorizationStatusDescription)")
        print("🎤 SpeechTranscriber disponible: \(SpeechTranscriber.isAvailable)")
    }

    // MARK: - Permissions

    func requestPermissions() async {

        print("🔐 Solicitando permisos de voz...")

        let microphoneGranted = await requestMicrophonePermission()

        print("🎙️ Permiso de micrófono: \(microphoneGranted)")

        guard microphoneGranted else {
            print("❌ Permiso de micrófono rechazado.")
            return
        }

        let speechStatus = await requestSpeechPermission()

        authorizationStatus = speechStatus

        print("🔎 Estado reconocimiento: \(speechStatus)")
        print("🎤 SpeechTranscriber disponible: \(SpeechTranscriber.isAvailable)")

        speechAvailable =
            speechStatus == .authorized &&
            SpeechTranscriber.isAvailable
    }

    private func requestMicrophonePermission() async -> Bool {

        await withCheckedContinuation { continuation in

            AVAudioApplication.requestRecordPermission { granted in

                continuation.resume(
                    returning: granted
                )
            }
        }
    }

    private func requestSpeechPermission()
        async -> SFSpeechRecognizerAuthorizationStatus {

        await withCheckedContinuation { continuation in

            SFSpeechRecognizer.requestAuthorization { status in

                continuation.resume(
                    returning: status
                )
            }
        }
    }

    // MARK: - Start Recording

    func startRecording() async {

        guard !isRecording else {
            print("⚠️ Ya hay una grabación activa.")
            return
        }

        print("🎙️ Preparando grabación...")

        if authorizationStatus != .authorized {

            await requestPermissions()

            guard authorizationStatus == .authorized else {

                print(
                    "❌ El reconocimiento de voz no está autorizado."
                )

                return
            }
        }

        guard SpeechTranscriber.isAvailable else {

            print(
                "❌ SpeechTranscriber no está disponible."
            )

            speechAvailable = false

            return
        }

        do {

            recognizedText = ""
            finalizedText = ""
            volatileText = ""

            try await prepareSpeechAnalyzer()

            try startAudioCapture()

            isRecording = true

            print(
                "🎙️ GRABACIÓN INICIADA CORRECTAMENTE."
            )

        } catch {

            print(
                "❌ Error iniciando grabación: \(error)"
            )

            await stopRecordingInternal()
        }
    }

    // MARK: - Prepare Speech Analyzer

    private func prepareSpeechAnalyzer() async throws {

        print("🔎 Buscando idioma compatible...")

        let locale: Locale

        let installedLocales =
            await SpeechTranscriber.installedLocales

        if let esUS = installedLocales.first(
            where: {
                $0.identifier == "es-US"
            }
        ) {

            locale = esUS

        } else if let esCO = installedLocales.first(
            where: {
                $0.identifier == "es-CO"
            }
        ) {

            locale = esCO

        } else {

            locale = Locale(
                identifier: "es-US"
            )
        }

        print(
            "🌎 Idioma seleccionado: \(locale.identifier)"
        )

        // MARK: SpeechTranscriber

        print(
            "🧠 Creando SpeechTranscriber..."
        )

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )

        self.transcriber = transcriber

        print(
            "🧠 SpeechTranscriber creado."
        )

        guard SpeechTranscriber.isAvailable else {

            throw VoiceError.transcriberUnavailable
        }

        // MARK: Model

        let currentInstalledLocales =
            await SpeechTranscriber.installedLocales

        let modelAlreadyInstalled =
            currentInstalledLocales.contains(
                where: {
                    $0.identifier == locale.identifier
                }
            )

        if modelAlreadyInstalled {

            print(
                "✅ Modelo de \(locale.identifier) ya está instalado."
            )

        } else {

            print(
                "⬇️ El modelo de \(locale.identifier) no está instalado."
            )

            print(
                "⬇️ Solicitando instalación del modelo..."
            )

            if let installationRequest =
                try await AssetInventory.assetInstallationRequest(
                    supporting: [transcriber]
                ) {

                try await installationRequest.downloadAndInstall()

                print(
                    "✅ Modelo instalado correctamente."
                )

            } else {

                print(
                    "⚠️ No fue necesario instalar ningún modelo."
                )
            }
        }

        // MARK: SpeechAnalyzer

        print(
            "🧠 Configurando SpeechAnalyzer..."
        )

        let analyzer =
            SpeechAnalyzer(
                modules: [transcriber]
            )

        self.analyzer = analyzer

        print(
            "🧠 SpeechAnalyzer creado correctamente."
        )

        // MARK: Audio Format

        guard let format =
            await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [transcriber]
            )
        else {

            throw VoiceError.audioFormatUnavailable
        }

        self.analyzerFormat = format

        print(
            "🎵 Formato requerido por SpeechAnalyzer:"
        )

        print(format)

        // MARK: AsyncStream

        let stream =
            AsyncStream<AnalyzerInput>.makeStream()

        self.inputStream = stream.stream
        self.inputBuilder = stream.continuation

        // MARK: Results

        resultsTask = Task {

            guard let transcriber = self.transcriber else {

                print(
                    "❌ SpeechTranscriber no disponible."
                )

                return
            }

            print(
                "📝 Task de resultados iniciada."
            )

            do {

                for try await result in transcriber.results {

                    if Task.isCancelled {
                        break
                    }

                    let text =
                        String(
                            result.text.characters
                        )

                    if result.isFinal {

                        self.finalizedText = text
                        self.volatileText = ""

                        self.recognizedText = text

                        print(
                            "📝 Texto FINAL: \(text)"
                        )

                    } else {

                        self.volatileText = text

                        let combinedText: String

                        if self.finalizedText.isEmpty {

                            combinedText =
                                self.volatileText

                        } else {

                            combinedText =
                                self.finalizedText +
                                " " +
                                self.volatileText
                        }

                        self.recognizedText =
                            combinedText

                        print(
                            "📝 Texto PARCIAL: \(combinedText)"
                        )
                    }
                }

                print(
                    "📝 Finalizó la lectura de resultados."
                )

            } catch {

                print(
                    "❌ Error leyendo resultados: \(error)"
                )
            }
        }

        // MARK: Start Analyzer

        guard let inputStream = self.inputStream else {

            throw VoiceError.analyzerUnavailable
        }

        analyzerTask = Task {

            do {

                try await analyzer.start(
                    inputSequence: inputStream
                )

                print(
                    "🧠 SpeechAnalyzer iniciado correctamente."
                )

            } catch {

                print(
                    "❌ Error iniciando SpeechAnalyzer: \(error)"
                )
            }
        }

        try? await Task.sleep(
            nanoseconds: 150_000_000
        )
    }

    // MARK: - Audio Capture

    private func startAudioCapture() throws {

        guard let analyzerFormat = self.analyzerFormat else {

            throw VoiceError.audioFormatUnavailable
        }

        let audioSession =
            AVAudioSession.sharedInstance()

        try audioSession.setCategory(
            .record,
            mode: .measurement,
            options: [.duckOthers]
        )

        try audioSession.setActive(
            true,
            options: .notifyOthersOnDeactivation
        )

        let inputNode =
            audioEngine.inputNode

        let microphoneFormat =
            inputNode.outputFormat(
                forBus: 0
            )

        print(
            "🎙️ Formato del micrófono:"
        )

        print(
            microphoneFormat
        )

        print(
            "🧠 Formato requerido:"
        )

        print(
            analyzerFormat
        )

        guard let converter =
            AVAudioConverter(
                from: microphoneFormat,
                to: analyzerFormat
            )
        else {

            throw VoiceError.converterUnavailable
        }

        self.audioConverter = converter

        inputNode.removeTap(
            onBus: 0
        )

        inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: microphoneFormat
        ) { [weak self] buffer, _ in

            guard let self else {
                return
            }

            guard let converter = self.audioConverter else {
                return
            }

            guard let inputBuilder = self.inputBuilder else {
                return
            }

            let outputFrameCount =
                AVAudioFrameCount(
                    ceil(
                        Double(buffer.frameLength) *
                        analyzerFormat.sampleRate /
                        microphoneFormat.sampleRate
                    )
                )

            guard outputFrameCount > 0 else {
                return
            }

            guard let convertedBuffer =
                AVAudioPCMBuffer(
                    pcmFormat: analyzerFormat,
                    frameCapacity: outputFrameCount
                )
            else {

                print(
                    "❌ No se pudo crear buffer convertido."
                )

                return
            }

            let state =
                ConverterInputState(
                    buffer: buffer
                )

            var conversionError: NSError?

            let status =
                converter.convert(
                    to: convertedBuffer,
                    error: &conversionError
                ) { _, outStatus in

                    if state.didProvideInput {

                        outStatus.pointee =
                            .noDataNow

                        return nil
                    }

                    state.didProvideInput = true

                    outStatus.pointee =
                        .haveData

                    return state.buffer
                }

            if let conversionError {

                print(
                    "❌ Error de conversión: \(conversionError)"
                )

                return
            }

            guard status == .haveData ||
                    status == .inputRanDry else {

                print(
                    "⚠️ Conversión terminó con estado: \(status)"
                )

                return
            }

            guard convertedBuffer.frameLength > 0 else {
                return
            }

            let analyzerInput =
                AnalyzerInput(
                    buffer: convertedBuffer
                )

            let result =
                inputBuilder.yield(
                    analyzerInput
                )

            print(
                "📤 Audio enviado al SpeechAnalyzer: \(result)"
            )
        }

        audioEngine.prepare()

        try audioEngine.start()

        print(
            "🎙️ GRABACIÓN DE AUDIO INICIADA."
        )
    }

    // MARK: - Stop Recording

    func stopRecording() {

        guard isRecording else {

            print(
                "⚠️ No hay una grabación activa."
            )

            return
        }

        Task {

            _ = await stopRecordingAndGetText()
        }
    }

    // MARK: - Stop And Get Text

    func stopRecordingAndGetText() async -> String {

        guard isRecording else {

            return recognizedText
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
        }

        await stopRecordingInternal()

        return recognizedText
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
    }

    // MARK: - Internal Stop

    private func stopRecordingInternal() async {

        isRecording = false

        print(
            "🎙️ Deteniendo grabación..."
        )

        audioEngine.stop()

        audioEngine.inputNode.removeTap(
            onBus: 0
        )

        audioConverter = nil

        print(
            "🛑 Finalizando entrada de audio..."
        )

        inputBuilder?.finish()

        inputBuilder = nil

        do {

            try await analyzer?
                .finalizeAndFinishThroughEndOfInput()

            print(
                "🧠 SpeechAnalyzer finalizó correctamente."
            )

        } catch {

            print(
                "❌ Error finalizando SpeechAnalyzer: \(error)"
            )
        }

        print(
            "⏳ Esperando resultado final de transcripción..."
        )

        if let resultsTask {

            await resultsTask.value
        }

        print(
            "✅ Resultado final procesado."
        )

        do {

            try AVAudioSession.sharedInstance()
                .setActive(
                    false,
                    options: .notifyOthersOnDeactivation
                )

        } catch {

            print(
                "⚠️ No se pudo desactivar AVAudioSession: \(error)"
            )
        }

        analyzerTask?.cancel()
        analyzerTask = nil

        resultsTask = nil

        analyzer = nil
        transcriber = nil

        inputStream = nil
        analyzerFormat = nil

        print(
            "🎙️ Grabación detenida."
        )

        print(
            "📝 Texto obtenido:"
        )

        print(
            recognizedText
        )
    }

    // MARK: - Text To Speech

    func speak(_ text: String) {

        let cleanText =
            text.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !cleanText.isEmpty else {
            return
        }

        print("🔊 Preparando respuesta de voz...")
        print("🔊 Texto: \(cleanText)")

        do {

            let audioSession =
                AVAudioSession.sharedInstance()

            // Cambiamos de modo grabación a reproducción.
            try audioSession.setCategory(
                .playAndRecord,
                mode: .spokenAudio,
                options: [
                    .defaultToSpeaker,
                    .allowBluetoothHFP
                ]
            )

            try audioSession.setActive(
                true,
                options: .notifyOthersOnDeactivation
            )

            print("🔊 AVAudioSession configurada para reproducción.")

        } catch {

            print(
                "❌ Error configurando audio para reproducción: \(error)"
            )
        }

        speechSynthesizer.stopSpeaking(
            at: .immediate
        )

        let utterance =
            AVSpeechUtterance(
                string: cleanText
            )

        // Velocidad natural para la demo.
        utterance.rate = 0.50

        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        // Voz colombiana si está disponible.
        if let voice =
            AVSpeechSynthesisVoice(
                language: "es-CO"
            ) {

            utterance.voice = voice

            print("🔊 Voz seleccionada: es-CO")

        } else if let voice =
                    AVSpeechSynthesisVoice(
                        language: "es-US"
                    ) {

            utterance.voice = voice

            print("🔊 Voz seleccionada: es-US")

        } else if let voice =
                    AVSpeechSynthesisVoice(
                        language: "es"
                    ) {

            utterance.voice = voice

            print("🔊 Voz seleccionada: es")

        } else {

            print(
                "⚠️ No se encontró una voz española específica."
            )
        }

        speechSynthesizer.speak(
            utterance
        )

        print("🔊 GUTI envió el texto al sintetizador.")
    }

    func stopSpeaking() {

        speechSynthesizer.stopSpeaking(
            at: .immediate
        )

        print("🔇 GUTI detuvo la reproducción.")
    }

    // MARK: - Authorization

    private var authorizationStatusDescription: String {

        switch authorizationStatus {

        case .authorized:
            return "authorized"

        case .denied:
            return "denied"

        case .restricted:
            return "restricted"

        case .notDetermined:
            return "notDetermined"

        @unknown default:
            return "unknown"
        }
    }
}

// MARK: - Converter Input State

private final class ConverterInputState: @unchecked Sendable {

    let buffer: AVAudioPCMBuffer?
    var didProvideInput = false

    init(buffer: AVAudioPCMBuffer?) {
        self.buffer = buffer
    }
}

// MARK: - Errors

enum VoiceError: LocalizedError {

    case transcriberUnavailable
    case converterUnavailable
    case analyzerUnavailable
    case audioFormatUnavailable
    case microphoneUnavailable

    var errorDescription: String? {

        switch self {

        case .transcriberUnavailable:
            return "SpeechTranscriber no está disponible."

        case .converterUnavailable:
            return "No se pudo crear el convertidor de audio."

        case .analyzerUnavailable:
            return "SpeechAnalyzer no está disponible."

        case .audioFormatUnavailable:
            return "No se pudo obtener el formato de audio."

        case .microphoneUnavailable:
            return "El micrófono no está disponible."
        }
    }
}

// MARK: - Speech Synthesizer Delegate

extension VoiceService: AVSpeechSynthesizerDelegate {

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {

        print(
            "🔊 GUTI comenzó a hablar."
        )
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {

        print(
            "🔊 GUTI terminó de hablar."
        )
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {

        print(
            "🔇 GUTI dejó de hablar."
        )
    }
}
