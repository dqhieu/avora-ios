import AuthenticationServices
import CryptoKit
import Supabase

@MainActor
enum AuthService {
    static func signInWithApple(presentationAnchor: ASPresentationAnchor) async throws {
        let nonce = randomNonce()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        let cred = try await performAppleRequest(request, anchor: presentationAnchor)
        guard let tokenData = cred.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            throw AvoraError.unauthorized
        }
        try await SupabaseClientProvider.client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
        )
    }

    private static func randomNonce(_ length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if Int(random) < chars.count {
                result.append(chars[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
private func performAppleRequest(
    _ request: ASAuthorizationAppleIDRequest,
    anchor: ASPresentationAnchor
) async throws -> ASAuthorizationAppleIDCredential {
    final class Delegate: NSObject,
        ASAuthorizationControllerDelegate,
        ASAuthorizationControllerPresentationContextProviding
    {
        let anchor: ASPresentationAnchor
        var cont: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

        init(_ a: ASPresentationAnchor) { anchor = a }

        func presentationAnchor(for c: ASAuthorizationController) -> ASPresentationAnchor { anchor }

        func authorizationController(
            controller: ASAuthorizationController,
            didCompleteWithAuthorization auth: ASAuthorization
        ) {
            if let c = auth.credential as? ASAuthorizationAppleIDCredential {
                cont?.resume(returning: c)
            } else {
                cont?.resume(throwing: AvoraError.unauthorized)
            }
        }

        func authorizationController(
            controller: ASAuthorizationController,
            didCompleteWithError error: Error
        ) {
            cont?.resume(throwing: error)
        }
    }

    let delegate = Delegate(anchor)
    let controller = ASAuthorizationController(authorizationRequests: [request])
    controller.delegate = delegate
    controller.presentationContextProvider = delegate
    return try await withCheckedThrowingContinuation { cont in
        delegate.cont = cont
        objc_setAssociatedObject(controller, "d", delegate, .OBJC_ASSOCIATION_RETAIN)
        controller.performRequests()
    }
}
