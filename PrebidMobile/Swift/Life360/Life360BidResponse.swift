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
            hb_env=mobile-app&hb_env_life360=mobile-app&hb_bidder=life360&hb_size=300x250&hb_pb_life360=1.00&hb_bidder_life360=life360&hb_size_life360=300x250&hb_pb=1.00
         */
        if let winningBid = self.winningBid {
            var targeting = [String : String]()
            targeting["hb_env"] = "mobile-app"
            targeting["hb_env_life360"] = "mobile-app"
            let size = winningBid.size
            let sizeString = "\(Int(size.width))x\(Int(size.height))"
            targeting["hb_size"] = sizeString
            targeting["hb_size_life360"] = sizeString
            targeting["hb_bidder"] = "life360"
            targeting["hb_bidder_life360"] = "life360"
            let priceString = String(format: "%.2f", winningBid.price)
            targeting["hb_pb"] = priceString
            targeting["hb_pb_life360"] = priceString
            self.targetingInfo = targeting
        }
    }
}
