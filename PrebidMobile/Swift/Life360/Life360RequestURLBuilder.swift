import Foundation

/// Appends developer-configured custom query parameters (see `Life360QueryParameterStore`) to the
/// Life360 bid-request URL. A Swift class rather than the usual caseless-enum namespace, since the
/// only caller, `Life360BidRequester`, is Objective-C and can't see Swift enum static members.
@objc(Life360RequestURLBuilder) @objcMembers
public class Life360RequestURLBuilder: NSObject {

    /// Returns `urlString` with any developer-configured query parameters appended. A custom
    /// parameter is dropped if `urlString` already has a query item with the same name, so a
    /// misconfigured custom parameter can't clobber a structural one like `ntv_epid`.
    @objc(urlByAppendingCustomQueryParametersToURLString:)
    public static func urlByAppendingCustomQueryParameters(to urlString: String) -> String {
        let customParams = Life360QueryParameterStore.all
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
