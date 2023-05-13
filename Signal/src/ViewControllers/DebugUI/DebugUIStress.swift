//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalMessaging
import SignalServiceKit
import SignalUI

#if USE_DEBUG_UI

class DebugUIStress: DebugUIPage, Dependencies {

    let name = "Stress"

    func section(thread: TSThread?) -> OWSTableSection? {
        var items = [OWSTableItem]()

        if let thread {
            items.append(OWSTableItem(title: "Send empty message", actionBlock: {
                DebugUIStress.sendStressMessage(toThread: thread, block: { return Data() })
            }))
            items.append(OWSTableItem(title: "Send random noise message", actionBlock: {
                DebugUIStress.sendStressMessage(toThread: thread, block: {
                    return Cryptography.generateRandomBytes(.random(in: 0...31))
                })
            }))
            items.append(OWSTableItem(title: "Send no payload message", actionBlock: {
                DebugUIStress.sendStressMessage(toThread: thread, block: {
                    let contentBuilder = SSKProtoContent.builder()
                    return (contentBuilder.buildIgnoringErrors()?.serializedDataIgnoringErrors())!
                })
            }))
            items.append(OWSTableItem(title: "Send empty null message", actionBlock: {
                DebugUIStress.sendStressMessage(toThread: thread, block: {
                    let contentBuilder = SSKProtoContent.builder()
                    if let nullMessage = SSKProtoNullMessage.builder().buildIgnoringErrors() {
                        contentBuilder.setNullMessage(nullMessage)
                    }
                    return (contentBuilder.buildIgnoringErrors()?.serializedDataIgnoringErrors())!
                })
            }))
            items.append(OWSTableItem(title: "Send whitespace text data message", actionBlock: {
                DebugUIStress.sendStressMessage(toThread: thread, block: {
                    let contentBuilder = SSKProtoContent.builder()
                    let dataMessageBuilder = SSKProtoDataMessage.builder()
                    dataMessageBuilder.setBody(" ")
                    DebugUIStress.ensureGroupOfDataBuilder(dataMessageBuilder, thread: thread)
                    if let dataMessage = dataMessageBuilder.buildIgnoringErrors() {
                        contentBuilder.setDataMessage(dataMessage)
                    }
                    return (contentBuilder.buildIgnoringErrors()?.serializedDataIgnoringErrors())!
                })
            }))
            items.append(OWSTableItem(title: "Send normal text data message", actionBlock: {
                DebugUIStress.sendStressMessage(toThread: thread, block: {
                    let contentBuilder = SSKProtoContent.builder()
                    let dataMessageBuilder = SSKProtoDataMessage.builder()
                    dataMessageBuilder.setBody("alice")
                    DebugUIStress.ensureGroupOfDataBuilder(dataMessageBuilder, thread: thread)
                    if let dataMessage = dataMessageBuilder.buildIgnoringErrors() {
                        contentBuilder.setDataMessage(dataMessage)
                    }
                    return (contentBuilder.buildIgnoringErrors()?.serializedDataIgnoringErrors())!
                })
            }))
            items.append(OWSTableItem(title: "Send N text messages with same timestamp", actionBlock: {
                let timestamp = Date.ows_millisecondTimestamp()
                for i in 0...2 {
                    DebugUIStress.sendStressMessage(toThread: thread, timestamp: timestamp, block: {
                        let contentBuilder = SSKProtoContent.builder()
                        let dataMessageBuilder = SSKProtoDataMessage.builder()
                        dataMessageBuilder.setBody("\(UUID().uuidString) \(i)")
                        DebugUIStress.ensureGroupOfDataBuilder(dataMessageBuilder, thread: thread)
                        if let dataMessage = dataMessageBuilder.buildIgnoringErrors() {
                            contentBuilder.setDataMessage(dataMessage)
                        }
                        return (contentBuilder.buildIgnoringErrors()?.serializedDataIgnoringErrors())!
                    })
                }
            }))
            items.append(OWSTableItem(title: "Send text message with current timestamp", actionBlock: {
                let timestamp = Date.ows_millisecondTimestamp()
                DebugUIStress.sendStressMessage(toThread: thread, timestamp: timestamp, block: {
                    let contentBuilder = SSKProtoContent.builder()
                    let dataMessageBuilder = SSKProtoDataMessage.builder()
                    dataMessageBuilder.setBody("\(UUID().uuidString) now")
                    DebugUIStress.ensureGroupOfDataBuilder(dataMessageBuilder, thread: thread)
                    if let dataMessage = dataMessageBuilder.buildIgnoringErrors() {
                        contentBuilder.setDataMessage(dataMessage)
                    }
                    return (contentBuilder.buildIgnoringErrors()?.serializedDataIgnoringErrors())!
                })
            }))
            items.append(OWSTableItem(title: "Send text message with future timestamp", actionBlock: {
                let timestamp = Date.ows_millisecondTimestamp() + kHourInMs
                DebugUIStress.sendStressMessage(toThread: thread, timestamp: timestamp, block: {
                    let contentBuilder = SSKProtoContent.builder()
                    let dataMessageBuilder = SSKProtoDataMessage.builder()
                    dataMessageBuilder.setBody("\(UUID().uuidString) now")
                    DebugUIStress.ensureGroupOfDataBuilder(dataMessageBuilder, thread: thread)
                    if let dataMessage = dataMessageBuilder.buildIgnoringErrors() {
                        contentBuilder.setDataMessage(dataMessage)
                    }
                    return (contentBuilder.buildIgnoringErrors()?.serializedDataIgnoringErrors())!
                })
            }))
            items.append(OWSTableItem(title: "Send text message with past timestamp", actionBlock: {
                let timestamp = Date.ows_millisecondTimestamp() - kHourInMs
                DebugUIStress.sendStressMessage(toThread: thread, timestamp: timestamp, block: {
                    let contentBuilder = SSKProtoContent.builder()
                    let dataMessageBuilder = SSKProtoDataMessage.builder()
                    dataMessageBuilder.setBody("\(UUID().uuidString) now")
                    DebugUIStress.ensureGroupOfDataBuilder(dataMessageBuilder, thread: thread)
                    if let dataMessage = dataMessageBuilder.buildIgnoringErrors() {
                        contentBuilder.setDataMessage(dataMessage)
                    }
                    return (contentBuilder.buildIgnoringErrors()?.serializedDataIgnoringErrors())!
                })
            }))
            items.append(OWSTableItem(title: "Send N text messages with same timestamp", actionBlock: {
                let contentBuilder = SSKProtoContent.builder()
                let timestamp = Date.ows_millisecondTimestamp()
                let dataMessageBuilder = SSKProtoDataMessage.builder()
                dataMessageBuilder.setBody("alice")
                DebugUIStress.ensureGroupOfDataBuilder(dataMessageBuilder, thread: thread)
                if let dataMessage = dataMessageBuilder.buildIgnoringErrors() {
                    contentBuilder.setDataMessage(dataMessage)
                }
                let data = (contentBuilder.buildIgnoringErrors()?.serializedDataIgnoringErrors())!
                for _ in 0...2 {
                    DebugUIStress.sendStressMessage(toThread: thread, timestamp: timestamp, block: { return data })
                }
            }))
            items.append(OWSTableItem(title: "Send bad attachment data message", actionBlock: {
                DebugUIStress.sendStressMessage(toThread: thread, block: {
                    let contentBuilder = SSKProtoContent.builder()
                    let dataMessageBuilder = SSKProtoDataMessage.builder()
                    let attachmentPointerBuilder = SSKProtoAttachmentPointer.builder()
                    attachmentPointerBuilder.setCdnID(.random(in: 1...32))
                    attachmentPointerBuilder.setContentType("1")
                    attachmentPointerBuilder.setSize(.random(in: 1...32))
                    attachmentPointerBuilder.setDigest(Cryptography.generateRandomBytes(1))
                    attachmentPointerBuilder.setFileName(" ")
                    if let attachmentPointer = attachmentPointerBuilder.buildIgnoringErrors() {
                        dataMessageBuilder.setAttachments([attachmentPointer])
                    }
                    DebugUIStress.ensureGroupOfDataBuilder(dataMessageBuilder, thread: thread)
                    if let dataMessage = dataMessageBuilder.buildIgnoringErrors() {
                        contentBuilder.setDataMessage(dataMessage)
                    }
                    return (contentBuilder.buildIgnoringErrors()?.serializedDataIgnoringErrors())!
                })
            }))

            // Sync

            items.append(OWSTableItem(title: "Send empty sync message", actionBlock: {
                DebugUIStress.sendStressMessage(toThread: thread, block: {
                    let contentBuilder = SSKProtoContent.builder()
                    if let syncMessage = SSKProtoSyncMessage.builder().buildIgnoringErrors() {
                        contentBuilder.setSyncMessage(syncMessage)
                    }
                    return (contentBuilder.buildIgnoringErrors()?.serializedDataIgnoringErrors())!
                })
            }))
            items.append(OWSTableItem(title: "Send empty sync sent message", actionBlock: {
                DebugUIStress.sendStressMessage(toThread: thread, block: {
                    let contentBuilder = SSKProtoContent.builder()
                    let syncMessageBuilder = SSKProtoSyncMessage.builder()
                    if let syncSentMessage = SSKProtoSyncMessageSent.builder().buildIgnoringErrors() {
                        syncMessageBuilder.setSent(syncSentMessage)
                    }
                    if let syncMessage = SSKProtoSyncMessage.builder().buildIgnoringErrors() {
                        contentBuilder.setSyncMessage(syncMessage)
                    }
                    return (contentBuilder.buildIgnoringErrors()?.serializedDataIgnoringErrors())!
                })
            }))
            items.append(OWSTableItem(title: "Send malformed sync sent message 1", actionBlock: {
                DebugUIStress.sendStressMessage(toThread: thread, block: {
                    let contentBuilder = SSKProtoContent.builder()
                    let syncMessageBuilder = SSKProtoSyncMessage.builder()
                    let syncSentMessageBuilder = SSKProtoSyncMessageSent.builder()
                    syncSentMessageBuilder.setDestinationUuid("abc")
                    syncSentMessageBuilder.setTimestamp(.random(in: 1...32))
                    if let message = SSKProtoDataMessage.builder().buildIgnoringErrors() {
                        syncSentMessageBuilder.setMessage(message)
                    }
                    if let syncSentMessage = syncSentMessageBuilder.buildIgnoringErrors() {
                        syncMessageBuilder.setSent(syncSentMessage)
                    }
                    if let syncMessage = SSKProtoSyncMessage.builder().buildIgnoringErrors() {
                        contentBuilder.setSyncMessage(syncMessage)
                    }
                    return (contentBuilder.buildIgnoringErrors()?.serializedDataIgnoringErrors())!
                })
            }))
            items.append(OWSTableItem(title: "Send malformed sync sent message 2", actionBlock: {
                DebugUIStress.sendStressMessage(toThread: thread, block: {
                    let contentBuilder = SSKProtoContent.builder()
                    let syncMessageBuilder = SSKProtoSyncMessage.builder()
                    let syncSentMessageBuilder = SSKProtoSyncMessageSent.builder()
                    syncSentMessageBuilder.setDestinationUuid("abc")
                    syncSentMessageBuilder.setTimestamp(0)
                    if let message = SSKProtoDataMessage.builder().buildIgnoringErrors() {
                        syncSentMessageBuilder.setMessage(message)
                    }
                    if let syncSentMessage = syncSentMessageBuilder.buildIgnoringErrors() {
                        syncMessageBuilder.setSent(syncSentMessage)
                    }
                    if let syncMessage = SSKProtoSyncMessage.builder().buildIgnoringErrors() {
                        contentBuilder.setSyncMessage(syncMessage)
                    }
                    return (contentBuilder.buildIgnoringErrors()?.serializedDataIgnoringErrors())!
                })
            }))
            items.append(OWSTableItem(title: "Send malformed sync sent message 3", actionBlock: {
                DebugUIStress.sendStressMessage(toThread: thread, block: {
                    let contentBuilder = SSKProtoContent.builder()
                    let syncMessageBuilder = SSKProtoSyncMessage.builder()
                    let syncSentMessageBuilder = SSKProtoSyncMessageSent.builder()
                    syncSentMessageBuilder.setDestinationUuid("abc")
                    syncSentMessageBuilder.setTimestamp(0)
                    let dataMessageBuilder = SSKProtoDataMessage.builder()
                    dataMessageBuilder.setBody(" ")
                    if let message = dataMessageBuilder.buildIgnoringErrors() {
                        syncSentMessageBuilder.setMessage(message)
                    }
                    if let syncSentMessage = syncSentMessageBuilder.buildIgnoringErrors() {
                        syncMessageBuilder.setSent(syncSentMessage)
                    }
                    if let syncMessage = SSKProtoSyncMessage.builder().buildIgnoringErrors() {
                        contentBuilder.setSyncMessage(syncMessage)
                    }
                    return (contentBuilder.buildIgnoringErrors()?.serializedDataIgnoringErrors())!
                })
            }))
            items.append(OWSTableItem(title: "Send malformed sync sent message 4", actionBlock: {
                DebugUIStress.sendStressMessage(toThread: thread, block: {
                    let contentBuilder = SSKProtoContent.builder()
                    let syncMessageBuilder = SSKProtoSyncMessage.builder()
                    let syncSentMessageBuilder = SSKProtoSyncMessageSent.builder()
                    syncSentMessageBuilder.setDestinationUuid("abc")
                    syncSentMessageBuilder.setTimestamp(0)
                    let dataMessageBuilder = SSKProtoDataMessage.builder()
                    dataMessageBuilder.setBody(" ")
                    let groupBuilder = SSKProtoGroupContext.builder(id: Cryptography.generateRandomBytes(1))
                    groupBuilder.setType(.deliver)
                    if let group = groupBuilder.buildIgnoringErrors() {
                        dataMessageBuilder.setGroup(group)
                    }
                    if let message = dataMessageBuilder.buildIgnoringErrors() {
                        syncSentMessageBuilder.setMessage(message)
                    }
                    if let syncSentMessage = syncSentMessageBuilder.buildIgnoringErrors() {
                        syncMessageBuilder.setSent(syncSentMessage)
                    }
                    if let syncMessage = SSKProtoSyncMessage.builder().buildIgnoringErrors() {
                        contentBuilder.setSyncMessage(syncMessage)
                    }
                    return (contentBuilder.buildIgnoringErrors()?.serializedDataIgnoringErrors())!
                })
            }))
            items.append(OWSTableItem(title: "Send malformed sync sent message 5", actionBlock: {
                DebugUIStress.sendStressMessage(toThread: thread, block: {
                    let contentBuilder = SSKProtoContent.builder()
                    let syncMessageBuilder = SSKProtoSyncMessage.builder()
                    let syncSentMessageBuilder = SSKProtoSyncMessageSent.builder()
                    syncSentMessageBuilder.setDestinationUuid("abc")
                    if let syncSentMessage = syncSentMessageBuilder.buildIgnoringErrors() {
                        syncMessageBuilder.setSent(syncSentMessage)
                    }
                    if let syncMessage = SSKProtoSyncMessage.builder().buildIgnoringErrors() {
                        contentBuilder.setSyncMessage(syncMessage)
                    }
                    return (contentBuilder.buildIgnoringErrors()?.serializedDataIgnoringErrors())!
                })
            }))
        }

        // Groups

        if let groupThread = thread as? TSGroupThread {
            items.append(OWSTableItem(title: "Clone as v1 group", actionBlock: {
                DebugUIStress.cloneAsV1Group(groupThread)
            }))
            items.append(OWSTableItem(title: "Clone as v2 group", actionBlock: {
                DebugUIStress.cloneAsV2Group(groupThread)
            }))
            items.append(OWSTableItem(title: "Copy members to another group", actionBlock: {
                guard let fromViewController = UIApplication.shared.frontmostViewController else { return }
                DebugUIStress.copyToAnotherGroup(groupThread, fromViewController: fromViewController)
            }))
            items.append(OWSTableItem(title: "Add debug members to group", actionBlock: {
                DebugUIStress.addDebugMembersToGroup(groupThread)
            }))
            if groupThread.isGroupV2Thread {
                items.append(OWSTableItem(title: "Make all members admins", actionBlock: {
                    DebugUIStress.makeAllMembersAdmin(groupThread)

                }))
            }
            items.append(OWSTableItem(title: "Log membership", actionBlock: {
                DebugUIStress.logMembership(groupThread)
            }))
        }

        items.append(OWSTableItem(title: "Make group w. unregistered users", actionBlock: {
            DebugUIStress.makeUnregisteredGroup()
        }))

        // Other
        items.append(OWSTableItem(title: "Delete other profiles", actionBlock: {
            DebugUIStress.deleteOtherProfiles()
        }))
        if let contactThread = thread as? TSContactThread {
            items.append(OWSTableItem(title: "Log groups for contact", actionBlock: {
                DebugUIStress.logGroupsForAddress(contactThread.contactAddress)
            }))
        }

        return OWSTableSection(title: name, items: items)
    }

    static private let shared = DebugUIStress()

    // MARK: -

    private static func sendStressMessage(_ message: TSOutgoingMessage) {
        if let dynamicMessage = message as? OWSDynamicOutgoingMessage {
            messageSender.sendMessage(dynamicMessage.asPreparer) {
                Logger.info("Success.")
            } failure: { error in
                owsFailDebug("Error: \(error)")
            }
        } else {
            databaseStorage.write { transaction in
                self.sskJobQueues.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
            }
        }
    }

    private static func sendStressMessage(
        toThread thread: TSThread,
        timestamp: UInt64 = Date.ows_millisecondTimestamp(),
        block: @escaping DynamicOutgoingMessageBlock
    ) {
        let message = databaseStorage.read { transaction in
            OWSDynamicOutgoingMessage(
                thread: thread,
                timestamp: timestamp,
                transaction: transaction,
                plainTextDataBlock: block
            )
        }
        sendStressMessage(message)
    }

    private static func ensureGroupOfDataBuilder(_ dataBuilder: SSKProtoDataMessageBuilder, thread: TSThread) {
        guard let groupThread = thread as? TSGroupThread else { return }
        let groupBuilder = SSKProtoGroupContext.builder(id: groupThread.groupModel.groupId)
        groupBuilder.setType(.deliver)
        groupBuilder.setId(groupThread.groupModel.groupId)
        guard let group = groupBuilder.buildIgnoringErrors() else {
            owsFailDebug("Failed to build group")
            return
        }
        dataBuilder.setGroup(group)
    }

    // MARK: Groups

    private static func makeUnregisteredGroup() {
        var recipientAddresses: [SignalServiceAddress] = (0...2).map { _ in
            var phoneNumber = "+1999"
            for _ in 0...2 {
                phoneNumber.append(String(format: "%d", UInt8.random(in: 0...9)))
            }
            return SignalServiceAddress(uuid: UUID(), phoneNumber: phoneNumber)
        }

        if let localAddress = tsAccountManager.localAddress {
            recipientAddresses.append(localAddress)
        }

        recipientAddresses.append(contentsOf: (0...2).map { _ in SignalServiceAddress(uuid: UUID(), phoneNumber: nil) })

        GroupManager.localCreateNewGroup(
            members: recipientAddresses,
            name: UUID().uuidString,
            disappearingMessageToken: .disabledToken,
            shouldSendMessage: false
        ).done { groupThread in
            SignalApp.shared().presentConversation(for: groupThread, animated: true)
        }.catch { error in
            owsFailDebug("Error: \(error)")
        }
    }

    private static func nameForClonedGroup(_ groupThread: TSGroupThread) -> String {
        guard let groupName = groupThread.groupModel.groupName else {
            return "Cloned Group"
        }
        return groupName + " Copy"
    }

    // Creates a new group (by cloning the current group) without informing the,
    // other members. This can be used to test "group info requests", etc.
    private static func cloneAsV1Group(_ oldGroupThread: TSGroupThread) {
        do {
            let groupName = Self.nameForClonedGroup(oldGroupThread) + " (v1)"
            let newGroupThread = try self.databaseStorage.write { (transaction: SDSAnyWriteTransaction) throws -> TSGroupThread in
                let newGroupThread = try GroupManager.createGroupForTests(members: oldGroupThread.groupModel.groupMembers,
                                                                          name: groupName,
                                                                          avatarData: oldGroupThread.groupModel.avatarData,
                                                                          groupId: nil,
                                                                          groupsVersion: .V1,
                                                                          transaction: transaction)

                let oldDMConfig = oldGroupThread.disappearingMessagesConfiguration(with: transaction)
                _ = OWSDisappearingMessagesConfiguration.applyToken(oldDMConfig.asToken,
                                                                    toThread: newGroupThread,
                                                                    transaction: transaction)

                return newGroupThread
            }
            assert(newGroupThread.groupModel.groupsVersion == .V1)

            SignalApp.shared().presentConversation(for: newGroupThread, animated: true)
        } catch {
            owsFailDebug("Error: \(error)")
        }
    }

    // Creates a new group (by cloning the current group) without informing the,
    // other members. This can be used to test "group info requests", etc.
    private static func cloneAsV2Group(_ oldGroupThread: TSGroupThread) {
        firstly { () -> Promise<TSGroupThread> in
            guard GroupManager.defaultGroupsVersion == .V2 else {
                throw OWSAssertionError("Groups v2 not enabled.")
            }
            let members: [SignalServiceAddress] = oldGroupThread.groupModel.groupMembers.filter { address in
                GroupManager.doesUserSupportGroupsV2(address: address)
            }
            for member in members {
                Logger.verbose("Member: \(member)")
            }
            var groupName = Self.nameForClonedGroup(oldGroupThread) + " (v2)"
            groupName = groupName.trimToGlyphCount(GroupManager.maxGroupNameGlyphCount)

            return GroupManager.localCreateNewGroup(members: members,
                                                    groupId: nil,
                                                    name: groupName,
                                                    avatarData: oldGroupThread.groupModel.avatarData,
                                                    disappearingMessageToken: .disabledToken,
                                                    newGroupSeed: nil,
                                                    shouldSendMessage: false)
        }.done { (newGroupThread) in
            assert(newGroupThread.groupModel.groupsVersion == .V2)

            self.databaseStorage.write { transaction in
                let oldDMConfig = oldGroupThread.disappearingMessagesConfiguration(with: transaction)
                _ = OWSDisappearingMessagesConfiguration.applyToken(oldDMConfig.asToken,
                                                                    toThread: newGroupThread,
                                                                    transaction: transaction)
            }

            Logger.info("Complete.")

            SignalApp.shared().presentConversation(for: newGroupThread, animated: true)
        }.catch(on: DispatchQueue.global()) { error in
            owsFailDebug("Error: \(error)")
        }
    }

    private static func copyToAnotherGroup(_ srcGroupThread: TSGroupThread, fromViewController: UIViewController) {
        let groupThreads = self.databaseStorage.read { (transaction: SDSAnyReadTransaction) -> [TSGroupThread] in
            TSThread.anyFetchAll(transaction: transaction).compactMap { $0 as? TSGroupThread }
        }
        guard !groupThreads.isEmpty else {
            owsFailDebug("No groups.")
            return
        }
        let groupThreadPicker = GroupThreadPicker(groupThreads: groupThreads) { (dstGroupThread: TSGroupThread) in
            Self.copyToAnotherGroup(srcGroupThread: srcGroupThread, dstGroupThread: dstGroupThread)
        }
        fromViewController.present(groupThreadPicker, animated: true)
    }

    private static func copyToAnotherGroup(srcGroupThread: TSGroupThread, dstGroupThread: TSGroupThread) {
        let membersToAdd = srcGroupThread.groupMembership.allMembersOfAnyKind.subtracting(dstGroupThread.groupMembership.allMembersOfAnyKind)
        let uuidsToAdd = membersToAdd.compactMap { $0.uuid }
        for uuid in uuidsToAdd {
            Logger.verbose("Adding: \(uuid)")
        }
        firstly {
            GroupManager.addOrInvite(
                aciOrPniUuids: uuidsToAdd,
                toExistingGroup: dstGroupThread.groupModel
            )
        }.done { (groupThread) in
            Logger.info("Complete.")

            SignalApp.shared().presentConversation(for: groupThread, animated: true)
        }.catch(on: DispatchQueue.global()) { error in
            owsFailDebug("Error: \(error)")
        }
    }

    private static func addDebugMembersToGroup(_ groupThread: TSGroupThread) {
        let oldGroupModel = groupThread.groupModel

        let e164ToAdd: [String] = [
            "+16785621057"
        ]

        let uuidsToAdd = e164ToAdd
            .map { SignalServiceAddress(phoneNumber: $0) }
            .compactMap { $0.uuid }
            .filter { uuid in
                if oldGroupModel.groupMembership.isMemberOfAnyKind(uuid) {
                    Logger.warn("Recipient is already in group.")
                    return false
                }

                return true
            }

        firstly { () -> Promise<Void> in
            return GroupManager.messageProcessingPromise(for: oldGroupModel,
                                                         description: String(describing: type(of: self)))
        }.then(on: DispatchQueue.global()) { _ in
            GroupManager.addOrInvite(
                aciOrPniUuids: uuidsToAdd,
                toExistingGroup: oldGroupModel
            )
        }.done(on: DispatchQueue.global()) { (_) in
            Logger.info("Complete.")
        }.catch(on: DispatchQueue.global()) { error in
            owsFailDebug("Error: \(error)")
        }
    }

    private static func makeAllMembersAdmin(_ groupThread: TSGroupThread) {
        guard let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 else {
            owsFailDebug("Invalid group model.")
            return
        }
        let uuids = groupModelV2.groupMembership.fullMembers.compactMap { $0.uuid }
        firstly { () -> Promise<TSGroupThread> in
            GroupManager.changeMemberRolesV2(groupModel: groupModelV2, uuids: uuids, role: .administrator)
        }.done(on: DispatchQueue.global()) { (_) in
            Logger.info("Complete.")
        }.catch(on: DispatchQueue.global()) { error in
            owsFailDebug("Error: \(error)")
        }
    }

    private static func logMembership(_ groupThread: TSGroupThread) {
        let groupMembership = groupThread.groupModel.groupMembership
        let uuids = groupMembership.allMembersOfAnyKind.compactMap { $0.uuid }
        let phoneNumbers = groupMembership.allMembersOfAnyKind.compactMap { $0.phoneNumber }
        Logger.info("uuids: \(uuids.map { $0.uuidString }.joined(separator: "\n")).")
        Logger.info("phoneNumbers: \(phoneNumbers.joined(separator: "\n")).")
    }

    private static func deleteOtherProfiles() {
        databaseStorage.write { transaction in
            let profiles = OWSUserProfile.anyFetchAll(transaction: transaction)
            for profile in profiles {
                guard !OWSUserProfile.isLocalProfileAddress(profile.address) else {
                    continue
                }
                Logger.verbose("Deleting: \(profile.address)")
                profile.anyRemove(transaction: transaction)
            }
        }
    }

    private static func logGroupsForAddress(_ address: SignalServiceAddress) {
        Self.databaseStorage.read { transaction in
            TSGroupThread.enumerateGroupThreads(
                with: address,
                transaction: transaction
            ) { thread, _ in
                let displayName = Self.contactsManager.displayName(for: thread, transaction: transaction)
                Logger.verbose("Group[\(thread.groupId.hexadecimalString)]: \(displayName)")
            }
        }
    }
}

// MARK: -

private class GroupThreadPicker: OWSTableViewController {

    private let groupThreads: [TSGroupThread]
    private let completion: (TSGroupThread) -> Void

    init(groupThreads: [TSGroupThread], completion: @escaping (TSGroupThread) -> Void) {
        self.groupThreads = groupThreads
        self.completion = completion

        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = "Select Destination Group"

        rebuildTableContents()
        setupNavigationBar()
        applyTheme()
    }

    // MARK: - Data providers

    private func setupNavigationBar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: CommonStrings.cancelButton,
            style: .plain,
            target: self,
            action: #selector(didTapCancel)
        )
    }

    private func rebuildTableContents() {
        let contactsManager = Self.contactsManager
        let databaseStorage = Self.databaseStorage

        let contents = OWSTableContents()
        let section = OWSTableSection()
        section.headerTitle = "Select a group to add the members to"

        databaseStorage.read { transaction in
            let sortedGroupThreads = self.groupThreads.sorted { (left, right) -> Bool in
                left.lastInteractionRowId > right.lastInteractionRowId
            }
            for groupThread in sortedGroupThreads {
                let groupName = contactsManager.displayName(for: groupThread, transaction: transaction)
                section.add(OWSTableItem.actionItem(withText: groupName) { [weak self] in
                    self?.didSelectGroupThread(groupThread)
                })
            }
        }
        contents.addSection(section)
        self.contents = contents
    }

    // MARK: - Actions

    @objc
    private func didTapCancel() {
        presentingViewController?.dismiss(animated: true, completion: nil)
    }

    private func didSelectGroupThread(_ groupThread: TSGroupThread) {
        let completion = self.completion
        presentingViewController?.dismiss(animated: true) {
            completion(groupThread)
        }
    }
}

#endif
