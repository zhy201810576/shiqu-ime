package com.memeboard.ime.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

data class Gallery(val id: Long, val name: String)
data class MtFile(val id: Long, val md5: String, val fileName: String)

/**
 * MT Photos 开放 API 客户端（PoC 精简版）。
 * JSON API 用 x-api-key header 鉴权；图片 URL 用 auth_code query 鉴权。
 */
class MtPhotosClient(
    private val baseUrl: String,
    private val apiKey: String,
) {
    private val http = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .build()

    private val jsonMedia = "application/json; charset=utf-8".toMediaType()

    @Volatile private var cachedAuthCode: String? = null
    @Volatile private var cachedAuthAt: Long = 0L

    fun isConfigured() = baseUrl.isNotBlank() && apiKey.isNotBlank()

    /** 获取 auth_code（缓存 20 小时，24 小时有效） */
    suspend fun getAuthCode(): String = withContext(Dispatchers.IO) {
        cachedAuthCode?.let {
            if (System.currentTimeMillis() - cachedAuthAt < 20 * 3600_000L) return@withContext it
        }
        val body = JSONObject().put("api_key", apiKey).toString()
        val req = Request.Builder()
            .url(root() + "/auth/auth_code")
            .post(body.toRequestBody(jsonMedia))
            .build()
        val json = http.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) throw IllegalStateException("auth_code 请求失败: HTTP " + resp.code)
            JSONObject(resp.body?.string() ?: "{}")
        }
        val code = json.optString("auth_code")
        if (code.isEmpty()) throw IllegalStateException("auth_code 为空，请检查 API Key 是否正确")
        cachedAuthCode = code
        cachedAuthAt = System.currentTimeMillis()
        code
    }

    /** 用户图库列表 */
    suspend fun galleries(): List<Gallery> = withContext(Dispatchers.IO) {
        val req = Request.Builder()
            .url(root() + "/gateway/myGalleryList")
            .header("x-api-key", apiKey)
            .get().build()
        val arr = http.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) throw IllegalStateException("图库列表失败: HTTP " + resp.code)
            JSONArray(resp.body?.string() ?: "[]")
        }
        buildList {
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                add(Gallery(o.optLong("id"), o.optString("name")))
            }
        }
    }

    /** 最近添加的文件（galleryIds 必填，多个用下划线分隔） */
    suspend fun recentFiles(galleryIds: String): List<MtFile> = withContext(Dispatchers.IO) {
        val req = Request.Builder()
            .url(root() + "/gateway/recentFiles?galleryIds=" + enc(galleryIds))
            .header("x-api-key", apiKey)
            .get().build()
        parseFileArray(req)
    }

    /** 全部文件（时间线 V2，galleryIds 可选） */
    suspend fun timelineFiles(): List<MtFile> = withContext(Dispatchers.IO) {
        val req = Request.Builder()
            .url(root() + "/gateway/filesInTimelineV2")
            .header("x-api-key", apiKey)
            .get().build()
        parseFileArray(req)
    }

    /** 搜索文件 */
    suspend fun search(key: String): List<MtFile> = withContext(Dispatchers.IO) {
        val body = JSONObject().put("key", key).toString()
        val req = Request.Builder()
            .url(root() + "/gateway/search")
            .header("x-api-key", apiKey)
            .post(body.toRequestBody(jsonMedia))
            .build()
        val json = http.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) throw IllegalStateException("搜索失败: HTTP " + resp.code)
            JSONObject(resp.body?.string() ?: "{}")
        }
        val list = json.optJSONArray("list") ?: return@withContext emptyList()
        buildList {
            for (i in 0 until list.length()) {
                val o = list.getJSONObject(i)
                add(MtFile(o.optLong("id"), o.optString("MD5"), o.optString("fileName")))
            }
        }
    }

    /** 缩略图 URL（给 Coil 加载） */
    fun thumbUrl(md5: String, authCode: String): String =
        root() + "/gateway/h220/" + md5 + "?auth_code=" + enc(authCode)

    /** 原图 URL（下载用） */
    fun originalUrl(id: Long, md5: String, authCode: String): String =
        root() + "/gateway/file/" + id + "/" + md5 + "?type=ori&auth_code=" + enc(authCode)

    /** 下载原图到 destDir，返回本地文件 */
    suspend fun downloadOriginal(id: Long, md5: String, destDir: File): File = withContext(Dispatchers.IO) {
        val code = getAuthCode()
        val req = Request.Builder().url(originalUrl(id, md5, code)).build()
        http.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) throw IllegalStateException("下载失败: HTTP " + resp.code)
            val bytes = resp.body?.bytes() ?: throw IllegalStateException("下载响应为空")
            destDir.mkdirs()
            val ext = guessExt(resp.header("Content-Type"))
            val f = File(destDir, id.toString() + "." + ext)
            f.writeBytes(bytes)
            f
        }
    }

    private fun parseFileArray(req: Request): List<MtFile> {
        val arr = http.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) throw IllegalStateException("请求失败: HTTP " + resp.code)
            JSONArray(resp.body?.string() ?: "[]")
        }
        return buildList {
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                add(MtFile(o.optLong("id"), o.optString("MD5"), o.optString("fileName")))
            }
        }
    }

    private fun root() = baseUrl.trimEnd('/')

    companion object {
        private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")
        private fun guessExt(contentType: String?): String = when {
            contentType == null -> "jpg"
            contentType.contains("png") -> "png"
            contentType.contains("webp") -> "webp"
            contentType.contains("gif") -> "gif"
            contentType.contains("heic") || contentType.contains("heif") -> "heic"
            else -> "jpg"
        }
    }
}

fun guessMime(ext: String): String = when (ext.lowercase()) {
    "png" -> "image/png"
    "webp" -> "image/webp"
    "gif" -> "image/gif"
    "heic" -> "image/heic"
    "heif" -> "image/heif"
    else -> "image/jpeg"
}
