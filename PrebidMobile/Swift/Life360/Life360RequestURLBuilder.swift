import Foundation

/// Appends developer-configured custom query parameters (see `Life360QueryParameterStore`) to the
/// Life360 bid-request URL. 
@objc(Life360RequestURLBuilder) @objcMembers
public class Life360RequestURLBuilder: NSObject {

    /// Returns `urlString` with any query parameters configured for `configId` appended. A custom
    /// parameter is dropped if `urlString` already has a query item with the same name, so a
    /// misconfigured custom parameter can't clobber a structural one like `ntv_epid`.
    @objc(urlByAppendingCustomQueryParametersToURLString:forConfigId:)
    public static func urlByAppendingCustomQueryParameters(to urlString: String, forConfigId configId: String) -> String {
        let customParams = Life360QueryParameterStore.queryParameters(forConfigId: configId)
        guard !customParams.isEmpty, var components = URLComponents(string: urlString) else {
            return urlString
        }

        let existingKeys = Set((components.queryItems ?? []).map(\.name))
        let additions = customParams
            .filter { !existingKeys.contains($0.key) }
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }

        guard !additions.isEmpty else { return urlString }

        components.queryItems = (components.queryItems ?? []) + additions
        return components.url?.absoluteString ?? urlString
    }
}
