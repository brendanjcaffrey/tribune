import Foundation

// the app signs in and the share extension only ever reads what it stored, so
// the service, account and access group have to be agreed on in one place.
//
// the group is the app's own application-identifier, which is where items
// written before the keychain-sharing entitlement existed already live, so
// adding the entitlement doesn't sign anyone out.
enum AuthToken {
    static let service = "com.jcaffrey.tribune.auth"
    static let account = "jwt"

    static var accessGroup: String {
        let prefix = AppConfig.appIdentifierPrefix
        return prefix.isEmpty ? "" : "\(prefix)com.jcaffrey.Tribune"
    }

    static func read() throws -> String? {
        try Keychain.readJWT(service: service, account: account, accessGroup: accessGroup)
    }

    static func store(_ jwt: String) throws {
        try Keychain.storeJWT(jwt, service: service, account: account, accessGroup: accessGroup)
    }

    static func delete() throws {
        try Keychain.deleteJWT(service: service, account: account, accessGroup: accessGroup)
    }
}
