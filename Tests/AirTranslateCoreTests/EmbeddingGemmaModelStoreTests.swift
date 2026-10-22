import CryptoKit
import Foundation
import Testing
@testable import AirTranslate

@Suite("EmbeddingGemma model installation")
struct EmbeddingGemmaModelStoreTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AIRTRANSLATE_EG2_DOWNLOAD_TEST"] == "1"))
    func optInDownloadsAndVerifiesRealModel() async throws {
        let store = EmbeddingGemmaModelStore()
        let directory = try await store.install()
        #expect(directory == EmbeddingGemmaModelStore.modelDirectory)
        #expect(try await store.installedDirectory() == directory)
        print("EmbeddingGemma model verified: \(directory.path)")
    }

    @Test func pinnedManifestContainsBothCompleteModelBundles() throws {
        let files = EmbeddingGemmaModelStore.manifest
        #expect(EmbeddingGemmaModelStore.revision == "76865ae46793e05617c2a7420454b0c7eb8541a4")
        #expect(EmbeddingGemmaModelStore.totalBytes == 935_493_417)
        for bundle in ["eg2_audio_fp16_T3000", "eg2_reader_v2_fp16_T750"] {
            let prefix = "macos/\(bundle).aimodel/"
            #expect(Set(files.filter { $0.relativePath.hasPrefix(prefix) }.map(\.relativePath)) == Set([
                prefix + "main.hash", prefix + "main.mlirb", prefix + "metadata.json",
            ]))
        }
        for file in files {
            let request = try EmbeddingGemmaModelStore.downloadRequest(for: file.relativePath)
            #expect(request.httpMethod == "GET")
            #expect(request.httpBody == nil)
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.url?.host == "huggingface.co")
            #expect(request.url?.path.contains("/resolve/\(EmbeddingGemmaModelStore.revision)/") == true)
        }
    }

    @Test func rejectsTraversalAndAmbiguousPathsBeforeTransport() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["../outside", "/absolute", "a/../../outside", "a//b", "a/./b", "a\\b", "https://host/file", "a/%2e%2e/b"] {
            let file = entry(path, data: Data("x".utf8))
            let client = ModelTestClient(data: [path: Data("x".utf8)])
            let store = EmbeddingGemmaModelStore(directory: root.appendingPathComponent("model"), manifest: [file], client: client)
            await #expect(throws: EmbeddingGemmaModelStoreError.invalidPath) {
                try await store.install()
            }
            #expect(await client.requests.isEmpty)
        }
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test func installationRequiresEveryVerifiedFileAndSkipsExistingDownload() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("model", isDirectory: true)
        let data = [
            "macos/encoder.aimodel/main.hash": Data("hash".utf8),
            "macos/encoder.aimodel/main.mlirb": Data("weights".utf8),
            "macos/encoder.aimodel/metadata.json": Data("{}".utf8),
            "vocab.txt": Data("hello\nworld".utf8),
        ]
        let files = data.keys.sorted().map { entry($0, data: data[$0]!) }
        let client = ModelTestClient(data: data)
        let store = EmbeddingGemmaModelStore(directory: directory, manifest: files, client: client)
        #expect(try await store.installedDirectory() == nil)
        let result = try await store.install()
        #expect(result == directory)
        #expect(try await store.installedDirectory() == directory)
        #expect(await client.requests.count == files.count)
        #expect(try await store.install() == directory)
        #expect(await client.requests.count == files.count)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["model"])

        try FileManager.default.removeItem(at: directory.appendingPathComponent("macos/encoder.aimodel/metadata.json"))
        #expect(try await store.installedDirectory() == nil)
    }

    @Test func sameSizeTamperingIsNotAnInstalledModel() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let expected = Data("correct".utf8)
        let client = ModelTestClient(data: ["weights": expected])
        let store = EmbeddingGemmaModelStore(directory: root, manifest: [entry("weights", data: expected)], client: client)
        _ = try await store.install()
        try Data("changed".utf8).write(to: root.appendingPathComponent("weights"))
        #expect(try await store.installedDirectory() == nil)
    }

    @Test func failedHashLeavesPriorDirectoryAndRemovesPartialDownload() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("model", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = Data("original installation".utf8)
        try original.write(to: directory.appendingPathComponent("previous"))
        let client = ModelTestClient(data: ["weights": Data("bad".utf8)])
        let store = EmbeddingGemmaModelStore(directory: directory, manifest: [entry("weights", data: Data("new".utf8))], client: client)

        await #expect(throws: EmbeddingGemmaModelStoreError.hashMismatch("weights")) {
            try await store.install()
        }
        #expect(try Data(contentsOf: directory.appendingPathComponent("previous")) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["model"])
    }

    @Test func cancellationRemovesPartialFilesAndPreservesPriorDirectory() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("model", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = Data("previous version".utf8)
        try original.write(to: directory.appendingPathComponent("previous"))
        let data = Data("new weights".utf8)
        let client = ModelTestClient(data: ["weights": data], waitsForCancellation: true)
        let store = EmbeddingGemmaModelStore(directory: directory, manifest: [entry("weights", data: data)], client: client)
        let task = Task { try await store.install() }
        await client.waitUntilDownloadStarts()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }

        #expect(try Data(contentsOf: directory.appendingPathComponent("previous")) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["model"])
    }

    @Test func symbolicLinkCannotStandInForVerifiedWeights() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("model", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = Data("weights".utf8)
        let external = root.appendingPathComponent("outside")
        try data.write(to: external)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("weights"), withDestinationURL: external)
        let store = EmbeddingGemmaModelStore(directory: directory, manifest: [entry("weights", data: data)], client: ModelTestClient(data: [:]))
        #expect(try await store.installedDirectory() == nil)
    }

    @Test func insufficientSpaceDoesNotStartDownload() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data("weights".utf8)
        let client = ModelTestClient(data: ["weights": bytes])
        let store = EmbeddingGemmaModelStore(
            directory: root.appendingPathComponent("model"), manifest: [entry("weights", data: bytes)],
            client: client, availableCapacity: { _ in EmbeddingGemmaModelStore.minimumFreeDiskBytes - 1 }
        )
        await #expect(throws: EmbeddingGemmaModelStoreError.insufficientDiskSpace) {
            try await store.install()
        }
        #expect(await client.requests.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("model").path))
    }

    @Test func separateInstancesCannotInstallToSameDirectoryConcurrently() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("model")
        let bytes = Data("weights".utf8)
        let files = [entry("weights", data: bytes)]
        let slowClient = ModelTestClient(data: ["weights": bytes], waitsForCancellation: true)
        let first = EmbeddingGemmaModelStore(directory: directory, manifest: files, client: slowClient)
        let second = EmbeddingGemmaModelStore(directory: directory, manifest: files, client: ModelTestClient(data: ["weights": bytes]))
        let task = Task { try await first.install() }
        await slowClient.waitUntilDownloadStarts()
        await #expect(throws: EmbeddingGemmaModelStoreError.installInProgress) {
            try await second.install()
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await second.install() == directory)
    }

    private func entry(_ path: String, data: Data) -> EmbeddingGemmaModelFile {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return .init(relativePath: path, byteCount: Int64(data.count), sha256: digest)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("EmbeddingGemmaModelTests-\(UUID().uuidString)", isDirectory: true)
    }
}

private actor ModelTestClient: EmbeddingGemmaModelDownloadClient {
    private let data: [String: Data]
    private let waitsForCancellation: Bool
    private var didStart = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private(set) var requests: [URLRequest] = []

    init(data: [String: Data], waitsForCancellation: Bool = false) {
        self.data = data
        self.waitsForCancellation = waitsForCancellation
    }

    func download(
        _ request: URLRequest, to destination: URL, expectedByteCount: Int64,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        requests.append(request)
        let marker = "/resolve/\(EmbeddingGemmaModelStore.revision)/"
        let path = request.url!.path.components(separatedBy: marker).last!
        let bytes = try #require(data[path])
        try bytes.write(to: destination)
        progress(Int64(bytes.count))
        didStart = true
        startWaiter?.resume()
        startWaiter = nil
        if waitsForCancellation { try await Task.sleep(for: .seconds(60)) }
        try Task.checkCancellation()
    }

    func waitUntilDownloadStarts() async {
        if didStart { return }
        await withCheckedContinuation { startWaiter = $0 }
    }
}
