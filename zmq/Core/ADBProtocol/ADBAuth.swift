import Foundation
import Security
import CommonCrypto

enum ADBAuth {

    static func signToken(token: Data, privateKey: SecKey) -> Data? {
        var error: Unmanaged<CFError>?
        // Android ADB 使用的是 kSecKeyAlgorithmRsaSignatureRaw，即直接对原始数据进行 RSA 签名
        // 而不是 rsaSignatureMessagePKCS1v15SHA1（这个会先对数据进行 SHA1 哈希）
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureRaw,
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
        let privateKeyAttr: [String: Any] = [
            kSecAttrIsPermanent as String: true,
            kSecAttrApplicationTag as String: "com.zmq.adb.privatekey".data(using: .utf8)!,
        ]

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: keySize,
            kSecPrivateKeyAttrs as String: privateKeyAttr
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
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
        // Android ADB 使用的公钥格式是 "user@host:BASE64DATA\n"
        // 而不是标准的 PEM 格式
        return "ADBKEY@\(base64)\n"
    }

    static func deleteKeyPair() {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: "com.zmq.adb.privatekey".data(using: .utf8)!
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let deleteQuery2: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: "com.zmq.adb.publickey".data(using: .utf8)!
        ]
        SecItemDelete(deleteQuery2 as CFDictionary)
    }

    static func signPairingCode(_ pairingCode: String) -> Data? {
        guard let keyPair = ADBKeyManager().loadOrCreateKeyPair() else {
            Logger.error("无法加载密钥对用于配对码签名", category: "ADBAuth")
            return nil
        }

        let codeData = pairingCode.data(using: .utf8) ?? Data()
        let hashedData = sha256(codeData)

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            keyPair.privateKey,
            .rsaSignatureRaw,
            hashedData as CFData,
            &error
        ) else {
            if let err = error?.takeRetainedValue() {
                Logger.error("配对码签名失败: \(err)", category: "ADBAuth")
            }
            return nil
        }

        return signature as Data
    }

    private static func sha256(_ data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }
}
