package com.memeboard.ime

import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 全局未捕获异常处理：把崩溃堆栈写到 filesDir/crash.log，便于后续定位。
 */
class CrashHandler(private val context: Context) : Thread.UncaughtExceptionHandler {

    private val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()

    override fun uncaughtException(t: Thread, e: Throwable) {
        try {
            val stamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())
            val log = buildString {
                append("========== ").append(stamp).append(" ==========\n")
                append("thread: ").append(t.name).append("\n")
                append(e.stackTraceToString()).append("\n\n")
            }
            File(context.filesDir, "crash.log").appendText(log)
        } catch (_: Exception) {
        }
        defaultHandler?.uncaughtException(t, e)
    }

    companion object {
        fun readCrashLog(context: Context): String {
            return try {
                File(context.filesDir, "crash.log").readText()
            } catch (_: Exception) {
                ""
            }
        }
    }
}
