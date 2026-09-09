package com.memeboard.ime

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.inputmethodservice.InputMethodService
import android.util.Log
import android.view.View
import android.widget.Toast
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import androidx.core.view.inputmethod.InputConnectionCompat
import androidx.core.view.inputmethod.InputContentInfoCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.lifecycle.setViewTreeViewModelStoreOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import com.memeboard.ime.data.MtPhotosClient
import com.memeboard.ime.data.Prefs
import com.memeboard.ime.ui.MemeBoardTheme
import com.memeboard.ime.ui.RootPanel
import java.io.File

class MemeBoardImeService : InputMethodService(),
    LifecycleOwner,
    ViewModelStoreOwner,
    SavedStateRegistryOwner {

    private val lifecycleRegistry = LifecycleRegistry(this)
    private val viewModelStoreInstance = ViewModelStore()
    private val savedStateRegistryController = SavedStateRegistryController.create(this)

    override val lifecycle: Lifecycle get() = lifecycleRegistry
    override val viewModelStore: ViewModelStore get() = viewModelStoreInstance
    override val savedStateRegistry: SavedStateRegistry
        get() = savedStateRegistryController.savedStateRegistry

    override fun onCreate() {
        // performAttach 要求 lifecycle 处于 INITIALIZED，注册 Recreator 等 observer。
        savedStateRegistryController.performAttach()
        super.onCreate()
        // fcitx5-android 的做法：把三个 owner 挂到窗口 decorView（真正的根视图）。
        // Compose 从 parentPanel 向上查找 ViewTree owner 时会找到 decorView 上的设置。
        val decorView = window.window?.decorView
        decorView?.setViewTreeLifecycleOwner(this)
        decorView?.setViewTreeViewModelStoreOwner(this)
        decorView?.setViewTreeSavedStateRegistryOwner(this)
        // 关键：performRestore 必须在 ON_CREATE 之前（它把 isRestored 置 true，
        // Recreator 在 ON_CREATE 时 consume 才不抛异常）。
        savedStateRegistryController.performRestore(null)
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_CREATE)
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_START)
    }

    override fun onDestroy() {
        super.onDestroy()
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_STOP)
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_DESTROY)
        viewModelStoreInstance.clear()
    }

    // 禁用全屏提取模式：网页富文本输入（如豆包 chat）会触发全屏，
    // 既挡住目标文本，又会让 Compose 在 extract 窗口里因缺少三个 owner 而闪退。
    override fun onEvaluateFullscreenMode(): Boolean = false

    override fun onCreateInputView(): View {
        val composeView = ComposeView(this)
        composeView.setContent {
            MemeBoardTheme {
                // 关键：InputMethodService.setInputView 会用 WRAP_CONTENT 高度
                // 覆盖 view 的 layoutParams，所以必须在 Compose 内容里固定高度。
                Box(Modifier.fillMaxWidth().height(300.dp)) {
                    RootPanel(
                        onOpenConfig = { openConfig() },
                        onCommitText = { text -> commitText(text) },
                        onPaste = { pasteClipboard() },
                        clientProvider = { buildClient() },
                        onSend = { file, mime -> sendImage(file, mime) },
                        onShare = { file, mime -> shareImage(file, mime) },
                    )
                }
            }
        }
        return composeView
    }

    private fun buildClient(): MtPhotosClient? {
        val url = Prefs.getServerUrl(this)
        val key = Prefs.getApiKey(this)
        if (url.isBlank() || key.isBlank()) return null
        return MtPhotosClient(url, key)
    }

    private fun openConfig() {
        // SINGLE_TOP + CLEAR_TOP：复用已有实例，避免反复触发时 Activity 栈无限叠加。
        val i = Intent(this, ConfigActivity::class.java)
            .addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
            )
        startActivity(i)
    }

    private fun commitText(text: String) {
        val ic = currentInputConnection
        if (ic == null) {
            toast("无输入连接，请先在目标应用中聚焦输入框")
            return
        }
        ic.commitText(text, 1)
    }

    private fun pasteClipboard() {
        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = cm.primaryClip
        if (clip == null || clip.itemCount == 0) {
            toast("剪贴板为空")
            return
        }
        val text = clip.getItemAt(0).coerceToText(this).toString()
        if (text.isBlank()) {
            toast("剪贴板没有文本")
            return
        }
        commitText(text)
    }

    private fun sendImage(file: File, mimeType: String) {
        Log.d("MemeBoard", "sendImage: name=" + file.name + ", exists=" + file.exists() +
            ", size=" + file.length() + ", mime=" + mimeType)
        val ic = currentInputConnection
        if (ic == null) {
            toast("无输入连接")
            return
        }
        val uri = FileProvider.getUriForFile(this, packageName + ".fileprovider", file)
        val desc = ClipDescription("meme", arrayOf(mimeType))
        val info = InputContentInfoCompat(uri, desc, null)
        try {
            info.requestPermission()
        } catch (e: Exception) {
            Log.w("MemeBoard", "requestPermission failed", e)
        }
        val flags = InputConnectionCompat.INPUT_CONTENT_GRANT_READ_URI_PERMISSION
        val ok = try {
            InputConnectionCompat.commitContent(ic, currentInputEditorInfo, info, flags, null)
        } catch (e: Exception) {
            Log.e("MemeBoard", "commitContent exception", e)
            false
        }
        Log.d("MemeBoard", "commitContent result=" + ok)
        if (ok) {
            toast("已发送图片")
        } else {
            // 目标 App 不支持直发（如 Chrome 网页输入框）：复制到剪贴板并收起键盘，
            // 让用户看到目标界面去长按粘贴。
            val clip = ClipData.newUri(contentResolver, "meme", uri)
            (getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(clip)
            toast("已复制图片，长按输入框粘贴")
            requestHideSelf(0)
        }
    }

    /** 系统分享：拉起分享面板选微信/QQ 好友发送，不依赖输入框是否支持直发。 */
    private fun shareImage(file: File, mimeType: String) {
        val uri = FileProvider.getUriForFile(this, packageName + ".fileprovider", file)
        val share = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        // createChooser 只复制 URI 权限 flags，不会复制 NEW_TASK；
        // 从 Service 上下文启动必须显式给 chooser 加 NEW_TASK。
        val chooser = Intent.createChooser(share, "发送图片")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            startActivity(chooser)
        } catch (e: Exception) {
            Log.e("MemeBoard", "share failed", e)
            toast("无法打开分享面板")
        }
    }

    private fun toast(msg: String) {
        Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()
    }
}