import Foundation

/// Mirrors the database CHECK constraint (`^[a-z0-9_]{3,20}$` + at least one
/// letter) so the UI can give instant feedback. The server is authoritative.
enum UsernameValidator {
    static func isValid(_ username: String) -> Bool {
        let formatOK = username.range(
            of: "^[a-z0-9_]{3,20}$", options: .regularExpression) != nil
        let hasLetter = username.range(
            of: "[a-z]", options: .regularExpression) != nil
        return formatOK && hasLetter
    }
}
