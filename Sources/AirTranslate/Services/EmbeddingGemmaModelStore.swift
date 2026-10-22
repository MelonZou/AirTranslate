import CryptoKit
import Foundation

struct EmbeddingGemmaModelFile: Equatable, Sendable {
    let relativePath: String
    let byteCount: Int64
    let sha256: String
}

protocol EmbeddingGemmaModelDownloadClient: Sendable {
    func download(
        _ request: URLRequest, to destination: URL, expectedByteCount: Int64,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws
}

actor EmbeddingGemmaModelStore {
    nonisolated static let revision = "76865ae46793e05617c2a7420454b0c7eb8541a4"
    nonisolated static let repository = "mlboydaisuke/EmbeddingGemma-2-Transcribe-CoreAI"
    nonisolated static let modelDirectory: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AirTranslate/Models/EmbeddingGemma2Transcribe", isDirectory: true)
            .appendingPathComponent(revision, isDirectory: true)
    }()

    // 공개 HF revision의 파일 트리와 SHA256SUMS를 함께 고정한다. .aimodel은 디렉터리다.
    nonisolated static let manifest: [EmbeddingGemmaModelFile] = [
        .init(relativePath: "SHA256SUMS", byteCount: 13_169, sha256: "bf7c6aff17d23978a87f600302bd3ce8841f300cd1d262f7647452386fe3490b"),
        .init(relativePath: "LICENSE", byteCount: 11_358, sha256: "cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30"),
        .init(relativePath: "NOTICE", byteCount: 2_295, sha256: "495c5aa97dd8cce993ba37fbda13dd14b0278714da6fdc581df1a898c027a0e6"),
        .init(relativePath: "config.json", byteCount: 4_455, sha256: "b8f1e9931b57fbc054acdb445c41765d55b0074c58d145fa82839941ad1b5bb3"),
        .init(relativePath: "macos/eg2_audio_fp16_T3000.aimodel/main.hash", byteCount: 32, sha256: "ae463dbfa9e57b58f4a1bc8b51a3b63aa6df794d63ab6e4f280a55ef60e520fb"),
        .init(relativePath: "macos/eg2_audio_fp16_T3000.aimodel/main.mlirb", byteCount: 586_856_814, sha256: "330ff806a36cc7299de0350b26d27c32b2e8dc96ffee8f2f437d4f86a103498a"),
        .init(relativePath: "macos/eg2_audio_fp16_T3000.aimodel/metadata.json", byteCount: 455, sha256: "9f832dab8f65a60098afee565887f1042fe670398b7d56a15c16ff86ecee223a"),
        .init(relativePath: "macos/eg2_reader_v2_fp16_T750.aimodel/main.hash", byteCount: 32, sha256: "1eba4e43ef5547e81a7878ca72261c3bd5490e002a6d0393aefee6c6efc8ad3b"),
        .init(relativePath: "macos/eg2_reader_v2_fp16_T750.aimodel/main.mlirb", byteCount: 346_600_148, sha256: "eb5580145f17df29f5fedc6adb08b473922d4a263cc8c57986d7177ed0990c17"),
        .init(relativePath: "macos/eg2_reader_v2_fp16_T750.aimodel/metadata.json", byteCount: 693, sha256: "bf1e4b3e4948346efc6caa8b19af9306e0b75f7e4786fc79935235dabb4d8d51"),
        .init(relativePath: "mel_filters.bin", byteCount: 263_168, sha256: "525f8745cf88c08d054328635e93aa8a663e1239bdec4004a73d5d8bd0d3ef41"),
        .init(relativePath: "pipeline.json", byteCount: 1_130, sha256: "feadef992a99ae6f1e364ab27d705da82f7da19e92c85aec766d8c4a90b994bd"),
        .init(relativePath: "reader_config.json", byteCount: 2_080, sha256: "3aede371f7fc1b69bd948a3fce6f861e44eedb237d7b6dce360063ea007a90ed"),
        .init(relativePath: "vocab.txt", byteCount: 1_737_588, sha256: "bb3b3c70379082333e1bbd90d07ca69fe5c0096bd1c3b2b3f83edd65f1062a68"),
    ]
    nonisolated static let totalBytes = manifest.reduce(Int64(0)) { $0 + $1.byteCount }
    nonisolated static let minimumFreeDiskBytes: Int64 = 2_147_483_648

    private let directory: URL
    private let files: [EmbeddingGemmaModelFile]
    private let client: any EmbeddingGemmaModelDownloadClient
    private let availableCapacity: @Sendable (URL) throws -> Int64
    private var isInstalling = false

    init(
        directory: URL = EmbeddingGemmaModelStore.modelDirectory,
        manifest: [EmbeddingGemmaModelFile] = EmbeddingGemmaModelStore.manifest,
        client: any EmbeddingGemmaModelDownloadClient = EmbeddingGemmaModelURLSessionClient(),
        availableCapacity: @escaping @Sendable (URL) throws -> Int64 = { location in
            let values = try location.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let available = values.volumeAvailableCapacityForImportantUsage { return available }
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: location.path)
            return (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        }
    ) {
        self.directory = directory
        self.files = manifest
        self.client = client
        self.availableCapacity = availableCapacity
    }

    func installedDirectory() async throws -> URL? {
        do {
            try verifyDirectory(directory)
            return directory
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    func install(progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        guard !isInstalling else { throw EmbeddingGemmaModelStoreError.installInProgress }
        isInstalling = true
        defer { isInstalling = false }
        try Task.checkCancellation()
        let coordinator = EmbeddingGemmaModelInstallCoordinator.shared
        let installationKey = directory.standardizedFileURL.resolvingSymlinksInPath().path
        guard await coordinator.acquire(installationKey) else { throw EmbeddingGemmaModelStoreError.installInProgress }
        do {
            let installed = try await installExclusively(progress: progress)
            await coordinator.release(installationKey)
            return installed
        } catch {
            await coordinator.release(installationKey)
            throw error
        }
    }

    private func installExclusively(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try Task.checkCancellation()
        try validateManifest()
        if let installed = try await installedDirectory() {
            progress(1)
            return installed
        }

        let manager = FileManager.default
        let parent = directory.deletingLastPathComponent()
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        try Self.rejectSymbolicLinks(between: parent, and: parent)
        guard try availableCapacity(parent) >= Self.minimumFreeDiskBytes else {
            throw EmbeddingGemmaModelStoreError.insufficientDiskSpace
        }
        let staging = parent.appendingPathComponent(".download-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: staging) }
        let total = files.reduce(Int64(0)) { $0 + $1.byteCount }
        var completed: Int64 = 0
        progress(0)

        for file in files {
            try Task.checkCancellation()
            let destination = try Self.fileURL(for: file.relativePath, inside: staging)
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let base = completed
            let request = try Self.downloadRequest(for: file.relativePath)
            try await client.download(request, to: destination, expectedByteCount: file.byteCount) { received in
                progress(min(0.99, Double(base + max(0, min(received, file.byteCount))) / Double(total)))
            }
            try Task.checkCancellation()
            try Self.verify(file, inside: staging)
            completed += file.byteCount
            progress(min(0.99, Double(completed) / Double(total)))
        }
        try verifyDirectory(staging)
        try Task.checkCancellation()

        // 기존 설치는 새 파일이 모두 검증될 때까지 보존하고 이동 실패 시 복원한다.
        let backup = parent.appendingPathComponent(".previous-\(UUID().uuidString)", isDirectory: true)
        let hadPrevious = manager.fileExists(atPath: directory.path)
        if hadPrevious { try manager.moveItem(at: directory, to: backup) }
        do {
            try manager.moveItem(at: staging, to: directory)
        } catch {
            if hadPrevious { try? manager.moveItem(at: backup, to: directory) }
            throw error
        }
        if hadPrevious { try? manager.removeItem(at: backup) }
        progress(1)
        return directory
    }

    private func validateManifest() throws {
        guard !files.isEmpty, Set(files.map(\.relativePath)).count == files.count else {
            throw EmbeddingGemmaModelStoreError.invalidManifest
        }
        for file in files {
            _ = try Self.fileURL(for: file.relativePath, inside: directory)
            guard file.byteCount > 0, file.sha256.count == 64,
                  file.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                throw EmbeddingGemmaModelStoreError.invalidManifest
            }
        }
    }

    private func verifyDirectory(_ root: URL) throws {
        try validateManifest()
        for file in files {
            try Task.checkCancellation()
            try Self.verify(file, inside: root)
        }
    }

    nonisolated static func fileURL(for relativePath: String, inside root: URL) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ component in
                  !component.isEmpty && component != "." && component != ".."
                      && component.utf8.allSatisfy({
                          (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                              || $0 == 45 || $0 == 46 || $0 == 95
                      })
              }) else { throw EmbeddingGemmaModelStoreError.invalidPath }
        return components.reduce(root) { $0.appendingPathComponent(String($1)) }
    }

    nonisolated static func downloadRequest(for relativePath: String) throws -> URLRequest {
        let base = URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)")!
        let url = try fileURL(for: relativePath, inside: base)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    nonisolated private static func rejectSymbolicLinks(between root: URL, and file: URL) throws {
        var current = file.standardizedFileURL
        let boundary = root.standardizedFileURL
        while true {
            let values = try current.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw EmbeddingGemmaModelStoreError.invalidPath }
            if current == boundary { return }
            let parent = current.deletingLastPathComponent()
            guard parent != current else { throw EmbeddingGemmaModelStoreError.invalidPath }
            current = parent
        }
    }

    nonisolated private static func verify(_ file: EmbeddingGemmaModelFile, inside root: URL) throws {
        let url = try fileURL(for: file.relativePath, inside: root)
        try rejectSymbolicLinks(between: root, and: url)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, Int64(values.fileSize ?? -1) == file.byteCount else {
            throw EmbeddingGemmaModelStoreError.invalidSize(file.relativePath)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == file.sha256 else { throw EmbeddingGemmaModelStoreError.hashMismatch(file.relativePath) }
    }
}

enum EmbeddingGemmaModelStoreError: Error, Equatable, LocalizedError {
    case invalidManifest
    case invalidPath
    case invalidSize(String)
    case hashMismatch(String)
    case downloadFailed(Int)
    case invalidResponse
    case installInProgress
    case insufficientDiskSpace

    var errorDescription: String? {
        switch self {
        case .invalidManifest, .invalidPath:
            AppText.localized(english: "The model file list is invalid.", korean: "모델 파일 목록이 올바르지 않습니다.")
        case .invalidSize, .hashMismatch:
            AppText.localized(english: "Model verification failed. Download the models again.", korean: "모델 무결성 확인에 실패했습니다. 모델을 다시 다운로드해 주세요.")
        case .downloadFailed, .invalidResponse:
            AppText.localized(english: "The model download failed. Check the connection and try again.", korean: "모델 다운로드에 실패했습니다. 연결을 확인하고 다시 시도해 주세요.")
        case .installInProgress:
            AppText.localized(english: "A model download is already running.", korean: "모델을 이미 다운로드하고 있습니다.")
        case .insufficientDiskSpace:
            AppText.localized(english: "At least 2 GiB of free space is required to install the models.", korean: "모델을 설치하려면 2GiB 이상의 여유 공간이 필요합니다.")
        }
    }
}

// 같은 프로세스의 서로 다른 설정 창·저장소 인스턴스도 같은 설치 경로를 동시에 바꾸지 않는다.
private actor EmbeddingGemmaModelInstallCoordinator {
    static let shared = EmbeddingGemmaModelInstallCoordinator()
    private var activePaths: Set<String> = []

    func acquire(_ path: String) -> Bool {
        activePaths.insert(path).inserted
    }

    func release(_ path: String) {
        activePaths.remove(path)
    }
}

private struct EmbeddingGemmaModelURLSessionClient: EmbeddingGemmaModelDownloadClient {
    func download(
        _ request: URLRequest, to destination: URL, expectedByteCount: Int64,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        let operation = EmbeddingGemmaModelDownloadOperation(
            destination: destination, expectedByteCount: expectedByteCount, progress: progress
        )
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await operation.run(request)
        } onCancel: {
            operation.cancel()
        }
    }
}

private final class EmbeddingGemmaModelDownloadOperation: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let destination: URL
    private let expectedByteCount: Int64
    private let progress: @Sendable (Int64) -> Void
    private var continuation: CheckedContinuation<Void, any Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var isCancelled = false
    private var terminalError: Error?
    private var lastProgressUptime: TimeInterval = 0

    init(destination: URL, expectedByteCount: Int64, progress: @escaping @Sendable (Int64) -> Void) {
        self.destination = destination
        self.expectedByteCount = expectedByteCount
        self.progress = progress
    }

    func run(_ request: URLRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let download: URLSessionDownloadTask? = lock.withLock {
                guard !isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return nil
                }
                self.continuation = continuation
                let configuration = URLSessionConfiguration.ephemeral
                configuration.urlCache = nil
                configuration.urlCredentialStorage = nil
                configuration.httpCookieStorage = nil
                configuration.httpShouldSetCookies = false
                configuration.timeoutIntervalForRequest = 60
                configuration.timeoutIntervalForResource = 3_600
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                self.session = session
                let download = session.downloadTask(with: request)
                self.task = download
                return download
            }
            download?.resume()
        }
    }

    func cancel() {
        let download = lock.withLock {
            isCancelled = true
            return task
        }
        download?.cancel()
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // HF의 서명된 CDN 이동만 HTTPS로 허용하며 인증·쿠키는 사용하지 않는다.
        guard let url = request.url, let host = url.host?.lowercased(),
              url.scheme == "https", url.user == nil, url.password == nil,
              host == "huggingface.co" || host.hasSuffix(".huggingface.co")
                  || host == "hf.co" || host.hasSuffix(".hf.co") else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard !lock.withLock({ isCancelled }) else { return }
        if totalBytesWritten > expectedByteCount {
            lock.withLock { terminalError = EmbeddingGemmaModelStoreError.invalidSize(destination.lastPathComponent) }
            downloadTask.cancel()
            return
        }
        // 큰 모델을 받는 동안 바이트 콜백마다 메인 UI 작업을 쌓지 않는다.
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastProgressUptime >= 0.1 || totalBytesWritten == expectedByteCount {
            lastProgressUptime = now
            progress(totalBytesWritten)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            if lock.withLock({ isCancelled }) { throw CancellationError() }
            guard let response = downloadTask.response as? HTTPURLResponse else {
                throw EmbeddingGemmaModelStoreError.invalidResponse
            }
            guard response.statusCode == 200 else {
                throw EmbeddingGemmaModelStoreError.downloadFailed(response.statusCode)
            }
            let size = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard Int64(size ?? -1) == expectedByteCount else {
                throw EmbeddingGemmaModelStoreError.invalidSize(destination.lastPathComponent)
            }
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            lock.withLock { terminalError = error }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let result: (CheckedContinuation<Void, any Error>?, Error?) = lock.withLock {
            let continuation = self.continuation
            self.continuation = nil
            self.task = nil
            self.session = nil
            return (continuation, isCancelled ? CancellationError() : (terminalError ?? error))
        }
        session.finishTasksAndInvalidate()
        if let error = result.1 { result.0?.resume(throwing: error) }
        else { result.0?.resume() }
    }
}
