//
// Copyright 2018-2025 Prebid.org, Inc.

// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at

// http://www.apache.org/licenses/LICENSE-2.0

// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
    

import Foundation

class ORTBBidExtLife360: PBMJsonCodable {
    
    // Special Life360 property to declare if ad should be rendered immediately
    private(set) var isOwnedOperated: Bool?
    private(set) var life360AdType: Life360AdType?
    
    private enum KeySet: String {
        case oo
        case life360AdType
    }

    init() { }

    required init(jsonDictionary: [String : Any]) {
        let _ = JSONObject<KeySet>(jsonDictionary)
        if let raw = jsonDictionary[KeySet.oo.rawValue] {
            if let b = raw as? Bool {
                isOwnedOperated = b
            } else if let n = raw as? NSNumber {
                isOwnedOperated = n.boolValue
            } else {
                isOwnedOperated = nil
            }
        } else {
            isOwnedOperated = nil
        }
        if let raw = jsonDictionary[KeySet.life360AdType.rawValue] {
            if let n = raw as? NSNumber {
                life360AdType = Life360AdType(rawValue: n.intValue)
            } else {
                life360AdType = nil
            }
        } else {
            life360AdType = nil
        }
    }

    var jsonDictionary: [String : Any] {
        var json = JSONObject<KeySet>()
        if let isOwnedOperated {
            json[.oo] = NSNumber(value: isOwnedOperated)
        }
        if let life360AdType {
            json[.life360AdType] = NSNumber(value: life360AdType.rawValue)
        }
        return json.dict
    }
}
