//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

public class AppEnvironment: NSObject {

    private static var _shared: AppEnvironment = AppEnvironment()

    @objc
    public class var shared: AppEnvironment {
        get {
            return _shared
        }
        set {
            guard CurrentAppContext().isRunningTests else {
                owsFailDebug("Can only switch environments in tests.")
                return
            }

            _shared = newValue
        }
    }

    public var callServiceRef: CallService

    // A temporary hack until `.shared` goes away and this can be provided to `init`.
    static let sharedNotificationPresenter = NotificationPresenter()

    public var notificationPresenterRef: NotificationPresenter

    public var pushRegistrationManagerRef: PushRegistrationManager

    let deviceTransferServiceRef = DeviceTransferService()

    let avatarHistorManagerRef = AvatarHistoryManager()

    let cvAudioPlayerRef = CVAudioPlayer()

    let speechManagerRef = SpeechManager()

    let windowManagerRef = WindowManager()

    private(set) var appIconBadgeUpdater: AppIconBadgeUpdater!
    private(set) var badgeManager: BadgeManager!
    private var usernameValidationObserverRef: UsernameValidationObserver?

    private override init() {
        self.callServiceRef = CallService()
        self.notificationPresenterRef = Self.sharedNotificationPresenter
        self.pushRegistrationManagerRef = PushRegistrationManager()

        super.init()

        SwiftSingletons.register(self)
    }

    func setup() {
        callService.createCallUIAdapter()

        self.badgeManager = BadgeManager(
            databaseStorage: databaseStorage,
            mainScheduler: DispatchQueue.main,
            serialScheduler: DispatchQueue.sharedUtility
        )
        self.appIconBadgeUpdater = AppIconBadgeUpdater(badgeManager: badgeManager)
        self.usernameValidationObserverRef = UsernameValidationObserver(
            manager: DependenciesBridge.shared.usernameValidationManager,
            database: DependenciesBridge.shared.db
        )

        AppReadiness.runNowOrWhenAppWillBecomeReady {
            self.badgeManager.startObservingChanges(in: self.databaseStorage)
            self.appIconBadgeUpdater.startObserving()
        }

        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            let isPrimaryDevice = self.databaseStorage.read { tx -> Bool in
                return DependenciesBridge.shared.tsAccountManager.registrationState(tx: tx.asV2Read).isPrimaryDevice ?? true
            }

            let db = DependenciesBridge.shared.db
            let learnMyOwnPniManager = DependenciesBridge.shared.learnMyOwnPniManager
            let linkedDevicePniKeyManager = DependenciesBridge.shared.linkedDevicePniKeyManager
            let pniHelloWorldManager = DependenciesBridge.shared.pniHelloWorldManager
            let schedulers = DependenciesBridge.shared.schedulers

            if isPrimaryDevice {
                firstly(on: schedulers.sync) { () -> Promise<Void> in
                    learnMyOwnPniManager.learnMyOwnPniIfNecessary()
                }
                .done(on: schedulers.global()) {
                    db.write { tx in
                        pniHelloWorldManager.sayHelloWorldIfNecessary(tx: tx)
                    }
                }
                .cauterize()
            } else {
                db.read { tx in
                    linkedDevicePniKeyManager.validateLocalPniIdentityKeyIfNecessary(tx: tx)
                }
            }

            db.asyncWrite { tx in
                DependenciesBridge.shared.masterKeySyncManager.runStartupJobs(tx: tx)
            }

            db.asyncWrite { tx in
                GroupCallRecordRingingCleanupManager.fromGlobals()
                    .cleanupRingingCalls(tx: tx)
            }

            DependenciesBridge.shared.deletedCallRecordCleanupManager
                .startCleanupIfNecessary()
        }

        // Hang certain singletons on SSKEnvironment too.
        SSKEnvironment.shared.lightweightGroupCallManagerRef = callServiceRef
    }
}
