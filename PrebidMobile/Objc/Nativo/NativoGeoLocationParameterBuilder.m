//
// Copyright 2018-2025 Prebid.org, Inc.

// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at

// http://www.apache.org/licenses/LICENSE-2.0

// Unless required by applicable law or agreed to in writing, software
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "NativoGeoLocationParameterBuilder.h"
#import "PBMORTB.h"
#import "PBMConstants.h"
#import "SwiftImport.h"
#import <CoreLocation/CoreLocation.h>

@interface NativoGeoLocationParameterBuilder ()
@property (nonatomic, strong, nonnull, readonly) PBMLocationManager *locationManager;
@end

@implementation NativoGeoLocationParameterBuilder

- (instancetype)initWithLocationManager:(PBMLocationManager *)locationManager {
    if (!(self = [super init])) {
        return nil;
    }
    _locationManager = locationManager;
    return self;
}

- (void)buildBidRequest:(PBMORTBBidRequest *)bidRequest {
    if (!Prebid.shared.shareGeoLocationWithNativo) {
        return;
    }
    if (!(self.locationManager && bidRequest)) {
        return;
    }

    if (self.locationManager.coordinatesAreValid) {
        CLLocationCoordinate2D coordinates = [[Utils shared] roundWithCoordinates:self.locationManager.coordinates
                                                                        precision:[Targeting shared].locationPrecision];
        bidRequest.device.geo.type = @(PrebidConstants.LOCATION_SOURCE_GPS);
        bidRequest.device.geo.lat  = @(coordinates.latitude);
        bidRequest.device.geo.lon  = @(coordinates.longitude);
    }
}

@end
