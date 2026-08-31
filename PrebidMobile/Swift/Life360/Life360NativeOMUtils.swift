//
//  Life360NativeOMUtils.swift
//

import Foundation

/// One Open Measurement verification resource, in the shape `OMIDVerificationScriptResource` needs.
///
/// All three fields are non-optional because the OM SDK rejects a resource that is missing any of them —
/// a partially populated resource is the same as no resource at all, so it never gets built.
struct Life360NativeOMResource: Equatable {

    /// URL of the vendor's verification script.
    let url: String

    /// Vendor identifier the verification script is registered under.
    let vendorKey: String

    /// Opaque string handed back to the vendor's script when it runs.
    let verificationParameters: String
}

/// Locates the Open Measurement verification resource in a native bid response.
///
/// The IAB integration guide explicitly declines to standardise where OM resources live in a native
/// response — "you must embed this information in the ad response through your own mechanism" — so every
/// exchange has picked a different spot. Rather than betting on one, this searches the known shapes in
/// order of how specific each one is, and stops at the first resource that is complete enough to measure
/// with. Callers pass a markup and get a resource or nothing; which shapes exist and what their key
/// spellings are stays in here.
enum Life360NativeOMUtils {

    /// Ordered list of places a verification resource is known to appear. The earlier phases are the more
    /// explicit declarations, so they win over the looser VAST-style fallback.
    private static let searchPhases: [(name: String, search: (NativeAdMarkup) -> Life360NativeOMResource?)] = [
        ("eventtrackers", resourceFromEventTrackers),
        ("native.ext.omid", resourceFromOmidExt),
        ("native.ext.adverifications", resourceFromAdVerifications),
    ]

    /// Returns the first complete verification resource found in the markup, or `nil` if the response
    /// carries none — which is the common case, since only some demand includes OM measurement.
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

    /// The OpenRTB-native way to declare a JS tracker: an `eventtrackers` entry with `method: 2`, whose
    /// `ext` carries the vendor key and verification parameters alongside the script `url`.
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

    /// A dedicated `omid` object (or array of them) hung off the native markup's `ext`.
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

    /// The VAST `AdVerifications` shape, which bidders serving both video and native tend to reuse for
    /// native rather than inventing a second format.
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

    /// Reads a resource out of a single dictionary, whatever phase handed it over — the key spellings are
    /// the same wherever the object is nested.
    private static func resource(from dict: [String: Any]) -> Life360NativeOMResource? {
        makeResource(url: string(in: dict, urlKeys),
                     vendorKey: string(in: dict, vendorKeys),
                     parameters: string(in: dict, parameterKeys))
    }

    /// Builds a resource only when every field is present and the URL is usable, logging what was missing
    /// otherwise — a resource that the OM SDK silently drops is much harder to diagnose than a log line.
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

    /// Looks up the first non-empty string among `keys`, ignoring case and word separators so that
    /// `vendorKey`, `vendorkey` and `vendor_key` all resolve to the same value. Bidders are inconsistent
    /// about casing and this is cheaper than teaching every call site all three spellings.
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

    /// Returns the dictionaries found under any of `keys`, flattening the object-or-array ambiguity that
    /// shows up in nearly every one of these shapes.
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

    private static func normalizeKey(_ key: String) -> String {
        key.lowercased().filter { $0 != "_" && $0 != "-" && $0 != " " }
    }
}

private extension String {

    /// `nil` rather than an empty string, so a present-but-blank JSON value is treated as absent.
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
