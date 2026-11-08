import Darwin
import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
func peakBytes() -> Int64 {
    var usage = rusage()
    precondition(getrusage(RUSAGE_SELF, &usage) == 0)
    return Int64(usage.ru_maxrss)
}
let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let file = root.appendingPathComponent("package.lzc")
try Data("abc".utf8).write(to: file)
let smallHash = try LocalLensFileHasher.sha256(of: file)
expect(smallHash == "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD",
       "hash all file bytes correctly")
try Data().write(to: file)
expect(try! LocalLensFileHasher.sha256(of: file) == "E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855",
       "hash an empty file correctly")
let writer = try FileHandle(forWritingTo: file)
let block = Data(repeating: 0x5A, count: 1_048_576)
for _ in 0..<512 { writer.write(block) }
writer.closeFile()
let before = peakBytes()
autoreleasepool {
    let actual = try! LocalLensFileHasher.sha256(of: file)
    expect(actual == "15A1868C12CC53951E182344277447CD0979536BADCC512AD24C67E9B2D4F3DD", "large-file hash must match an independent SHA-256 reference")
    let growth = peakBytes() - before
    print("Peak memory growth while hashing 512 MiB: \(growth / 1_048_576) MiB")
    expect(growth < 64 * 1_048_576,
           "verification must release read buffers without waiting for the caller's autorelease pool")
}
print("LocalLensFileHasherTests passed")
