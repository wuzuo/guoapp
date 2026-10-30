package com.duanju.duanju_app.playback

import android.content.Context
import android.media.MediaCodecList
import android.media.MediaFormat
import android.util.Log

/**
 * 设备解码能力探测：低端盒子常把 AVC 上限卡在 1920x1088，竖屏 1080x1920 会被拒；
 * 也有盒子声称支持却没有对应解码器。运行期失败会被记住，下次直接跳过该编码与尺寸。
 */
object CodecCapabilities {
    private const val TAG = "duanju-codec"
    private const val STORE = "duanju-decoder-lessons"
    private const val KEY = "failures"

    private val failed = HashSet<String>()
    private val verdicts = HashMap<String, Boolean>()
    private var prefs: android.content.SharedPreferences? = null

    fun init(context: Context) {
        if (prefs != null) return
        val store = context.getSharedPreferences(STORE, Context.MODE_PRIVATE)
        prefs = store
        failed.addAll(store.getStringSet(KEY, emptySet()).orEmpty())
    }

    fun mimeOf(codec: String): String? = when (codec.trim().lowercase()) {
        "h264", "avc", "avc1", "avc3" -> MediaFormat.MIMETYPE_VIDEO_AVC
        "bytevc1", "hvc1", "hev1", "h265", "hevc" -> MediaFormat.MIMETYPE_VIDEO_HEVC
        else -> null
    }

    fun supports(codec: String, width: Int, height: Int): Boolean {
        val name = codec.trim().lowercase()
        if (name.isEmpty()) return true
        if (width > 0 && height > 0 && failed.contains("$name|${width}|$height")) return false
        if (failed.contains(name)) return false
        val mime = mimeOf(name) ?: return true
        if (width <= 0 || height <= 0) return true
        val verdictKey = "$mime $width $height"
        synchronized(verdicts) { verdicts[verdictKey]?.let { return it } }
        val verdict = runCatching {
            MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.any { info ->
                !info.isEncoder && runCatching {
                    info.getCapabilitiesForType(mime).videoCapabilities.isSizeSupported(width, height)
                }.getOrDefault(false)
            }
        }.getOrDefault(true)
        synchronized(verdicts) { verdicts[verdictKey] = verdict }
        return verdict
    }

    fun learnFailure(codec: String, width: Int, height: Int) {
        val name = codec.trim().lowercase()
        if (name.isEmpty()) return
        val key = if (width > 0 && height > 0) "$name|${width}|$height" else name
        if (!failed.add(key)) return
        prefs?.edit()?.putStringSet(KEY, failed.toSet())?.apply()
        Log.w(TAG, "记住解码失败 $key")
    }

    fun logDevice() {
        runCatching {
            val lines = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
                .filter { !it.isEncoder }
                .flatMap { info ->
                    listOf(MediaFormat.MIMETYPE_VIDEO_AVC, MediaFormat.MIMETYPE_VIDEO_HEVC)
                        .filter { runCatching { info.getCapabilitiesForType(it) }.isSuccess }
                        .map { type ->
                            val video = info.getCapabilitiesForType(type).videoCapabilities
                            "${info.name} $type 至 ${video.supportedWidths.upper}x${video.supportedHeights.upper}"
                        }
                }
            Log.i(TAG, "解码能力：" + lines.joinToString("; "))
        }
    }
}
