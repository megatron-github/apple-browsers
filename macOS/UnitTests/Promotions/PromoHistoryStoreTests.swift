//
//  PromoHistoryStoreTests.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Combine
import PersistenceTestingUtils
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class PromoHistoryStoreTests: XCTestCase {

    private var store: PromoHistoryStore!
    private var backingStore: InMemoryThrowingKeyValueStore!

    override func setUp() {
        super.setUp()
        backingStore = InMemoryThrowingKeyValueStore()
        store = PromoHistoryStore(store: backingStore, queue: nil)
    }

    override func tearDown() {
        store = nil
        backingStore = nil
        super.tearDown()
    }

    func testWhenRecordForUnknownId_ThenReturnsDefaultRecord() {
        let record = store.record(for: "unknown-promo")

        XCTAssertEqual(record.id, "unknown-promo")
        XCTAssertEqual(record.timesDismissed, 0)
        XCTAssertNil(record.lastDismissed)
        XCTAssertNil(record.nextEligibleDate)
    }

    func testWhenSaveRecord_ThenRecordForReturnsSavedRecord() {
        var record = PromoHistoryRecord(id: "test-promo")
        record.timesDismissed = 2
        record.lastDismissed = Date()
        record.nextEligibleDate = .distantFuture

        store.save(record)

        let loaded = store.record(for: "test-promo")
        XCTAssertEqual(loaded.id, record.id)
        XCTAssertEqual(loaded.timesDismissed, 2)
        XCTAssertNotNil(loaded.lastDismissed)
        XCTAssertEqual(loaded.nextEligibleDate, .distantFuture)
    }

    func testWhenSaveRecord_ThenStateRoundTripsCorrectly() {
        var record = PromoHistoryRecord(id: "round-trip-promo")
        record.timesDismissed = 3
        let now = Date()
        record.lastDismissed = now
        record.nextEligibleDate = now.addingTimeInterval(86400)

        store.save(record)

        let newStore = PromoHistoryStore(store: backingStore, queue: nil)
        let loaded = newStore.record(for: "round-trip-promo")
        XCTAssertEqual(loaded.timesDismissed, 3)
        XCTAssertEqual(try XCTUnwrap(loaded.lastDismissed).timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(loaded.nextEligibleDate).timeIntervalSince1970, try XCTUnwrap(record.nextEligibleDate).timeIntervalSince1970, accuracy: 1)
    }

    func testWhenSaveVisiblePromoIds_ThenLoadVisiblePromoIdsReturnsSameSet() {
        let ids: Set<String> = ["promo-a", "promo-b", "promo-c"]
        store.saveVisiblePromoIds(ids)

        let loaded = store.loadVisiblePromoIds()
        XCTAssertEqual(loaded, ids)
    }

    func testWhenResetAll_ThenRecordsAndVisibleIdsAreCleared() {
        let record = PromoHistoryRecord(id: "reset-promo")
        store.save(record)
        store.saveVisiblePromoIds(["reset-promo"])

        store.resetAll()

        XCTAssertEqual(store.record(for: "reset-promo").timesDismissed, 0)
        XCTAssertNil(store.record(for: "reset-promo").lastDismissed)
        XCTAssertNil(store.record(for: "reset-promo").nextEligibleDate)
        XCTAssertTrue(store.loadVisiblePromoIds().isEmpty)
    }

    func testWhenStoreThrowsOnRead_ThenLoadReturnsEmpty() {
        let throwingStore = InMemoryThrowingKeyValueStore()
        throwingStore.throwOnRead = InMemoryThrowingKeyValueStore.MockError.getError

        let storeWithThrowingBacking = PromoHistoryStore(store: throwingStore, queue: nil)

        let visibleIds = storeWithThrowingBacking.loadVisiblePromoIds()
        XCTAssertTrue(visibleIds.isEmpty)
    }

    func testIsEligibleAsOf_MatchesIsEligibleBehavior() {
        var record = PromoHistoryRecord(id: "eligible-test")
        record.nextEligibleDate = Date().addingTimeInterval(-1)

        XCTAssertTrue(record.isEligible(asOf: Date()))
        XCTAssertTrue(record.isEligible)

        record.nextEligibleDate = Date().addingTimeInterval(3600)
        XCTAssertFalse(record.isEligible(asOf: Date()))
        XCTAssertFalse(record.isEligible)
    }
}
