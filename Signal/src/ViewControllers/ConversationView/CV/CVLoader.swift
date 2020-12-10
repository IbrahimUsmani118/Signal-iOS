//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

// This entity performs a single load.
@objc
public class CVLoader: NSObject {

    // MARK: - Dependencies

    private static var databaseStorage: SDSDatabaseStorage {
        return .shared
    }

    // MARK: -

    private let threadUniqueId: String
    private let loadRequest: CVLoadRequest
    private let viewStateSnapshot: CVViewStateSnapshot
    private let lastRenderState: CVRenderState
    private let messageMapping: CVMessageMapping

    private let benchSteps = BenchSteps(title: "CVLoader")

    required init(threadUniqueId: String,
                  loadRequest: CVLoadRequest,
                  viewStateSnapshot: CVViewStateSnapshot,
                  lastRenderState: CVRenderState,
                  messageMapping: CVMessageMapping) {
        self.threadUniqueId = threadUniqueId
        self.loadRequest = loadRequest
        self.viewStateSnapshot = viewStateSnapshot
        self.lastRenderState = lastRenderState
        self.messageMapping = messageMapping
    }

    func loadPromise() -> Promise<CVUpdate> {

        let threadUniqueId = self.threadUniqueId
        let loadRequest = self.loadRequest
        let viewStateSnapshot = self.viewStateSnapshot
        let lastRenderState = self.lastRenderState
        let messageMapping = self.messageMapping

        Logger.verbose("---- loadType: \(loadRequest.loadType)")

        struct LoadState {
            let threadViewModel: ThreadViewModel
            let items: [CVRenderItem]
            let threadInteractionCount: UInt
        }

        return firstly(on: CVUtils.workQueue) { () -> LoadState in
            // To ensure coherency, the entire load should use this transaction.
            try Self.databaseStorage.read { transaction in

                self.benchSteps.step("start")
                let loadThreadViewModel = { () -> ThreadViewModel in
                    guard let thread = TSThread.anyFetch(uniqueId: threadUniqueId, transaction: transaction) else {
                        // If thread has been deleted from the database, use last known model.
                        return lastRenderState.threadViewModel
                    }
                    return ThreadViewModel(thread: thread, transaction: transaction)
                }
                let threadViewModel = loadThreadViewModel()

                let loadContext = CVLoadContext(loadRequest: loadRequest,
                                                threadViewModel: threadViewModel,
                                                viewStateSnapshot: viewStateSnapshot,
                                                messageMapping: messageMapping,
                                                lastRenderState: lastRenderState,
                                                transaction: transaction)

                self.benchSteps.step("threadViewModel")

                if loadRequest.shouldClearOldestUnreadInteraction {
                    messageMapping.oldestUnreadInteraction = nil
                }

                // Don't cache in the reset() case.
                let canReuseInteractions = loadRequest.canReuseInteractionModels && !loadRequest.didReset
                let updatedInteractionIds = loadRequest.updatedInteractionIds
                let deletedInteractionIds: Set<String>? = loadRequest.didReset ? loadRequest.deletedInteractionIds : nil
                var reusableInteractions = [String: TSInteraction]()
                if canReuseInteractions {
                    for renderItem in lastRenderState.items {
                        let interaction = renderItem.interaction
                        let interactionId = interaction.uniqueId
                        if !updatedInteractionIds.contains(interactionId) {
                            reusableInteractions[interactionId] = interaction
                        }
                    }
                }

                do {
                    switch loadRequest.loadType {
                    case .loadInitialMapping(let focusMessageIdOnOpen, _):
                        owsAssertDebug(reusableInteractions.isEmpty)
                        Logger.verbose("---- .loadInitialMapping")
                        try messageMapping.loadInitialMessagePage(focusMessageId: focusMessageIdOnOpen,
                                                                  reusableInteractions: [:],
                                                                  deletedInteractionIds: [],
                                                                  transaction: transaction)
                    case .loadSameLocation:
                        Logger.verbose("---- .loadSameLocation")
                        try messageMapping.loadSameLocation(reusableInteractions: reusableInteractions,
                                                            deletedInteractionIds: deletedInteractionIds,
                                                            transaction: transaction)
                    case .loadOlder:
                        Logger.verbose("---- .loadOlder")
                        try messageMapping.loadOlderMessagePage(reusableInteractions: reusableInteractions,
                                                                deletedInteractionIds: deletedInteractionIds,
                                                                transaction: transaction)
                    case .loadNewer:
                        Logger.verbose("---- .loadNewer")
                        try messageMapping.loadNewerMessagePage(reusableInteractions: reusableInteractions,
                                                                deletedInteractionIds: deletedInteractionIds,
                                                                transaction: transaction)
                    case .loadNewest:
                        Logger.verbose("---- .loadNewest")
                        try messageMapping.loadNewestMessagePage(reusableInteractions: reusableInteractions,
                                                                 deletedInteractionIds: deletedInteractionIds,
                                                                 transaction: transaction)
                    case .loadPageAroundInteraction(let interactionId, _):
                        Logger.verbose("---- .loadPageAroundInteraction")
                        try messageMapping.loadMessagePage(aroundInteractionId: interactionId,
                                                           reusableInteractions: reusableInteractions,
                                                           deletedInteractionIds: deletedInteractionIds,
                                                           transaction: transaction)
                    }
                } catch {
                    owsFailDebug("Error: \(error)")
                    // Fail over to try to load newest.
                    try messageMapping.loadNewestMessagePage(reusableInteractions: reusableInteractions,
                                                             deletedInteractionIds: deletedInteractionIds,
                                                             transaction: transaction)
                }

                self.benchSteps.step("messageMapping")

                let thread = threadViewModel.threadRecord
                let threadInteractionCount = thread.numberOfInteractions(with: transaction)

                self.benchSteps.step("threadInteractionCount")

                let items: [CVRenderItem] = self.buildRenderItems(loadContext: loadContext)

                self.benchSteps.step("buildRenderItems")

                return LoadState(threadViewModel: threadViewModel,
                                 items: items,
                                 threadInteractionCount: threadInteractionCount)
            }
        }.map(on: CVText.measurementQueue) { (loadState: LoadState) -> (LoadState, CVRenderState) in

            let conversationStyle = viewStateSnapshot.conversationStyle
            let items: [CVRenderItem]
            if CVText.measureOnMainThread {
                self.benchSteps.step("measure cells on main.1")
                items = loadState.items.map { item in
                    // Measure
                    let cellMeasurement = Self.buildCellMeasurement(rootComponent: item.rootComponent,
                                                                    conversationStyle: conversationStyle)
                    return CVRenderItem(itemModel: item.itemModel,
                                        rootComponent: item.rootComponent,
                                        cellMeasurement: cellMeasurement)
                }
                self.benchSteps.step("measure cells on main.2")
            } else {
                // Items are already measured.
                items = loadState.items
            }

            //                for item in items {
            //                    Logger.verbose("item: \(item.debugDescription)")
            //                }

            let threadViewModel = loadState.threadViewModel
            let renderState = CVRenderState(threadViewModel: threadViewModel,
                                            lastThreadViewModel: lastRenderState.threadViewModel,
                                            items: items,
                                            canLoadOlderItems: messageMapping.canLoadOlder,
                                            canLoadNewerItems: messageMapping.canLoadNewer,
                                            viewStateSnapshot: viewStateSnapshot,
                                            loadType: loadRequest.loadType)

            self.benchSteps.step("build render state")

            return (loadState, renderState)
        }.map(on: CVUtils.workQueue) { (loadState: LoadState, renderState: CVRenderState) -> CVUpdate in

            let threadInteractionCount = loadState.threadInteractionCount
            let update = CVUpdate.build(renderState: renderState,
                                        lastRenderState: lastRenderState,
                                        loadRequest: loadRequest,
                                        threadInteractionCount: threadInteractionCount)

            self.benchSteps.step("build render update")

            self.benchSteps.logAll()

            Logger.verbose("---- load complete: \(renderState.items.count)")
            return update
        }
    }

    // MARK: -

    private func buildRenderItems(loadContext: CVLoadContext) -> [CVRenderItem] {

        let conversationStyle = loadContext.conversationStyle

        // Don't cache in the reset() case.
        let canReuseState = (loadRequest.canReuseComponentStates &&
                                conversationStyle.isEqualForCellRendering(lastRenderState.conversationStyle))

        var itemModelBuilder = CVItemModelBuilder(loadContext: loadContext)

        // CVComponentStates are loaded from the database; these loads
        // can be expensive. Therefore we want to reuse them _unless_:
        //
        // * The corresponding interaction was updated.
        // * We're do a "reset" reload where we deliberately reload everything, e.g.
        //   in response to an error or a cross-process write, etc.
        if canReuseState {
            itemModelBuilder.reuseComponentStates(lastRenderState: lastRenderState,
                                                  updatedInteractionIds: loadRequest.updatedInteractionIds)
        }
        let itemModels: [CVItemModel] = itemModelBuilder.buildItems()

        //        Logger.verbose("---- itemViewStates: \(itemViewStates.count)")
        //        Logger.verbose("---- itemModels: \(itemModels.count)")

        var renderItems = [CVRenderItem]()
        for itemModel in itemModels {
            guard let renderItem = buildRenderItem(itemBuildingContext: loadContext,
                                                   itemModel: itemModel) else {
                continue
            }
            renderItems.append(renderItem)
        }

        //        Logger.verbose("---- renderItems: \(renderItems.count)")

        return renderItems
    }

    private func buildRenderItem(itemBuildingContext: CVItemBuildingContext,
                                 itemModel: CVItemModel) -> CVRenderItem? {
        Self.buildRenderItem(itemBuildingContext: itemBuildingContext,
                             itemModel: itemModel)
    }

    @objc
    public static func buildStandaloneRenderItem(interaction: TSInteraction,
                                                 thread: TSThread,
                                                 containerView: UIView,
                                                 transaction: SDSAnyReadTransaction) -> CVRenderItem? {
        let cellMediaCache = NSCache<NSString, AnyObject>()
        let conversationStyle = ConversationStyle(type: .`default`,
                                                  thread: thread,
                                                  viewWidth: containerView.width)
        let coreState = CVCoreState(conversationStyle: conversationStyle,
                                    cellMediaCache: cellMediaCache)
        return CVLoader.buildStandaloneRenderItem(interaction: interaction,
                                                  thread: thread,
                                                  coreState: coreState,
                                                  transaction: transaction)
    }

    private static func buildStandaloneRenderItem(interaction: TSInteraction,
                                                  thread: TSThread,
                                                  coreState: CVCoreState,
                                                  transaction: SDSAnyReadTransaction) -> CVRenderItem? {
        AssertIsOnMainThread()

        let threadViewModel = ThreadViewModel(thread: thread, transaction: transaction)
        let viewStateSnapshot = CVViewStateSnapshot.mockSnapshotForStandaloneItems(coreState: coreState)
        let avatarBuilder = CVAvatarBuilder(transaction: transaction)
        let itemBuildingContext = CVItemBuildingContextImpl(threadViewModel: threadViewModel,
                                                            viewStateSnapshot: viewStateSnapshot,
                                                            transaction: transaction,
                                                            avatarBuilder: avatarBuilder)
        guard let itemModel = CVItemModelBuilder.buildStandaloneItem(interaction: interaction,
                                                                     thread: thread,
                                                                     itemBuildingContext: itemBuildingContext,
                                                                     transaction: transaction) else {
            owsFailDebug("Couldn't build item model.")
            return nil
        }
        return Self.buildRenderItem(itemBuildingContext: itemBuildingContext,
                                    itemModel: itemModel)
    }

    private static func buildRenderItem(itemBuildingContext: CVItemBuildingContext,
                                        itemModel: CVItemModel) -> CVRenderItem? {

        let conversationStyle = itemBuildingContext.conversationStyle

        let rootComponent: CVRootComponent
        switch itemModel.messageCellType {
        case .dateHeader:
            guard let dateHeaderState = itemModel.itemViewState.dateHeaderState else {
                owsFailDebug("Missing dateHeader.")
                return nil
            }
            rootComponent = CVComponentDateHeader(itemModel: itemModel,
                                                  dateHeaderState: dateHeaderState)
        case .unreadIndicator:
            rootComponent = CVComponentUnreadIndicator(itemModel: itemModel)
        case .threadDetails:
            guard let threadDetails = itemModel.componentState.threadDetails else {
                owsFailDebug("Missing threadDetails.")
                return nil
            }
            rootComponent = CVComponentThreadDetails(itemModel: itemModel, threadDetails: threadDetails)
        case .textOnlyMessage, .audio, .genericAttachment, .contactShare, .bodyMedia, .viewOnce, .stickerMessage:
            rootComponent = CVComponentMessage(itemModel: itemModel)
        case .typingIndicator:
            guard let typingIndicator = itemModel.componentState.typingIndicator else {
                owsFailDebug("Missing typingIndicator.")
                return nil
            }
            rootComponent = CVComponentTypingIndicator(itemModel: itemModel,
                                                       typingIndicator: typingIndicator)
        case .systemMessage:
            guard let systemMessage = itemModel.componentState.systemMessage else {
                owsFailDebug("Missing systemMessage.")
                return nil
            }
            rootComponent = CVComponentSystemMessage(itemModel: itemModel, systemMessage: systemMessage)
        case .unknown:
            Logger.warn("---- discarding item: \(itemModel.messageCellType).")
            return nil
        default:
            owsFailDebug("---- discarding item: \(itemModel.messageCellType).")
            return nil
        }

        assertOnQueue(CVUtils.workQueue)

        // If we're going to measure on the main thread, use
        // an empty placeholder measurement for now.
        let cellMeasurement = (CVText.measureOnMainThread
                                ? buildEmptyCellMeasurement()
                                : buildCellMeasurement(rootComponent: rootComponent,
                                                       conversationStyle: conversationStyle))

        return CVRenderItem(itemModel: itemModel,
                            rootComponent: rootComponent,
                            cellMeasurement: cellMeasurement)
    }

    private static func buildEmptyCellMeasurement() -> CVCellMeasurement {
        CVCellMeasurement.Builder().build()
    }

    private static func buildCellMeasurement(rootComponent: CVRootComponent,
                                             conversationStyle: ConversationStyle) -> CVCellMeasurement {
        assertOnQueue(CVText.measurementQueue)

        let measurementBuilder = CVCellMeasurement.Builder()
        measurementBuilder.cellSize = rootComponent.measure(maxWidth: conversationStyle.viewWidth,
                                                            measurementBuilder: measurementBuilder)
        let cellMeasurement = measurementBuilder.build()
        owsAssertDebug(cellMeasurement.cellSize.width <= conversationStyle.viewWidth)
        return cellMeasurement
    }
}
