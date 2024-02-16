//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import SignalServiceKit

class CallRecordLoader {
    struct Configuration {
        /// Whether the loader should only load missed calls.
        let onlyLoadMissedCalls: Bool

        /// If present, the loader will only load calls matching threads with
        /// the given SQLite row IDs.
        let onlyMatchThreadRowIds: [Int64]?

        init(
            onlyLoadMissedCalls: Bool,
            onlyMatchThreadRowIds: [Int64]?
        ) {
            self.onlyLoadMissedCalls = onlyLoadMissedCalls
            self.onlyMatchThreadRowIds = onlyMatchThreadRowIds
        }
    }

    enum LoadDirection {
        case older(oldestCallTimestamp: UInt64?)
        case newer(newestCallTimestamp: UInt64)
    }

    private let callRecordQuerier: CallRecordQuerier
    private let configuration: Configuration

    init(
        callRecordQuerier: CallRecordQuerier,
        configuration: Configuration
    ) {
        self.callRecordQuerier = callRecordQuerier
        self.configuration = configuration
    }

    /// Loads a page of ``CallRecord``s in the given direction.
    ///
    /// - Returns
    /// The newly-loaded records. These records are always sorted descending;
    /// i.e., the first record is the newest and the last record is the oldest.
    func loadCallRecords(
        loadDirection: LoadDirection,
        pageSize: UInt,
        tx: DBReadTransaction
    ) -> [CallRecord] {
        let fetchOrdering: CallRecordQuerierFetchOrdering = {
            switch loadDirection {
            case .older(nil):
                return .descending
            case .older(.some(let oldestCallTimestamp)):
                return .descendingBefore(timestamp: oldestCallTimestamp)
            case .newer(let newestCallTimestamp):
                return .ascendingAfter(timestamp: newestCallTimestamp)
            }
        }()

        let newCallRecords: [CallRecord] = {
            let callRecordCursors = callRecordCursors(
                ordering: fetchOrdering,
                tx: tx
            )

            if callRecordCursors.isEmpty {
                return []
            }

            do {
                let interleavingCursor = try InterleavingCompositeCursor(
                    interleaving: callRecordCursors.map {
                        InterleavableCallRecordCursor(callRecordCursor: $0)
                    },
                    nextElementComparator: { (lhs, rhs) in
                        switch fetchOrdering {
                        case .descending, .descendingBefore:
                            // When descending, we want the newest record next.
                            return lhs.callBeganTimestamp > rhs.callBeganTimestamp
                        case .ascendingAfter:
                            // When ascending, we want the oldest record next.
                            return lhs.callBeganTimestamp < rhs.callBeganTimestamp
                        }
                    }
                )

                return try interleavingCursor.drain(maxResults: pageSize)
            } catch let error {
                CallRecordLogger.shared.error("Failed to drain cursors! \(error)")
                return []
            }
        }()

        switch fetchOrdering {
        case .descending, .descendingBefore:
            return newCallRecords
        case .ascendingAfter:
            // The new call records will be sorted ascending, which makes sense
            // for the query but we want to return them descending.
            return newCallRecords.reversed()
        }
    }

    private func callRecordCursors(
        ordering: CallRecordQuerierFetchOrdering,
        tx: DBReadTransaction
    ) -> [CallRecordCursor] {
        if
            let onlyMatchThreadRowIds = configuration.onlyMatchThreadRowIds,
            configuration.onlyLoadMissedCalls
        {
            return onlyMatchThreadRowIds.flatMap { threadRowId -> [CallRecordCursor] in
                return CallRecord.CallStatus.missedCalls.compactMap { callStatus -> CallRecordCursor? in
                    return callRecordQuerier.fetchCursor(
                        threadRowId: threadRowId,
                        callStatus: callStatus,
                        ordering: ordering,
                        tx: tx
                    )
                }
            }
        } else if let onlyMatchThreadRowIds = configuration.onlyMatchThreadRowIds {
            return onlyMatchThreadRowIds.compactMap { threadRowId -> CallRecordCursor? in
                return callRecordQuerier.fetchCursor(
                    threadRowId: threadRowId,
                    ordering: ordering,
                    tx: tx
                )
            }
        } else if configuration.onlyLoadMissedCalls {
            return CallRecord.CallStatus.missedCalls.compactMap { callStatus -> CallRecordCursor? in
                return callRecordQuerier.fetchCursor(
                    callStatus: callStatus,
                    ordering: ordering,
                    tx: tx
                )
            }
        } else if let fetchCursor = callRecordQuerier.fetchCursor(
            ordering: ordering,
            tx: tx
        ) {
            return [fetchCursor]
        } else {
            return []
        }
    }
}

extension CallRecord.CallStatus {
    static var missedCalls: [CallRecord.CallStatus] {
        return [
            .individual(.incomingMissed),
            .group(.ringingMissed)
        ]
    }

    var isMissedCall: Bool {
        return Self.missedCalls.contains(self)
    }
}

// MARK: -

private extension CallRecordLoader {
    struct InterleavableCallRecordCursor: InterleavableCursor {
        private let callRecordCursor: CallRecordCursor

        init(callRecordCursor: CallRecordCursor) {
            self.callRecordCursor = callRecordCursor
        }

        // MARK: InterleavableCursor

        typealias Element = CallRecord

        func nextElement() throws -> Element? {
            return try callRecordCursor.next()
        }
    }
}

// MARK: -

private extension InterleavingCompositeCursor {
    func drain(maxResults: UInt) throws -> [CursorType.Element] {
        var results = [CursorType.Element]()

        while
            let next = try next(),
            results.count < maxResults
        {
            results.append(next)
        }

        return results
    }
}
