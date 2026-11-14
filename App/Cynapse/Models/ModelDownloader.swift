// ModelDownloader.swift — downloads an MLX model from Hugging Face by its
// name (e.g. "mlx-community/Qwen3-0.6B-4bit") into Cynapse's own folder,
// for people using Cynapse on its own.
//
// Hugging Face publishes a SHA-256 for each large file; each download is
// checked against it, so the files checked are the files published.

import Foundation
import CryptoKit

enum ModelDownloader {

    /// Cynapse's own models: Application Support/Cynapse/Models/<org>--<name>.
    static var folder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = support.appendingPathComponent("Cynapse/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    enum Failure: LocalizedError {
        case notFound(String), notMLX(String), mismatch(String), http(Int)
        var errorDescription: String? {
            switch self {
            case .notFound(let id): "No model called \(id) on Hugging Face."
            case .notMLX(let id): "\(id) isn't an MLX model (it has no config.json and .safetensors weights)."
            case .mismatch(let file): "\(file) didn't match the fingerprint Hugging Face publishes for it, so it was deleted."
            case .http(let code): "Hugging Face answered \(code)."
            }
        }
    }

    /// Downloads every file the model needs; `progress` gets 0…1.
    static func download(_ id: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let id = id.trimmingCharacters(in: .whitespaces)
        guard let api = URL(string: "https://huggingface.co/api/models/\(id)/tree/main") else { throw Failure.notFound(id) }
        let (data, response) = try await URLSession.shared.data(from: api)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.notFound(id) }
        let entries = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        let files = entries.filter { ($0["type"] as? String) == "file" }.compactMap { entry -> (path: String, size: Int64, sha: String?)? in
            guard let path = entry["path"] as? String else { return nil }
            let lfs = entry["lfs"] as? [String: Any]
            return (path, (entry["size"] as? NSNumber)?.int64Value ?? 0, lfs?["oid"] as? String)
        }
        let wanted = files.filter { f in
            f.path.hasSuffix(".safetensors") || f.path.hasSuffix(".json") || f.path.hasSuffix(".txt") || f.path.hasSuffix(".model") || f.path.hasSuffix(".jinja")
        }
        guard wanted.contains(where: { $0.path == "config.json" }), wanted.contains(where: { $0.path.hasSuffix(".safetensors") }) else {
            throw Failure.notMLX(id)
        }
        let target = folder.appendingPathComponent(id.replacingOccurrences(of: "/", with: "--"), isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let total = Double(max(wanted.reduce(0) { $0 + $1.size }, 1))
        var done = 0.0
        for file in wanted {
            let destination = target.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let url = URL(string: "https://huggingface.co/\(id)/resolve/main/\(file.path)")!
            let (temporary, response) = try await URLSession.shared.download(from: url)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { throw Failure.http(code) }
            if let sha = file.sha, try sha256(of: temporary) != sha {
                try? FileManager.default.removeItem(at: temporary)
                throw Failure.mismatch(file.path)
            }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporary, to: destination)
            done += Double(file.size)
            progress(done / total)
        }
        return target
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
