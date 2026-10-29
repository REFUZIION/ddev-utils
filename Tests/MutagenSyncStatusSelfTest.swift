// Compiled out of the app. Run from the repo root:
// swiftc -parse-as-library -D MUTAGEN_SELFTEST Models/MutagenSyncStatus.swift Tests/MutagenSyncStatusSelfTest.swift -o /tmp/mutagen-selftest && /tmp/mutagen-selftest
#if MUTAGEN_SELFTEST
@main
enum MutagenSyncStatusSelfTest {
    static func main() {
        let cases: [(String, MutagenSyncStatus)] = [
            ("Mutagen: ok (Watching for changes)", .synced),
            ("Mutagen: problems\nScan problems: ...\nStatus: Watching for changes", .problems),
            ("Mutagen: ok (Scanning files)", .scanning),
            ("Status: Staging files on beta", .staging),
            ("Status: Applying changes, Syncing", .syncing),
            ("Mutagen: paused", .paused),
            ("Mutagen is not enabled on project 'foo'", .disabled),
            ("Project foo is not running", .disconnected),
            ("", .unknown),
        ]
        for (input, expected) in cases {
            let actual = MutagenSyncStatus(fromString: input)
            precondition(actual == expected, "\(input.debugDescription): expected \(expected), got \(actual)")
        }
        print("MutagenSyncStatus: \(cases.count) cases passed")
    }
}
#endif
