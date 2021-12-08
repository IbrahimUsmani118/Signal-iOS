//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalMessaging

@objc
public class HVTableDataSource: NSObject {
    private var viewState: HVViewState!

    public let tableView = HVTableView()

    @objc
    public weak var viewController: HomeViewController?

    fileprivate var splitViewController: UISplitViewController? { viewController?.splitViewController }

    @objc
    public var renderState: HVRenderState = .empty

    private let kArchivedConversationsReuseIdentifier = "kArchivedConversationsReuseIdentifier"

    fileprivate var lastReloadDate: Date? { tableView.lastReloadDate }

    fileprivate var lastPreloadCellDate: Date?

    public required override init() {
        super.init()
    }

    func configure(viewState: HVViewState) {
        AssertIsOnMainThread()

        self.viewState = viewState

        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.separatorColor = Theme.cellSeparatorColor
        tableView.register(HomeViewCell.self, forCellReuseIdentifier: HomeViewCell.reuseIdentifier)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: kArchivedConversationsReuseIdentifier)
        tableView.tableFooterView = UIView()
    }
}

// MARK: -

extension HVTableDataSource {
    public func threadViewModel(forThread thread: TSThread) -> ThreadViewModel {
        let threadViewModelCache = viewState.threadViewModelCache
        if let value = threadViewModelCache.get(key: thread.uniqueId) {
            return value
        }
        let threadViewModel = databaseStorage.read { transaction in
            ThreadViewModel(thread: thread, forHomeView: true, transaction: transaction)
        }
        threadViewModelCache.set(key: thread.uniqueId, value: threadViewModel)
        return threadViewModel
    }

    @objc
    func threadViewModel(forIndexPath indexPath: IndexPath) -> ThreadViewModel? {
        guard let thread = self.thread(forIndexPath: indexPath) else {
            return nil
        }
        return self.threadViewModel(forThread: thread)
    }

    func thread(forIndexPath indexPath: IndexPath) -> TSThread? {
        renderState.thread(forIndexPath: indexPath)
    }
}

// MARK: - UIScrollViewDelegate

extension HVTableDataSource: UIScrollViewDelegate {

    private func preloadCellsIfNecessary() {
        AssertIsOnMainThread()

        guard let viewController = self.viewController else {
            owsFailDebug("Missing viewController.")
            return
        }
        guard viewController.hasEverAppeared else {
            return
        }
        let newContentOffset = tableView.contentOffset
        let oldContentOffset = viewController.lastKnownTableViewContentOffset
        viewController.lastKnownTableViewContentOffset = newContentOffset
        guard let oldContentOffset = oldContentOffset else {
            return
        }
        let deltaY = (newContentOffset - oldContentOffset).y
        guard deltaY != 0 else {
            return
        }
        let isScrollingDownward = deltaY > 0

        // Debounce.
        let maxPreloadFrequency: TimeInterval = kSecondInterval / 100
        if let lastPreloadCellDate = self.lastPreloadCellDate,
           abs(lastPreloadCellDate.timeIntervalSinceNow) < maxPreloadFrequency {
            return
        }
        lastPreloadCellDate = Date()

        guard let visibleIndexPaths = tableView.indexPathsForVisibleRows else {
            owsFailDebug("Missing visibleIndexPaths.")
            return
        }
        let conversationIndexPaths = visibleIndexPaths.compactMap { indexPath -> IndexPath? in
            guard let section = HomeViewSection(rawValue: indexPath.section) else {
                owsFailDebug("Invalid section: \(indexPath.section).")
                return nil
            }

            switch section {
            case .reminders:
                return nil
            case .pinned, .unpinned:
                return indexPath
            case .archiveButton:
                return nil
            }
        }
        guard !conversationIndexPaths.isEmpty else {
            return
        }
        let sortedIndexPaths = conversationIndexPaths.sorted()
        var indexPathsToPreload = [IndexPath]()
        func tryToEnqueue(_ indexPath: IndexPath) {
            let rowCount = numberOfRows(inSection: indexPath.section)
            guard indexPath.row >= 0,
                  indexPath.row < rowCount else {
                return
            }
            indexPathsToPreload.append(indexPath)
        }

        let preloadCount: Int = 3
        if isScrollingDownward {
            guard let lastIndexPath = sortedIndexPaths.last else {
                owsFailDebug("Missing indexPath.")
                return
            }
            // Order matters; we want to preload in order of proximity
            // to viewport.
            for index in 0..<preloadCount {
                let offset = +index
                tryToEnqueue(IndexPath(row: lastIndexPath.row + offset,
                                       section: lastIndexPath.section))
            }
        } else {
            guard let firstIndexPath = sortedIndexPaths.first else {
                owsFailDebug("Missing indexPath.")
                return
            }
            guard firstIndexPath.row > 0 else {
                return
            }
            // Order matters; we want to preload in order of proximity
            // to viewport.
            for index in 0..<preloadCount {
                let offset = -index
                tryToEnqueue(IndexPath(row: firstIndexPath.row + offset,
                                       section: firstIndexPath.section))
            }
        }

        for indexPath in indexPathsToPreload {
            preloadCellIfNecessaryAsync(indexPath: indexPath)
        }
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        AssertIsOnMainThread()

        guard let viewController = viewController else {
            owsFailDebug("Missing viewController.")
            return
        }

        viewController.dismissSearchKeyboard()
    }
}

// MARK: -

@objc
public enum HomeViewMode: Int, CaseIterable {
    case archive
    case inbox
}

// MARK: -

@objc
public enum HomeViewSection: Int, CaseIterable {
    case reminders
    case pinned
    case unpinned
    case archiveButton
}

// MARK: -

extension HVTableDataSource: UITableViewDelegate {

    public func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        AssertIsOnMainThread()

        guard let section = HomeViewSection(rawValue: section) else {
            owsFailDebug("Invalid section: \(section).")
            return 0
        }

        switch section {
        case .pinned, .unpinned:
            if !renderState.hasPinnedAndUnpinnedThreads {
                return CGFloat.epsilon
            }

            return UITableView.automaticDimension
        default:
            // Without returning a header with a non-zero height, Grouped
            // table view will use a default spacing between sections. We
            // do not want that spacing so we use the smallest possible height.
            return CGFloat.epsilon
        }
    }

    public func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        AssertIsOnMainThread()

        // Without returning a footer with a non-zero height, Grouped
        // table view will use a default spacing between sections. We
        // do not want that spacing so we use the smallest possible height.
        return CGFloat.epsilon
    }

    public func tableView(_ tableView: UITableView,
                          viewForHeaderInSection section: Int) -> UIView? {
        AssertIsOnMainThread()

        guard let section = HomeViewSection(rawValue: section) else {
            owsFailDebug("Invalid section: \(section).")
            return nil
        }

        switch section {
        case .pinned, .unpinned:
            let container = UIView()
            container.layoutMargins = UIEdgeInsets(top: 14, leading: 16, bottom: 8, trailing: 16)

            let label = UILabel()
            container.addSubview(label)
            label.autoPinEdgesToSuperviewMargins()
            label.font = UIFont.ows_dynamicTypeBody.ows_semibold
            label.textColor = Theme.primaryTextColor
            label.text = (section == .pinned
                            ? NSLocalizedString("PINNED_SECTION_TITLE",
                                                comment: "The title for pinned conversation section on the conversation list")
                            : NSLocalizedString("UNPINNED_SECTION_TITLE",
                                                comment: "The title for unpinned conversation section on the conversation list"))

            return container
        default:
            return UIView()
        }
    }

    public func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        AssertIsOnMainThread()

        return UIView()
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        AssertIsOnMainThread()

        Logger.info("\(indexPath)")

        guard let viewController = self.viewController else {
            owsFailDebug("Missing viewController.")
            return
        }

        viewController.dismissSearchKeyboard()

        guard let section = HomeViewSection(rawValue: indexPath.section) else {
            owsFailDebug("Invalid section: \(indexPath.section).")
            return
        }

        switch section {
        case .reminders:
            break
        case .pinned, .unpinned:
            guard let threadViewModel = threadViewModel(forIndexPath: indexPath) else {
                owsFailDebug("Missing threadViewModel.")
                return
            }
            viewController.present(threadViewModel.threadRecord, action: .none, animated: true)
        case .archiveButton:
            viewController.showArchivedConversations()
        }
    }

    @available(iOS 13.0, *)
    public func tableView(_ tableView: UITableView,
                          contextMenuConfigurationForRowAt indexPath: IndexPath,
                          point: CGPoint) -> UIContextMenuConfiguration? {
        AssertIsOnMainThread()

        guard let viewController = self.viewController else {
            owsFailDebug("Missing viewController.")
            return nil
        }
        guard viewController.canPresentPreview(fromIndexPath: indexPath) else {
            return nil
        }
        guard let thread = renderState.thread(forIndexPath: indexPath) else {
            return nil
        }

        return UIContextMenuConfiguration(identifier: thread.uniqueId as NSString,
                                          previewProvider: { [weak viewController] in
                                            viewController?.createPreviewController(atIndexPath: indexPath)
                                          },
                                          actionProvider: { _ in
                                            // nil for now. But we may want to add options like "Pin" or "Mute" in the future
                                            return nil
                                          })
    }

    @available(iOS 13.0, *)
    public func tableView(_ tableView: UITableView,
                          previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        AssertIsOnMainThread()

        guard let threadId = configuration.identifier as? String else {
            owsFailDebug("Unexpected context menu configuration identifier")
            return nil
        }
        guard let indexPath = renderState.indexPath(forUniqueId: threadId) else {
            Logger.warn("No index path for threadId: \(threadId).")
            return nil
        }

        // Below is a partial workaround for database updates causing cells to reload mid-transition:
        // When the conversation view controller is dismissed, it touches the database which causes
        // the row to update.
        //
        // The way this *should* appear is that during presentation and dismissal, the row animates
        // into and out of the platter. Currently, it looks like UIKit uses a portal view to accomplish
        // this. It seems the row stays in its original position and is occluded by context menu internals
        // while the portal view is translated.
        //
        // But in our case, when the table view is updated the old cell will be removed and hidden by
        // UITableView. So mid-transition, the cell appears to disappear. What's left is the background
        // provided by UIPreviewParameters. By default this is opaque and the end result is that an empty
        // row appears while dismissal completes.
        //
        // A straightforward way to work around this is to just set the background color to clear. When
        // the row is updated because of a database change, it will appear to snap into position instead
        // of properly animating. This isn't *too* much of an issue since the row is usually occluded by
        // the platter anyway. This avoids the empty row issue. A better solution would probably be to
        // defer data source updates until the transition completes but, as far as I can tell, we aren't
        // notified when this happens.

        guard let cell = tableView.cellForRow(at: indexPath) as? HomeViewCell else {
            owsFailDebug("Invalid cell.")
            return nil
        }
        let cellFrame = tableView.rectForRow(at: indexPath)
        let center = cellFrame.center
        let target = UIPreviewTarget(container: tableView, center: center)
        let params = UIPreviewParameters()
        params.backgroundColor = .clear
        return UITargetedPreview(view: cell, parameters: params, target: target)
    }

    @available(iOS 13.0, *)
    public func tableView(_ tableView: UITableView,
                          willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
                          animator: UIContextMenuInteractionCommitAnimating) {
        AssertIsOnMainThread()

        guard let viewController = self.viewController else {
            owsFailDebug("Missing viewController.")
            return
        }
        guard let vc = animator.previewViewController else {
            owsFailDebug("Missing previewViewController.")
            return
        }
        animator.addAnimations { [weak viewController] in
            viewController?.commitPreviewController(vc)
        }
    }

    public func tableView(_ tableView: UITableView,
                          willDisplay cell: UITableViewCell,
                          forRowAt indexPath: IndexPath) {
        AssertIsOnMainThread()

        guard let cell = cell as? HomeViewCell else {
            return
        }
        viewController?.updateCellVisibility(cell: cell, isCellVisible: true)

        preloadCellsIfNecessary()
    }

    public func tableView(_ tableView: UITableView,
                          didEndDisplaying cell: UITableViewCell,
                          forRowAt indexPath: IndexPath) {
        AssertIsOnMainThread()

        guard let cell = cell as? HomeViewCell else {
            return
        }
        viewController?.updateCellVisibility(cell: cell, isCellVisible: false)
    }
}

// MARK: -

extension HVTableDataSource: UITableViewDataSource {

    public func numberOfSections(in tableView: UITableView) -> Int {
        AssertIsOnMainThread()

        return HomeViewSection.allCases.count
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        AssertIsOnMainThread()

        return numberOfRows(inSection: section)
    }

    fileprivate func numberOfRows(inSection section: Int) -> Int {
        AssertIsOnMainThread()

        guard let viewController = self.viewController else {
            owsFailDebug("Missing viewController.")
            return 0
        }

        guard let section = HomeViewSection(rawValue: section) else {
            owsFailDebug("Invalid section: \(section).")
            return 0
        }
        switch section {
        case .reminders:
            return viewController.hasVisibleReminders ? 1 : 0
        case .pinned:
            return renderState.pinnedThreads.count
        case .unpinned:
            return renderState.unpinnedThreads.count
        case .archiveButton:
            return viewController.hasArchivedThreadsRow ? 1 : 0
        }
    }

    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        AssertIsOnMainThread()
                guard let section = HomeViewSection(rawValue: indexPath.section) else {
            owsFailDebug("Invalid section: \(indexPath.section).")
            return UITableView.automaticDimension
        }

        switch section {
        case .reminders:
            return UITableView.automaticDimension
        case .pinned, .unpinned:
            return measureConversationCell(tableView: tableView, indexPath: indexPath)
        case .archiveButton:
            return UITableView.automaticDimension
        }
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        AssertIsOnMainThread()

        guard let viewController = self.viewController else {
            owsFailDebug("Missing viewController.")
            return UITableViewCell()
        }
        guard let section = HomeViewSection(rawValue: indexPath.section) else {
            owsFailDebug("Invalid section: \(indexPath.section).")
            return UITableViewCell()
        }

        let cell: UITableViewCell = {
            switch section {
            case .reminders:
                return viewController.reminderViewCell
            case .pinned, .unpinned:
                return buildConversationCell(tableView: tableView, indexPath: indexPath)
            case .archiveButton:
                return buildArchivedConversationsButtonCell(tableView: tableView, indexPath: indexPath)
            }
        }()

        if let splitViewController = self.splitViewController {
            if !splitViewController.isCollapsed {
                cell.selectedBackgroundView?.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray65 : .ows_gray15
                cell.backgroundColor = Theme.secondaryBackgroundColor
            }
        } else {
            owsFailDebug("Missing splitViewController.")
        }

        return cell
    }

    private func measureConversationCell(tableView: UITableView, indexPath: IndexPath) -> CGFloat {
        AssertIsOnMainThread()

        guard let viewController = self.viewController else {
            owsFailDebug("Missing viewController.")
            return UITableView.automaticDimension
        }
        if let result = viewController.conversationCellHeightCache {
            return result
        }
        guard let cellConfigurationAndContentToken = buildCellConfigurationAndContentTokenSync(forIndexPath: indexPath) else {
            owsFailDebug("Missing cellConfigurationAndContentToken.")
            return UITableView.automaticDimension
        }
        let result = HomeViewCell.measureCellHeight(cellContentToken: cellConfigurationAndContentToken.contentToken)
        viewController.conversationCellHeightCache = result
        return result
    }

    private func buildConversationCell(tableView: UITableView, indexPath: IndexPath) -> UITableViewCell {
        AssertIsOnMainThread()

        guard let cell = tableView.dequeueReusableCell(withIdentifier: HomeViewCell.reuseIdentifier) as? HomeViewCell else {
            owsFailDebug("Invalid cell.")
            return UITableViewCell()
        }
        guard let cellConfigurationAndContentToken = buildCellConfigurationAndContentTokenSync(forIndexPath: indexPath) else {
            owsFailDebug("Missing cellConfigurationAndContentToken.")
            return UITableViewCell()
        }
        let configuration = cellConfigurationAndContentToken.configuration
        let contentToken = cellConfigurationAndContentToken.contentToken

        cell.configure(cellContentToken: contentToken)

        let thread = configuration.thread.threadRecord
        let cellName: String = {
            if let groupThread = thread as? TSGroupThread {
                return "cell-group-\(groupThread.groupModel.groupName ?? "unknown")"
            } else if let contactThread = thread as? TSContactThread {
                return "cell-contact-\(contactThread.contactAddress.stringForDisplay)"
            } else {
                owsFailDebug("invalid-thread-\(thread.uniqueId) ")
                return "Unknown"
            }
        }()
        cell.accessibilityIdentifier = cellName

        if isConversationActive(forThread: thread) {
            tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
        } else {
            tableView.deselectRow(at: indexPath, animated: false)
        }

        return cell
    }

    private func isConversationActive(forThread thread: TSThread) -> Bool {
        AssertIsOnMainThread()

        guard let conversationSplitViewController = splitViewController as? ConversationSplitViewController else {
            owsFailDebug("Missing conversationSplitViewController.")
            return false
        }
        return conversationSplitViewController.selectedThread?.uniqueId == thread.uniqueId
    }

    private func buildArchivedConversationsButtonCell(tableView: UITableView, indexPath: IndexPath) -> UITableViewCell {
        AssertIsOnMainThread()

        guard let cell = tableView.dequeueReusableCell(withIdentifier: kArchivedConversationsReuseIdentifier) else {
            owsFailDebug("Invalid cell.")
            return UITableViewCell()
        }
        OWSTableItem.configureCell(cell)
        cell.selectionStyle = .none

        for subview in cell.contentView.subviews {
            subview.removeFromSuperview()
        }

        let disclosureImageName = CurrentAppContext().isRTL ? "NavBarBack" : "NavBarBackRTL"
        let disclosureImageView = UIImageView.withTemplateImageName(disclosureImageName,
                                                                    tintColor: UIColor(rgbHex: 0xd1d1d6))
        disclosureImageView.setContentHuggingHigh()
        disclosureImageView.setCompressionResistanceHigh()

        let label = UILabel()
        label.text = NSLocalizedString("HOME_VIEW_ARCHIVED_CONVERSATIONS",
                                       comment: "Label for 'archived conversations' button.")
        label.textAlignment = .center
        label.font = .ows_dynamicTypeBody
        label.textColor = Theme.primaryTextColor

        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 5
        // If alignment isn't set, UIStackView uses the height of
        // disclosureImageView, even if label has a higher desired height.
        stackView.alignment = .center
        stackView.addArrangedSubview(label)
        stackView.addArrangedSubview(disclosureImageView)
        cell.contentView.addSubview(stackView)
        stackView.autoCenterInSuperview()
        // Constrain to cell margins.
        stackView.autoPinEdge(toSuperviewMargin: .leading, relation: .greaterThanOrEqual)
        stackView.autoPinEdge(toSuperviewMargin: .trailing, relation: .greaterThanOrEqual)
        stackView.autoPinEdge(toSuperviewMargin: .top)
        stackView.autoPinEdge(toSuperviewMargin: .bottom)

        cell.accessibilityIdentifier = "archived_conversations"

        return cell
    }

    // MARK: - Edit Actions

    public func tableView(_ tableView: UITableView,
                          commit editingStyle: UITableViewCell.EditingStyle,
                          forRowAt indexPath: IndexPath) {
        AssertIsOnMainThread()

        // TODO: Is this method necessary?
    }

    public func tableView(_ tableView: UITableView,
                          trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        AssertIsOnMainThread()

        guard let section = HomeViewSection(rawValue: indexPath.section) else {
            owsFailDebug("Invalid section: \(indexPath.section).")
            return nil
        }

        switch section {
        case .reminders, .archiveButton:
            return nil
        case .pinned, .unpinned:
            guard let threadViewModel = threadViewModel(forIndexPath: indexPath) else {
                owsFailDebug("Missing threadViewModel.")
                return nil
            }
            guard let viewController = self.viewController else {
                owsFailDebug("Missing viewController.")
                return nil
            }

            let muteAction = UIContextualAction(style: .normal,
                                                title: nil) { [weak viewController] (_, _, completion) in
                if threadViewModel.isMuted {
                    viewController?.unmuteThread(threadViewModel: threadViewModel)
                } else {
                    viewController?.muteThreadWithSelection(threadViewModel: threadViewModel)
                }
                completion(false)
            }
            muteAction.backgroundColor = .ows_accentIndigo
            muteAction.image = self.actionImage(name: threadViewModel.isMuted ? "bell-solid-24" : "bell-disabled-solid-24",
                                                title: threadViewModel.isMuted ? CommonStrings.unmuteButton : CommonStrings.muteButton)
            muteAction.accessibilityLabel = threadViewModel.isMuted ? CommonStrings.unmuteButton :CommonStrings.muteButton

            let deleteAction = UIContextualAction(style: .destructive,
                                                  title: nil) { [weak viewController] (_, _, completion) in
                viewController?.deleteThreadWithConfirmation(threadViewModel: threadViewModel)
                completion(false)
            }
            deleteAction.backgroundColor = .ows_accentRed
            deleteAction.image = self.actionImage(name: "trash-solid-24",
                                                  title: CommonStrings.deleteButton)
            deleteAction.accessibilityLabel = CommonStrings.deleteButton

            let archiveAction = UIContextualAction(style: .normal,
                                                   title: nil) { [weak viewController] (_, _, completion) in
                viewController?.archiveThread(threadViewModel: threadViewModel)
                completion(false)
            }

            let archiveTitle = (viewController.homeViewMode == .inbox
                                    ? CommonStrings.archiveAction
                                    : CommonStrings.unarchiveAction)

            archiveAction.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray45 : .ows_gray25
            archiveAction.image = self.actionImage(name: "archive-solid-24",
                                                  title: archiveTitle)
            archiveAction.accessibilityLabel = archiveTitle

            // The first action will be auto-performed for "very long swipes".
            return UISwipeActionsConfiguration(actions: [ archiveAction, deleteAction, muteAction ])
        }
    }

    private func actionImage(name imageName: String, title: String) -> UIImage? {
        AssertIsOnMainThread()

        // We need to bake the title text into the image because `UIContextualAction`
        // only displays title + image when the cell's height > 91. We want to always
        // show both.
        guard let image = UIImage(named: imageName) else {
            owsFailDebug("Missing image.")
            return nil
        }
        guard let image = image.withTitle(title,
                                          font: UIFont.systemFont(ofSize: 13),
                                          color: .ows_white,
                                          maxTitleWidth: 68,
                                          minimumScaleFactor: CGFloat(8) / CGFloat(13),
                                          spacing: 4) else {
            owsFailDebug("Missing image.")
            return nil
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    public func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        AssertIsOnMainThread()

        guard let section = HomeViewSection(rawValue: indexPath.section) else {
            owsFailDebug("Invalid section: \(indexPath.section).")
            return false
        }

        switch section {
        case .reminders:
            return false
        case .pinned, .unpinned:
            return true
        case .archiveButton:
            return false
        }
    }

    public func tableView(_ tableView: UITableView,
                          leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        AssertIsOnMainThread()

        guard let section = HomeViewSection(rawValue: indexPath.section) else {
            owsFailDebug("Invalid section: \(indexPath.section).")
            return nil
        }

        switch section {
        case .reminders:
            return nil
        case .archiveButton:
            return nil
        case .pinned, .unpinned:
            guard let threadViewModel = threadViewModel(forIndexPath: indexPath) else {
                owsFailDebug("Missing threadViewModel.")
                return nil
            }
            let thread = threadViewModel.threadRecord

            let isThreadPinned = PinnedThreadManager.isThreadPinned(thread)
            let pinnedStateAction: UIContextualAction
            if isThreadPinned {
                pinnedStateAction = UIContextualAction(style: .normal,
                                                       title: nil) { [weak viewController] (_, _, completion) in
                    viewController?.unpinThread(threadViewModel: threadViewModel)
                    completion(false)
                }
                pinnedStateAction.backgroundColor = UIColor(rgbHex: 0xff990a)
                pinnedStateAction.accessibilityLabel = CommonStrings.unpinAction
                pinnedStateAction.image = actionImage(name: "unpin-solid-24",
                                                      title: CommonStrings.unpinAction)
            } else {
                pinnedStateAction = UIContextualAction(style: .destructive,
                                                       title: nil) { [weak viewController] (_, _, completion) in
                    completion(false)
                    viewController?.pinThread(threadViewModel: threadViewModel)
                }
                pinnedStateAction.backgroundColor = UIColor(rgbHex: 0xff990a)
                pinnedStateAction.accessibilityLabel = CommonStrings.pinAction
                pinnedStateAction.image = actionImage(name: "pin-solid-24",
                                                      title: CommonStrings.pinAction)
            }

            let kPullbackAnimationDuration = 0.65
            let userInfo = ["markAsRead": threadViewModel.hasUnreadMessages, "duration": kPullbackAnimationDuration + 0.2] as [String: Any]
            let readStateAction: UIContextualAction
            if threadViewModel.hasUnreadMessages {
                readStateAction = UIContextualAction(style: .destructive,
                                                     title: nil) { [weak viewController] (_, _, completion) in
                    completion(false)
                    NotificationCenter.default.post(name: HomeViewCell.TEMPORARY_CHANGE_UNREAD_BADGE, object: thread, userInfo: userInfo)
                    // We delay here so the animation can play out before we
                    // reload the cell
                    DispatchQueue.main.asyncAfter(deadline: .now() + kPullbackAnimationDuration) { [weak viewController] in
                        viewController?.markThreadAsRead(threadViewModel: threadViewModel)
                    }
                }
                readStateAction.backgroundColor = .ows_accentBlue
                readStateAction.accessibilityLabel = CommonStrings.readAction
                readStateAction.image = actionImage(name: "read-solid-24",
                                                    title: CommonStrings.readAction)
            } else {
                readStateAction = UIContextualAction(style: .normal,
                                                     title: nil) { [weak viewController] (_, _, completion) in
                    completion(false)
                    NotificationCenter.default.post(name: HomeViewCell.TEMPORARY_CHANGE_UNREAD_BADGE, object: thread, userInfo: userInfo)
                    // We delay here so the animation can play out before we
                    // reload the cell
                    DispatchQueue.main.asyncAfter(deadline: .now() + kPullbackAnimationDuration) { [weak viewController] in
                        viewController?.markThreadAsUnread(threadViewModel: threadViewModel)
                    }
                }
                readStateAction.backgroundColor = .ows_accentBlue
                readStateAction.accessibilityLabel = CommonStrings.unreadAction
                readStateAction.image = actionImage(name: "unread-solid-24",
                                                    title: CommonStrings.unreadAction)
            }

            // The first action will be auto-performed for "very long swipes".
            return UISwipeActionsConfiguration(actions: [ readStateAction, pinnedStateAction ])
        }
    }
}

// MARK: -

extension HVTableDataSource {

    fileprivate struct HVCellConfigurationAndContentToken {
        let configuration: HomeViewCell.Configuration
        let contentToken: HVCellContentToken
    }

    // This method can be called from any thread.
    private static func buildCellConfiguration(threadViewModel: ThreadViewModel,
                                               lastReloadDate: Date?) -> HomeViewCell.Configuration {
        owsAssertDebug(threadViewModel.homeViewInfo != nil)

        let isBlocked = threadViewModel.homeViewInfo?.isBlocked == true
        let configuration = HomeViewCell.Configuration(thread: threadViewModel,
                                                       lastReloadDate: lastReloadDate,
                                                       isBlocked: isBlocked)
        return configuration
    }

    fileprivate func buildCellConfigurationAndContentTokenSync(forIndexPath indexPath: IndexPath) -> HVCellConfigurationAndContentToken? {
        AssertIsOnMainThread()

        guard let threadViewModel = threadViewModel(forIndexPath: indexPath) else {
            owsFailDebug("Missing threadViewModel.")
            return nil
        }
        guard let viewController = self.viewController else {
            owsFailDebug("Missing viewController.")
            return nil
        }
        let lastReloadDate: Date? = {
            guard viewState.hasEverAppeared else {
                return nil
            }
            return self.lastReloadDate
        }()
        let configuration = Self.buildCellConfiguration(threadViewModel: threadViewModel,
                                                        lastReloadDate: lastReloadDate)
        let cellContentCache = viewController.cellContentCache
        let contentToken = { () -> HVCellContentToken in
            // If we have an existing HVCellContentToken, use it.
            // Cell measurement/arrangement is expensive.
            let cacheKey = configuration.thread.threadRecord.uniqueId
            if let cellContentToken = cellContentCache.get(key: cacheKey) {
                return cellContentToken
            }

            let cellContentToken = HomeViewCell.buildCellContentToken(forConfiguration: configuration)
            cellContentCache.set(key: cacheKey, value: cellContentToken)
            return cellContentToken
        }()
        return HVCellConfigurationAndContentToken(configuration: configuration,
                                                  contentToken: contentToken)
    }

    // TODO: It would be preferable to figure out some way to use ReverseDispatchQueue.
    private static let preloadSerialQueue = DispatchQueue(label: "HVTableDataSource.preloadSerialQueue")

    fileprivate func preloadCellIfNecessaryAsync(indexPath: IndexPath) {
        AssertIsOnMainThread()

        guard let viewController = self.viewController else {
            owsFailDebug("Missing viewController.")
            return
        }
        // These caches should only be accessed on the main thread.
        // They are thread-safe, but we don't want to race with a reset.
        let cellContentCache = viewController.cellContentCache
        let threadViewModelCache = viewController.threadViewModelCache
        // Take note of the cache reset counts. If either cache is reset
        // before we complete, discard the outcome of the preload.
        let cellContentCacheResetCount = cellContentCache.resetCount
        let threadViewModelCacheResetCount = threadViewModelCache.resetCount

        guard let thread = self.thread(forIndexPath: indexPath) else {
            owsFailDebug("Missing thread.")
            return
        }
        let cacheKey = thread.uniqueId
        guard nil == cellContentCache.get(key: cacheKey) else {
            // If we already have an existing HVCellContentToken, abort.
            return
        }

        let lastReloadDate: Date? = {
            guard viewState.hasEverAppeared else {
                return nil
            }
            return self.lastReloadDate
        }()

        // We use a serial queue to ensure we don't race and preload the same cell
        // twice at the same time.
        firstly(on: Self.preloadSerialQueue) { () -> (ThreadViewModel, HVCellContentToken) in
            guard nil == cellContentCache.get(key: cacheKey) else {
                // If we already have an existing HVCellContentToken, abort.
                throw HVPreloadError.alreadyLoaded
            }
            // This is the expensive work we do off the main thread.
            let threadViewModel = Self.databaseStorage.read { transaction in
                ThreadViewModel(thread: thread, forHomeView: true, transaction: transaction)
            }
            let configuration = Self.buildCellConfiguration(threadViewModel: threadViewModel,
                                                            lastReloadDate: lastReloadDate)
            let contentToken = HomeViewCell.buildCellContentToken(forConfiguration: configuration)
            return (threadViewModel, contentToken)
        }.done(on: .main) { (threadViewModel: ThreadViewModel,
                             contentToken: HVCellContentToken) in
            // Commit the preloaded values to their respective caches.
            guard cellContentCacheResetCount == cellContentCache.resetCount else {
                Logger.info("cellContentCache was reset.")
                return
            }
            guard threadViewModelCacheResetCount == threadViewModelCache.resetCount else {
                Logger.info("cellContentCache was reset.")
                return
            }
            if nil == threadViewModelCache.get(key: cacheKey) {
                threadViewModelCache.set(key: cacheKey, value: threadViewModel)
            } else {
                Logger.info("threadViewModel already loaded.")
            }
            if nil == cellContentCache.get(key: cacheKey) {
                cellContentCache.set(key: cacheKey, value: contentToken)
            } else {
                Logger.info("contentToken already loaded.")
            }
        }.catch(on: .global()) { error in
            if case HVPreloadError.alreadyLoaded = error {
                return
            }
            owsFailDebugUnlessNetworkFailure(error)
        }
    }

    private enum HVPreloadError: Error {
        case alreadyLoaded
    }
}

// MARK: -

public class HVTableView: UITableView {

    fileprivate var lastReloadDate: Date?

    @objc
    public override func reloadData() {
        AssertIsOnMainThread()

        lastReloadDate = Date()
        super.reloadData()
    }

    @objc
    public required init() {
        super.init(frame: .zero, style: .grouped)
    }

    @available(*, unavailable, message: "use other constructor instead.")
    required init?(coder: NSCoder) {
        notImplemented()
    }
}
