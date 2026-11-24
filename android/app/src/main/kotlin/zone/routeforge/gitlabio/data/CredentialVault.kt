package zone.routeforge.gitlabio.data

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import zone.routeforge.gitlabio.core.TrustPolicy
import java.security.KeyStore
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Everything needed to talk to one GitLab account. Lives only inside [CredentialVault]. */
@Serializable
data class StoredAccount(
    val id: String,
    val instance: String,
    val username: String,
    val name: String,
    val token: String,
    val trust: TrustPolicy = TrustPolicy.System,
    /** Token scopes as reported when the account was verified; empty when the instance did not say. */
    val scopes: List<String> = emptyList(),
    val tokenExpiresAt: String? = null,
)

/**
 * Accounts encrypted with an AES-256-GCM key that never leaves the Android Keystore. The ciphertext
 * sits in app-private preferences, which are excluded from backup and device transfer.
 */
class CredentialVault(context: Context) {
    private val prefs = context.getSharedPreferences("credential-vault", Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true }
    private val serializer = ListSerializer(StoredAccount.serializer())

    private fun key(create: Boolean): SecretKey {
        val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        check(create) { "无法读取设备安全密钥，请重新添加账户。" }
        // Not bound to an unlocked device so the background to-do check can still read the token.
        val spec = KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setRandomizedEncryptionRequired(true)
            .build()
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE).apply { init(spec) }.generateKey()
    }

    @Synchronized
    fun read(): List<StoredAccount> {
        val payload = prefs.getString(ENTRY, null) ?: return emptyList()
        val bytes = Base64.getDecoder().decode(payload)
        check(bytes.size > IV_BYTES) { "账户存储损坏，请重新连接。" }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, key(false), GCMParameterSpec(128, bytes, 0, IV_BYTES))
        val plain = cipher.doFinal(bytes, IV_BYTES, bytes.size - IV_BYTES)
        return json.decodeFromString(serializer, plain.toString(Charsets.UTF_8))
    }

    @Synchronized
    fun write(accounts: List<StoredAccount>) {
        if (accounts.isEmpty()) {
            check(prefs.edit().remove(ENTRY).commit()) { "无法保存账户更改。" }
            return
        }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key(true))
        check(cipher.iv.size == IV_BYTES) { "无法初始化加密。" }
        val bytes = cipher.iv + cipher.doFinal(json.encodeToString(serializer, accounts).toByteArray(Charsets.UTF_8))
        check(prefs.edit().putString(ENTRY, Base64.getEncoder().encodeToString(bytes)).commit()) { "无法保存账户更改。" }
    }

    private companion object {
        const val KEYSTORE = "AndroidKeyStore"
        const val ALIAS = "zone.routeforge.gitlabio.accounts.v2"
        const val ENTRY = "accounts.v2"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val IV_BYTES = 12
    }
}
