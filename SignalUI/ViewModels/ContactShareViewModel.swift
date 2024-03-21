//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import SignalServiceKit

public class ContactShareViewModel: NSObject {

    public let dbRecord: OWSContact

    public var avatarImageData: Data? {
        didSet {
            self.cachedAvatarImage = nil
        }
    }

    private var cachedAvatarImage: UIImage?

    public var avatarImage: UIImage? {
        if self.cachedAvatarImage != nil {
            return self.cachedAvatarImage
        }

        guard let avatarImageData = self.avatarImageData else {
            return nil
        }

        self.cachedAvatarImage = UIImage(data: avatarImageData)
        return cachedAvatarImage
    }

    public static func load(
        cnContact: CNContact,
        signalContact: @autoclosure () -> Contact,
        tx: SDSAnyReadTransaction
    ) -> ContactShareViewModel {
        let contactShareRecord = OWSContact(cnContact: cnContact)
        let avatarData = loadAvatarData(cnContact: cnContact, signalContact: signalContact(), tx: tx)
        return ContactShareViewModel(
            contactShareRecord: contactShareRecord,
            avatarImageData: avatarData
        )
    }

    private static func loadAvatarData(
        cnContact: CNContact,
        signalContact: @autoclosure () -> Contact,
        tx: SDSAnyReadTransaction
    ) -> Data? {
        if let systemAvatarImageData = contactsManager.avatarData(for: cnContact.identifier) {
            return systemAvatarImageData
        }

        let recipientManager = DependenciesBridge.shared.recipientManager
        let profileAvatarData: Data? = signalContact().e164sForIntersection.lazy.compactMap { phoneNumber in
            let recipient = recipientManager.fetchRecipientIfPhoneNumberVisible(phoneNumber, tx: tx.asV2Read)
            guard let recipient else {
                return nil
            }
            return profileManager.profileAvatarData(for: recipient.address, transaction: tx)
        }.first
        if let profileAvatarData {
            return profileAvatarData
        }

        return nil
    }

    public required init(contactShareRecord: OWSContact, avatarImageData: Data?) {
        self.dbRecord = contactShareRecord
        self.avatarImageData = avatarImageData
    }

    public convenience init(contactShareRecord: OWSContact, transaction: SDSAnyReadTransaction) {
        if let avatarAttachment = contactShareRecord.avatarAttachment(with: transaction) as? TSAttachmentStream {
            self.init(contactShareRecord: contactShareRecord, avatarImageData: avatarAttachment.validStillImageData())
        } else {
            self.init(contactShareRecord: contactShareRecord, avatarImageData: nil)
        }
    }

    public func getAvatarImageWithSneakyTransaction(diameter: CGFloat) -> UIImage? {
        databaseStorage.read { transaction in
            self.getAvatarImage(diameter: diameter, transaction: transaction)
        }
    }

    public func getAvatarImage(diameter: CGFloat, transaction: SDSAnyReadTransaction) -> UIImage? {
        if let avatarImage = avatarImage {
            return avatarImage
        }

        // Note: We build an avatar that _never_ reflects the name,
        // not any corresponding system contact or profile.
        // This could mislead the user into thinking
        // that an avatar they did not share was in fact included in the
        // contact share.
        return Self.avatarBuilder.avatarImage(
            personNameComponents: name.components,
            diameterPoints: UInt(diameter),
            transaction: transaction
        )
    }

    // MARK: Delegated -> dbRecord

    public var name: OWSContactName {
        get {
            return dbRecord.name
        }
        set {
            return dbRecord.name = newValue
        }
    }

    public var addresses: [OWSContactAddress] {
        get {
            return dbRecord.addresses
        }
        set {
            return dbRecord.addresses = newValue
        }
    }

    public var emails: [OWSContactEmail] {
        get {
            return dbRecord.emails
        }
        set {
            dbRecord.emails = newValue
        }
    }

    public var phoneNumbers: [OWSContactPhoneNumber] {
        get {
            return dbRecord.phoneNumbers
        }
        set {
            dbRecord.phoneNumbers = newValue
        }
    }

    public var displayName: String {
        return dbRecord.name.displayName
    }

    public var ows_isValid: Bool {
        return dbRecord.isValid
    }

    public func copy(withName name: OWSContactName) -> ContactShareViewModel {

        // TODO move the `copy` logic into the view model?
        let newDbRecord = dbRecord.copy(with: name)

        return ContactShareViewModel(contactShareRecord: newDbRecord, avatarImageData: self.avatarImageData)
    }

    public func newContact(withName name: OWSContactName) -> ContactShareViewModel {
        // If we want to keep the avatar image, the caller will need to re-apply it.
        return ContactShareViewModel(contactShareRecord: OWSContact(name: name), avatarImageData: nil)
    }

    public func copyForResending() -> ContactShareViewModel {
        let newDbRecord = dbRecord.copy() as! OWSContact
        return ContactShareViewModel(contactShareRecord: newDbRecord, avatarImageData: avatarImageData)
    }
}
