import Foundation
import Testing
@testable import AirTranslate

@Suite(.serialized)
struct TranslationSessionStoreLanguageCandidateTests {
    @Test
    func supportedLanguageOrderIsUsedForAutoDetectionCandidateSelection() {
        let candidates = LanguageOption.prioritizedAutoDetectionCandidates(
            sourceLanguage: LanguageOption.korean,
            targetLanguage: LanguageOption.korean
        )

        #expect(candidates.first == LanguageOption.english)
    }

    @Test
    func targetLanguageIsExcludedFromAutoDetectionCandidates() {
        let candidates = LanguageOption.prioritizedAutoDetectionCandidates(
            sourceLanguage: LanguageOption.korean,
            targetLanguage: LanguageOption.english
        )

        #expect(!candidates.contains(LanguageOption.english))
    }

    @Test
    func targetLanguageIsExcludedWhenManualSourceMatchesTarget() {
        let candidates = LanguageOption.prioritizedAutoDetectionCandidates(
            sourceLanguage: LanguageOption.korean,
            targetLanguage: LanguageOption.korean
        )

        #expect(candidates.first == LanguageOption.english)
        #expect(!candidates.contains(LanguageOption.korean))
    }

    @Test
    func autoDetectionCandidatesIncludeAllNonTargetSupportedLanguagesInSourcePriorityOrder() {
        let candidates = LanguageOption.prioritizedAutoDetectionCandidates(
            sourceLanguage: LanguageOption.korean,
            targetLanguage: LanguageOption.english
        )
        let expected = LanguageOption.supported.filter { $0 != LanguageOption.english }

        #expect(candidates == expected)
        #expect(Set(candidates.map({ $0.id })) == Set(expected.map({ $0.id })))
    }

    @Test
    func everySupportedLanguageIsExcludedWhenItIsTheTarget() {
        for target in LanguageOption.supported {
            let candidates = LanguageOption.prioritizedAutoDetectionCandidates(
                sourceLanguage: LanguageOption.english,
                targetLanguage: target
            )

            #expect(!candidates.contains(target))
            #expect(candidates.count == LanguageOption.supported.count - 1)
        }
    }

    @Test
    func autoDetectionRequestsConfirmationForLanguageChangeAfterSilence() {
        let shouldConfirm = AutoDetectionLanguageChangePolicy.shouldRequestConfirmation(
            isAutoDetectionEnabled: true,
            activeLanguage: LanguageOption.english,
            detectedLanguage: LanguageOption.supported[2],
            confidence: 0.9,
            hadLongSilence: true,
            hasVisibleTranscript: true,
            minimumSwitchConfidence: 0.72
        )

        #expect(shouldConfirm)
    }

    @Test
    func autoDetectionDoesNotRequestConfirmationWithoutSilence() {
        let shouldConfirm = AutoDetectionLanguageChangePolicy.shouldRequestConfirmation(
            isAutoDetectionEnabled: true,
            activeLanguage: LanguageOption.english,
            detectedLanguage: LanguageOption.supported[2],
            confidence: 0.9,
            hadLongSilence: false,
            hasVisibleTranscript: true,
            minimumSwitchConfidence: 0.72
        )

        #expect(!shouldConfirm)
    }

    @Test
    func autoDetectionDoesNotRequestConfirmationForLowConfidenceSwitch() {
        let shouldConfirm = AutoDetectionLanguageChangePolicy.shouldRequestConfirmation(
            isAutoDetectionEnabled: true,
            activeLanguage: LanguageOption.english,
            detectedLanguage: LanguageOption.supported[2],
            confidence: 0.5,
            hadLongSilence: true,
            hasVisibleTranscript: true,
            minimumSwitchConfidence: 0.72
        )

        #expect(!shouldConfirm)
    }

    @Test
    func autoDetectionDoesNotRequestConfirmationForInitialLanguageDetection() {
        let shouldConfirm = AutoDetectionLanguageChangePolicy.shouldRequestConfirmation(
            isAutoDetectionEnabled: true,
            activeLanguage: nil,
            detectedLanguage: LanguageOption.supported[2],
            confidence: 0.9,
            hadLongSilence: true,
            hasVisibleTranscript: false,
            minimumSwitchConfidence: 0.72
        )

        #expect(!shouldConfirm)
    }

    @Test
    func longSessionCaptionLineTrimsDisplayOnly() {
        let text = (1...500)
            .map { "Live transcript line \($0) keeps accumulating during a long session." }
            .joined(separator: "\n")
        let line = CaptionLine(
            sourceText: text,
            translatedText: text,
            createdAt: Date(),
            isFinal: false,
            usesLongSessionDisplay: true
        )

        #expect(line.sourceText == text)
        #expect(line.translatedText == text)
        #expect(line.sourceDisplayText != text)
        #expect(line.translatedDisplayText != text)
        #expect(line.sourceDisplayText.hasPrefix("..."))
        #expect(line.translatedDisplayText.hasPrefix("..."))
    }

    @Test
    func veryLargeCaptionLineTrimsDisplayEvenInStandardMode() {
        let text = (1...500)
            .map { "Standard session can still receive a very long realtime transcript line \($0)." }
            .joined(separator: "\n")
        let line = CaptionLine(
            sourceText: text,
            translatedText: text,
            createdAt: Date(),
            isFinal: false
        )

        #expect(line.sourceText == text)
        #expect(line.translatedText == text)
        #expect(line.sourceDisplayText != text)
        #expect(line.translatedDisplayText != text)
        #expect(line.sourceDisplayText.hasPrefix("..."))
        #expect(line.translatedDisplayText.hasPrefix("..."))
    }

    @Test
    @MainActor
    func savedTranscriptContentsLoadOnlyWhenSelected() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirTranslateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let tailMarker = "TAIL_MARKER_AFTER_PREVIEW"
        let text = "Launch title\n"
            + String(repeating: "Preview filler keeps this saved transcript large.\n", count: 200)
            + tailMarker
        let fileURL = directory.appendingPathComponent("2026-06-13_Launch-title.txt")
        try text.write(to: fileURL, atomically: true, encoding: .utf8)

        let session = TranslationSessionStore(
            modelAvailabilityProvider: { _, _ in [:] },
            transcriptsDirectoryURL: directory
        )
        let transcript = try #require(session.savedTranscripts.first)

        #expect(transcript.title == "Launch title")
        #expect(!transcript.sourceText.contains(tailMarker))

        session.selectSavedTranscript(transcript.id)

        #expect(session.savedDraftSourceText.contains(tailMarker))
    }

    @Test
    @MainActor
    func transcribeOnlyModeHidesTranslationPane() {
        let session = TranslationSessionStore()

        session.selectedModel = .appleSpeechOnly
        #expect(!session.shouldShowTranslationPane)

        session.selectedModel = .appleSystem
        #expect(session.shouldShowTranslationPane)
    }

    @Test
    @MainActor
    func sameLanguagePairSwitchesToTranscribeOnlyMode() {
        let session = TranslationSessionStore()

        session.useAppleDefaultMode()
        session.sourceLanguage = LanguageOption.english
        session.targetLanguage = LanguageOption.english

        #expect(session.liveOutputMode == .transcription)
        #expect(!session.shouldShowTranslationPane)
    }

    @Test
    @MainActor
    func quickSourceLanguageChangeKeepsTranslationModeWhenItWouldMatchTarget() {
        let session = TranslationSessionStore()
        session.useAppleDefaultMode()
        session.useQuickSourceLanguage(.english)
        session.useQuickTargetLanguage(.korean)

        session.useQuickSourceLanguage(.korean)

        #expect(session.sourceLanguage == .korean)
        #expect(session.targetLanguage == .english)
        #expect(session.liveOutputMode == .translation)
        #expect(session.shouldShowTranslationPane)
    }

    @Test
    @MainActor
    func quickLanguageSwapKeepsTranslationMode() {
        let session = TranslationSessionStore()
        session.useAppleDefaultMode()
        session.useQuickSourceLanguage(.english)
        session.useQuickTargetLanguage(.korean)

        session.swapQuickLanguagePair()

        #expect(session.sourceLanguage == .korean)
        #expect(session.targetLanguage == .english)
        #expect(session.liveOutputMode == .translation)
        #expect(session.shouldShowTranslationPane)
    }

    @Test
    @MainActor
    func quickTargetLanguageRejectsMatchingSourceWithoutChangingOutputMode() {
        let session = TranslationSessionStore()
        session.useAppleDefaultMode()
        session.useQuickSourceLanguage(.english)
        session.useQuickTargetLanguage(.korean)

        session.useQuickTargetLanguage(.english)

        #expect(session.sourceLanguage == .english)
        #expect(session.targetLanguage == .korean)
        #expect(session.liveOutputMode == .translation)
        #expect(session.shouldShowTranslationPane)
    }

    @Test
    @MainActor
    func sourceLanguageChangeKeepsTranscribeOnlyModeAndSyncsHiddenTarget() {
        let session = TranslationSessionStore()

        session.sourceLanguage = LanguageOption.english
        session.targetLanguage = LanguageOption.english
        session.useTranscribeOnlyMode()
        session.targetLanguage = LanguageOption.supported[2]

        #expect(session.liveOutputMode == .transcription)
        #expect(!session.shouldShowTranslationPane)
        #expect(session.targetLanguage == session.sourceLanguage)
    }

    @Test
    @MainActor
    func explicitTranslationModeRestoresTranslationModeFromTranscribeOnly() {
        let session = TranslationSessionStore()

        session.useTranscribeOnlyMode()
        session.useTranslationMode()

        #expect(session.liveOutputMode == .translation)
        #expect(session.shouldShowTranslationPane)
    }

    @Test
    @MainActor
    func transcribeOnlyModeUsesOriginalOnlyFloatingCaptionsAndRestoresPreviousMode() {
        let session = TranslationSessionStore()

        session.useTranslationMode()
        session.floatingCaptionDisplayMode = .originalAndTranslation
        #expect(session.floatingCaptionDisplayMode == .originalAndTranslation)

        session.useTranscribeOnlyMode()
        #expect(session.floatingCaptionDisplayMode == .original)
        #expect(session.floatingNoticeText == nil)

        session.useTranslationMode()
        #expect(session.floatingCaptionDisplayMode == .originalAndTranslation)
    }

    @Test
    @MainActor
    func transcribeOnlyModeKeepsFloatingCaptionsOriginalOnly() {
        let session = TranslationSessionStore()

        session.useTranscribeOnlyMode()
        session.floatingCaptionDisplayMode = .translation

        #expect(session.floatingCaptionDisplayMode == .original)
        #expect(session.availableFloatingCaptionDisplayModes == [.original])
    }

    @Test
    @MainActor
    func geminiModeUsesLiveTranslateAndDisablesOtherRealtimeProviders() {
        let session = TranslationSessionStore()
        session.useGPTRealtimeMode()

        session.useGeminiTranslationMode()

        #expect(session.selectedModel == .appleSystem)
        #expect(session.geminiTranslationModel == .gemini35LiveTranslate)
        #expect(!session.openAITranscriptionModel.isEnabled)
        #expect(!session.openAITranslationModel.isEnabled)
        #expect(session.liveOutputMode == .translation)
        #expect(session.isDubbingEnabled)

        session.useAppleDefaultMode()
        #expect(session.geminiTranslationModel == .off)
        #expect(!session.isDubbingEnabled)
    }

    @Test
    @MainActor
    func geminiTranscriptionIsOriginalOnlyAndRestoresPreferences() {
        let session = TranslationSessionStore()
        session.useTranslationMode()
        session.floatingCaptionDisplayMode = .originalAndTranslation
        session.savedTranscriptContentMode = .originalAndTranslation
        session.isDubbingEnabled = true

        session.useGeminiMode(.gemini35TranscribeLive)

        #expect(session.isUsingGeminiTranscriptionMode)
        #expect(session.isUsingProviderTranscriptionMode)
        #expect(!session.shouldShowTranslationPane)
        #expect(session.floatingCaptionDisplayMode == .original)
        #expect(session.availableFloatingCaptionDisplayModes == [.original])
        #expect(session.savedTranscriptContentMode == .originalAndTranslation)
        #expect(session.effectiveSavedTranscriptContentMode == .original)
        #expect(session.availableSavedTranscriptContentModes == [.original])
        #expect(!session.isDubbingEnabled)
        #expect(session.languageSummary == AppText.localized(
            english: "Automatic language detection",
            korean: "입력 언어 자동 감지",
            japanese: "入力言語を自動検出",
            chineseSimplified: "自动检测输入语言"
        ))

        session.useGeminiMode(.gemini35LiveTranslate)

        #expect(session.isUsingGeminiTranslation)
        #expect(session.shouldShowTranslationPane)
        #expect(session.floatingCaptionDisplayMode == .originalAndTranslation)
        #expect(session.savedTranscriptContentMode == .originalAndTranslation)
        #expect(session.effectiveSavedTranscriptContentMode == .originalAndTranslation)
        #expect(session.isDubbingEnabled)
    }

    @Test
    @MainActor
    func geminiPreferredSubmodeReturnsAfterAnotherProvider() {
        let session = TranslationSessionStore()
        session.floatingCaptionDisplayMode = .originalAndTranslation

        session.useGeminiMode(.gemini35TranscribeLive)
        session.useAppleDefaultMode()

        #expect(session.floatingCaptionDisplayMode == .originalAndTranslation)

        session.usePreferredGeminiMode()

        #expect(session.geminiTranslationModel == .gemini35TranscribeLive)
        #expect(session.preferredGeminiModel == .gemini35TranscribeLive)
        #expect(!session.openAITranscriptionModel.isEnabled)
        #expect(!session.openAITranslationModel.isEnabled)
    }

    @Test
    @MainActor
    func restoredGeminiTranscriptionPreservesFloatingCaptionPreference() {
        let suiteName = "TranslationSessionStoreLanguageCandidateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(IntelligenceModel.appleSystem.rawValue, forKey: "selectedModelID")
        defaults.set(OpenAIRealtimeTranscriptionModel.off.rawValue, forKey: "openAITranscriptionModelID")
        defaults.set(OpenAIRealtimeTranslationModel.off.rawValue, forKey: "openAITranslationModelID")
        defaults.set(GeminiTranslationModel.gemini35TranscribeLive.rawValue, forKey: "geminiTranslationModelID")
        defaults.set(GeminiTranslationModel.gemini35TranscribeLive.rawValue, forKey: "preferredGeminiModelID")
        defaults.set(FloatingCaptionDisplayMode.originalAndTranslation.rawValue, forKey: "floatingCaptionDisplayMode")

        let session = TranslationSessionStore(
            modelAvailabilityProvider: { _, _ in [:] },
            settingsDefaults: defaults
        )

        #expect(session.isUsingGeminiTranscriptionMode)
        #expect(session.floatingCaptionDisplayMode == .original)

        session.useGeminiMode(.gemini35LiveTranslate)

        #expect(session.floatingCaptionDisplayMode == .originalAndTranslation)
    }

    @Test
    @MainActor
    func geminiTranscriptionFinalizesAPlainSourceLine() {
        let session = TranslationSessionStore()
        session.useGeminiMode(.gemini35TranscribeLive)
        session.isRunning = true

        session.updateGeminiLiveTranscription("hello", isFinal: false)
        #expect(session.lines.count == 1)
        #expect(session.lines[0].sourceText == "hello")
        #expect(session.lines[0].translatedText.isEmpty)
        #expect(!session.lines[0].isFinal)

        session.updateGeminiLiveTranscription("hello world", isFinal: true)
        #expect(session.lines.count == 1)
        #expect(session.lines[0].sourceText == "hello world")
        #expect(session.lines[0].translatedText.isEmpty)
        #expect(session.lines[0].isFinal)

        session.updateGeminiLiveTranscription("next sentence", isFinal: false)
        #expect(session.lines.count == 2)
        #expect(session.lines[1].sourceText == "next sentence")
    }

    @Test
    @MainActor
    func geminiTranscriptionStartRequiresGeminiAPIKey() {
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] })
        session.useGeminiMode(.gemini35TranscribeLive)
        session.hasGeminiAPIKey = false

        let readiness = session.startReadinessAssessment()

        #expect(readiness.issue == .geminiAPIKeyMissing)
        #expect(!readiness.canStart)
    }

    @Test
    @MainActor
    func geminiTranscriptionStartDoesNotRequireAppleLocalAssets() {
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] })
        session.useGeminiMode(.gemini35TranscribeLive)
        session.hasGeminiAPIKey = true

        let readiness = session.startReadinessAssessment()

        #expect(readiness.canStart)
        #expect(readiness.issue == nil)
    }

    @Test
    @MainActor
    func openAIModeUsesRealtimeTranslateOnlyAndLeavesAPIForTranscription() {
        let session = TranslationSessionStore()
        session.isDubbingEnabled = false

        session.useGPTRealtimeMode()

        #expect(session.liveOutputMode == .translation)
        #expect(!session.openAITranscriptionModel.isEnabled)
        #expect(session.openAITranslationModel == .gptRealtimeTranslate)
        #expect(session.isUsingOpenAIRealtime)
        #expect(session.isUsingProviderRealtimeTranslation)
        #expect(session.isDubbingEnabled)

        session.useTranscribeOnlyMode()

        #expect(session.liveOutputMode == .transcription)
        #expect(!session.openAITranscriptionModel.isEnabled)
        #expect(!session.openAITranslationModel.isEnabled)
        #expect(!session.isUsingOpenAIRealtime)
        #expect(!session.isUsingProviderRealtimeTranslation)
        #expect(!session.shouldShowTranslationPane)
    }

    @Test
    @MainActor
    func openAIModeKeepsVoiceAgentModelsOutOfTranslationEndpoint() {
        let session = TranslationSessionStore()

        #expect(OpenAIRealtimeTranslationModel.liveTranslationCases == [.gptRealtimeTranslate])
        #expect(OpenAIRealtimeTranslationModel.voiceAgentCases.contains(.gptRealtime21))
        #expect(OpenAIRealtimeTranslationModel.voiceAgentCases.contains(.gptRealtime21Mini))
        #expect(!OpenAIRealtimeTranslationModel.gptRealtime21.usesRealtimeAudioTranslation)
        #expect(!OpenAIRealtimeTranslationModel.gptRealtime21Mini.usesRealtimeAudioTranslation)

        session.openAITranslationModel = .gptRealtime21

        #expect(session.openAITranslationModel == .gptRealtimeTranslate)
        #expect(session.isUsingOpenAIRealtime)
        #expect(session.isUsingProviderRealtimeTranslation)

        session.useGPTRealtimeMode(model: .gptRealtime21Mini)

        #expect(session.openAITranslationModel == .gptRealtimeTranslate)
        #expect(session.openAITranslationModel.apiModelID == "gpt-realtime-translate")
        #expect(session.isUsingOpenAIRealtime)
        #expect(session.isUsingProviderRealtimeTranslation)

        session.useGPTRealtimeMode()

        #expect(session.openAITranslationModel == .gptRealtimeTranslate)
    }

    @Test
    @MainActor
    func openAIRealtimeTranslationShowsSourceTranscriptAndTranslation() async {
        let session = TranslationSessionStore()
        session.useGPTRealtimeMode()
        session.isRunning = true
        let transcriber = LiveSpeechTranscriber()

        session.liveSpeechTranscriber(
            transcriber,
            didRecognizeSourceTranscript: "Hello from the source audio.",
            confidence: 0.5
        )
        await Task.yield()

        #expect(session.lines.first?.sourceText == "Hello from the source audio.")
        #expect(session.lines.first?.translatedText == AppText.translating)

        session.liveSpeechTranscriber(
            transcriber,
            didTranslate: "원본 오디오에서 안녕하세요.",
            language: .korean,
            confidence: 0.5
        )
        await Task.yield()

        #expect(session.lines.first?.sourceText == "Hello from the source audio.")
        #expect(session.lines.first?.translatedText == "원본 오디오에서 안녕하세요.")
    }

    @Test
    @MainActor
    func appleDefaultModeDisablesVoiceOutputToAvoidSystemDucking() {
        let session = TranslationSessionStore()
        session.isDubbingEnabled = true

        session.useAppleDefaultMode()

        #expect(!session.isDubbingEnabled)
        #expect(!session.isUsingProviderRealtimeTranslation)
    }

    @Test
    @MainActor
    func apiRealtimeVoiceOutputDefaultsOnAndCanBeTurnedOff() {
        let session = TranslationSessionStore()

        session.useAppleDefaultMode()
        #expect(!session.isDubbingEnabled)

        session.useGPTRealtimeMode()
        #expect(session.isDubbingEnabled)

        session.isDubbingEnabled = false
        #expect(!session.isDubbingEnabled)

        session.useAppleDefaultMode()
        session.useGeminiTranslationMode()
        #expect(session.isDubbingEnabled)
    }

    @Test
    @MainActor
    func geminiLiveVoiceOutputTurnsOffWhenLeavingMode() {
        let session = TranslationSessionStore()
        session.isDubbingEnabled = false

        session.useGeminiTranslationMode()
        #expect(session.isDubbingEnabled)

        session.useAppleDefaultMode()
        #expect(!session.isDubbingEnabled)
    }

    @Test
    @MainActor
    func liveTranslationVolumeSettingClampsToSupportedRange() {
        let session = TranslationSessionStore()

        session.translatedVoiceVolume = -1
        #expect(session.translatedVoiceVolume == 0)

        session.translatedVoiceVolume = 1.5
        #expect(session.translatedVoiceVolume == 1)
    }

    @Test
    @MainActor
    func transcribeOnlyModeTurnsOffGeminiLiveTranslate() {
        let session = TranslationSessionStore()
        session.useGeminiTranslationMode()
        session.hasGeminiAPIKey = false

        session.useTranscribeOnlyMode()
        session.modelAvailabilityByModelID[IntelligenceModel.appleSpeechOnly.id] = ModelAvailability(
            state: .installed,
            detail: "Installed"
        )

        #expect(session.liveOutputMode == .transcription)
        #expect(!session.isUsingGeminiTranslation)
        #expect(!session.shouldShowTranslationPane)
        #expect(session.startReadinessAssessment().canStart)

        session.useTranslationMode()

        #expect(session.liveOutputMode == .translation)
        #expect(!session.isUsingGeminiTranslation)
        #expect(session.shouldShowTranslationPane)
    }

    @Test
    @MainActor
    func stopReplacesPendingTranslationPlaceholderOnVisibleLines() {
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] })
        session.isRunning = true
        session.lines = [
            CaptionLine(
                sourceText: "But let's do the real test now.",
                translatedText: AppText.translating,
                createdAt: Date(),
                isFinal: false
            )
        ]

        session.stop()

        #expect(session.lines.first?.sourceText == "But let's do the real test now.")
        #expect(session.lines.first?.translatedText == AppText.translationCancelled)
        #expect(session.statusMessage == AppText.stopped)
    }

    @Test
    func liveSourceCompatibilityAcceptsGrowingTranscriptLine() {
        let requested = "This is a short Gemini translation test."
        let current = "This is a short Gemini translation test. The app should show Korean text quickly."

        #expect(TranslationSessionStore.isCompatibleLiveSource(current: current, requested: requested))
        #expect(TranslationSessionStore.isCompatibleLiveSource(current: "  \(current)", requested: requested))
        #expect(!TranslationSessionStore.isCompatibleLiveSource(current: "A different line.", requested: requested))
    }

    @Test
    func startReadinessBlocksAppleStartWhenAssetsAreStillChecking() {
        let readiness = StartReadinessPolicy.assess(
            requiresOpenAIAPIKey: false,
            hasOpenAIAPIKey: false,
            requiredLocalModelAvailability: ModelAvailability(
                state: .checking,
                detail: "Checking"
            )
        )

        #expect(readiness.issue == .localAssetsChecking)
        #expect(!readiness.canStart)
    }

    @Test
    func startReadinessBlocksAppleStartWhenAssetsNeedDownload() {
        let readiness = StartReadinessPolicy.assess(
            requiresOpenAIAPIKey: false,
            hasOpenAIAPIKey: false,
            requiredLocalModelAvailability: ModelAvailability(
                state: .downloadRequired,
                detail: "Download needed"
            )
        )

        #expect(readiness.issue == .localAssetsDownloadRequired)
        #expect(!readiness.canStart)
    }

    @Test
    func startReadinessBlocksOpenAIStartWithoutAPIKey() {
        let readiness = StartReadinessPolicy.assess(
            requiresOpenAIAPIKey: true,
            hasOpenAIAPIKey: false,
            requiredLocalModelAvailability: nil
        )

        #expect(readiness.issue == .openAIAPIKeyMissing)
        #expect(!readiness.canStart)
    }

    @Test
    func startReadinessAllowsOpenAIStartWithAPIKeyWithoutLocalAssets() {
        let readiness = StartReadinessPolicy.assess(
            requiresOpenAIAPIKey: true,
            hasOpenAIAPIKey: true,
            requiredLocalModelAvailability: nil
        )

        #expect(readiness.canStart)
    }

    @Test
    func startReadinessBlocksGeminiStartWithoutAPIKey() {
        let readiness = StartReadinessPolicy.assess(
            requiresOpenAIAPIKey: false,
            hasOpenAIAPIKey: false,
            requiresGeminiAPIKey: true,
            hasGeminiAPIKey: false,
            requiredLocalModelAvailability: nil
        )

        #expect(readiness.issue == .geminiAPIKeyMissing)
        #expect(!readiness.canStart)
    }

    @Test
    func startReadinessAllowsGeminiStartWithAPIKeyWithoutTranslationAssets() {
        let readiness = StartReadinessPolicy.assess(
            requiresOpenAIAPIKey: false,
            hasOpenAIAPIKey: false,
            requiresGeminiAPIKey: true,
            hasGeminiAPIKey: true,
            requiredLocalModelAvailability: nil
        )

        #expect(readiness.canStart)
    }

    @Test
    func captureStartFailuresChooseActionableRecovery() {
        #expect(
            CaptureStartRecoveryAction.forFailure(
                CaptureError.systemAudioUnavailable(-1),
                audioInputSource: .systemAudio
            ) == .privacy(.systemAudioRecording)
        )
        #expect(
            CaptureStartRecoveryAction.forFailure(
                CaptureError.microphoneNotGranted,
                audioInputSource: .microphone
            ) == .privacy(.microphone)
        )
        #expect(
            CaptureStartRecoveryAction.forFailure(
                SpeechError.notAuthorized,
                audioInputSource: .microphone
            ) == .privacy(.speechRecognition)
        )
        #expect(
            CaptureStartRecoveryAction.forReadiness(
                StartReadinessPolicy.assess(
                    requiresOpenAIAPIKey: true,
                    hasOpenAIAPIKey: false,
                    requiresGeminiAPIKey: false,
                    hasGeminiAPIKey: false,
                    requiredLocalModelAvailability: nil
                )
            ) == .apiKeys
        )
    }

    @Test
    @MainActor
    func startDownloadsRequiredAssetsWithoutClearingVisibleTranscript() async {
        let downloadProbe = ModelAssetDownloadProbe()
        let session = TranslationSessionStore(
            modelAvailabilityProvider: { _, _ in [:] },
            modelAssetDownloader: { model, _, _ in
                await downloadProbe.record(model)
                try await Task.sleep(for: .seconds(1))
            }
        )
        let existingLine = CaptionLine(
            sourceText: "Existing transcript should stay visible.",
            translatedText: "기존 기록은 남아 있어야 합니다.",
            createdAt: Date(),
            isFinal: true
        )
        session.sourceLanguage = .english
        session.targetLanguage = .korean
        session.useAppleDefaultMode()
        session.lines = [existingLine]
        session.modelAvailabilityByModelID[session.selectedModel.id] = ModelAvailability(
            state: .downloadRequired,
            detail: "Download needed"
        )

        session.start()
        defer { session.stop() }
        try? await Task.sleep(for: .milliseconds(50))

        #expect(!session.isRunning)
        #expect(session.isStarting)
        #expect(session.lines == [existingLine])
        #expect(session.statusMessage == "\(AppText.modelStatusDownloading): \(IntelligenceModel.appleSystem.title)")
        #expect(await downloadProbe.modelIDs() == [IntelligenceModel.appleSystem.id])
    }
}

private actor ModelAssetDownloadProbe {
    private var models = [IntelligenceModel]()

    func record(_ model: IntelligenceModel) {
        models.append(model)
    }

    func modelIDs() -> [String] {
        models.map(\.id)
    }
}
