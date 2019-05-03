//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import XCTest
import Foundation
import SignalCoreKit
import SignalMetadataKit
@testable import SignalServiceKit

class StickerManagerTest: SSKBaseTestSwift {

    var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    func testFirstEmoji() {
        XCTAssertNil(StickerManager.firstEmoji(inEmojiString: nil))
        XCTAssertEqual("🇨🇦", StickerManager.firstEmoji(inEmojiString: "🇨🇦"))
        XCTAssertEqual("🇨🇦", StickerManager.firstEmoji(inEmojiString: "🇨🇦🇨🇦"))
        XCTAssertEqual("🇹🇹", StickerManager.firstEmoji(inEmojiString: "🇹🇹🌼🇹🇹🌼🇹🇹"))
        XCTAssertEqual("🌼", StickerManager.firstEmoji(inEmojiString: "🌼🇹🇹🌼🇹🇹"))
        XCTAssertEqual("👌🏽", StickerManager.firstEmoji(inEmojiString: "👌🏽👌🏾"))
        XCTAssertEqual("👌🏾", StickerManager.firstEmoji(inEmojiString: "👌🏾👌🏽"))
        XCTAssertEqual("👾", StickerManager.firstEmoji(inEmojiString: "👾🙇💁🙅🙆🙋🙎🙍"))
        XCTAssertEqual("👾", StickerManager.firstEmoji(inEmojiString: "👾🙇💁🙅🙆🙋🙎🙍"))
    }

    func testAllEmoji() {
        XCTAssertEqual([], StickerManager.allEmoji(inEmojiString: nil))
        XCTAssertEqual(["🇨🇦"], StickerManager.allEmoji(inEmojiString: "🇨🇦"))
        XCTAssertEqual(["🇨🇦", "🇨🇦"], StickerManager.allEmoji(inEmojiString: "🇨🇦🇨🇦"))
        XCTAssertEqual(["🇹🇹", "🌼", "🇹🇹", "🌼", "🇹🇹"], StickerManager.allEmoji(inEmojiString: "🇹🇹🌼🇹🇹🌼🇹🇹"))
        XCTAssertEqual(["🌼", "🇹🇹", "🌼", "🇹🇹"], StickerManager.allEmoji(inEmojiString: "🌼🇹🇹🌼🇹🇹"))
        XCTAssertEqual(["👌🏽", "👌🏾"], StickerManager.allEmoji(inEmojiString: "👌🏽👌🏾"))
        XCTAssertEqual(["👌🏾", "👌🏽"], StickerManager.allEmoji(inEmojiString: "👌🏾👌🏽"))
        XCTAssertEqual(["👾", "🙇", "💁", "🙅", "🙆", "🙋", "🙎", "🙍"], StickerManager.allEmoji(inEmojiString: "👾🙇💁🙅🙆🙋🙎🙍"))

        XCTAssertEqual(["🇨🇦"], StickerManager.allEmoji(inEmojiString: "a🇨🇦a"))
        XCTAssertEqual(["🇨🇦", "🇹🇹"], StickerManager.allEmoji(inEmojiString: "a🇨🇦b🇹🇹c"))
    }

    func testSuggestedStickers() {
        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "").count)
        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "Hey Bob, what's up?").count)
        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "🇨🇦").count)
        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "🇨🇦🇹🇹").count)
        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "This is a flag: 🇨🇦").count)

        let stickerInfo = StickerInfo.defaultValue
        let stickerData = Randomness.generateRandomBytes(1)!

        let expectation = self.expectation(description: "Wait for sticker to be installed.")
        StickerManager.installSticker(stickerInfo: stickerInfo,
                                      stickerData: stickerData,
                                      emojiString: "🌼🇨🇦") {
                                        expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0, handler: nil)

        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "").count)
        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "Hey Bob, what's up?").count)
        // The sticker should only be suggested if user enters a single emoji
        // (and nothing else) that is associated with the sticker.
        XCTAssertEqual(1, StickerManager.suggestedStickers(forTextInput: "🇨🇦").count)
        XCTAssertEqual(1, StickerManager.suggestedStickers(forTextInput: "🌼").count)
        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "🇹🇹").count)
        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "a🇨🇦").count)
        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "🇨🇦a").count)
        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "🇨🇦🇹🇹").count)
        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "🌼🇨🇦").count)
        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "This is a flag: 🇨🇦").count)

        databaseStorage.writeSwallowingErrors { (transaction) in
            // Don't bother calling completion.
            _ = StickerManager.uninstallSticker(stickerInfo: stickerInfo,
                                                    transaction: transaction)
        }

        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "").count)
        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "Hey Bob, what's up?").count)
        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "🇨🇦").count)
        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "🇨🇦🇹🇹").count)
        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "This is a flag: 🇨🇦").count)
    }
}
