package com.memeboard.ime

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.memeboard.ime.data.MtPhotosClient
import com.memeboard.ime.data.Prefs
import com.memeboard.ime.ui.MemeBoardTheme
import kotlinx.coroutines.launch

class ConfigActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MemeBoardTheme {
                ConfigScreen()
            }
        }
    }
}

@Composable
private fun ConfigScreen() {
    val context = LocalContext.current
    var server by remember { mutableStateOf(Prefs.getServerUrl(context)) }
    var apiKey by remember { mutableStateOf(Prefs.getApiKey(context)) }
    var galleryIds by remember { mutableStateOf(Prefs.getGalleryIds(context)) }
    var status by remember { mutableStateOf("") }
    var testing by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    Column(
        Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("MemeBoard IME 配置", style = MaterialTheme.typography.headlineSmall)

        OutlinedTextField(
            value = server,
            onValueChange = { server = it },
            label = { Text("MT Photos 服务端地址") },
            placeholder = { Text("如 http://192.168.1.10:8063") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = apiKey,
            onValueChange = { apiKey = it },
            label = { Text("API Key（sk_live_...，加密存储）") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = galleryIds,
            onValueChange = { galleryIds = it },
            label = { Text("图库 ID（可选，多个用下划线分隔）") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )

        Button(
            onClick = {
                Prefs.setServerUrl(context, server)
                Prefs.setApiKey(context, apiKey)
                Prefs.setGalleryIds(context, galleryIds)
                status = "已保存"
            },
            modifier = Modifier.fillMaxWidth(),
        ) { Text("保存配置") }

        Button(
            onClick = {
                scope.launch {
                    testing = true
                    status = "测试中…"
                    try {
                        val client = MtPhotosClient(server.trim(), apiKey.trim())
                        val code = client.getAuthCode()
                        val gs = client.galleries()
                        status = "连接成功，auth_code 前 8 位: " + code.take(8) + "，图库数: " + gs.size
                    } catch (e: Exception) {
                        status = "连接失败: " + (e.message ?: "")
                    } finally {
                        testing = false
                    }
                }
            },
            enabled = !testing && server.isNotBlank() && apiKey.isNotBlank(),
            modifier = Modifier.fillMaxWidth(),
        ) { Text(if (testing) "测试中…" else "测试连接") }

        Text(status, style = MaterialTheme.typography.bodyMedium)

        Text(
            "使用说明：1) 保存配置并测试连接；2) 系统设置 → 语言与输入法 → 启用 MemeBoard IME；3) 在任意输入框切换到本输入法，点「图库」选图发送（支持 commitContent 直发，不支持时自动复制到剪贴板）。",
            style = MaterialTheme.typography.bodySmall,
        )

        val crashLog = remember { CrashHandler.readCrashLog(context) }
        if (crashLog.isNotBlank()) {
            Text("检测到崩溃日志（闪退后点下面按钮复制给我）：", style = MaterialTheme.typography.labelLarge)
            Button(
                onClick = {
                    val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    cm.setPrimaryClip(ClipData.newPlainText("crash", crashLog))
                    status = "崩溃日志已复制，请粘贴给我"
                },
                modifier = Modifier.fillMaxWidth(),
            ) { Text("复制崩溃日志") }
        }
    }
}
