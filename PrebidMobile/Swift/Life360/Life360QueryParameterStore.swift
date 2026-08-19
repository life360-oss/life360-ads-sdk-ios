import Foundation

/// Reads developer-configured query parameters appended to Life360 bid requests, scoped by ad
/// unit `configId` so different placements/`BannerView`s can carry distinct parameters.
/// 
/// Example usage:
/// UserDefaults.standard.set(["my-config-id": ["publisher_id": "abc123"]], forKey: Life360QueryParameterStore.customQueryParametersKey)
enum Life360QueryParameterStore {
    static let customQueryParametersKey = "l360_exchange_params"

    /// Returns the custom query parameters written for `configId`, or empty if none were set. A
    /// malformed entry for one `configId` only drops that `configId`'s parameters, not every
    /// other placement's.
    static func queryParameters(forConfigId configId: String) -> [String: String] {
        let allParameters = UserDefaults.standard.dictionary(forKey: customQueryParametersKey)
        return allParameters?[configId] as? [String: String] ?? [:]
    }
}
