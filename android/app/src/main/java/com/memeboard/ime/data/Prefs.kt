package com.memeboard.ime.data

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * 配置存储：服务端地址（明文）+ API Key（Android Keystore AES/GCM 加密）。
 */
object Prefs {
    private const val NAME = "memeboard_prefs"
    private const val KEY_SERVER = "server_url"
    private const val KEY_APIKEY_ENC = "api_key_enc"
    private const val KEY_GALLERY = "gallery_ids"

    private const val KEYSTORE = "AndroidKeyStore"
    private const val ALIAS = "memeboard_api_key"

    private fun sp(ctx: Context) = ctx.getSharedPreferences(NAME, Context.MODE_PRIVATE)

    fun getServerUrl(ctx: Context): String = sp(ctx).getString(KEY_SERVER, "") ?: ""
    fun setServerUrl(ctx: Context, v: String) = sp(ctx).edit().putString(KEY_SERVER, v.trim()).apply()

    fun getGalleryIds(ctx: Context): String = sp(ctx).getString(KEY_GALLERY, "") ?: ""
    fun setGalleryIds(ctx: Context, v: String) = sp(ctx).edit().putString(KEY_GALLERY, v.trim()).apply()

    fun getApiKey(ctx: Context): String {
        val enc = sp(ctx).getString(KEY_APIKEY_ENC, "") ?: return ""
        if (enc.isEmpty()) return ""
        return try { decrypt(enc) } catch (e: Exception) { "" }
    }

    fun setApiKey(ctx: Context, v: String) {
        val value = v.trim()
        if (value.isEmpty()) {
            sp(ctx).edit().remove(KEY_APIKEY_ENC).apply()
        } else {
            sp(ctx).edit().putString(KEY_APIKEY_ENC, encrypt(value)).apply()
        }
    }

    fun hasConfig(ctx: Context) = getServerUrl(ctx).isNotBlank() && getApiKey(ctx).isNotBlank()

    private fun getOrCreateKey(): SecretKey {
        val ks = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (ks.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        gen.init(
            KeyGenParameterSpec.Builder(
                ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build()
        )
        return gen.generateKey()
    }

    private fun encrypt(plain: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        val iv = cipher.iv
        val enc = cipher.doFinal(plain.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(iv, Base64.NO_WRAP) + ":" + Base64.encodeToString(enc, Base64.NO_WRAP)
    }

    private fun decrypt(data: String): String {
        val parts = data.split(":")
        if (parts.size != 2) return ""
        val iv = Base64.decode(parts[0], Base64.NO_WRAP)
        val enc = Base64.decode(parts[1], Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(128, iv))
        return String(cipher.doFinal(enc), Charsets.UTF_8)
    }
}
