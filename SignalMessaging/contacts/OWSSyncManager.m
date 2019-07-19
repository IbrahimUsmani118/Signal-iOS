//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSSyncManager.h"
#import "Environment.h"
#import "OWSContactsManager.h"
#import "OWSPreferences.h"
#import "OWSProfileManager.h"
#import "OWSReadReceiptManager.h"
#import <PromiseKit/AnyPromise.h>
#import <SignalServiceKit/AppReadiness.h>
#import <SignalServiceKit/DataSource.h>
#import <SignalServiceKit/MIMETypeUtil.h>
#import <SignalServiceKit/OWSError.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/OWSPrimaryStorage.h>
#import <SignalServiceKit/OWSSyncConfigurationMessage.h>
#import <SignalServiceKit/OWSSyncContactsMessage.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/YapDatabaseConnection+OWS.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kSyncManagerCollection = @"kTSStorageManagerOWSSyncManagerCollection";
NSString *const kSyncManagerLastContactSyncKey = @"kTSStorageManagerOWSSyncManagerLastMessageKey";

@interface OWSSyncManager ()

@property (nonatomic, readonly) dispatch_queue_t serialQueue;

@property (nonatomic) BOOL isRequestInFlight;

@end

@implementation OWSSyncManager

+ (instancetype)shared {
    OWSAssertDebug(SSKEnvironment.shared.syncManager);

    return SSKEnvironment.shared.syncManager;
}

- (instancetype)initDefault {
    self = [super init];

    if (!self) {
        return self;
    }

    OWSSingletonAssert();

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(signalAccountsDidChange:)
                                                 name:OWSContactsManagerSignalAccountsDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(profileKeyDidChange:)
                                                 name:kNSNotificationName_ProfileKeyDidChange
                                               object:nil];

    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Dependencies

- (OWSContactsManager *)contactsManager {
    OWSAssertDebug(Environment.shared.contactsManager);

    return Environment.shared.contactsManager;
}

- (OWSIdentityManager *)identityManager {
    OWSAssertDebug(SSKEnvironment.shared.identityManager);

    return SSKEnvironment.shared.identityManager;
}

- (OWSMessageSender *)messageSender {
    OWSAssertDebug(SSKEnvironment.shared.messageSender);

    return SSKEnvironment.shared.messageSender;
}

- (MessageSenderJobQueue *)messageSenderJobQueue
{
    OWSAssertDebug(SSKEnvironment.shared.messageSenderJobQueue);

    return SSKEnvironment.shared.messageSenderJobQueue;
}

- (OWSProfileManager *)profileManager {
    OWSAssertDebug(SSKEnvironment.shared.profileManager);

    return SSKEnvironment.shared.profileManager;
}

- (TSAccountManager *)tsAccountManager
{
    return TSAccountManager.sharedInstance;
}

- (id<OWSTypingIndicators>)typingIndicators
{
    return SSKEnvironment.shared.typingIndicators;
}

#pragma mark - Notifications

- (void)signalAccountsDidChange:(id)notification {
    OWSAssertIsOnMainThread();

    [self sendSyncContactsMessageIfPossible];
}

- (void)profileKeyDidChange:(id)notification {
    OWSAssertIsOnMainThread();

    [self sendSyncContactsMessageIfPossible];
}

#pragma mark -

- (YapDatabaseConnection *)editingDatabaseConnection
{
    return OWSPrimaryStorage.sharedManager.dbReadWriteConnection;
}

- (YapDatabaseConnection *)readDatabaseConnection
{
    return OWSPrimaryStorage.sharedManager.dbReadConnection;
}

#pragma mark - Methods

- (void)sendSyncContactsMessageIfNecessary {
    OWSAssertIsOnMainThread();

    if (!self.serialQueue) {
        _serialQueue = dispatch_queue_create("org.whispersystems.contacts.syncing", DISPATCH_QUEUE_SERIAL);
    }

    dispatch_async(self.serialQueue, ^{
        if (self.isRequestInFlight) {
            // De-bounce.  It's okay if we ignore some new changes;
            // `sendSyncContactsMessageIfPossible` is called fairly
            // often so we'll sync soon.
            return;
        }

        TSThread *_Nullable thread = [TSAccountManager getOrCreateLocalThreadWithSneakyTransaction];
        if (thread == nil) {
            OWSFailDebug(@"Missing thread.");
            return;
        }

        OWSSyncContactsMessage *syncContactsMessage =
            [[OWSSyncContactsMessage alloc] initWithThread:thread
                                            signalAccounts:self.contactsManager.signalAccounts
                                           identityManager:self.identityManager
                                            profileManager:self.profileManager];
        __block NSData *_Nullable messageData;
        __block NSData *_Nullable lastMessageData;
        [self.readDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            messageData = [syncContactsMessage buildPlainTextAttachmentDataWithTransaction:transaction.asAnyRead];
            lastMessageData = [transaction objectForKey:kSyncManagerLastContactSyncKey
                                           inCollection:kSyncManagerCollection];
        }];

        if (!messageData) {
            OWSFailDebug(@"Failed to serialize contacts sync message.");
            return;
        }

        if (lastMessageData && [lastMessageData isEqual:messageData]) {
            // Ignore redundant contacts sync message.
            return;
        }

        self.isRequestInFlight = YES;

        // DURABLE CLEANUP - we could replace the custom durability logic in this class
        // with a durable JobQueue.
        DataSource *dataSource = [DataSourceValue dataSourceWithSyncMessageData:messageData];
        [self.messageSender sendTemporaryAttachment:dataSource
            contentType:OWSMimeTypeApplicationOctetStream
            inMessage:syncContactsMessage
            success:^{
                OWSLogInfo(@"Successfully sent contacts sync message.");

                [self.editingDatabaseConnection setObject:messageData
                                                   forKey:kSyncManagerLastContactSyncKey
                                             inCollection:kSyncManagerCollection];

                dispatch_async(self.serialQueue, ^{
                    self.isRequestInFlight = NO;
                });
            }
            failure:^(NSError *error) {
                OWSLogError(@"Failed to send contacts sync message with error: %@", error);

                dispatch_async(self.serialQueue, ^{
                    self.isRequestInFlight = NO;
                });
            }];
    });
}

- (void)sendSyncContactsMessageIfPossible {
    OWSAssertIsOnMainThread();

    if (!self.contactsManager.isSetup) {
        // Don't bother if the contacts manager hasn't finished setup.
        return;
    }

    if ([TSAccountManager sharedInstance].isRegisteredAndReady) {
        [self sendSyncContactsMessageIfNecessary];
    }
}

- (void)sendConfigurationSyncMessage {
    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        if (!self.tsAccountManager.isRegisteredAndReady) {
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self sendConfigurationSyncMessage_AppReady];
        });
    }];
}

- (void)sendConfigurationSyncMessage_AppReady {
    DDLogInfo(@"");

    if (![TSAccountManager sharedInstance].isRegisteredAndReady) {
        return;
    }

    BOOL areReadReceiptsEnabled = SSKEnvironment.shared.readReceiptManager.areReadReceiptsEnabled;
    BOOL showUnidentifiedDeliveryIndicators = Environment.shared.preferences.shouldShowUnidentifiedDeliveryIndicators;
    BOOL showTypingIndicators = self.typingIndicators.areTypingIndicatorsEnabled;

    [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        TSThread *_Nullable thread = [TSAccountManager getOrCreateLocalThreadWithTransaction:transaction.asAnyWrite];
        if (thread == nil) {
            OWSFailDebug(@"Missing thread.");
            return;
        }

        BOOL sendLinkPreviews = [SSKPreferences areLinkPreviewsEnabledWithTransaction:transaction.asAnyRead];

        OWSSyncConfigurationMessage *syncConfigurationMessage =
            [[OWSSyncConfigurationMessage alloc] initWithThread:thread
                                            readReceiptsEnabled:areReadReceiptsEnabled
                             showUnidentifiedDeliveryIndicators:showUnidentifiedDeliveryIndicators
                                           showTypingIndicators:showTypingIndicators
                                               sendLinkPreviews:sendLinkPreviews];

        [self.messageSenderJobQueue addMessage:syncConfigurationMessage transaction:transaction.asAnyWrite];
    }];
}

#pragma mark - Local Sync

- (AnyPromise *)syncLocalContact
{
    SignalAccount *signalAccount =
        [[SignalAccount alloc] initWithSignalServiceAddress:self.tsAccountManager.localAddress];
    signalAccount.contact = [Contact new];

    return [self syncContactsForSignalAccounts:@[ signalAccount ]];
}

- (AnyPromise *)syncAllContacts
{
    return [self syncContactsForSignalAccounts:self.contactsManager.signalAccounts];
}

- (AnyPromise *)syncContactsForSignalAccounts:(NSArray<SignalAccount *> *)signalAccounts
{
    AnyPromise *promise = [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            TSThread *_Nullable thread = [TSAccountManager getOrCreateLocalThreadWithSneakyTransaction];
            if (thread == nil) {
                OWSFailDebug(@"Missing thread.");
                NSError *error = OWSErrorWithCodeDescription(OWSErrorCodeMissingLocalThread, @"Missing local thread.");
                resolve(error);
                return;
            }

            OWSSyncContactsMessage *syncContactsMessage =
                [[OWSSyncContactsMessage alloc] initWithThread:thread
                                                signalAccounts:signalAccounts
                                               identityManager:self.identityManager
                                                profileManager:self.profileManager];

            __block DataSource *dataSource;
            [self.readDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
                dataSource = [DataSourceValue
                    dataSourceWithSyncMessageData:[syncContactsMessage
                                                      buildPlainTextAttachmentDataWithTransaction:transaction
                                                                                                      .asAnyRead]];
            }];

            [self.messageSender sendTemporaryAttachment:dataSource
                contentType:OWSMimeTypeApplicationOctetStream
                inMessage:syncContactsMessage
                success:^{
                    OWSLogInfo(@"Successfully sent contacts sync message.");
                    resolve(@(1));
                }
                failure:^(NSError *error) {
                    OWSLogError(@"Failed to send contacts sync message with error: %@", error);
                    resolve(error);
                }];
        });
    }];
    [promise retainUntilComplete];
    return promise;
}

@end

NS_ASSUME_NONNULL_END
