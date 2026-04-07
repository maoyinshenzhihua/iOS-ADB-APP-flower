import Foundation
import Security

enum ADBAuth {

    static func signToken(token: Data, privateKey: SecKey) -> Data? {
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA1,
            token as CFData,
            &error
        ) else {
            if let err = error?.takeRetainedValue() {
                Logger.error("RSA签名失败: \(err)", category: "ADBAuth")
            }
            return nil
        }
        return signature as Data
    }

    static func generateRSAKeyPair(keySize: Int = 2048) -> (privateKey: SecKey, publicKey: SecKey)? {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: keySize,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: "com.zmq.adb.privatekey",
                kSecAttrAccessControl as String: SecAccessControlCreateWithFlags(
                    nil,
                    kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                    .privateKeyUsage,
                    nil
                )!
            ],
            kSecPublicKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: "com.zmq.adb.publickey",
            ]
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreatePair(attributes as CFDictionary, &error) else {
            if let err = error?.takeRetainedValue() {
                Logger.error("RSA密钥生成失败: \(err)", category: "ADBAuth")
            }
            return nil
        }

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            Logger.error("获取公钥失败", category: "ADBAuth")
            return nil
        }

        return (privateKey, publicKey)
    }

    static func exportPublicKeyPEM(_ publicKey: SecKey) -> String? {
        var error: Unmanaged<CFError>?
        guard let cfData = SecKeyCopyExternalRepresentation(publicKey, &error) else {
            return nil
        }
        let data = cfData as Data

        let base64 = data.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN PUBLIC KEY-----\n\(base64)\n-----END PUBLIC KEY-----\n"
    }

    static func deleteKeyPair() {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: "com.zmq.adb.privatekey"
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let deleteQuery2: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: "com.zmq.adb.publickey"
        ]
        SecItemDelete(deleteQuery2 as CFDictionary)
    }
}
