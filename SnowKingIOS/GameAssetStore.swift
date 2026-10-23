import Foundation
import CryptoKit

enum GameAssetStoreError: Error {
    case packageMissing
    case invalidPackage
    case decryptionFailed
}

/// Decrypts the bundled game package into an app-private cache while preserving
/// the original GameAssets directory layout for Cocos and WKWebView.
final class GameAssetStore {
    static let shared = GameAssetStore()

    private let lock = NSLock()
    private var preparedRoot: URL?
    private let packageMagic = Data("SNOWENC1".utf8)
    private let payloadMagic = Data("SNOWPKG1".utf8)
    private let key = SymmetricKey(data: Data(hex: "b4760b217034ab31c4040587c57841042d4882d8dd3150ce3afafa3710d2ab39"))

    private init() {}

    func rootURL() throws -> URL {
        lock.lock()
        defer { lock.unlock() }
        if let preparedRoot { return preparedRoot }

        guard let packageURL = Bundle.main.url(
            forResource: "GameAssets.snow",
            withExtension: nil,
            subdirectory: "GameAssets"
        ) else {
            throw GameAssetStoreError.packageMissing
        }
        let encrypted = try Data(contentsOf: packageURL, options: [.mappedIfSafe])
        guard encrypted.count > packageMagic.count + 12 + 16,
              encrypted.prefix(packageMagic.count) == packageMagic else {
            throw GameAssetStoreError.invalidPackage
        }

        let digest = SHA256.hash(data: encrypted).map { String(format: "%02x", $0) }.joined()
        let cacheBase = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SnowKingGameAssets", isDirectory: true)
        let root = cacheBase.appendingPathComponent(digest, isDirectory: true)
        let marker = root.appendingPathComponent(".ready")
        if FileManager.default.fileExists(atPath: marker.path) {
            preparedRoot = root
            return root
        }

        try FileManager.default.createDirectory(at: cacheBase, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        do {
            let nonceRange = packageMagic.count..<(packageMagic.count + 12)
            let tagStart = encrypted.count - 16
            let nonce = try AES.GCM.Nonce(data: encrypted.subdata(in: nonceRange))
            let ciphertext = encrypted.subdata(in: (packageMagic.count + 12)..<tagStart)
            let tag = encrypted.subdata(in: tagStart..<encrypted.count)
            let sealed = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            let payload = try AES.GCM.open(sealed, using: key)
            try extract(payload, into: root)
            try Data("ready".utf8).write(to: marker, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw GameAssetStoreError.decryptionFailed
        }

        preparedRoot = root
        return root
    }

    func url(forResource name: String, withExtension ext: String? = nil, subdirectory: String? = nil) -> URL? {
        guard let root = try? rootURL() else { return nil }
        var relative = subdirectory ?? ""
        if !relative.isEmpty { relative += "/" }
        relative += name
        if let ext, !ext.isEmpty { relative += "." + ext }
        return root.appendingPathComponent(relative)
    }

    private func extract(_ payload: Data, into root: URL) throws {
        guard payload.count >= payloadMagic.count + 8,
              payload.prefix(payloadMagic.count) == payloadMagic else {
            throw GameAssetStoreError.invalidPackage
        }
        var offset = payloadMagic.count
        let version = try readUInt32(payload, offset: &offset)
        let count = try readUInt32(payload, offset: &offset)
        guard version == 1, count <= 10000 else { throw GameAssetStoreError.invalidPackage }

        for _ in 0..<count {
            let pathLength = Int(try readUInt32(payload, offset: &offset))
            let dataLength = Int(try readUInt64(payload, offset: &offset))
            guard pathLength > 0, pathLength <= 4096, dataLength >= 0,
                  offset + pathLength + dataLength <= payload.count else {
                throw GameAssetStoreError.invalidPackage
            }
            let pathData = payload.subdata(in: offset..<(offset + pathLength))
            offset += pathLength
            guard let relativePath = String(data: pathData, encoding: .utf8), isSafePath(relativePath) else {
                throw GameAssetStoreError.invalidPackage
            }
            let data = payload.subdata(in: offset..<(offset + dataLength))
            offset += dataLength
            let destination = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destination, options: .atomic)
        }
    }

    private func isSafePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
        return !path.split(separator: "/").contains { $0 == ".." || $0.isEmpty }
    }

    private func readUInt32(_ data: Data, offset: inout Int) throws -> UInt32 {
        guard offset + 4 <= data.count else { throw GameAssetStoreError.invalidPackage }
        let value = data[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        offset += 4
        return value
    }

    private func readUInt64(_ data: Data, offset: inout Int) throws -> UInt64 {
        guard offset + 8 <= data.count else { throw GameAssetStoreError.invalidPackage }
        let value = data[offset..<(offset + 8)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        offset += 8
        return value
    }
}

private extension Data {
    init(hex: String) {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16) ?? 0)
            index = next
        }
        self.init(bytes)
    }
}
