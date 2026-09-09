package com.memeboard.ime.ui

import android.content.Context
import android.widget.Toast
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.memeboard.ime.data.MtFile
import com.memeboard.ime.data.MtPhotosClient
import com.memeboard.ime.data.Prefs
import com.memeboard.ime.data.guessMime
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import java.io.File

@Composable
fun MemeBoardTheme(content: @Composable () -> Unit) {
    MaterialTheme(content = content)
}

@Composable
fun RootPanel(
    onOpenConfig: () -> Unit,
    onCommitText: (String) -> Unit,
    onPaste: () -> Unit,
    clientProvider: () -> MtPhotosClient?,
    onSend: (File, String) -> Unit,
    onShare: (File, String) -> Unit,
) {
    var tab by remember { mutableStateOf(1) }
    Column(
        Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.surface)
            .padding(8.dp)
    ) {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Button(onClick = { tab = 0 }, modifier = Modifier.weight(1f)) { Text("图库") }
            Button(onClick = { tab = 1 }, modifier = Modifier.weight(1f)) { Text("键盘") }
            OutlinedButton(onClick = onOpenConfig) { Text("设置") }
        }
        Spacer(Modifier.height(8.dp))
        when (tab) {
            0 -> GalleryPanel(clientProvider, onSend, onShare)
            else -> KeyboardPanel(onCommitText, onPaste)
        }
    }
}

@Composable
private fun GalleryPanel(
    clientProvider: () -> MtPhotosClient?,
    onSend: (File, String) -> Unit,
    onShare: (File, String) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var authCode by remember { mutableStateOf("") }
    var files by remember { mutableStateOf<List<MtFile>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var searchKey by remember { mutableStateOf("") }

    fun loadRecent() {
        scope.launch {
            loading = true
            error = null
            try {
                val client = clientProvider() ?: throw IllegalStateException("未配置服务器/API Key，请点「设置」")
                val code = client.getAuthCode()
                authCode = code
                val gids = Prefs.getGalleryIds(context)
                files = if (gids.isNotBlank()) client.recentFiles(gids) else client.timelineFiles()
            } catch (e: Exception) {
                error = e.message ?: "加载失败"
            } finally {
                loading = false
            }
        }
    }

    fun doSearch() {
        if (searchKey.isBlank()) return
        scope.launch {
            loading = true
            error = null
            try {
                val client = clientProvider() ?: throw IllegalStateException("未配置")
                authCode = client.getAuthCode()
                files = client.search(searchKey)
            } catch (e: Exception) {
                error = e.message ?: "搜索失败"
            } finally {
                loading = false
            }
        }
    }

    LaunchedEffect(Unit) { loadRecent() }

    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(
                value = searchKey,
                onValueChange = { searchKey = it },
                label = { Text("搜索关键词") },
                singleLine = true,
                modifier = Modifier.weight(1f),
            )
            Button(onClick = { doSearch() }, enabled = searchKey.isNotBlank()) { Text("搜索") }
        }
        Spacer(Modifier.height(4.dp))
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = { loadRecent() }) { Text("刷新最近文件") }
            Spacer(Modifier.weight(1f))
            Text("点击发送 · 长按分享", style = MaterialTheme.typography.bodySmall)
        }
        Spacer(Modifier.height(4.dp))

        when {
            error != null -> Text(error ?: "", color = MaterialTheme.colorScheme.error)
            loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            files.isEmpty() -> Text("暂无文件，请检查图库/搜索关键词")
            else -> LazyVerticalGrid(
                columns = GridCells.Fixed(3),
                modifier = Modifier.fillMaxSize(),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                items(files, key = { it.id }) { f ->
                    StickerCell(context, clientProvider, authCode, f, scope, onSend, onShare) { e ->
                        error = e
                        Toast.makeText(context, e, Toast.LENGTH_SHORT).show()
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun StickerCell(
    context: Context,
    clientProvider: () -> MtPhotosClient?,
    authCode: String,
    file: MtFile,
    scope: CoroutineScope,
    onSend: (File, String) -> Unit,
    onShare: (File, String) -> Unit,
    onError: (String) -> Unit,
) {
    val client = clientProvider()
    val model = if (client != null && authCode.isNotBlank()) client.thumbUrl(file.md5, authCode) else null
    val downloadAndAct: (Boolean) -> Unit = { share ->
        scope.launch {
            try {
                val c = clientProvider() ?: throw IllegalStateException("未配置")
                val dest = File(context.cacheDir, "stickers")
                val local = c.downloadOriginal(file.id, file.md5, dest)
                val mime = guessMime(local.extension)
                if (share) onShare(local, mime) else onSend(local, mime)
            } catch (e: Exception) {
                onError("发送失败: " + (e.message ?: ""))
            }
        }
    }
    AsyncImage(
        model = model,
        contentDescription = file.fileName,
        contentScale = ContentScale.Crop,
        modifier = Modifier
            .aspectRatio(1f)
            .clip(RoundedCornerShape(4.dp))
            .combinedClickable(
                onClick = { downloadAndAct(false) },
                onLongClick = { downloadAndAct(true) },
            ),
    )
}

@Composable
private fun KeyboardPanel(onCommitText: (String) -> Unit, onPaste: () -> Unit) {
    var buffer by remember { mutableStateOf("") }
    Column(
        Modifier.fillMaxSize().padding(top = 2.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        // 操作行：预览 + 退格/清空/粘贴/提交
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = buffer.ifEmpty { "输入后点提交" },
                modifier = Modifier.weight(1f),
                maxLines = 1,
                style = MaterialTheme.typography.bodySmall,
            )
            TextButton(onClick = { buffer = buffer.dropLast(1) }) { Text("⌫") }
            TextButton(onClick = { buffer = "" }) { Text("清") }
            TextButton(onClick = onPaste) { Text("粘贴") }
            TextButton(
                onClick = { if (buffer.isNotBlank()) { onCommitText(buffer); buffer = "" } },
                enabled = buffer.isNotBlank(),
            ) { Text("提交") }
        }

        KeyRow(listOf("1", "2", "3", "4", "5", "6", "7", "8", "9", "0")) { buffer += it }
        KeyRow(listOf("q", "w", "e", "r", "t", "y", "u", "i", "o", "p")) { buffer += it }
        KeyRow(listOf("a", "s", "d", "f", "g", "h", "j", "k", "l")) { buffer += it }
        KeyRow(listOf("z", "x", "c", "v", "b", "n", "m", ":", "/")) { buffer += it }
        KeyRow(listOf(".", "@", "_", "-", "http://", "sk_live_", ":8063")) { buffer += it }
    }
}

@Composable
private fun KeyRow(keys: List<String>, onKey: (String) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        keys.forEach { k ->
            Button(
                onClick = { onKey(k) },
                modifier = Modifier.weight(1f),
                contentPadding = PaddingValues(horizontal = 0.dp, vertical = 4.dp),
            ) {
                Text(k, maxLines = 1)
            }
        }
    }
}
