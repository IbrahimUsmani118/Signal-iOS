//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

public enum ProfileRequestError: Error {
    case notAuthorized
    case notFound
    case rateLimit
}

// MARK: -

private struct ProfileFetchOptions {
    let mainAppOnly: Bool
    let shouldUpdateStore: Bool
    let authedAccount: AuthedAccount

    init(
        mainAppOnly: Bool = true,
        shouldUpdateStore: Bool = true,
        authedAccount: AuthedAccount
    ) {
        self.mainAppOnly = mainAppOnly
        self.shouldUpdateStore = shouldUpdateStore
        self.authedAccount = authedAccount
    }
}

// MARK: -

@objc
public class ProfileFetcherJob: NSObject {
    private let serviceId: ServiceId
    private let options: ProfileFetchOptions

    public class func fetchProfilePromise(
        serviceId: ServiceId,
        mainAppOnly: Bool = true,
        shouldUpdateStore: Bool = true,
        authedAccount: AuthedAccount = .implicit()
    ) -> Promise<FetchedProfile> {
        let options = ProfileFetchOptions(
            mainAppOnly: mainAppOnly,
            shouldUpdateStore: shouldUpdateStore,
            authedAccount: authedAccount
        )
        return Promise.wrapAsync { try await ProfileFetcherJob(serviceId: serviceId, options: options).run() }
    }

    @objc
    public class func fetchProfile(address: SignalServiceAddress, authedAccount: AuthedAccount = .implicit()) {
        Task { await _fetchProfile(serviceId: address.serviceId, authedAccount: authedAccount) }
    }

    private class func _fetchProfile(serviceId: ServiceId?, authedAccount: AuthedAccount) async {
        do {
            guard let serviceId else {
                throw ProfileRequestError.notFound
            }
            try await ProfileFetcherJob(
                serviceId: serviceId,
                options: ProfileFetchOptions(authedAccount: authedAccount)
            ).run()
        } catch where error.isNetworkFailureOrTimeout {
            Logger.warn("Error: \(error)")
        } catch let error as ProfileRequestError {
            Logger.warn("Error: \(error)")
        } catch {
            owsFailDebug("Error: \(error)")
        }
    }

    private init(serviceId: ServiceId, options: ProfileFetchOptions) {
        self.serviceId = serviceId
        self.options = options
    }

    // MARK: -

    @discardableResult
    private func run() async throws -> FetchedProfile {
        let backgroundTask = addBackgroundTask()
        defer {
            backgroundTask.end()
        }

        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        let localIdentifiers = try tsAccountManager.localIdentifiersWithMaybeSneakyTransaction(authedAccount: options.authedAccount)
        let fetchedProfile: FetchedProfile
        do {
            fetchedProfile = try await requestProfile(localIdentifiers: localIdentifiers)
        } catch let error as ProfileRequestError where error == .notFound && options.shouldUpdateStore {
            await databaseStorage.awaitableWrite { [serviceId] tx in
                let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
                let recipient = recipientDatabaseTable.fetchRecipient(serviceId: serviceId, transaction: tx.asV2Write)
                guard let recipient else {
                    return
                }
                let recipientManager = DependenciesBridge.shared.recipientManager
                recipientManager.markAsUnregisteredAndSave(recipient, unregisteredAt: .now, shouldUpdateStorageService: true, tx: tx.asV2Write)
                let recipientMerger = DependenciesBridge.shared.recipientMerger
                recipientMerger.splitUnregisteredRecipientIfNeeded(
                    localIdentifiers: localIdentifiers,
                    unregisteredRecipient: recipient,
                    tx: tx.asV2Write
                )
            }
            throw error
        }
        if options.shouldUpdateStore {
            try await updateProfile(fetchedProfile: fetchedProfile, localIdentifiers: localIdentifiers)
        }
        return fetchedProfile
    }

    private func requestProfile(localIdentifiers: LocalIdentifiers) async throws -> FetchedProfile {

        guard !options.mainAppOnly || CurrentAppContext().isMainApp else {
            // We usually only refresh profiles in the MainApp to decrease the
            // chance of missed SN notifications in the AppExtension for our users
            // who choose not to verify contacts.
            throw OWSGenericError("Not allowed in App Extensions.")
        }

        return try await requestProfileWithRetries(localIdentifiers: localIdentifiers)
    }

    private func requestProfileWithRetries(localIdentifiers: LocalIdentifiers, retryCount: Int = 0) async throws -> FetchedProfile {
        do {
            return try await requestProfileAttempt(localIdentifiers: localIdentifiers)
        } catch where error.httpStatusCode == 401 {
            throw ProfileRequestError.notAuthorized
        } catch where error.httpStatusCode == 404 {
            throw ProfileRequestError.notFound
        } catch where error.httpStatusCode == 413 || error.httpStatusCode == 429 {
            throw ProfileRequestError.rateLimit
        } catch where error.isRetryable && retryCount < 3 {
            return try await requestProfileWithRetries(localIdentifiers: localIdentifiers, retryCount: retryCount + 1)
        }
    }

    private func requestProfileAttempt(localIdentifiers: LocalIdentifiers) async throws -> FetchedProfile {
        let serviceId = self.serviceId

        let udAccess: OWSUDAccess?
        if localIdentifiers.contains(serviceId: serviceId) {
            // Don't use UD for "self" profile fetches.
            udAccess = nil
        } else {
            udAccess = databaseStorage.read { tx in udManager.udAccess(for: serviceId, tx: tx) }
        }

        var currentVersionedProfileRequest: VersionedProfileRequest?
        let requestMaker = RequestMaker(
            label: "Profile Fetch",
            requestFactoryBlock: { (udAccessKeyForRequest) -> TSRequest? in
                // Clear out any existing request.
                currentVersionedProfileRequest = nil

                switch serviceId {
                case let aci as Aci:
                    do {
                        let request = try self.versionedProfilesSwift.versionedProfileRequest(
                            for: aci,
                            udAccessKey: udAccessKeyForRequest,
                            auth: self.options.authedAccount.chatServiceAuth
                        )
                        currentVersionedProfileRequest = request
                        return request.request
                    } catch {
                        owsFailDebug("Error: \(error)")
                        return nil
                    }
                default:
                    Logger.info("Unversioned profile fetch.")
                    return OWSRequestFactory.getUnversionedProfileRequest(
                        serviceId: ServiceIdObjC.wrapValue(serviceId),
                        udAccessKey: udAccessKeyForRequest,
                        auth: self.options.authedAccount.chatServiceAuth
                    )
                }
            },
            serviceId: serviceId,
            udAccess: udAccess,
            authedAccount: self.options.authedAccount,
            options: [.allowIdentifiedFallback, .isProfileFetch]
        )

        let result = try await requestMaker.makeRequest().awaitable()

        let profile = try SignalServiceProfile(serviceId: serviceId, responseObject: result.responseJson)

        // If we sent a versioned request, store the credential that was returned.
        if let versionedProfileRequest = currentVersionedProfileRequest {
            // This calls databaseStorage.write { }
            await versionedProfilesSwift.didFetchProfile(profile: profile, profileRequest: versionedProfileRequest)
        }

        return fetchedProfile(
            for: profile,
            profileKeyFromVersionedRequest: currentVersionedProfileRequest?.profileKey
        )
    }

    private func fetchedProfile(
        for profile: SignalServiceProfile,
        profileKeyFromVersionedRequest: OWSAES256Key?
    ) -> FetchedProfile {
        let profileKey: OWSAES256Key?
        if let profileKeyFromVersionedRequest {
            // We sent a versioned request, so use the corresponding profile key for
            // decryption. If we don't, we might try to decrypt an old profile with a
            // new key, and that won't work.
            profileKey = profileKeyFromVersionedRequest
        } else {
            // We sent an unversioned request, so just use any profile key that's
            // available. If we explicitly sent an unversioned request, we may have a
            // key available locally. If we wanted a versioned request but ended up
            // with an unversioned request, we may have received a key while the
            // profile fetch was in flight.
            profileKey = databaseStorage.read { profileManager.profileKey(for: SignalServiceAddress(profile.serviceId), transaction: $0) }
        }
        return FetchedProfile(profile: profile, profileKey: profileKey)
    }

    private func updateProfile(
        fetchedProfile: FetchedProfile,
        localIdentifiers: LocalIdentifiers
    ) async throws {
        await updateProfile(
            fetchedProfile: fetchedProfile,
            avatarDownloadResult: try await downloadAvatarIfNeeded(fetchedProfile),
            localIdentifiers: localIdentifiers
        )
    }

    private struct AvatarDownloadResult {
        var remoteRelativePath: OptionalChange<String?>
        var localFileUrl: OptionalChange<URL?>
    }

    private func downloadAvatarIfNeeded(_ fetchedProfile: FetchedProfile) async throws -> AvatarDownloadResult {
        guard let profileKey = fetchedProfile.profileKey, fetchedProfile.decryptedProfile != nil else {
            // If we don't have a profile key for this user, or if the rest of their
            // encrypted profile wasn't valid, don't change their avatar because we
            // aren't changing their name.
            return AvatarDownloadResult(remoteRelativePath: .noChange, localFileUrl: .noChange)
        }
        guard let newAvatarUrlPath = fetchedProfile.profile.avatarUrlPath else {
            // If profile has no avatar, we don't need to download the avatar.
            return AvatarDownloadResult(remoteRelativePath: .setTo(nil), localFileUrl: .setTo(nil))
        }
        let profileAddress = SignalServiceAddress(fetchedProfile.profile.serviceId)
        let didAlreadyDownloadAvatar = databaseStorage.read { transaction -> Bool in
            let oldAvatarUrlPath = profileManager.profileAvatarURLPath(
                for: profileAddress,
                downloadIfMissing: false,
                authedAccount: options.authedAccount,
                transaction: transaction
            )
            return (
                oldAvatarUrlPath == newAvatarUrlPath
                && profileManager.hasProfileAvatarData(profileAddress, transaction: transaction)
            )
        }
        if didAlreadyDownloadAvatar {
            return AvatarDownloadResult(remoteRelativePath: .noChange, localFileUrl: .noChange)
        }
        let avatarData: Data?
        do {
            avatarData = try await profileManager.downloadAndDecryptAvatar(
                avatarUrlPath: newAvatarUrlPath,
                profileKey: profileKey
            )
        } catch {
            Logger.warn("Error: \(error)")
            if error.isNetworkFailureOrTimeout, profileAddress.isLocalAddress {
                // Fetches and local profile updates can conflict. To avoid these conflicts
                // we treat "partial" profile fetches (where we download the profile but
                // not the associated avatar) as failures.
                throw SSKUnretryableError.partialLocalProfileFetch
            }
            // Reaching this point with anything other than a network failure or
            // timeout should be very rare. It might reflect:
            //
            // * A race around rotating profile keys which would cause a decryption
            //   error.
            //
            // * An incomplete profile update (profile updated but avatar not uploaded
            //   afterward). This might be due to a race with an update that is in
            //   flight. We should eventually recover since profile updates are
            //   durable.
            avatarData = nil
        }
        return AvatarDownloadResult(
            remoteRelativePath: .setTo(newAvatarUrlPath),
            localFileUrl: .setTo(avatarData.flatMap { profileManager.writeAvatarDataToFile($0) })
        )
    }

    private func updateProfile(
        fetchedProfile: FetchedProfile,
        avatarDownloadResult: AvatarDownloadResult,
        localIdentifiers: LocalIdentifiers
    ) async {
        let profile = fetchedProfile.profile
        let serviceId = profile.serviceId

        await databaseStorage.awaitableWrite { transaction in
            Self.updateUnidentifiedAccess(
                serviceId: serviceId,
                verifier: profile.unidentifiedAccessVerifier,
                hasUnrestrictedAccess: profile.hasUnrestrictedUnidentifiedAccess,
                tx: transaction
            )

            // First, we add ensure we have a copy of any new badge in our badge store
            let badgeModels = fetchedProfile.profile.badges.map { $0.1 }
            let persistedBadgeIds: [String] = badgeModels.compactMap {
                do {
                    try self.profileManager.badgeStore.createOrUpdateBadge($0, transaction: transaction)
                    return $0.id
                } catch {
                    owsFailDebug("Failed to save badgeId: \($0.id). \(error)")
                    return nil
                }
            }

            // Then, we update the profile. `profileBadges` will contain the badgeId of
            // badges in the badge store
            let profileBadgeMetadata = fetchedProfile.profile.badges
                .map { $0.0 }
                .filter { persistedBadgeIds.contains($0.badgeId) }

            self.profileManager.updateProfile(
                address: SignalServiceAddress(serviceId),
                decryptedProfile: fetchedProfile.decryptedProfile,
                avatarUrlPath: avatarDownloadResult.remoteRelativePath,
                avatarFileName: avatarDownloadResult.localFileUrl.map { $0?.lastPathComponent },
                profileBadges: profileBadgeMetadata,
                lastFetchDate: Date(),
                userProfileWriter: .profileFetch,
                authedAccount: self.options.authedAccount,
                tx: transaction
            )

            if localIdentifiers.contains(serviceId: serviceId) {
                self.reconcileLocalProfileIfNeeded(fetchedProfile: fetchedProfile)
            }

            let identityManager = DependenciesBridge.shared.identityManager
            identityManager.saveIdentityKey(profile.identityKey, for: serviceId, tx: transaction.asV2Write)

            let paymentAddress = fetchedProfile.decryptedProfile?.paymentAddress(identityKey: fetchedProfile.identityKey)
            self.paymentsHelper.setArePaymentsEnabled(
                for: ServiceIdObjC.wrapValue(serviceId),
                hasPaymentsEnabled: paymentAddress != nil,
                transaction: transaction
            )
        }
    }

    private static func updateUnidentifiedAccess(
        serviceId: ServiceId,
        verifier: Data?,
        hasUnrestrictedAccess: Bool,
        tx: SDSAnyWriteTransaction
    ) {
        let unidentifiedAccessMode: UnidentifiedAccessMode = {
            guard let verifier else {
                // If there is no verifier, at least one of this user's devices
                // do not support UD.
                return .disabled
            }

            if hasUnrestrictedAccess {
                return .unrestricted
            }

            guard let udAccessKey = udManager.udAccessKey(for: serviceId, tx: tx) else {
                return .disabled
            }

            let dataToVerify = Data(count: 32)
            guard let expectedVerifier = Cryptography.computeSHA256HMAC(dataToVerify, key: udAccessKey.keyData) else {
                owsFailDebug("could not compute verification")
                return .disabled
            }

            guard expectedVerifier.ows_constantTimeIsEqual(to: verifier) else {
                return .disabled
            }

            return .enabled
        }()
        udManager.setUnidentifiedAccessMode(unidentifiedAccessMode, for: serviceId, tx: tx)
    }

    private func reconcileLocalProfileIfNeeded(fetchedProfile: FetchedProfile) {
        guard CurrentAppContext().isMainApp else {
            return
        }
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegisteredPrimaryDevice else {
            return
        }
        DependenciesBridge.shared.localProfileChecker.didFetchLocalProfile(LocalProfileChecker.RemoteProfile(
            avatarUrlPath: fetchedProfile.profile.avatarUrlPath,
            decryptedProfile: fetchedProfile.decryptedProfile
        ))
    }

    private func addBackgroundTask() -> OWSBackgroundTask {
        return OWSBackgroundTask(label: "\(#function)", completionBlock: { [weak self] status in
            AssertIsOnMainThread()

            guard status == .expired else {
                return
            }
            guard self != nil else {
                return
            }
            Logger.error("background task time ran out before profile fetch completed.")
        })
    }
}

// MARK: -

public struct DecryptedProfile {
    public let givenName: String
    public let familyName: String?
    public let bio: String?
    public let bioEmoji: String?
    public let paymentAddressData: Data?
    public let phoneNumberSharing: Bool?
}

// MARK: -

public struct FetchedProfile {
    let profile: SignalServiceProfile
    let profileKey: OWSAES256Key?
    public let decryptedProfile: DecryptedProfile?
    public let identityKey: IdentityKey

    init(profile: SignalServiceProfile, profileKey: OWSAES256Key?) {
        self.profile = profile
        self.profileKey = profileKey
        self.decryptedProfile = Self.decrypt(profile: profile, profileKey: profileKey)
        self.identityKey = profile.identityKey
    }

    private static func decrypt(profile: SignalServiceProfile, profileKey: OWSAES256Key?) -> DecryptedProfile? {
        guard let profileKey else {
            return nil
        }
        let nameComponents = profile.profileNameEncrypted.flatMap {
            OWSUserProfile.decrypt(profileNameData: $0, profileKey: profileKey)
        }
        guard let nameComponents else {
            return nil
        }
        let bio = profile.bioEncrypted.flatMap {
            OWSUserProfile.decrypt(profileStringData: $0, profileKey: profileKey)
        }
        let bioEmoji = profile.bioEmojiEncrypted.flatMap {
            OWSUserProfile.decrypt(profileStringData: $0, profileKey: profileKey)
        }
        let paymentAddressData = profile.paymentAddressEncrypted.flatMap {
            OWSUserProfile.decrypt(profileData: $0, profileKey: profileKey)
        }
        let phoneNumberSharing = profile.phoneNumberSharingEncrypted.flatMap {
            OWSUserProfile.decrypt(profileBooleanData: $0, profileKey: profileKey)
        }
        return DecryptedProfile(
            givenName: nameComponents.givenName,
            familyName: nameComponents.familyName,
            bio: bio,
            bioEmoji: bioEmoji,
            paymentAddressData: paymentAddressData,
            phoneNumberSharing: phoneNumberSharing
        )
    }
}

// MARK: -

public extension DecryptedProfile {
    func paymentAddress(identityKey: IdentityKey) -> TSPaymentAddress? {
        guard var paymentAddressData = paymentAddressData else {
            return nil
        }

        do {
            guard let (dataLength, dataLengthCount) = UInt32.from(littleEndianData: paymentAddressData) else {
                return nil
            }
            paymentAddressData = paymentAddressData.dropFirst(dataLengthCount)
            paymentAddressData = paymentAddressData.prefix(Int(dataLength))
            guard paymentAddressData.count == dataLength else {
                owsFailDebug("Invalid paymentAddressData.")
                return nil
            }
            let proto = try SSKProtoPaymentAddress(serializedData: paymentAddressData)
            return try TSPaymentAddress.fromProto(proto, identityKey: identityKey)
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }
}
