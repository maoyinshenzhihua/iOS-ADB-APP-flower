import Foundation
import Security

class ADBKeyManager {
    private let privateKeyTag = "com.zmq.adb.privatekey"
    private let publicKeyTag = "com.zmq.adb.publickey"
    private var privateKey: SecKey?
    private var publicKey: SecKey?

    func loadOrCreateKeyPair() -> (privateKey: SecKey, publicKey: SecKey)? {
        if let existing = loadExistingKeyPair() {
            privateKey = existing.privateKey
            publicKey = existing.publicKey
            return existing
        }

        ADBAuth.deleteKeyPair()

        guard let newPair = ADBAuth.generateRSAKeyPair() else {
            Logger.error("创建RSA密钥对失败", category: "ADBKeyManager")
            return nil
        }

        privateKey = newPair.privateKey
        publicKey = newPair.publicKey
        Logger.info("已创建新的RSA密钥对", category: "ADBKeyManager")
        return newPair
    }

    func getPublicKeyPEM() -> String? {
        guard let pubKey = publicKey ?? loadExistingKeyPair()?.publicKey else { return nil }
        return ADBAuth.exportPublicKeyPEM(pubKey)
    }

    func signToken(_ token: Data) -> Data? {
        guard let privKey = privateKey ?? loadExistingKeyPair()?.privateKey else { return nil }
        return ADBAuth.signToken(token: token, privateKey: privKey)
    }

    private func loadExistingKeyPair() -> (privateKey: SecKey, publicKey: SecKey)? {
        let privateQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: privateKeyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecReturnRef as String: true
        ]

        var privateKeyRef: AnyObject?
        let privateStatus = SecItemCopyMatching(privateQuery as CFDictionary, &privateKeyRef)
        guard privateStatus == errSecSuccess, let privKey = privateKeyRef else { return nil }

        guard let pubKey = SecKeyCopyPublicKey(privKey as! SecKey) else { return nil }

        return (privateKey: privKey as! SecKey, publicKey: pubKey)
    }
}
