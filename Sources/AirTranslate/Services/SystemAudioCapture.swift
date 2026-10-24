import AVFoundation
import AudioToolbox
import CoreAudio
import ScreenCaptureKit

protocol SystemAudioCaptureDelegate: AnyObject {
    func systemAudioCapture(
        _ capture: SystemAudioCapture,
        didOutput sampleBuffer: CMSampleBuffer,
        generation: UInt64
    )
    func systemAudioCapture(
        _ capture: SystemAudioCapture,
        didReceiveAudioSampleCount count: Int,
        level: Float?,
        generation: UInt64
    )
    func systemAudioCapture(
        _ capture: SystemAudioCapture,
        didFail error: Error,
        generation: UInt64
    )
    func systemAudioCaptureDidStopByUser(
        _ capture: SystemAudioCapture,
        generation: UInt64
    )
}

actor CaptureOperationGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        if !isLocked {
            isLocked = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func leave() {
        guard !waiters.isEmpty else {
            isLocked = false
            return
        }

        waiters.removeFirst().resume()
    }
}

/// Converts the tap's native float PCM (any channel count, interleaved or planar)
/// into mono float PCM at the requested sample rate.
private final class TapAudioConverter: @unchecked Sendable {
    private let monoInputFormat: AVAudioFormat
    private let converter: AVAudioConverter
    private let rateRatio: Double
    let outputFormat: AVAudioFormat

    init?(tapFormat: AVAudioFormat, outputSampleRate: Double) {
        guard tapFormat.commonFormat == .pcmFormatFloat32,
              let monoInput = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: tapFormat.sampleRate,
                  channels: 1,
                  interleaved: false
              ),
              let output = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: outputSampleRate,
                  channels: 1,
                  interleaved: false
              ),
              let converter = AVAudioConverter(from: monoInput, to: output)
        else {
            return nil
        }

        monoInputFormat = monoInput
        outputFormat = output
        self.converter = converter
        rateRatio = outputSampleRate / tapFormat.sampleRate
    }

    func convert(_ list: UnsafePointer<AudioBufferList>) -> AVAudioPCMBuffer? {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        guard let first = buffers.first else { return nil }

        let floatSize = MemoryLayout<Float>.size
        let frameCount: Int
        if buffers.count == 1 {
            let channels = max(1, Int(first.mNumberChannels))
            frameCount = Int(first.mDataByteSize) / (floatSize * channels)
        } else {
            frameCount = Int(first.mDataByteSize) / floatSize
        }
        guard frameCount > 0,
              let input = AVAudioPCMBuffer(
                  pcmFormat: monoInputFormat,
                  frameCapacity: AVAudioFrameCount(frameCount)
              ),
              let mono = input.floatChannelData?[0]
        else {
            return nil
        }
        input.frameLength = AVAudioFrameCount(frameCount)

        if buffers.count == 1 {
            guard let data = first.mData else { return nil }
            let channels = max(1, Int(first.mNumberChannels))
            let samples = data.assumingMemoryBound(to: Float.self)
            for frame in 0..<frameCount {
                var sum: Float = 0
                for channel in 0..<channels {
                    sum += samples[frame * channels + channel]
                }
                mono[frame] = sum / Float(channels)
            }
        } else {
            for frame in 0..<frameCount { mono[frame] = 0 }
            var usedChannels: Float = 0
            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                let available = min(frameCount, Int(buffer.mDataByteSize) / floatSize)
                let samples = data.assumingMemoryBound(to: Float.self)
                for frame in 0..<available { mono[frame] += samples[frame] }
                usedChannels += 1
            }
            guard usedChannels > 0 else { return nil }
            for frame in 0..<frameCount { mono[frame] /= usedChannels }
        }

        let capacity = AVAudioFrameCount(Double(frameCount) * rateRatio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return nil
        }

        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }
}

/// Captures system output audio with a Core Audio process tap. Unlike a
/// ScreenCaptureKit stream this creates no screen-capture session, so DRM video
/// (for example the Apple TV app) is not blanked while capturing.
final class SystemAudioCapture: NSObject, @unchecked Sendable {
    private static let audioLevelReportInterval = 8

    static func isUserStoppedError(_ error: Error) -> Bool {
        if error is SystemAudioCaptureLifecycleOutcome {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == SCStreamErrorDomain
            && nsError.code == SCStreamError.Code.userStopped.rawValue
    }

    static func isFatalStopError(_ error: Error) -> Bool {
        !isUserStoppedError(error)
    }

    private final class ActiveCapture: @unchecked Sendable {
        let tapID: AudioObjectID
        let aggregateID: AudioObjectID
        let converter: TapAudioConverter
        let generation: UInt64
        var ioProcID: AudioDeviceIOProcID?
        var audioSampleCount = 0

        init(
            tapID: AudioObjectID,
            aggregateID: AudioObjectID,
            converter: TapAudioConverter,
            generation: UInt64
        ) {
            self.tapID = tapID
            self.aggregateID = aggregateID
            self.converter = converter
            self.generation = generation
        }
    }

    private let stateLock = NSLock()
    private let operationGate = CaptureOperationGate()
    private let sampleQueue = DispatchQueue(
        label: "AirTranslate.SystemAudioCapture.sampleQueue",
        qos: .userInteractive
    )
    private weak var delegateStorage: SystemAudioCaptureDelegate?
    private var operationGeneration: UInt64 = 0
    private var activeCapture: ActiveCapture?

    var delegate: SystemAudioCaptureDelegate? {
        get { withStateLock { delegateStorage } }
        set { withStateLock { delegateStorage = newValue } }
    }

    @MainActor
    func start(sampleRate: Int = 16_000, generation: UInt64 = 0) async throws {
        let operation = beginOperation()
        await operationGate.enter()

        do {
            try await performStart(
                sampleRate: sampleRate,
                generation: generation,
                operation: operation
            )
            await operationGate.leave()
        } catch {
            await operationGate.leave()
            throw error
        }
    }

    func stop() async {
        invalidateOperations()
        await operationGate.enter()
        await performStop()
        await operationGate.leave()
    }

    private func performStart(
        sampleRate: Int,
        generation: UInt64,
        operation: UInt64
    ) async throws {
        await performStop()
        try ensureOperationIsCurrent(operation)

        let description = CATapDescription(
            stereoGlobalTapButExcludeProcesses: Self.currentProcessObjectIDs()
        )
        description.name = "AirTranslate System Audio"
        description.muteBehavior = .unmuted
        description.isPrivate = true

        var tapID = AudioObjectID(kAudioObjectUnknown)
        try Self.check(AudioHardwareCreateProcessTap(description, &tapID))

        let converter: TapAudioConverter
        do {
            var streamDescription = try Self.tapStreamDescription(of: tapID)
            guard let tapFormat = AVAudioFormat(streamDescription: &streamDescription),
                  let tapConverter = TapAudioConverter(
                      tapFormat: tapFormat,
                      outputSampleRate: Double(sampleRate)
                  )
            else {
                throw CaptureError.systemAudioUnavailable(kAudioHardwareUnsupportedOperationError)
            }
            converter = tapConverter
        } catch {
            AudioHardwareDestroyProcessTap(tapID)
            throw error
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AirTranslate System Audio",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(
            aggregateDescription as CFDictionary,
            &aggregateID
        )
        guard aggregateStatus == noErr else {
            AudioHardwareDestroyProcessTap(tapID)
            throw CaptureError.systemAudioUnavailable(aggregateStatus)
        }

        let capture = ActiveCapture(
            tapID: tapID,
            aggregateID: aggregateID,
            converter: converter,
            generation: generation
        )

        var procID: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(
            &procID,
            aggregateID,
            sampleQueue
        ) { [weak self, weak capture] _, inputData, _, _, _ in
            guard let self, let capture else { return }
            self.handleInput(inputData, capture: capture)
        }
        guard procStatus == noErr, let procID else {
            teardown(capture)
            throw CaptureError.systemAudioUnavailable(procStatus)
        }
        capture.ioProcID = procID

        let installed = withStateLock {
            guard operationGeneration == operation else { return false }
            activeCapture = capture
            return true
        }
        guard installed else {
            teardown(capture)
            throw CancellationError()
        }

        let startStatus = AudioDeviceStart(aggregateID, procID)
        guard startStatus == noErr else {
            clearAndTeardown(capture)
            throw CaptureError.systemAudioUnavailable(startStatus)
        }

        let remainsCurrent = withStateLock {
            operationGeneration == operation && activeCapture === capture
        }
        guard remainsCurrent else {
            clearAndTeardown(capture)
            throw CancellationError()
        }
    }

    private func performStop() async {
        let capture = withStateLock {
            let capture = activeCapture
            activeCapture = nil
            return capture
        }
        guard let capture else { return }
        teardown(capture)
    }

    private func clearAndTeardown(_ capture: ActiveCapture) {
        withStateLock {
            if activeCapture === capture {
                activeCapture = nil
            }
        }
        teardown(capture)
    }

    private func teardown(_ capture: ActiveCapture) {
        if let ioProcID = capture.ioProcID {
            AudioDeviceStop(capture.aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(capture.aggregateID, ioProcID)
            capture.ioProcID = nil
        }
        AudioHardwareDestroyAggregateDevice(capture.aggregateID)
        AudioHardwareDestroyProcessTap(capture.tapID)
    }

    private func handleInput(_ inputData: UnsafePointer<AudioBufferList>, capture: ActiveCapture) {
        guard let pcm = capture.converter.convert(inputData) else { return }

        let delivery = withStateLock { () -> (delegate: SystemAudioCaptureDelegate?, count: Int)? in
            guard activeCapture === capture else { return nil }
            capture.audioSampleCount += 1
            return (delegateStorage, capture.audioSampleCount)
        }
        guard let delivery, let delegate = delivery.delegate,
              let sampleBuffer = Self.makeSampleBuffer(from: pcm)
        else {
            return
        }

        delegate.systemAudioCapture(self, didOutput: sampleBuffer, generation: capture.generation)
        if delivery.count == 1 || delivery.count % Self.audioLevelReportInterval == 0 {
            delegate.systemAudioCapture(
                self,
                didReceiveAudioSampleCount: delivery.count,
                level: Self.audioLevel(of: pcm),
                generation: capture.generation
            )
        }
    }

    private static func makeSampleBuffer(from pcm: AVAudioPCMBuffer) -> CMSampleBuffer? {
        var formatDescription: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: pcm.format.streamDescription,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        ) == noErr, let formatDescription else {
            return nil
        }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: Int32(pcm.format.sampleRate)),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: CMItemCount(pcm.frameLength),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        ) == noErr, let sampleBuffer else {
            return nil
        }

        guard CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: pcm.audioBufferList
        ) == noErr else {
            return nil
        }
        return sampleBuffer
    }

    private static func audioLevel(of pcm: AVAudioPCMBuffer) -> Float? {
        guard let samples = pcm.floatChannelData?[0], pcm.frameLength > 0 else { return nil }

        var squareSum: Double = 0
        for index in 0..<Int(pcm.frameLength) {
            let sample = Double(samples[index])
            squareSum += sample * sample
        }
        let rms = sqrt(squareSum / Double(pcm.frameLength))
        return Float(20 * log10(max(rms, 0.000_001)))
    }

    private static func check(_ status: OSStatus) throws {
        guard status == noErr else {
            throw CaptureError.systemAudioUnavailable(status)
        }
    }

    private static func tapStreamDescription(of tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
        var description = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        try check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &description))
        return description
    }

    /// Excluding this process keeps AirTranslate's own audio out of the transcript.
    private static func currentProcessObjectIDs() -> [AudioObjectID] {
        var pid = getpid()
        var objectID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &pid,
            &size,
            &objectID
        )
        guard status == noErr, objectID != AudioObjectID(kAudioObjectUnknown) else { return [] }
        return [objectID]
    }

    private func beginOperation() -> UInt64 {
        withStateLock {
            operationGeneration &+= 1
            return operationGeneration
        }
    }

    private func invalidateOperations() {
        withStateLock {
            operationGeneration &+= 1
        }
    }

    private func ensureOperationIsCurrent(_ operation: UInt64) throws {
        guard withStateLock({ operationGeneration == operation }) else {
            throw CancellationError()
        }
    }

    private func withStateLock<Result>(_ body: () -> Result) -> Result {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }
}

enum SystemAudioCaptureLifecycleOutcome: Error {
    case userStopped
}

enum CaptureError: LocalizedError, Equatable {
    case systemAudioUnavailable(OSStatus)
    case microphoneNotGranted
    case microphoneUnavailable
    case microphoneInterrupted
    case microphoneRuntimeFailure

    var errorDescription: String? {
        switch self {
        case .systemAudioUnavailable(let status):
            AppText.localized(
                english: "System audio capture could not start (code \(status)). Allow System Audio Recording for AirTranslate in Privacy & Security, then try again.",
                korean: "시스템 오디오 캡처를 시작할 수 없습니다(코드 \(status)). 개인정보 보호 및 보안에서 AirTranslate의 시스템 오디오 녹음을 허용한 뒤 다시 시도하세요.",
                japanese: "システムオーディオのキャプチャを開始できません(コード \(status))。プライバシーとセキュリティで AirTranslate のシステムオーディオ録音を許可してから再試行してください。",
                chineseSimplified: "无法开始系统音频捕获(代码 \(status))。请在“隐私与安全性”中允许 AirTranslate 的系统音频录制,然后重试。"
            )
        case .microphoneNotGranted:
            AppText.microphoneNotGranted
        case .microphoneUnavailable:
            AppText.microphoneUnavailable
        case .microphoneInterrupted:
            AppText.localized(
                english: "Microphone capture was interrupted.",
                korean: "마이크 캡처가 중단되었습니다.",
                japanese: "マイクのキャプチャが中断されました。",
                chineseSimplified: "麦克风捕获已中断。"
            )
        case .microphoneRuntimeFailure:
            AppText.localized(
                english: "Microphone capture stopped unexpectedly.",
                korean: "마이크 캡처가 예기치 않게 중지되었습니다.",
                japanese: "マイクのキャプチャが予期せず停止しました。",
                chineseSimplified: "麦克风捕获意外停止。"
            )
        }
    }
}
