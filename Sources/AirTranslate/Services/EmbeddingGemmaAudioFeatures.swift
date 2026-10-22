// Adapted from john-rocky/eg2-transcribe (Apache-2.0), commit
// e9c1c2653ff2ebe81447394b3cf22e407433dbed, Audio/LogMelExtractor.swift.
// AirTranslate 변경: 30초 버퍼에 전역 프레임의 왼쪽 문맥을 유지하고 취소·입력 검증을 추가했다.
// https://github.com/john-rocky/eg2-transcribe

import Accelerate
import Foundation

/// Gemma 4 오디오 전처리: 16kHz, 320 표본 주기 Hann, 160 hop, 512 FFT의 진폭, HTK mel, log(mel+0.001).
/// 연속 오디오의 프레임 경계를 보존하려면 두 번째 창부터 앞의 160 표본도 전달한다.
struct EmbeddingGemmaAudioFeatures: Sendable {
    static let frameLength = 320
    static let hopLength = 160
    static let bins = 257
    static let mels = 128
    private let filters: [Double]
    private let window: [Float]

    init(filtersURL: URL) throws {
        let data = try Data(contentsOf: filtersURL)
        let expected = Self.bins * Self.mels
        guard data.count == expected * 8 else {
            throw EmbeddingGemmaTranscriptionError.model("mel_filters.bin 크기가 올바르지 않습니다.")
        }
        let values = data.withUnsafeBytes { raw in
            (0..<expected).map {
                Double(bitPattern: UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 8, as: UInt64.self)))
            }
        }
        try self.init(filters: values)
    }

    init(filters: [Double]) throws {
        guard filters.count == Self.bins * Self.mels,
              filters.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw EmbeddingGemmaTranscriptionError.model("mel 필터 값이 올바르지 않습니다.")
        }
        self.filters = filters
        window = (0..<Self.frameLength).map { k in
            Float(0.5 + 0.5 * cos(Double.pi * Double(-Self.frameLength + 2 * k) / Double(Self.frameLength)))
        }
    }

    /// 321개 펼침 중 처음 320개를 사용하는 원본 extractor의 유효 마스크와 같다.
    static func frameCount(samples: Int) -> Int {
        samples < 161 ? 0 : (samples - 161) / hopLength + 1
    }

    /// `firstFrameSample`은 버퍼 안에서 첫 프레임의 중심 위치다. 맨 처음만 앞을 0으로 채운다.
    func features(_ samples: [Float], firstFrameSample: Int = 0, frames: Int? = nil) throws -> [Float] {
        let n = frames ?? Self.frameCount(samples: samples.count)
        guard n >= 0, n <= 3000, firstFrameSample >= 0,
              n == 0 || firstFrameSample + (n - 1) * Self.hopLength + 160 < samples.count,
              samples.allSatisfy(\.isFinite) else {
            throw EmbeddingGemmaTranscriptionError.audio("오디오 프레임에 유효하지 않은 값이 있습니다.")
        }
        guard n > 0 else { return [] }
        guard let setup = vDSP_create_fftsetupD(9, FFTRadix(kFFTRadix2)) else {
            throw EmbeddingGemmaTranscriptionError.audio("오디오 FFT를 준비하지 못했습니다.")
        }
        defer { vDSP_destroy_fftsetupD(setup) }
        var result = [Float](repeating: 0, count: n * Self.mels)
        let blockSize = 256
        for first in stride(from: 0, to: n, by: blockSize) {
            try Task.checkCancellation()
            let rows = first..<min(n, first + blockSize)
            var fft = [Double](repeating: 0, count: 512)
            var real = [Double](repeating: 0, count: 256)
            var imaginary = [Double](repeating: 0, count: 256)
            var magnitudes = [Double](repeating: 0, count: rows.count * Self.bins)
            var mel = [Double](repeating: 0, count: rows.count * Self.mels)
            for (row, frame) in rows.enumerated() {
                let start = firstFrameSample + frame * Self.hopLength - 160
                for j in 0..<Self.frameLength {
                    let sample = start + j
                    fft[j] = sample >= 0 ? Double(samples[sample] * window[j]) : 0
                }
                real.withUnsafeMutableBufferPointer { re in
                    imaginary.withUnsafeMutableBufferPointer { im in
                        var split = DSPDoubleSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                        fft.withUnsafeBufferPointer { values in
                            values.baseAddress!.withMemoryRebound(to: DSPDoubleComplex.self, capacity: 256) {
                                vDSP_ctozD($0, 2, &split, 1, 256)
                            }
                        }
                        vDSP_fft_zripD(setup, &split, 1, 9, FFTDirection(kFFTDirection_Forward))
                    }
                }
                let base = row * Self.bins
                magnitudes[base] = Double(Float(abs(real[0] * 0.5)))
                magnitudes[base + 256] = Double(Float(abs(imaginary[0] * 0.5)))
                for bin in 1..<256 {
                    magnitudes[base + bin] = Double(Float(hypot(real[bin] * 0.5, imaginary[bin] * 0.5)))
                }
            }
            magnitudes.withUnsafeBufferPointer { a in
                filters.withUnsafeBufferPointer { b in
                    mel.withUnsafeMutableBufferPointer { c in
                        vDSP_mmulD(a.baseAddress!, 1, b.baseAddress!, 1, c.baseAddress!, 1,
                                   vDSP_Length(rows.count), vDSP_Length(Self.mels), vDSP_Length(Self.bins))
                    }
                }
            }
            for index in mel.indices {
                result[first * Self.mels + index] = Float(log(mel[index] + 0.001))
            }
        }
        return result
    }
}

/// 창을 이은 뒤 CTC를 축약한다. 창마다 previous를 초기화하면 경계 단어가 중복된다.
struct EmbeddingGemmaCTC: Sendable {
    let blankID: Int
    private(set) var previous: Int?
    private(set) var words: [Int] = []

    mutating func append(_ labels: [Int]) throws {
        for label in labels {
            guard (0...blankID).contains(label) else {
                throw EmbeddingGemmaTranscriptionError.model("전사 모델이 잘못된 단어 번호를 반환했습니다.")
            }
            if label != blankID, label != previous { words.append(label) }
            previous = label
        }
    }

    static func label(index: Int32, top: Float, blank: Float, blankID: Int) throws -> Int {
        guard index >= 0, Int(index) < blankID, top.isFinite, blank.isFinite else {
            throw EmbeddingGemmaTranscriptionError.model("전사 모델 출력이 올바르지 않습니다.")
        }
        return blank > top ? blankID : Int(index)
    }
}

/// 원본 30초 창 계약. 첫 창 뒤에는 96토큰을 문맥으로만 쓰며 마지막1토큰은 다음 창에서 읽는다.
enum EmbeddingGemmaWindowing {
    static let frames = 3000
    static let tokens = 750
    static let leftOverlap = 96
    static let dropLast = 1
    static let stepFrames = (tokens - leftOverlap - dropLast) * 4

    static func tokenCount(frames: Int) -> Int { ((frames + 1) / 2 + 1) / 2 }

    static func keptTokens(frames: Int, first: Bool, final: Bool) throws -> Range<Int> {
        guard (1...Self.frames).contains(frames) else {
            throw EmbeddingGemmaTranscriptionError.model("전사 창의 길이가 올바르지 않습니다.")
        }
        let lower = first ? 0 : leftOverlap
        let upper = final ? tokenCount(frames: frames) : tokens - dropLast
        guard lower <= upper, final || frames == Self.frames else {
            throw EmbeddingGemmaTranscriptionError.model("전사 창의 문맥 범위가 올바르지 않습니다.")
        }
        return lower..<upper
    }
}
