import CryptoKit
import Foundation

/// Hash Lens packages with bounded temporary storage.
enum LocalLensFileHasher {
    static func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { handle.closeFile() }

        var hasher = SHA256()
        while true {
            // FileHandle's NSData buffers are autoreleased. Drain each chunk here
            // instead of retaining a whole catalog until the caller's pool drains.
            let readChunk = autoreleasepool { () -> Bool in
                let chunk = handle.readData(ofLength: 1_048_576)
                guard !chunk.isEmpty else { return false }
                hasher.update(data: chunk)
                return true
            }
            guard readChunk else { break }
        }
        return hasher.finalize().map { String(format: "%02X", $0) }.joined()
    }
}
