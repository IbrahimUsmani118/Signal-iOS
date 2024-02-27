//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import Contacts
@testable import Signal
@testable import SignalMessaging
@testable import SignalServiceKit
@testable import SignalUI

// MARK: -

class GRDBFullTextSearcherTest: SignalBaseTest {

    // MARK: - Dependencies

    var searcher: FullTextSearcher {
        FullTextSearcher.shared
    }

    // MARK: - Test Life Cycle

    private var bobRecipient: SignalServiceAddress!
    private var aliceRecipient: SignalServiceAddress!

    override func setUp() {
        super.setUp()

        let localIdentifiers: LocalIdentifiers = .forUnitTests

        // We need to create new instances of SignalServiceAddress
        // for each test because we're using a new
        // SignalServiceAddressCache for each test and we need
        // consistent backingHashValue.
        let alicePhoneNumber = "+12345678900"
        aliceRecipient = SignalServiceAddress(phoneNumber: alicePhoneNumber)
        let bobPhoneNumber = "+49030183000"
        bobRecipient = SignalServiceAddress(phoneNumber: bobPhoneNumber)

        // Replace this singleton.
        let fakeContactManager = FakeContactsManager()
        fakeContactManager.mockSignalAccounts = [
            alicePhoneNumber: SignalAccount(
                contact: Contact(phoneNumber: alicePhoneNumber, phoneNumberLabel: "", givenName: "Alice", familyName: nil, nickname: nil, fullName: "Alice"),
                address: aliceRecipient
            ),
            bobPhoneNumber: SignalAccount(
                contact: Contact(phoneNumber: bobPhoneNumber, phoneNumberLabel: "", givenName: "Bob", familyName: "Barker", nickname: nil, fullName: "Bob Barker"),
                address: bobRecipient
            ),
        ]
        SSKEnvironment.shared.setContactManagerForUnitTests(fakeContactManager)

        // ensure local client has necessary "registered" state
        let localE164Identifier = "+13235551234"
        let localUUID = UUID()
        databaseStorage.write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: localIdentifiers,
                tx: tx.asV2Write
            )
        }

        self.write { transaction in
            let bookClubGroupThread = try! GroupManager.createGroupForTests(members: [self.aliceRecipient, self.bobRecipient, DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read)!.aciAddress],
                                                                            name: "Book Club",
                                                                            transaction: transaction)
            self.bookClubThread = ThreadViewModel(thread: bookClubGroupThread,
                                                  forChatList: true,
                                                  transaction: transaction)

            let snackClubGroupThread = try! GroupManager.createGroupForTests(members: [self.aliceRecipient],
                                                                             name: "Snack Club",
                                                                             transaction: transaction)
            self.snackClubThread = ThreadViewModel(thread: snackClubGroupThread,
                                                   forChatList: true,
                                                   transaction: transaction)

            let aliceContactThread = TSContactThread.getOrCreateThread(withContactAddress: self.aliceRecipient, transaction: transaction)
            self.aliceThread = ThreadViewModel(thread: aliceContactThread,
                                               forChatList: true,
                                               transaction: transaction)

            let bobContactThread = TSContactThread.getOrCreateThread(withContactAddress: self.bobRecipient, transaction: transaction)
            self.bobEmptyThread = ThreadViewModel(thread: bobContactThread,
                                                  forChatList: true,
                                                  transaction: transaction)

            let helloAlice = TSOutgoingMessage(in: aliceContactThread, messageBody: "Hello Alice", attachmentId: nil)
            helloAlice.anyInsert(transaction: transaction)

            let goodbyeAlice = TSOutgoingMessage(in: aliceContactThread, messageBody: "Goodbye Alice", attachmentId: nil)
            goodbyeAlice.anyInsert(transaction: transaction)

            let helloBookClub = TSOutgoingMessage(in: bookClubGroupThread, messageBody: "Hello Book Club", attachmentId: nil)
            helloBookClub.anyInsert(transaction: transaction)

            let goodbyeBookClub = TSOutgoingMessage(in: bookClubGroupThread, messageBody: "Goodbye Book Club", attachmentId: nil)
            goodbyeBookClub.anyInsert(transaction: transaction)

            let bobsPhoneNumber = TSOutgoingMessage(in: bookClubGroupThread, messageBody: "My phone number is: 321-321-4321", attachmentId: nil)
            bobsPhoneNumber.anyInsert(transaction: transaction)

            let bobsFaxNumber = TSOutgoingMessage(in: bookClubGroupThread, messageBody: "My fax is: 222-333-4444", attachmentId: nil)
            bobsFaxNumber.anyInsert(transaction: transaction)
        }
    }

    // MARK: - Fixtures

    var bookClubThread: ThreadViewModel!
    var snackClubThread: ThreadViewModel!

    var aliceThread: ThreadViewModel!
    var bobEmptyThread: ThreadViewModel!

    // MARK: Tests

    private func AssertEqualThreadLists(_ left: [ThreadViewModel], _ right: [ThreadViewModel], file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(left.count, right.count, file: file, line: line)
        guard left.count != right.count else {
            return
        }
        // Only bother comparing uniqueIds.
        let leftIds = left.map { $0.threadRecord.uniqueId }
        let rightIds = right.map { $0.threadRecord.uniqueId }
        XCTAssertEqual(leftIds, rightIds, file: file, line: line)
    }

    func testSearchByGroupName() {
        var threads: [ThreadViewModel] = []

        // No Match
        threads = searchConversations(searchText: "asdasdasd")
        XCTAssert(threads.isEmpty)

        // Partial Match
        threads = searchConversations(searchText: "Book")
        XCTAssertEqual(1, threads.count)
        AssertEqualThreadLists([bookClubThread], threads)

        threads = searchConversations(searchText: "Snack")
        XCTAssertEqual(1, threads.count)
        AssertEqualThreadLists([snackClubThread], threads)

        // Multiple Partial Matches
        threads = searchConversations(searchText: "Club")
        XCTAssertEqual(2, threads.count)
        AssertEqualThreadLists([bookClubThread, snackClubThread], threads)

        // Match Name Exactly
        threads = searchConversations(searchText: "Book Club")
        XCTAssertEqual(1, threads.count)
        AssertEqualThreadLists([bookClubThread], threads)
    }

    func testSearchContactByNumber() {
        var threads: [ThreadViewModel] = []

        // No match
        threads = searchConversations(searchText: "+5551239999")
        XCTAssertEqual(0, threads.count)

        // Exact match
        threads = searchConversations(searchText: aliceRecipient.phoneNumber!)
        XCTAssertEqual(3, threads.count)
        AssertEqualThreadLists([bookClubThread, aliceThread, snackClubThread], threads)

        // Partial match
        threads = searchConversations(searchText: "+123456")
        XCTAssertEqual(3, threads.count)
        AssertEqualThreadLists([bookClubThread, aliceThread, snackClubThread], threads)

        // Prefixes
        threads = searchConversations(searchText: "12345678900")
        XCTAssertEqual(3, threads.count)
        AssertEqualThreadLists([bookClubThread, aliceThread, snackClubThread], threads)

        threads = searchConversations(searchText: "49")
        XCTAssertEqual(1, threads.count)
        AssertEqualThreadLists([bookClubThread], threads)

        threads = searchConversations(searchText: "1-234-56")
        XCTAssertEqual(3, threads.count)
        AssertEqualThreadLists([bookClubThread, aliceThread, snackClubThread], threads)

        threads = searchConversations(searchText: "123456")
        XCTAssertEqual(3, threads.count)
        AssertEqualThreadLists([bookClubThread, aliceThread, snackClubThread], threads)

        threads = searchConversations(searchText: "1.234.56")
        XCTAssertEqual(3, threads.count)
        AssertEqualThreadLists([bookClubThread, aliceThread, snackClubThread], threads)

        threads = searchConversations(searchText: "1 234 56")
        XCTAssertEqual(3, threads.count)
        AssertEqualThreadLists([bookClubThread, aliceThread, snackClubThread], threads)
    }

    func testSearchContactByNumberWithoutCountryCode() {
        var threads: [ThreadViewModel] = []
        // Phone Number formatting should be forgiving
        threads = searchConversations(searchText: "234.56")
        XCTAssertEqual(3, threads.count)
        AssertEqualThreadLists([bookClubThread, aliceThread, snackClubThread], threads)

        threads = searchConversations(searchText: "234 56")
        XCTAssertEqual(3, threads.count)
        AssertEqualThreadLists([bookClubThread, aliceThread, snackClubThread], threads)
    }

    func testSearchConversationByContactByName() {
        var threads: [ThreadViewModel] = []

        threads = searchConversations(searchText: "Alice")
        XCTAssertEqual(3, threads.count)
        AssertEqualThreadLists([bookClubThread, aliceThread, snackClubThread], threads)

        threads = searchConversations(searchText: "Bob")
        XCTAssertEqual(1, threads.count)
        AssertEqualThreadLists([bookClubThread], threads)

        threads = searchConversations(searchText: "Barker")
        XCTAssertEqual(1, threads.count)
        AssertEqualThreadLists([bookClubThread], threads)

        threads = searchConversations(searchText: "Bob B")
        XCTAssertEqual(1, threads.count)
        AssertEqualThreadLists([bookClubThread], threads)
    }

    func testSearchMessageByBodyContent() {
        var resultSet: HomeScreenSearchResultSet = .empty

        resultSet = getResultSet(searchText: "Hello Alice")
        XCTAssertEqual(1, resultSet.messages.count)
        AssertEqualThreadLists([aliceThread], resultSet.messages.map { $0.thread })

        resultSet = getResultSet(searchText: "Hello")
        XCTAssertEqual(2, resultSet.messages.count)
        AssertEqualThreadLists([aliceThread, bookClubThread], resultSet.messages.map { $0.thread })
    }

    func testSearchEdgeCases() {
        var resultSet: HomeScreenSearchResultSet = .empty

        resultSet = getResultSet(searchText: "Hello Alice")
        XCTAssertEqual(1, resultSet.messages.count)
        XCTAssertEqual(["Hello Alice"], bodies(forMessageResults: resultSet.messages))

        resultSet = getResultSet(searchText: "hello alice")
        XCTAssertEqual(1, resultSet.messages.count)
        XCTAssertEqual(["Hello Alice"], bodies(forMessageResults: resultSet.messages))

        resultSet = getResultSet(searchText: "Hel")
        XCTAssertEqual(2, resultSet.messages.count)
        XCTAssertEqual(["Hello Alice", "Hello Book Club"], bodies(forMessageResults: resultSet.messages))

        resultSet = getResultSet(searchText: "Hel Ali")
        XCTAssertEqual(1, resultSet.messages.count)
        XCTAssertEqual(["Hello Alice"], bodies(forMessageResults: resultSet.messages))

        resultSet = getResultSet(searchText: "Hel Ali Alic")
        XCTAssertEqual(1, resultSet.messages.count)
        XCTAssertEqual(["Hello Alice"], bodies(forMessageResults: resultSet.messages))

        resultSet = getResultSet(searchText: "Ali Hel")
        XCTAssertEqual(1, resultSet.messages.count)
        XCTAssertEqual(["Hello Alice"], bodies(forMessageResults: resultSet.messages))

        resultSet = getResultSet(searchText: "CLU")
        XCTAssertEqual(2, resultSet.messages.count)
        XCTAssertEqual(["Goodbye Book Club", "Hello Book Club"], bodies(forMessageResults: resultSet.messages))

        resultSet = getResultSet(searchText: "hello !@##!@#!$^@!@#! alice")
        XCTAssertEqual(1, resultSet.messages.count)
        XCTAssertEqual(["Hello Alice"], bodies(forMessageResults: resultSet.messages))

        resultSet = getResultSet(searchText: "3213 phone")
        XCTAssertEqual(1, resultSet.messages.count)
        XCTAssertEqual(["My phone number is: 321-321-4321"], bodies(forMessageResults: resultSet.messages))

        resultSet = getResultSet(searchText: "PHO 3213")
        XCTAssertEqual(1, resultSet.messages.count)
        XCTAssertEqual(["My phone number is: 321-321-4321"], bodies(forMessageResults: resultSet.messages))

        resultSet = getResultSet(searchText: "fax")
        XCTAssertEqual(1, resultSet.messages.count)
        XCTAssertEqual(["My fax is: 222-333-4444"], bodies(forMessageResults: resultSet.messages))

        resultSet = getResultSet(searchText: "fax 2223")
        XCTAssertEqual(1, resultSet.messages.count)
        XCTAssertEqual(["My fax is: 222-333-4444"], bodies(forMessageResults: resultSet.messages))
    }

    // MARK: - More Tests

    func testModelLifecycle1() {

        var thread: TSGroupThread! = nil
        self.write { transaction in
            thread = try! GroupManager.createGroupForTests(members: [self.aliceRecipient, self.bobRecipient, DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read)!.aciAddress],
                                                           name: "Lifecycle",
                                                           transaction: transaction)
        }

        let message1 = TSOutgoingMessage(in: thread, messageBody: "This world contains glory and despair.", attachmentId: nil)
        let message2 = TSOutgoingMessage(in: thread, messageBody: "This world contains hope and despair.", attachmentId: nil)

        XCTAssertEqual(0, getResultSet(searchText: "GLORY").messages.count)
        XCTAssertEqual(0, getResultSet(searchText: "HOPE").messages.count)
        XCTAssertEqual(0, getResultSet(searchText: "DESPAIR").messages.count)
        XCTAssertEqual(0, getResultSet(searchText: "DEFEAT").messages.count)

        self.write { transaction in
            message1.anyInsert(transaction: transaction)
            message2.anyInsert(transaction: transaction)
        }

        XCTAssertEqual(1, getResultSet(searchText: "GLORY").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "HOPE").messages.count)
        XCTAssertEqual(2, getResultSet(searchText: "DESPAIR").messages.count)
        XCTAssertEqual(0, getResultSet(searchText: "DEFEAT").messages.count)

        self.write { transaction in
            message1.update(withMessageBody: "This world contains glory and defeat.", transaction: transaction)
        }

        XCTAssertEqual(1, getResultSet(searchText: "GLORY").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "HOPE").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "DESPAIR").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "DEFEAT").messages.count)

        self.write { transaction in
            message1.anyRemove(transaction: transaction)
        }

        XCTAssertEqual(0, getResultSet(searchText: "GLORY").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "HOPE").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "DESPAIR").messages.count)
        XCTAssertEqual(0, getResultSet(searchText: "DEFEAT").messages.count)

        self.write { transaction in
            message2.anyRemove(transaction: transaction)
        }

        XCTAssertEqual(0, getResultSet(searchText: "GLORY").messages.count)
        XCTAssertEqual(0, getResultSet(searchText: "HOPE").messages.count)
        XCTAssertEqual(0, getResultSet(searchText: "DESPAIR").messages.count)
        XCTAssertEqual(0, getResultSet(searchText: "DEFEAT").messages.count)
    }

    func testModelLifecycle2() {

        self.write { transaction in
            let thread = try! GroupManager.createGroupForTests(members: [self.aliceRecipient, self.bobRecipient, DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read)!.aciAddress],
                                                               name: "Lifecycle",
                                                               transaction: transaction)

            let message1 = TSOutgoingMessage(in: thread, messageBody: "This world contains glory and despair.", attachmentId: nil)
            let message2 = TSOutgoingMessage(in: thread, messageBody: "This world contains hope and despair.", attachmentId: nil)

            message1.anyInsert(transaction: transaction)
            message2.anyInsert(transaction: transaction)
        }

        XCTAssertEqual(1, getResultSet(searchText: "GLORY").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "HOPE").messages.count)
        XCTAssertEqual(2, getResultSet(searchText: "DESPAIR").messages.count)
        XCTAssertEqual(0, getResultSet(searchText: "DEFEAT").messages.count)

        self.write { transaction in
            TSInteraction.anyRemoveAllWithInstantation(transaction: transaction)
        }

        XCTAssertEqual(0, getResultSet(searchText: "GLORY").messages.count)
        XCTAssertEqual(0, getResultSet(searchText: "HOPE").messages.count)
        XCTAssertEqual(0, getResultSet(searchText: "DESPAIR").messages.count)
        XCTAssertEqual(0, getResultSet(searchText: "DEFEAT").messages.count)
    }

    func testDiacritics() {

        self.write { transaction in
            let thread = try! GroupManager.createGroupForTests(members: [self.aliceRecipient, self.bobRecipient, DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read)!.aciAddress],
                                                               name: "Lifecycle",
                                                               transaction: transaction)

            TSOutgoingMessage(in: thread, messageBody: "NOËL and SØRINA and ADRIÁN and FRANÇOIS and NUÑEZ and Björk.", attachmentId: nil).anyInsert(transaction: transaction)
        }

        XCTAssertEqual(1, getResultSet(searchText: "NOËL").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "noel").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "SØRINA").messages.count)
        // I guess Ø isn't a diacritical mark but a separate letter.
        XCTAssertEqual(0, getResultSet(searchText: "sorina").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "ADRIÁN").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "adrian").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "FRANÇOIS").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "francois").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "NUÑEZ").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "nunez").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "Björk").messages.count)
        XCTAssertEqual(1, getResultSet(searchText: "Bjork").messages.count)
    }

    private func AssertValidResultSet(query: String, expectedResultCount: Int, file: StaticString = #file, line: UInt = #line) {
        // For these simple test cases, the snippet should contain the entire query.
        let expectedSnippetContent: String = query

        let resultSet = getResultSet(searchText: query)
        XCTAssertEqual(expectedResultCount, resultSet.messages.count, file: file, line: line)
        for result in resultSet.messages {
            guard let snippet = result.snippet else {
                XCTFail("Missing snippet.", file: file, line: line)
                continue
            }
            let snippetString: String
            switch snippet {
            case .text(let string):
                snippetString = string
            case .attributedText(let nSAttributedString):
                snippetString = nSAttributedString.string
            case .messageBody(let hydratedMessageBody):
                snippetString = hydratedMessageBody.asPlaintext()
            }
            XCTAssertTrue(snippetString.lowercased().contains(expectedSnippetContent.lowercased()), file: file, line: line)
        }
    }

    func testSnippets() {

        var thread: TSGroupThread! = nil
        self.write { transaction in
            thread = try! GroupManager.createGroupForTests(members: [self.aliceRecipient, self.bobRecipient, DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read)!.aciAddress],
                                                           name: "Lifecycle",
                                                           transaction: transaction)
        }

        let message1 = TSOutgoingMessage(in: thread, messageBody: "This world contains glory and despair.", attachmentId: nil)
        let message2 = TSOutgoingMessage(in: thread, messageBody: "This world contains hope and despair.", attachmentId: nil)

        AssertValidResultSet(query: "GLORY", expectedResultCount: 0)
        AssertValidResultSet(query: "HOPE", expectedResultCount: 0)
        AssertValidResultSet(query: "DESPAIR", expectedResultCount: 0)
        AssertValidResultSet(query: "DEFEAT", expectedResultCount: 0)

        self.write { transaction in
            message1.anyInsert(transaction: transaction)
            message2.anyInsert(transaction: transaction)
        }

        AssertValidResultSet(query: "GLORY", expectedResultCount: 1)
        AssertValidResultSet(query: "HOPE", expectedResultCount: 1)
        AssertValidResultSet(query: "DESPAIR", expectedResultCount: 2)
        AssertValidResultSet(query: "DEFEAT", expectedResultCount: 0)
    }

    // MARK: - Perf

    func testPerf() {
        databaseStorage.write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: .forUnitTests,
                tx: tx.asV2Write
            )
        }

        let string1 = "krazy"
        let string2 = "kat"
        let messageCount: UInt = 100

        Bench(title: "Populate Index", memorySamplerRatio: 1) { _ in
            self.write { transaction in
                let thread = try! GroupManager.createGroupForTests(members: [self.aliceRecipient, self.bobRecipient, DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read)!.aciAddress],
                                                                   name: "Perf",
                                                                   transaction: transaction)

                TSOutgoingMessage(in: thread, messageBody: string1, attachmentId: nil).anyInsert(transaction: transaction)

                for _ in 0...messageCount {
                    let message = TSOutgoingMessage(in: thread, messageBody: UUID().uuidString, attachmentId: nil)
                    message.anyInsert(transaction: transaction)
                    message.update(withMessageBody: UUID().uuidString, transaction: transaction)
                }

                TSOutgoingMessage(in: thread, messageBody: string2, attachmentId: nil).anyInsert(transaction: transaction)
            }
        }

        Bench(title: "Search", memorySamplerRatio: 1) { _ in
            self.read { transaction in
                let getMatchCount = { (searchText: String) -> UInt in
                    var count: UInt = 0
                    FullTextSearchFinder.enumerateObjects(
                        searchText: searchText,
                        collections: [TSMessage.collection()],
                        maxResults: 500,
                        transaction: transaction
                    ) { (match, snippet, _) in
                        Logger.verbose("searchText: \(searchText), match: \(match), snippet: \(snippet)")
                        count += 1
                    }
                    return count
                }
                XCTAssertEqual(1, getMatchCount(string1))
                XCTAssertEqual(1, getMatchCount(string2))
                XCTAssertEqual(0, getMatchCount(UUID().uuidString))
            }
        }
    }

    // MARK: - Helpers

    func bodies<T>(forMessageResults messageResults: [ConversationSearchResult<T>]) -> [String] {
        var result = [String]()

        self.read { transaction in
            for messageResult in messageResults {
                guard let messageId = messageResult.messageId else {
                    owsFailDebug("message result missing message id")
                    continue
                }
                guard let interaction = TSInteraction.anyFetch(uniqueId: messageId, transaction: transaction) else {
                    owsFailDebug("couldn't load interaction for message result")
                    continue
                }
                guard let message = interaction as? TSMessage else {
                    owsFailDebug("invalid message for message result")
                    continue
                }
                guard let messageBody = message.body else {
                    owsFailDebug("message result missing message body")
                    continue
                }
                result.append(messageBody)
            }
        }

        return result.sorted()
    }

    private func searchConversations(searchText: String) -> [ThreadViewModel] {
        let results = getResultSet(searchText: searchText)
        let contactThreads = results.contactThreads.map { $0.thread }
        let groupThreads = results.groupThreads.map { $0.thread }
        return contactThreads + groupThreads
    }

    private func getResultSet(searchText: String) -> HomeScreenSearchResultSet {
        self.read { transaction in
            self.searcher.searchForHomeScreen(
                searchText: searchText,
                isCanceled: { false },
                transaction: transaction
            )!
        }
    }
}
