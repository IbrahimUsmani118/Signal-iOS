//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

// This file contains common interfaces for dealing with
// HTTP request responses, failures and errors in a consistent
// way without concern for whether the request is made via
//
// * REST (e.g. AFNetworking, OWSURLSession, URLSession, etc.).
// * a Websocket (e.g. OWSWebSocket).

// A common protocol for responses from OWSUrlSession, NetworkManager, SocketManager, etc.
@objc
public protocol HTTPResponse {
    var requestUrl: URL { get }
    var responseStatusCode: Int { get }
    var responseHeaders: [String: String] { get }
    var responseBodyData: Data? { get }
    var responseBodyJson: Any? { get }
    var responseBodyString: String? { get }
}

// MARK: -

// A common protocol for errors from OWSUrlSession, NetworkManager, SocketManager, etc.
public protocol HTTPError {
    var requestUrl: URL { get }
    // status is zero by default, if request never made or failed.
    var responseStatusCode: Int { get }
    var responseHeaders: OWSHttpHeaders? { get }
    // TODO: Can we eventually eliminate responseError?
    var responseError: Error? { get }
    var responseBodyData: Data? { get }

    var customRetryAfterDate: Date? { get }
    var isNetworkConnectivityError: Bool { get }
}

// MARK: -

public struct HTTPErrorServiceResponse {
    let requestUrl: URL
    let responseStatus: Int
    let responseHeaders: OWSHttpHeaders
    let responseError: Error?
    let responseData: Data?
    let customRetryAfterDate: Date?
    let customLocalizedDescription: String?
    let customLocalizedRecoverySuggestion: String?
}

// MARK: -

public enum OWSHTTPError: Error, IsRetryableProvider, UserErrorDescriptionProvider {
    case invalidAppState(requestUrl: URL)
    case invalidRequest(requestUrl: URL)
    case invalidResponse(requestUrl: URL)
    // Request failed without a response from the service.
    case networkFailure(requestUrl: URL)
    // Request failed with a response from the service.
    case serviceResponse(serviceResponse: HTTPErrorServiceResponse)

    // The first 5 parameters are required (even if nil).
    // The custom parameters are optional.
    public static func forServiceResponse(requestUrl: URL,
                                          responseStatus: Int,
                                          responseHeaders: OWSHttpHeaders,
                                          responseError: Error?,
                                          responseData: Data?,
                                          customRetryAfterDate: Date? = nil,
                                          customLocalizedDescription: String? = nil,
                                          customLocalizedRecoverySuggestion: String? = nil) -> OWSHTTPError {
        let serviceResponse = HTTPErrorServiceResponse(requestUrl: requestUrl,
                                                       responseStatus: responseStatus,
                                                       responseHeaders: responseHeaders,
                                                       responseError: responseError,
                                                       responseData: responseData,
                                                       customRetryAfterDate: customRetryAfterDate,
                                                       customLocalizedDescription: customLocalizedDescription,
                                                       customLocalizedRecoverySuggestion: customLocalizedRecoverySuggestion)
        return .serviceResponse(serviceResponse: serviceResponse)
    }

    // NSError bridging: the domain of the error.
    public static var errorDomain: String {
        return "OWSHTTPError"
    }

    // NSError bridging: the error code within the given domain.
    public var errorUserInfo: [String: Any] {
        var result = [String: Any]()
        if let responseError = self.responseError {
            result[NSUnderlyingErrorKey] = responseError
        }
        result[NSLocalizedDescriptionKey] = localizedDescription
        if let customLocalizedRecoverySuggestion = self.customLocalizedRecoverySuggestion {
            result[NSLocalizedRecoverySuggestionErrorKey] = customLocalizedRecoverySuggestion
        }
        return result
    }

    public var localizedDescription: String {
        if let customLocalizedRecoverySuggestion = self.customLocalizedRecoverySuggestion {
            return customLocalizedRecoverySuggestion
        }
        switch self {
        case .invalidAppState, .invalidRequest, .networkFailure:
            return NSLocalizedString("ERROR_DESCRIPTION_REQUEST_FAILED",
                                     comment: "Error indicating that a socket request failed.")
        case .invalidResponse, .serviceResponse:
            return NSLocalizedString("ERROR_DESCRIPTION_RESPONSE_FAILED",
                                     comment: "Error indicating that a socket response failed.")
        }
    }

    // MARK: - IsRetryableProvider

    public var isRetryableProvider: Bool {
        if isNetworkConnectivityError {
            return true
        }
        switch self {
        case .invalidAppState, .invalidRequest:
            return false
        case .invalidResponse:
            return true
        case .networkFailure:
            return true
        case .serviceResponse:
            // TODO: We might eventually special-case 413 Rate Limited errors.
            let responseStatus = self.responseStatusCode
            // We retry 5xx.
            if responseStatus >= 400, responseStatus <= 499 {
                return false
            } else {
                return true
            }
        }
    }
}

// MARK: -

extension OWSHTTPError: HTTPError {

    public var requestUrl: URL {
        switch self {
        case .invalidAppState(let requestUrl):
            return requestUrl
        case .invalidRequest(let requestUrl):
            return requestUrl
        case .invalidResponse(let requestUrl):
            return requestUrl
        case .networkFailure(let requestUrl):
            return requestUrl
        case .serviceResponse(let serviceResponse):
            return serviceResponse.requestUrl
        }
    }

    // NOTE: This function should only be called from NetworkManager.swiftHTTPStatusCodeForError.
    public var responseStatusCode: Int {
        switch self {
        case .invalidAppState, .invalidRequest, .invalidResponse, .networkFailure:
            return 0
        case .serviceResponse(let serviceResponse):
            return Int(serviceResponse.responseStatus)
        }
    }

    public var responseHeaders: OWSHttpHeaders? {
        switch self {
        case .invalidAppState, .invalidRequest, .invalidResponse, .networkFailure:
            return nil
        case .serviceResponse(let serviceResponse):
            return serviceResponse.responseHeaders
        }
    }

    public var responseError: Error? {
        switch self {
        case .invalidAppState, .invalidRequest, .invalidResponse, .networkFailure:
            return nil
        case .serviceResponse(let serviceResponse):
            return serviceResponse.responseError
        }
    }

    public var responseBodyData: Data? {
        switch self {
        case .invalidAppState, .invalidRequest, .invalidResponse, .networkFailure:
            return nil
        case .serviceResponse(let serviceResponse):
            return serviceResponse.responseData
        }
    }

    public var customRetryAfterDate: Date? {
        if let responseHeaders = self.responseHeaders,
           let retryAfterDate = responseHeaders.retryAfterDate {
            return retryAfterDate
        }

        switch self {
        case .invalidAppState, .invalidRequest, .invalidResponse, .networkFailure:
            return nil
        case .serviceResponse(let serviceResponse):
            return serviceResponse.customRetryAfterDate
        }
    }

    public var customLocalizedDescription: String? {
        switch self {
        case .invalidAppState, .invalidRequest, .invalidResponse, .networkFailure:
            return nil
        case .serviceResponse(let serviceResponse):
            return serviceResponse.customLocalizedDescription
        }
    }

    public var customLocalizedRecoverySuggestion: String? {
        switch self {
        case .invalidAppState, .invalidRequest, .invalidResponse, .networkFailure:
            return nil
        case .serviceResponse(let serviceResponse):
            return serviceResponse.customLocalizedRecoverySuggestion
        }
    }

    // NOTE: This function should only be called from NetworkManager.isSwiftNetworkConnectivityError.
    public var isNetworkConnectivityError: Bool {
        switch self {
        case .invalidAppState, .invalidRequest, .invalidResponse:
            return false
        case .networkFailure:
            return true
        case .serviceResponse:
            if 0 == self.responseStatusCode {
                // statusCode should now be nil, not zero, in this
                // case, but there might be some legacy code that is
                // still using zero.
                owsFailDebug("Unexpected status code.")
                return true
            }
            if let responseError = responseError {
                return IsNetworkConnectivityFailure(responseError)
            }
            return false
        }
    }
}

// MARK: -

extension OWSHttpHeaders {

    // fallback retry-after delay if we fail to parse a non-empty retry-after string
    private static var kOWSFallbackRetryAfter: TimeInterval { 60 }
    private static var kOWSRetryAfterHeaderKey: String { "Retry-After" }

    public var retryAfterDate: Date? {
        Self.retryAfterDate(responseHeaders: headers)
    }

    fileprivate static func retryAfterDate(responseHeaders: [String: String]) -> Date? {
        guard let retryAfterString = responseHeaders[Self.kOWSRetryAfterHeaderKey] else {
            return nil
        }
        return Self.parseRetryAfterHeaderValue(retryAfterString)
    }

    static func parseRetryAfterHeaderValue(_ rawValue: String?) -> Date? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return nil
        }
        if let result = Date.ows_parseFromHTTPDateString(value) {
            return result
        }
        if let result = Date.ows_parseFromISO8601String(value) {
            return result
        }
        func parseWithScanner() -> Date? {
            // We need to use NSScanner instead of -[NSNumber doubleValue] so we can differentiate
            // because the NSNumber method returns 0.0 on a parse failure. NSScanner lets us detect
            // a parse failure.
            let scanner = Scanner(string: value)
            var delay: TimeInterval = 0
            guard scanner.scanDouble(&delay),
                  scanner.isAtEnd else {
                      // Only return the delay if we've made it to the end.
                      // Helps to prevent things like: 8/11/1994 being interpreted as delay: 8.
                      return nil
                  }
            return Date(timeIntervalSinceNow: max(0, delay))
        }
        if let result = parseWithScanner() {
            return result
        }
        if !CurrentAppContext().isRunningTests {
            owsFailDebug("Failed to parse retry-after string: \(String(describing: rawValue))")
        }
        return Date(timeIntervalSinceNow: Self.kOWSFallbackRetryAfter)
    }
}

// MARK: -

public extension Error {
    var httpStatusCode: Int? {
        HTTPStatusCodeForError(self)?.intValue
    }

    var httpRetryAfterDate: Date? {
        HTTPUtils.httpRetryAfterDate(forError: self)
    }

    var httpResponseData: Data? {
        HTTPUtils.httpResponseData(forError: self)
    }

    var httpRequestUrl: URL? {
        guard let error = self as? HTTPError else {
            return nil
        }
        return error.requestUrl
    }

    var httpResponseJson: Any? {
        guard let data = httpResponseData else {
            return nil
        }
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            return json
        } catch {
            owsFailDebug("Could not parse JSON: \(error).")
            return nil
        }
    }
}

// MARK: -

public extension NSError {
    var httpRetryAfterDate: Date? {
        HTTPUtils.httpRetryAfterDate(forError: self)
    }

    var httpResponseData: Data? {
        HTTPUtils.httpResponseData(forError: self)
    }
}

// MARK: -

// This extension contains the canonical implementations for
// extracting various HTTP metadata from errors.  They should
// only be called from the convenience accessors on Error and
// NSError above.
fileprivate extension HTTPUtils {
    static func httpRetryAfterDate(forError error: Error?) -> Date? {
        if let httpError = error as? OWSHTTPError {
            if let retryAfterDate = httpError.customRetryAfterDate {
                return retryAfterDate
            }
            if let retryAfterDate = httpError.responseHeaders?.retryAfterDate {
                return retryAfterDate
            }
            if let responseError = httpError.responseError {
                return httpRetryAfterDate(forError: responseError)
            }
        }
        return nil
    }

    static func httpResponseData(forError error: Error?) -> Data? {
        guard let error = error else {
            return nil
        }
        switch error {
        case let httpError as OWSHTTPError:
            if let responseData = httpError.responseBodyData {
                return responseData
            }
            if let responseError = httpError.responseError {
                return httpResponseData(forError: responseError)
            }
            return nil
        default:
            return nil
        }
    }
}

// MARK: -

@objc
public extension NetworkManager {
    // NOTE: This function should only be called from IsNetworkConnectivityFailure().
    static func isSwiftNetworkConnectivityError(_ error: Error?) -> Bool {
        guard let error = error else {
            return false
        }
        switch error {
        case let httpError as OWSHTTPError:
            return httpError.isNetworkConnectivityError
        case GroupsV2Error.timeout:
            return true
        case let contactDiscoveryError as ContactDiscoveryError:
            return contactDiscoveryError.kind == .timeout
        case PaymentsError.timeout:
            return true
        default:
            return false
        }
    }

    // NOTE: This function should only be called from HTTPStatusCodeForError().
    static func swiftHTTPStatusCodeForError(_ error: Error?) -> NSNumber? {
        if let httpError = error as? OWSHTTPError {
            let statusCode = httpError.responseStatusCode
            guard statusCode > 0 else {
                return nil
            }
            return NSNumber(value: statusCode)
        }
        return nil
    }
}

// MARK: -

@objc
public class HTTPResponseImpl: NSObject {

    @objc
    public let requestUrl: URL

    @objc
    public let status: Int

    @objc
    public let headers: OWSHttpHeaders

    @objc
    public let bodyData: Data?

    public let stringEncoding: String.Encoding

    private struct JSONValue {
        let json: Any?
    }

    // This property should only be accessed with unfairLock acquired.
    private var jsonValue: JSONValue?

    private static let unfairLock = UnfairLock()

    public required init(requestUrl: URL,
                         status: Int,
                         headers: OWSHttpHeaders,
                         bodyData: Data?,
                         stringEncoding: String.Encoding = .utf8) {
        self.requestUrl = requestUrl
        self.status = status
        self.headers = headers
        self.bodyData = bodyData
        self.stringEncoding = stringEncoding
    }

    public static func build(requestUrl: URL,
                             httpUrlResponse: HTTPURLResponse,
                             bodyData: Data?) -> HTTPResponse {
        let headers = OWSHttpHeaders(response: httpUrlResponse)
        let stringEncoding: String.Encoding = httpUrlResponse.parseStringEncoding() ?? .utf8
        return HTTPResponseImpl(requestUrl: requestUrl,
                                status: httpUrlResponse.statusCode,
                                headers: headers,
                                bodyData: bodyData,
                                stringEncoding: stringEncoding)
    }

    @objc
    public var bodyJson: Any? {
        Self.unfairLock.withLock {
            if let jsonValue = self.jsonValue {
                return jsonValue.json
            }
            let jsonValue = Self.parseJSON(data: bodyData)
            self.jsonValue = jsonValue
            return jsonValue.json
        }
    }

    private static func parseJSON(data: Data?) -> JSONValue {
        guard let data = data,
              !data.isEmpty else {
                  return JSONValue(json: nil)
              }
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            return JSONValue(json: json)
        } catch {
            owsFailDebug("Could not parse JSON: \(error).")
            return JSONValue(json: nil)
        }
    }
}

// MARK: -

extension HTTPResponseImpl: HTTPResponse {
    @objc
    public var responseStatusCode: Int { Int(status) }
    @objc
    public var responseHeaders: [String: String] { headers.headers }
    @objc
    public var responseBodyData: Data? { bodyData }
    @objc
    public var responseBodyJson: Any? { bodyJson }
    @objc
    public var responseBodyString: String? {
        guard let data = bodyData,
              let string = String(data: data, encoding: stringEncoding) else {
                  Logger.warn("Invalid body string.")
                  return nil
              }
        return string
    }
}

// MARK: -

extension HTTPURLResponse {
    fileprivate func parseStringEncoding() -> String.Encoding? {
        guard let encodingName = textEncodingName else {
            return nil
        }
        let encoding = CFStringConvertIANACharSetNameToEncoding(encodingName as CFString)
        guard encoding != kCFStringEncodingInvalidId else {
            return nil
        }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))
    }
}

// MARK: -

extension HTTPUtils {

    // This DRYs up handling of main service errors
    // so that REST and websocket errors are handled
    // in the same way.
    public static func preprocessMainServiceHTTPError(request: TSRequest,
                                                      requestUrl: URL,
                                                      responseStatus: Int,
                                                      responseHeaders: OWSHttpHeaders,
                                                      responseError: Error?,
                                                      responseData: Data?) -> OWSHTTPError {
        let error = HTTPUtils.buildServiceError(request: request,
                                                requestUrl: requestUrl,
                                                responseStatus: responseStatus,
                                                responseHeaders: responseHeaders,
                                                responseError: responseError,
                                                responseData: responseData)

        if error.isNetworkConnectivityError {
            Self.outageDetection.reportConnectionFailure()
        }

        #if TESTABLE_BUILD
        HTTPUtils.logCurl(for: request as URLRequest)
        #endif

        if error.responseStatusCode == AppExpiry.appExpiredStatusCode {
            appExpiry.setHasAppExpiredAtCurrentVersion()
        }

        return error
    }

    private static func buildServiceError(request: TSRequest,
                                          requestUrl: URL,
                                          responseStatus: Int,
                                          responseHeaders: OWSHttpHeaders,
                                          responseError: Error?,
                                          responseData: Data?) -> OWSHTTPError {

        var errorDescription = "URL: \(request.httpMethod) \(requestUrl.absoluteString), status: \(responseStatus)"
        if let responseError = responseError {
            errorDescription += ", error: \(responseError)"
        }
        let retryAfterDate: Date? = responseHeaders.retryAfterDate
        func buildServiceResponseError(description: String? = nil,
                                       recoverySuggestion: String? = nil) -> OWSHTTPError {
            .forServiceResponse(requestUrl: requestUrl,
                                responseStatus: responseStatus,
                                responseHeaders: responseHeaders,
                                responseError: responseError,
                                responseData: responseData,
                                customRetryAfterDate: retryAfterDate,
                                customLocalizedDescription: description,
                                customLocalizedRecoverySuggestion: recoverySuggestion)
        }

        switch responseStatus {
        case 0:
            Logger.warn("The network request failed because of a connectivity error: \(request.httpMethod) \(requestUrl.absoluteString)")
            let error = OWSHTTPError.networkFailure(requestUrl: requestUrl)
            return error
        case 400:
            Logger.warn("The request contains an invalid parameter: \(errorDescription)")
            return buildServiceResponseError()
        case 401:
            Logger.warn("The server returned an error about the authorization header: \(errorDescription)")
            deregisterAfterAuthErrorIfNecessary(request: request,
                                                requestUrl: requestUrl,
                                                statusCode: responseStatus)
            return buildServiceResponseError()
        case 402:
            return buildServiceResponseError()
        case 403:
            Logger.warn("The server returned an authentication failure: \(errorDescription)")
            deregisterAfterAuthErrorIfNecessary(request: request,
                                                requestUrl: requestUrl,
                                                statusCode: responseStatus)
            return buildServiceResponseError()
        case 404:
            Logger.warn("The requested resource could not be found: \(errorDescription)")
            return buildServiceResponseError()
        case 411:
            Logger.info("Multi-device pairing: \(responseStatus), \(errorDescription)")
            let description = NSLocalizedString("MULTIDEVICE_PAIRING_MAX_DESC",
                                                comment: "alert title: cannot link - reached max linked devices")
            let recoverySuggestion = NSLocalizedString("MULTIDEVICE_PAIRING_MAX_RECOVERY",
                                                       comment: "alert body: cannot link - reached max linked devices")
            let error = buildServiceResponseError(description: description,
                                                  recoverySuggestion: recoverySuggestion)
            return error
        case 413:
            Logger.warn("Rate limit exceeded: \(request.httpMethod) \(requestUrl.absoluteString)")
            let description = NSLocalizedString("REGISTER_RATE_LIMITING_ERROR", comment: "")
            let recoverySuggestion = NSLocalizedString("REGISTER_RATE_LIMITING_BODY", comment: "")
            let error = buildServiceResponseError(description: description,
                                                  recoverySuggestion: recoverySuggestion)
            return error
        case 417:
            // TODO: Is this response code obsolete?
            Logger.warn("The number is already registered on a relay. Please unregister there first: \(request.httpMethod) \(requestUrl.absoluteString)")
            let description = NSLocalizedString("REGISTRATION_ERROR", comment: "")
            let recoverySuggestion = NSLocalizedString("RELAY_REGISTERED_ERROR_RECOVERY", comment: "")
            let error = buildServiceResponseError(description: description,
                                                  recoverySuggestion: recoverySuggestion)
            return error
        case 422:
            Logger.error("The registration was requested over an unknown transport: \(errorDescription)")
            return buildServiceResponseError()
        default:
            Logger.warn("Unknown error: \(responseStatus), \(errorDescription)")
            return buildServiceResponseError()
        }
    }

    private static func deregisterAfterAuthErrorIfNecessary(request: TSRequest,
                                                            requestUrl: URL,
                                                            statusCode: Int) {
        let requestHeaders: [String: String] = request.allHTTPHeaderFields ?? [:]
        Logger.verbose("Invalid auth: \(requestHeaders)")

        // We only want to de-register for:
        //
        // * Auth errors...
        // * ...received from Signal service...
        // * ...that used standard authorization.
        //
        // * We don't want want to deregister for:
        //
        // * CDS requests.
        // * Requests using UD auth.
        // * etc.
        //
        // TODO: Will this work with censorship circumvention?
        if requestUrl.absoluteString.hasPrefix(TSConstants.mainServiceURL),
           request.shouldHaveAuthorizationHeaders {
            DispatchQueue.main.async {
                if Self.tsAccountManager.isRegisteredAndReady {
                    Self.tsAccountManager.setIsDeregistered(true)
                } else {
                    Logger.warn("Ignoring auth failure not registered and ready: \(request.httpMethod) \(requestUrl.absoluteString).")
                }
            }
        } else {
            Logger.warn("Ignoring \(statusCode) for URL: \(request.httpMethod) \(requestUrl.absoluteString)")
        }
    }
}

// MARK: -

// Temporary obj-c wrapper for OWSHTTPError until
// OWSWebSocket, etc. have been ported to Swift.
@objc
public class OWSHTTPErrorWrapper: NSObject {
    public let error: OWSHTTPError
    @objc
    public var asNSError: NSError { error as NSError }

    public init(error: OWSHTTPError) {
        self.error = error
    }

    @objc
    public var asConnectionFailureError: OWSHTTPErrorWrapper {
        let newError = OWSHTTPError.forServiceResponse(requestUrl: error.requestUrl,
                                                       responseStatus: error.responseStatusCode,
                                                       responseHeaders: error.responseHeaders ?? OWSHttpHeaders(),
                                                       responseError: error.responseError,
                                                       responseData: error.responseBodyData,
                                                       customRetryAfterDate: error.customRetryAfterDate,
                                                       customLocalizedDescription: NSLocalizedString("ERROR_DESCRIPTION_NO_INTERNET",
                                                                                                     comment: "Generic error used whenever Signal can't contact the server"),
                                                       customLocalizedRecoverySuggestion: NSLocalizedString("NETWORK_ERROR_RECOVERY",
                                                                                                            comment: ""))
        return OWSHTTPErrorWrapper(error: newError)
    }
}

// MARK: -

@inlinable
public func owsFailDebugUnlessNetworkFailure(_ error: Error,
                                             file: String = #file,
                                             function: String = #function,
                                             line: Int = #line) {
    if IsNetworkConnectivityFailure(error) {
        // Log but otherwise ignore network failures.
        Logger.warn("Error: \(error)", file: file, function: function, line: line)
    } else {
        owsFailDebug("Error: \(error)", file: file, function: function, line: line)
    }
}

// MARK: -

extension Error {
    public func hasFatalStatusCode() -> Bool {
        guard let statusCode = self.httpStatusCode else {
            return false
        }
        if statusCode == 429 {
            // "Too Many Requests", retry with backoff.
            return false
        }
        return 400 <= statusCode && statusCode <= 499
    }
}

// MARK: -

extension NSError {
    @objc
    public func matchesDomainAndCode(of other: NSError) -> Bool {
        other.hasDomain(domain, code: code)
    }

    @objc
    public func hasDomain(_ domain: String, code: Int) -> Bool {
        self.domain == domain && self.code == code
    }
}
