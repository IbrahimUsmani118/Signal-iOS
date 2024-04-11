//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Uniquely and stably identifies an ``AttachmentReference``
public struct AttachmentReferenceId: Equatable, Hashable {
    public let ownerId: AttachmentReference.OwnerId

    /// Body media attachments on the same message share an owner id.
    ///
    /// For those body media attachments, order disambiguates,
    /// which makes this identifier object as a whole unique.
    ///
    /// In other owner cases this order value is nil.
    public let orderInOwner: UInt32?
}
