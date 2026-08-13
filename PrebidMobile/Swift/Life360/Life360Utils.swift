
import Foundation

enum Life360Utils {

    /// Searches available bundles to find the requested resource
    /// This is nessessary since SPM packages resources differently than cocoapods
    ///
    /// - Parameters:
    ///   - name: Resource filename without extension (e.g. `"omsdk"`).
    ///   - ext: File extension (e.g. `"js"`, `"json"`).
    ///   - additionalBundle: Optional bundle to search first — useful for tests or host-app overrides.
    /// - Returns: The file contents decoded as UTF-8.
    /// - Throws: An `NSError` if the resource cannot be found in any bundle, or a file-read error
    ///           if the resource was located but could not be read.
    static func loadBundledText(
        name: String,
        extension ext: String,
        additionalBundle: Bundle? = nil
    ) throws -> String {
        let candidates = searchBundles(additionalBundle: additionalBundle)

        for bundle in candidates {
            guard let path = bundle.path(forResource: name, ofType: ext) else {
                Log.debug("\(name).\(ext) not found in bundle '\(bundle.bundleIdentifier ?? "nil")'")
                continue
            }
            do {
                let contents = try String(contentsOfFile: path, encoding: .utf8)
                Log.info("Loaded \(name).\(ext) (\(contents.utf8.count) bytes)")
                return contents
            } catch {
                Log.error("Found \(name).\(ext) at '\(path)' but could not read it — \(error.localizedDescription)")
                throw error
            }
        }

        let reason = "Could not locate \(name).\(ext) in any bundle. " +
            "Ensure it is included in the target's Copy Bundle Resources phase, " +
            "declared as a SwiftPM resource (Bundle.module), or passed via additionalBundle."
        Log.error(reason)
        throw NSError(
            domain: PrebidConstants.SDK_NAME,
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: reason]
        )
    }

    // MARK: - Private

    /// Private anchor class used solely to resolve the SDK's framework bundle via `Bundle(for:)`.
    /// This avoids coupling `Life360Utils` to any other SDK type.
    private final class BundleAnchor {}

    /// Returns an ordered, deduplicated list of bundles to search.
    private static func searchBundles(additionalBundle: Bundle?) -> [Bundle] {
        var candidates: [Bundle] = []

        // 1. Explicitly provided bundle (tests / host-app overrides).
        if let additionalBundle {
            candidates.append(additionalBundle)
        }

        // 2. SwiftPM module bundle — only present when built with SPM.
        #if SWIFT_PACKAGE
        candidates.append(Bundle.module)
        #endif

        // 3. The framework bundle where this code lives (CocoaPods / manual XCFramework).
        candidates.append(Bundle(for: BundleAnchor.self))

        // 4. Main app bundle (fallback for resources copied into the app target directly).
        candidates.append(.main)

        // Deduplicate while preserving order.
        var seen = Set<ObjectIdentifier>()
        return candidates.filter { bundle in
            let id = ObjectIdentifier(bundle)
            guard !seen.contains(id) else { return false }
            seen.insert(id)
            return true
        }
    }
}
