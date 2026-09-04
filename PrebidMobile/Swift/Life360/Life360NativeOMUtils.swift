//
//  Life360NativeOMUtils.swift
//

import Foundation

/// One Open Measurement verification resource, in the shape `OMIDVerificationScriptResource` needs.
/// All three fields are non-optional because the OM SDK rejects a partially populated resource.
struct Life360NativeOMResource: Equatable {
    let url: String
    let vendorKey: String
    let verificationParameters: String
}

/// Locates the Open Measurement verification resource in a native bid response.
///
/// The IAB integration guide explicitly declines to standardise where OM resources live in a native
/// response — "you must embed this information in the ad response through your own mechanism" — so every
/// exchange has picked a different spot and a different key spelling. Rather than betting on one, this
/// searches the known shapes in order of how specific each one is.
enum Life360NativeOMUtils {

    /// Earlier phases are the more explicit declarations, so they win over the VAST-style fallback.
    private static let searchPhases: [(name: String, search: (NativeAdMarkup) -> Life360NativeOMResource?)] = [
        ("eventtrackers", resourceFromEventTrackers),
        ("native.ext.omid", resourceFromOmidExt),
        ("native.ext.adverifications", resourceFromAdVerifications),
    ]

    static func verificationResource(in markup: NativeAdMarkup) -> Life360NativeOMResource? {
        for phase in searchPhases {
            if let resource = phase.search(markup) {
                Log.debug("Found Open Measurement verification resource in \(phase.name) — vendor \(resource.vendorKey)")
                return resource
            }
        }

        Log.debug("No Open Measurement verification resource found in the native ad markup")
        return nil
    }

    // MARK: - Phase 1: event trackers

    private static func resourceFromEventTrackers(_ markup: NativeAdMarkup) -> Life360NativeOMResource? {
        guard let trackers = markup.eventtrackers else { return nil }

        for tracker in trackers where tracker.method == EventTracking.js.value {
            guard let ext = tracker.ext else { continue }

            // The script URL is normally the tracker's own `url`, but some responses only put it in `ext`.
            let url = tracker.url?.nonEmpty ?? string(in: ext, urlKeys)

            if let resource = makeResource(url: url,
                                           vendorKey: string(in: ext, vendorKeys),
                                           parameters: string(in: ext, parameterKeys)) {
                return resource
            }
        }

        return nil
    }

    // MARK: - Phase 2: native.ext.omid

    private static func resourceFromOmidExt(_ markup: NativeAdMarkup) -> Life360NativeOMResource? {
        guard let ext = markup.ext else { return nil }

        for candidate in dictionaries(in: ext, ["omid", "openmeasurement", "om"]) {
            if let resource = resource(from: candidate) {
                return resource
            }
        }

        return nil
    }

    // MARK: - Phase 3: native.ext adverifications

    /// Bidders serving both video and native tend to reuse the VAST `AdVerifications` shape rather than
    /// inventing a second format.
    private static func resourceFromAdVerifications(_ markup: NativeAdMarkup) -> Life360NativeOMResource? {
        guard let ext = markup.ext else { return nil }

        for container in dictionaries(in: ext, ["adverifications"]) + [ext] {
            for verification in dictionaries(in: container, ["verifications", "verification"]) {
                if let resource = resource(from: verification) {
                    return resource
                }
            }
        }

        return nil
    }

    // MARK: - Resource assembly

    private static let urlKeys = [
        "url",
        "omidJsUrl",
        "javascriptResourceUrl",
        "jsResourceUrl",
        "resourceUrl",
        "script",
    ]

    private static let vendorKeys = ["vendorKey", "vendor"]

    private static let parameterKeys = ["verificationParameters", "verificationParams", "params"]

    private static func resource(from dict: [String: Any]) -> Life360NativeOMResource? {
        makeResource(url: string(in: dict, urlKeys),
                     vendorKey: string(in: dict, vendorKeys),
                     parameters: string(in: dict, parameterKeys))
    }

    /// Logs what was missing rather than failing silently — a resource the OM SDK drops on its own is
    /// much harder to diagnose than a log line.
    private static func makeResource(url: String?, vendorKey: String?, parameters: String?) -> Life360NativeOMResource? {
        guard let url, let vendorKey, let parameters else {
            if url != nil || vendorKey != nil || parameters != nil {
                Log.warn("Incomplete Open Measurement verification resource in native markup. " +
                         "Url: \(url ?? "nil"), vendorKey: \(vendorKey ?? "nil"), params: \(parameters ?? "nil")")
            }
            return nil
        }

        // The scheme is checked rather than just parseability: the OM SDK fetches this script over the
        // network, and `URL(string:)` happily accepts a relative reference on newer OS versions.
        guard let parsed = URL(string: url),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            Log.warn("Open Measurement verification resource has an unusable URL: \(url)")
            return nil
        }

        return Life360NativeOMResource(url: url, vendorKey: vendorKey, verificationParameters: parameters)
    }

    // MARK: - Lenient JSON lookup

    private static func string(in dict: [String: Any], _ keys: [String]) -> String? {
        let normalized = normalize(dict)

        for key in keys {
            guard let value = normalized[normalizeKey(key)] else { continue }

            if let string = (value as? String)?.nonEmpty {
                return string
            }
            // Some exchanges wrap a single-element array around the value.
            if let string = (value as? [Any])?.compactMap({ ($0 as? String)?.nonEmpty }).first {
                return string
            }
        }

        return nil
    }

    /// Flattens the object-or-array ambiguity that shows up in nearly every one of these shapes.
    private static func dictionaries(in dict: [String: Any], _ keys: [String]) -> [[String: Any]] {
        let normalized = normalize(dict)

        for key in keys {
            guard let value = normalized[normalizeKey(key)] else { continue }

            if let single = value as? [String: Any] {
                return [single]
            }
            if let many = value as? [[String: Any]] {
                return many
            }
        }

        return []
    }

    private static func normalize(_ dict: [String: Any]) -> [String: Any] {
        var result = [String: Any](minimumCapacity: dict.count)
        for (key, value) in dict {
            result[normalizeKey(key)] = value
        }
        return result
    }

    /// Bidders are inconsistent about casing and separators, so `vendorKey`, `vendorkey` and
    /// `vendor_key` all have to resolve to the same value.
    private static func normalizeKey(_ key: String) -> String {
        key.lowercased().filter { $0 != "_" && $0 != "-" && $0 != " " }
    }
}

private extension String {

    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
