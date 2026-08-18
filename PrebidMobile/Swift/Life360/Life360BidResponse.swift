import Foundation

@objcMembers
public class Life360BidResponse: BidResponse {

    required init(rawBidResponse: RawBidResponse?) {
        super.init(rawBidResponse: rawBidResponse)
    }
    
    // Create bid using Life360Bid
    override func createBids(rawBidResponse: RawBidResponse) {
        var allBids: [Bid] = []
        if let seatbid = rawBidResponse.seatbid {
            for nextSeatBid in seatbid {
                guard let bids = nextSeatBid.bid else { continue }
                for nextBid in bids {
                    let bid = Life360Bid(bid: nextBid)
                    allBids.append(bid)
                    
                    // Select Life360's winning bid
                    if bid.price > self.winningBid?.price ?? 0 {
                        self.winningBid = bid
                    }
                }
            }
        }
        self.allBids = allBids
        
        /**
            Mimic targeting parameters sent from prebid server
            hb_env=mobile-app&hb_env_nativo=mobile-app&hb_bidder=nativo&hb_size=300x250&hb_pb_nativo=1.00&hb_bidder_nativo=nativo&hb_size_nativo=300x250&hb_pb=1.00
         */
        if let winningBid = self.winningBid {
            var targeting = [String : String]()
            targeting["hb_env"] = "mobile-app"
            targeting["hb_env_nativo"] = "mobile-app"
            let size = winningBid.size
            let sizeString = "\(Int(size.width))x\(Int(size.height))"
            targeting["hb_size"] = sizeString
            targeting["hb_size_nativo"] = sizeString
            targeting["hb_bidder"] = "nativo"
            targeting["hb_bidder_nativo"] = "nativo"
            let priceString = String(format: "%.2f", winningBid.price)
            targeting["hb_pb"] = priceString
            targeting["hb_pb_nativo"] = priceString
            self.targetingInfo = targeting

            // Also write this into the winning bid's own ext.prebid.targeting — the same place Prebid
            // Server's response carries it — so ORTBBid.jsonDictionary() reports it too. `Life360Bid`
            // overrides `targetingInfo` to avoid depending on ext.prebid when rendering (see its "avoid
            // ext.prebid dependency" overrides below); this is the opposite direction, a write for
            // reporting only, so it doesn't reintroduce that dependency.
            let ext = winningBid.bid.ext ?? ORTBBidExt()
            let prebid = ext.prebid ?? ORTBBidExtPrebid()
            prebid.targeting = targeting
            ext.prebid = prebid
            winningBid.bid.ext = ext
        }
    }
}
