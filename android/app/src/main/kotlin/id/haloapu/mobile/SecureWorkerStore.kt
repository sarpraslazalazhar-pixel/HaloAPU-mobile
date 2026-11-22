package id.haloapu.mobile

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONArray
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Hardware-backed encrypted persistence for background notification worker.
 * Stores Bearer token encrypted via AndroidKeyStore AES-256-GCM (never plaintext).
 */
object SecureWorkerStore {
    private const val KEYSTORE_PROVIDER = "AndroidKeyStore"
    private const val KEY_ALIAS = "haloapu_bg_worker_key_v1"
    private const val AES_GCM_TRANSFORMATION = "AES/GCM/NoPadding"
    private const val GCM_TAG_LENGTH_BITS = 128

    private const val PREFS_NAME = "haloapu_bg_worker_prefs"
    private const val KEY_AUTH_TOKEN_ENC = "auth_token_enc"
    private const val KEY_BASE_URL = "base_url"
    private const val KEY_RELEASE_CHANNEL = "release_channel"
    private const val KEY_BASELINE_SET = "baseline_set"
    private const val KEY_NOTIFIED_IDS = "notified_ids"

    private const val MAX_NOTIFIED_IDS = 50

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun getOrCreateSecretKey(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
        val existingEntry = keyStore.getEntry(KEY_ALIAS, null)
        if (existingEntry is KeyStore.SecretKeyEntry) {
            return existingEntry.secretKey
        }

        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            KEYSTORE_PROVIDER,
        )
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(false)
            .build()
        keyGenerator.init(spec)
        return keyGenerator.generateKey()
    }

    private fun encrypt(plainText: String): String {
        val cipher = Cipher.getInstance(AES_GCM_TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateSecretKey())
        val iv = cipher.iv
        val encrypted = cipher.doFinal(plainText.toByteArray(Charsets.UTF_8))
        val ivB64 = Base64.encodeToString(iv, Base64.NO_WRAP)
        val cipherB64 = Base64.encodeToString(encrypted, Base64.NO_WRAP)
        return "$ivB64:$cipherB64"
    }

    private fun decrypt(payload: String): String? {
        return try {
            val parts = payload.split(":", limit = 2)
            if (parts.size != 2) return null
            val iv = Base64.decode(parts[0], Base64.NO_WRAP)
            val cipherBytes = Base64.decode(parts[1], Base64.NO_WRAP)

            val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
            val entry = keyStore.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry
                ?: return null
            val cipher = Cipher.getInstance(AES_GCM_TRANSFORMATION)
            cipher.init(
                Cipher.DECRYPT_MODE,
                entry.secretKey,
                GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv),
            )
            String(cipher.doFinal(cipherBytes), Charsets.UTF_8)
        } catch (_: Exception) {
            null
        }
    }

    @Synchronized
    fun saveConfig(
        context: Context,
        authToken: String,
        baseUrl: String,
        releaseChannel: String,
        seenIds: List<String>,
        baselineSet: Boolean? = null,
    ) {
        val encryptedToken = encrypt(authToken.trim())
        val sharedPrefs = prefs(context)
        val existingIds = readIdsLocked(sharedPrefs)
        val mergedIds = mergeRingBuffer(existingIds, seenIds)
        val alreadyBaseline = sharedPrefs.getBoolean(KEY_BASELINE_SET, false)
        val resolvedBaseline = alreadyBaseline || (baselineSet == true) || seenIds.isNotEmpty()

        sharedPrefs.edit()
            .putString(KEY_AUTH_TOKEN_ENC, encryptedToken)
            .putString(KEY_BASE_URL, baseUrl.trim())
            .putString(KEY_RELEASE_CHANNEL, releaseChannel.trim().ifEmpty { "production" })
            .putBoolean(KEY_BASELINE_SET, resolvedBaseline)
            .putString(KEY_NOTIFIED_IDS, JSONArray(mergedIds).toString())
            .apply()
    }

    @Synchronized
    fun getAuthToken(context: Context): String? {
        val raw = prefs(context).getString(KEY_AUTH_TOKEN_ENC, null) ?: return null
        val decrypted = decrypt(raw)
        if (decrypted.isNullOrBlank()) return null
        return decrypted
    }

    @Synchronized
    fun getBaseUrl(context: Context): String? =
        prefs(context).getString(KEY_BASE_URL, null)?.trim()?.takeIf { it.isNotEmpty() }

    @Synchronized
    fun getReleaseChannel(context: Context): String =
        prefs(context).getString(KEY_RELEASE_CHANNEL, null)?.trim()?.ifEmpty { "production" }
            ?: "production"

    @Synchronized
    fun isBaselineSet(context: Context): Boolean =
        prefs(context).getBoolean(KEY_BASELINE_SET, false)

    @Synchronized
    fun setBaselineSet(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean(KEY_BASELINE_SET, value).apply()
    }

    @Synchronized
    fun getSeenNotificationIds(context: Context): List<String> =
        readIdsLocked(prefs(context))

    @Synchronized
    fun isNotificationIdSeen(context: Context, id: String): Boolean {
        val normalized = id.trim()
        if (normalized.isEmpty()) return false
        return readIdsLocked(prefs(context)).contains(normalized)
    }

    @Synchronized
    fun markNotificationIdSeen(context: Context, id: String) {
        val normalized = id.trim()
        if (normalized.isEmpty()) return
        val sharedPrefs = prefs(context)
        val current = readIdsLocked(sharedPrefs)
        val merged = mergeRingBuffer(current, listOf(normalized))
        sharedPrefs.edit()
            .putString(KEY_NOTIFIED_IDS, JSONArray(merged).toString())
            .apply()
    }

    @Synchronized
    fun clearAuth(context: Context) {
        prefs(context).edit().clear().apply()
    }

    @Synchronized
    fun clearAuthIfTokenMatches(context: Context, failedToken: String): Boolean {
        val currentToken = getAuthToken(context) ?: return false
        if (currentToken == failedToken) {
            clearAuth(context)
            return true
        }
        return false
    }

    private fun readIdsLocked(sharedPrefs: android.content.SharedPreferences): List<String> {
        val raw = sharedPrefs.getString(KEY_NOTIFIED_IDS, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            val result = ArrayList<String>(arr.length())
            for (i in 0 until arr.length()) {
                val item = arr.optString(i, "").trim()
                if (item.isNotEmpty()) result.add(item)
            }
            result
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun mergeRingBuffer(existing: List<String>, additions: List<String>): List<String> {
        val list = existing.toMutableList()
        for (raw in additions) {
            val item = raw.trim()
            if (item.isEmpty()) continue
            list.remove(item)
            list.add(item)
        }
        while (list.size > MAX_NOTIFIED_IDS) {
            list.removeAt(0)
        }
        return list
    }
}
