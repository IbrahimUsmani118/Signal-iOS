//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit
import SignalMetadataKit
import ZKGroup

@objc
public class VersionedProfileUpdate: NSObject {
    // This will only be set if there is a profile avatar.
    @objc
    public let avatarUrlPath: String?

    required init(avatarUrlPath: String? = nil) {
        self.avatarUrlPath = avatarUrlPath
    }
}

// MARK: -

public struct VersionedProfileRequest {
    public let request: TSRequest
    public let requestContext: ProfileKeyCredentialRequestContext?
}

// MARK: -

@objc
public class VersionedProfiles: NSObject {

    // MARK: - Dependencies

    private class var profileManager: OWSProfileManager {
        return OWSProfileManager.shared()
    }

    private class var networkManager: TSNetworkManager {
        return SSKEnvironment.shared.networkManager
    }

    private class var uploadHTTPManager: AFHTTPSessionManager {
        return OWSSignalService.sharedInstance().cdnSessionManager
    }

    private class var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: -

    public static let credentialStore = SDSKeyValueStore(collection: "VersionedProfiles.credentialStore")

    // Never instantiate this class.
    private override init() {}

    private class func asData(bytes: [UInt8]) -> Data {
        return NSData(bytes: bytes, length: bytes.count) as Data
    }

    // MARK: - Update

    @objc
    public class func updateProfileOnService(profileName: String?,
                                             profileAvatarData: Data?) {
        updateProfilePromise(profileName: profileName,
                             profileAvatarData: profileAvatarData)
            .done { _ in
                Logger.verbose("success")

                // TODO: This is temporary for testing.
                let localAddress = TSAccountManager.sharedInstance().localAddress!
                ProfileFetcherJob.fetchAndUpdateProfilePromise(address: localAddress,
                                                               mainAppOnly: false,
                                                               ignoreThrottling: true,
                                                               shouldUpdateProfile: true,
                                                               fetchType: .versioned)
                    .done { _ in
                        Logger.verbose("success")
                    }.catch { error in
                        owsFailDebug("error: \(error)")
                    }.retainUntilComplete()
            }.catch { error in
                owsFailDebug("error: \(error)")
            }.retainUntilComplete()
    }

    public class func updateProfilePromise(profileName: String?,
                                           profileAvatarData: Data?) -> Promise<VersionedProfileUpdate> {

        return DispatchQueue.global().async(.promise) {
            let profileKey: OWSAES256Key = self.profileManager.localProfileKey()
            return profileKey
        }.then(on: DispatchQueue.global()) { (profileKey: OWSAES256Key) -> Promise<TSNetworkManager.Response> in
            let localProfileKey = try self.parseProfileKey(profileKey: profileKey)

            let commitment = try localProfileKey.getCommitment()
            let commitmentData = self.asData(bytes: commitment.serialize())
            let hasAvatar = profileAvatarData != nil
            var nameData: Data?
            if let profileName = profileName {
                guard let encryptedPaddedProfileName = OWSProfileManager.encryptProfileName(withUnpaddedName: profileName, localProfileKey: profileKey) else {
                    throw OWSErrorMakeAssertionError("Could not encrypt profile name.")
                }
                nameData = encryptedPaddedProfileName
            }

            let profileKeyVersion = try localProfileKey.getProfileKeyVersion()
            let profileKeyVersionData = self.asData(bytes: profileKeyVersion.serialize())

            let request = OWSRequestFactory.versionedProfileSetRequest(withName: nameData, hasAvatar: hasAvatar, version: profileKeyVersionData, commitment: commitmentData)
            return self.networkManager.makePromise(request: request)
        }.then(on: DispatchQueue.global()) { (response: TSNetworkManager.Response) -> Promise<VersionedProfileUpdate> in
            if let profileAvatarData = profileAvatarData {
                return self.parseFormAndUpload(formResponseObject: response.responseObject,
                                               profileAvatarData: profileAvatarData)
            }
            return Promise.value(VersionedProfileUpdate())
        }
    }

    private class func parseFormAndUpload(formResponseObject: Any?,
                                          profileAvatarData: Data) -> Promise<VersionedProfileUpdate> {
        let urlPath: String = ""
        let (promise, resolver) = Promise<VersionedProfileUpdate>.pending()
        DispatchQueue.global().async {
            guard let response = formResponseObject as? [AnyHashable: Any] else {
                resolver.reject(OWSAssertionError("Unexpected response."))
                return
            }
            guard let form = OWSUploadForm.parse(response) else {
                resolver.reject(OWSAssertionError("Could not parse response."))
                return
            }

            // TODO: We will probably (continue to) use this within profile manager.
            let avatarUrlPath = form.formKey

            self.uploadHTTPManager.post(urlPath,
                                        parameters: nil,
                                        constructingBodyWith: { (formData: AFMultipartFormData) -> Void in

                                            // We have to build up the form manually vs. simply passing in a paramaters dict
                                            // because AWS is sensitive to the order of the form params (at least the "key"
                                            // field must occur early on).
                                            //
                                            // For consistency, all fields are ordered here in a known working order.
                                            form.append(toForm: formData)

                                            AppendMultipartFormPath(formData, "Content-Type", OWSMimeTypeApplicationOctetStream)

                                            formData.appendPart(withForm: profileAvatarData, name: "file")
            },
                                        progress: { progress in
                                            Logger.verbose("progress: \(progress.fractionCompleted)")
            },
                                        success: { (_, _) in
                                            Logger.verbose("Success.")
                                            resolver.fulfill(VersionedProfileUpdate(avatarUrlPath: avatarUrlPath))
            }, failure: { (_, error) in
                owsFailDebug("Error: \(error)")
                resolver.reject(error)
            })
        }
        return promise
    }

    // MARK: - Get

    private class func serverPublicParamsData() throws -> Data {
        // TODO:
        let encodedData = "SuMgznNiYR62ugEvVDnAY3x62QyGtfEWzBU0YZqcZSCWjqlmfAwZUUNNLHSJk5vj+XLygPV50/fG+yBYuPh5XGgEjczpd3VH3TqYvCnapHzqb5jW7OT/+DwT3010IBYvcon18UD4XRlgwERd12dh2Ffg6lOl3V2OMYKJoGKf4GIIR2r5316X4kP/9Nwau9vi4wggk0jGvQmlp3MAqRFvaxCCNz+DGDY4gkoA6JKWlzbOowu5fVpvREQimocRXoohFiAXqDbGhpWc7mcK3SIvEzpYVOHuhDi5/bjlTi+ugEBy+KjbWUpkEwI3lVlZAkpK1PT3rDVg66RApfimK3OLXQ=="

        guard let data = Data(base64Encoded: encodedData),
            data.count > 0 else {
                throw OWSErrorMakeAssertionError("Invalid server public params")
        }

        return data
    }

    private class func serverPublicParams() throws -> ServerPublicParams {
        let data = try serverPublicParamsData()
        let bytes = [UInt8](data)
        return try ServerPublicParams(contents: bytes)
    }

    private class func clientZkProfileOperations() throws -> ClientZkProfileOperations {
        return ClientZkProfileOperations(serverPublicParams: try serverPublicParams())
    }

    public class func versionedProfileRequest(address: SignalServiceAddress,
                                              udAccessKey: SMKUDAccessKey?) throws -> VersionedProfileRequest {
        guard address.isValid,
            let uuid: UUID = address.uuid else {
                throw OWSErrorMakeAssertionError("Invalid address: \(address)")
        }

        let canRequestCredential = true

        var requestContext: ProfileKeyCredentialRequestContext?
        var profileKeyVersionArg: Data?
        var credentialRequestArg: Data?
        try databaseStorage.read { transaction in
            guard let profileKeyForAddress: OWSAES256Key = self.profileManager.profileKey(for: address, transaction: transaction) else {
                return
            }
            let profileKey: ProfileKey = try self.parseProfileKey(profileKey: profileKeyForAddress)
            let profileKeyVersion = try profileKey.getProfileKeyVersion()
            let profileKeyVersionData = asData(bytes: profileKeyVersion.serialize())
            profileKeyVersionArg = profileKeyVersionData

            if canRequestCredential {
                let credential = try self.credentialData(for: address, transaction: transaction)
                if credential == nil {
                    let clientZkProfileOperations = try self.clientZkProfileOperations()
                    let uuidData: Data = withUnsafeBytes(of: uuid.uuid) { Data($0) }
                    let requestUuid = try Uuid(contents: [UInt8](uuidData))
                    let context = try clientZkProfileOperations.createProfileKeyCredentialRequestContext(uuid: requestUuid,
                                                                                                         profileKey: profileKey)
                    requestContext = context
                    let credentialRequest = try context.getRequest()
                    credentialRequestArg = asData(bytes: credentialRequest.serialize())
                }
            }
        }

        let request = OWSRequestFactory.getVersionedProfileRequest(address: address,
                                                                   profileKeyVersion: profileKeyVersionArg,
                                                                   credentialRequest: credentialRequestArg,
                                                                   udAccessKey: udAccessKey)

        return VersionedProfileRequest(request: request, requestContext: requestContext)
    }

    // MARK: -

    private class func parseProfileKey(profileKey: OWSAES256Key) throws -> ProfileKey {
        let profileKeyData: Data = profileKey.keyData
        guard profileKeyData.count == kAES256_KeyByteLength else {
            throw OWSErrorMakeAssertionError("Invalid profile key: \(profileKeyData.count)")
        }
        let profileKeyDataBytes = [UInt8](profileKeyData)
        guard profileKeyDataBytes.count == kAES256_KeyByteLength else {
            throw OWSErrorMakeAssertionError("Invalid profile key bytes: \(profileKeyDataBytes.count)")
        }
        return try ProfileKey(contents: profileKeyDataBytes)
    }

    public class func didFetchProfile(profile: SignalServiceProfile,
                                      profileRequest: VersionedProfileRequest) {
        do {
            guard let credentialResponseData = profile.credential else {
                return
            }
            guard credentialResponseData.count > 0 else {
                owsFailDebug("Invalid credential response.")
                return
            }
            guard let uuid = profile.address.uuid else {
                owsFailDebug("Missing uuid.")
                return
            }
            guard let requestContext = profileRequest.requestContext else {
                owsFailDebug("Missing request context.")
                return
            }
            let credentialResponse = try ProfileKeyCredentialResponse(contents: [UInt8](credentialResponseData))
            let clientZkProfileOperations = try self.clientZkProfileOperations()
            let profileKeyCredential = try clientZkProfileOperations.receiveProfileKeyCredential(profileKeyCredentialRequestContext: requestContext, profileKeyCredentialResponse: credentialResponse)
            let credentialData = self.asData(bytes: profileKeyCredential.serialize())
            guard credentialData.count > 0 else {
                owsFailDebug("Invalid credential data.")
                return
            }

            Logger.verbose("Updating credential for: \(uuid)")
            databaseStorage.write { transaction in
                credentialStore.setData(credentialData, key: uuid.uuidString, transaction: transaction)
            }
        } catch {
            owsFailDebug("Invalid credential: \(error).")
            return
        }
    }

    // MARK: - Credentials

    private class func credentialData(for address: SignalServiceAddress,
                                      transaction: SDSAnyReadTransaction) throws -> Data? {
        guard address.isValid,
            let uuid = address.uuid else {
                throw OWSErrorMakeAssertionError("Invalid address: \(address)")
        }
        return credentialStore.getData(uuid.uuidString, transaction: transaction)
    }
}
