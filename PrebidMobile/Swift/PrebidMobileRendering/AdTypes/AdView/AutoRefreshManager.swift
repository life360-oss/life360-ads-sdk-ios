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
    

import Foundation
import UIKit

@objc(PBMAutoRefreshManager)
@_spi(PBMInternal) public
final class AutoRefreshManager: NSObject {

    // MARK: - Properties

    let lockingQueue: DispatchQueue?
    let lockProvider: (() -> NSLocking?)?
    let prefetchTime: TimeInterval

    let refreshDelayBlock: () -> NSNumber?
    let mayRefreshNowBlock: () -> Bool
    let refreshBlock: VoidBlock

    var delayedBlock: DispatchWorkItem?
    let delayedBlockLock = NSLock()

    // MARK: - Init

    @objc init(prefetchTime: TimeInterval,
               lockingQueue: DispatchQueue?,
               lockProvider: (() -> NSLocking?)?,
               refreshDelayBlock: @escaping () -> NSNumber?,
               mayRefreshNowBlock: @escaping () -> Bool,
               refreshBlock: @escaping VoidBlock) {
        self.prefetchTime = prefetchTime
        self.lockingQueue = lockingQueue
        self.lockProvider = lockProvider
        self.refreshDelayBlock = refreshDelayBlock
        self.mayRefreshNowBlock = mayRefreshNowBlock
        self.refreshBlock = refreshBlock
        super.init()
    }

    // MARK: - Public Methods

    func setupRefreshTimer() {
        Log.whereAmI()

        let refreshOptions = getRefreshOptions()
        guard refreshOptions.type == .reloadLater else { return }

        let refreshDelay = refreshOptions.delay
        Log.info("Will load another ad in \(Int(refreshDelay)) seconds")

        delayedBlockLock.lock()
        cancelDelayedBlock()

        let destinationQueue: DispatchQueue
        let rawBlock: VoidBlock

        if lockProvider != nil, let lockingQueue = lockingQueue {
            destinationQueue = lockingQueue
            rawBlock = { [weak self] in
                self?.acquireLockAndRefresh()
            }
        } else {
            destinationQueue = DispatchQueue.main
            rawBlock = { [weak self] in
                self?.refresh()
            }
        }

        let block = DispatchWorkItem(block: rawBlock)
        self.delayedBlock = block

        let dispatchTime = DispatchTime.now() + refreshDelay
        destinationQueue.asyncAfter(deadline: dispatchTime, execute: block)
        delayedBlockLock.unlock()
    }

    func cancelRefreshTimer() {
        delayedBlockLock.lock()
        cancelDelayedBlock()
        delayedBlockLock.unlock()
    }

    // MARK: - Private

    private func acquireLockAndRefresh() {
        delayedBlockLock.lock()

        guard let lock = lockProvider?() else {
            delayedBlockLock.unlock()
            return
        }

        lock.lock()

        // The unlock is deliberately outside the cancellable work item and outside the `guard let
        // self`. `cancelRefreshTimer()` cancels whatever is in `delayedBlock`, and this manager can be
        // released while the item is queued — either would otherwise leave the caller's lock held for
        // the rest of the process, blocking every later block on the queue it guards.
        let refreshItem = DispatchWorkItem { [weak self] in
            self?.refresh()
        }
        delayedBlock = refreshItem

        DispatchQueue.main.async {
            defer { lock.unlock() }
            refreshItem.perform()
        }

        delayedBlockLock.unlock()
    }

    private func refresh() {
        let appState = UIApplication.shared.applicationState
        let isBackground = (appState == .background || appState == .inactive)

        if !isBackground, mayRefreshNowBlock() {
            refreshBlock()
        } else {
            Log.info("Creative is invisible or opened. Skipping refresh.")
            setupRefreshTimer()
        }
    }

    private func cancelDelayedBlock() {
        delayedBlock?.cancel()
        delayedBlock = nil
    }

    private func getRefreshOptions() -> AdRefreshOptions {
        guard let delayValue = refreshDelayBlock(), delayValue.doubleValue > 0 else {
            return AdRefreshOptions(type: .stopWithRefreshDelay, delay: 0)
        }

        let delay = max(delayValue.doubleValue - prefetchTime, 1.0)
        Log.info("Will load another ad in \(delay) seconds")

        return AdRefreshOptions(type: .reloadLater, delay: delay)
    }
}
