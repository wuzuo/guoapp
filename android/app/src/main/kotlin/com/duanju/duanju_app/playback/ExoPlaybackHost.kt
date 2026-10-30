package com.duanju.duanju_app.playback

import android.content.Context
import android.graphics.Color
import android.net.Uri
import android.util.Log
import android.view.Surface
import android.view.View
import android.os.Handler
import android.os.Looper
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DecoderReuseEvaluation
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.view.TextureRegistry
import java.util.concurrent.Executors

@androidx.annotation.OptIn(UnstableApi::class)
class ExoPlaybackHost(
    private val engine: FlutterEngine,
    private val context: Context,
) : MethodChannel.MethodCallHandler {
    private companion object {
        const val TAG = "duanju-playback"
    }

    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "duanju/playback")
    private val sessions = mutableMapOf<Int, Session>()
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var nextId = 1

    init {
        CodecCapabilities.init(context)
        CodecCapabilities.logDevice()
        channel.setMethodCallHandler(this)
        engine.platformViewsController.registry.registerViewFactory(
            "duanju/playback-view",
            PlaybackViewFactory(this),
        )
    }

    fun platformView(context: Context, id: Int, fit: Int): PlatformView {
        val session = sessions[id]
        val view = PlayerView(context).apply {
            useController = false
            isFocusable = false
            isClickable = false
            setShutterBackgroundColor(Color.BLACK)
            setKeepContentOnPlayerReset(true)
            setShowBuffering(PlayerView.SHOW_BUFFERING_NEVER)
            resizeMode = when (fit) {
                1 -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                2 -> AspectRatioFrameLayout.RESIZE_MODE_FILL
                else -> AspectRatioFrameLayout.RESIZE_MODE_FIT
            }
            player = session?.player
        }
        session?.attachPlatformView(view)
        return object : PlatformView {
            override fun getView(): View = view

            override fun dispose() {
                session?.detachPlatformView(view)
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "create") {
            try {
                val id = nextId++
                val session = Session(id)
                sessions[id] = session
                result.success(mapOf("id" to id, "texture" to session.textureId))
            } catch (error: Throwable) {
                result.error("create_failed", error.message ?: "播放器初始化失败", null)
            }
            return
        }
        val id = call.argument<Int>("id") ?: 0
        val session = sessions[id]
        if (session == null) {
            result.success(null)
            return
        }
        try {
            when (call.method) {
                "open" -> {
                    session.open(call, result)
                    return
                }
                "play" -> session.player.play()
                "pause" -> session.player.pause()
                "stop" -> session.player.stop()
                "seek" -> session.player.seekTo((call.argument<Number>("value")?.toLong() ?: 0L).coerceAtLeast(0L))
                "rate" -> session.player.setPlaybackSpeed(
                    (call.argument<Number>("value")?.toFloat() ?: 1f).coerceIn(0.25f, 4f),
                )
                "volume" -> session.player.volume =
                    (call.argument<Number>("value")?.toFloat() ?: 1f).coerceIn(0f, 1f)
                "dispose" -> {
                    sessions.remove(id)
                    session.release()
                }
            }
        } catch (error: Throwable) {
            session.send("error", mapOf("message" to (error.message ?: "播放控制失败")))
        }
        result.success(null)
    }

    inner class Session(private val id: Int) {
        // 纹理 0 在该引擎里等同于「无纹理」，画面会全黑，因此跳过 0。
        private val producer: TextureRegistry.SurfaceProducer = createProducer()
        val textureId: Long = producer.id()

        val player: ExoPlayer = ExoPlayer.Builder(
            context,
            DefaultRenderersFactory(context).setEnableDecoderFallback(true),
        )
            .setLoadControl(
                DefaultLoadControl.Builder()
                    .setBufferDurationsMs(15000, 30000, 1000, 2000)
                    .setTargetBufferBytes(12 * 1024 * 1024)
                    .build(),
            )
            .build()

        private var platformView: PlayerView? = null
        private var ticker: Runnable? = null
        private var attached: Surface? = null
        private var dropped = 0
        private var released = false
        private var sources: List<Source> = emptyList()
        private var softChecked = false
        private var sourceIndex = 0
        private var downgrades = 0
        private var wantPlay = true
        private val syncGuard = PlaybackSyncGuard()

        init {
            try {
                player.videoScalingMode = C.VIDEO_SCALING_MODE_SCALE_TO_FIT
                player.setAudioAttributes(
                    androidx.media3.common.AudioAttributes.Builder()
                        .setUsage(C.USAGE_MEDIA)
                        .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                        .build(),
                    true,
                )
                player.setHandleAudioBecomingNoisy(true)
            } catch (_: Throwable) {
            }
            producer.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
                override fun onSurfaceCreated() = attachSurface()

                override fun onSurfaceAvailable() = attachSurface()

                override fun onSurfaceDestroyed() = detachSurface()

                override fun onSurfaceCleanup() = detachSurface()
            })
            player.addAnalyticsListener(object : AnalyticsListener {
                override fun onVideoInputFormatChanged(
                    eventTime: AnalyticsListener.EventTime,
                    format: Format,
                    decoderReuseEvaluation: DecoderReuseEvaluation?,
                ) {
                    Log.i(
                        TAG,
                        "视频流 ${format.sampleMimeType} ${format.width}x${format.height} " +
                            "${format.frameRate}fps ${format.bitrate}bps",
                    )
                }

                override fun onVideoDecoderInitialized(
                    eventTime: AnalyticsListener.EventTime,
                    decoderName: String,
                    initializedTimestampMs: Long,
                    initializationDurationMs: Long,
                ) {
                    Log.i(TAG, "解码器 $decoderName 初始化 ${initializationDurationMs}ms")
                    send("decoder", mapOf("name" to decoderName))
                    softDowngradeIfNeeded(decoderName)
                }

                override fun onDroppedVideoFrames(
                    eventTime: AnalyticsListener.EventTime,
                    droppedFrames: Int,
                    elapsedMs: Long,
                ) {
                    dropped += droppedFrames
                    Log.w(TAG, "丢帧 $droppedFrames 累计 $dropped 耗时 ${elapsedMs}ms")
                }

                override fun onVideoFrameProcessingOffset(
                    eventTime: AnalyticsListener.EventTime,
                    totalProcessingOffsetUs: Long,
                    frameCount: Int,
                ) {
                    if (!syncGuard.offer(totalProcessingOffsetUs, frameCount, player.isPlaying)) {
                        return
                    }
                    Log.w(
                        TAG,
                        "音画漂移过大，重新对齐（偏移 ${totalProcessingOffsetUs / 1000}ms）",
                    )
                    runCatching { player.seekTo(player.currentPosition) }
                }

                override fun onAudioUnderrun(
                    eventTime: AnalyticsListener.EventTime,
                    bufferSize: Int,
                    bufferSizeMs: Long,
                    elapsedSinceLastFeedMs: Long,
                ) {
                    Log.w(TAG, "音频欠载 buffer=$bufferSize 滞后 ${elapsedSinceLastFeedMs}ms")
                }
            })
            player.addListener(object : Player.Listener {
                override fun onPlaybackStateChanged(playbackState: Int) {
                    emitState()
                }

                override fun onIsPlayingChanged(isPlaying: Boolean) {
                    emitState()
                }

                override fun onPlaybackParametersChanged(playbackParameters: androidx.media3.common.PlaybackParameters) {
                    send("rate", mapOf("rate" to playbackParameters.speed.toDouble()))
                }

                override fun onRenderedFirstFrame() {
                    Log.i(TAG, "首帧渲染")
                }

                override fun onVideoSizeChanged(videoSize: VideoSize) {
                    Log.i(TAG, "尺寸回调 ${videoSize.width}x${videoSize.height}")
                    if (videoSize.width <= 0 || videoSize.height <= 0) return
                    resizeSurface(videoSize.width, videoSize.height)
                    send(
                        "video",
                        mapOf("width" to videoSize.width, "height" to videoSize.height),
                    )
                }

                override fun onPlayerError(error: PlaybackException) {
                    Log.w(TAG, "player error ${error.errorCodeName}: ${error.message}")
                    if (fallbackToLowerSource(error)) return
                    send("error", mapOf("message" to (error.message ?: error.errorCodeName)))
                }
            })
            try {
                val initial = surfaceSize(1280, 720)
                producer.setSize(initial.first, initial.second)
            } catch (_: Throwable) {
            }
            attachSurface()
            startTicker()
        }

        private fun createProducer(): TextureRegistry.SurfaceProducer {
            val first = engine.renderer.createSurfaceProducer(
                TextureRegistry.SurfaceLifecycle.resetInBackground,
            )
            if (first.id() != 0L) return first
            val second = engine.renderer.createSurfaceProducer(
                TextureRegistry.SurfaceLifecycle.resetInBackground,
            )
            first.release()
            return second
        }

        private fun attachSurface() {
            if (released || platformView != null) return
            try {
                val surface = producer.getForcedNewSurface()
                player.setVideoSurface(surface)
                attached?.release()
                attached = surface
            } catch (error: Throwable) {
                Log.w(TAG, "attach surface failed", error)
            }
        }

        private fun detachSurface() {
            if (released) return
            try {
                if (platformView == null) player.setVideoSurface(null)
            } catch (_: Throwable) {
            }
            try {
                attached?.release()
            } catch (_: Throwable) {
            }
            attached = null
        }

        private fun resizeSurface(width: Int, height: Int) {
            if (released || platformView != null) return
            val target = surfaceSize(width, height)
            if (producer.width == target.first && producer.height == target.second) return
            detachSurface()
            try {
                producer.setSize(target.first, target.second)
                Log.i(TAG, "纹理 ${target.first}x${target.second}（视频 ${width}x$height）")
            } catch (error: Throwable) {
                Log.w(TAG, "resize failed", error)
            }
            attachSurface()
        }

        private fun surfaceSize(width: Int, height: Int): Pair<Int, Int> {
            val metrics = context.resources.displayMetrics
            val maxWidth = metrics.widthPixels
            val maxHeight = metrics.heightPixels
            if (width <= maxWidth && height <= maxHeight) {
                return width.coerceAtLeast(2) to height.coerceAtLeast(2)
            }
            val scale = minOf(maxWidth.toDouble() / width, maxHeight.toDouble() / height)
            val scaledWidth = ((width * scale).toInt() / 2 * 2).coerceAtLeast(2)
            val scaledHeight = ((height * scale).toInt() / 2 * 2).coerceAtLeast(2)
            return scaledWidth to scaledHeight
        }

        private fun startTicker() {
            val runnable = object : Runnable {
                override fun run() {
                    if (released) return
                    emitState()
                    main.postDelayed(this, 100)
                }
            }
            ticker = runnable
            main.postDelayed(runnable, 100)
        }

        fun send(type: String, fields: Map<String, Any?>) {
            if (released) return
            try {
                channel.invokeMethod("event", mapOf("id" to id, "type" to type) + fields)
            } catch (_: Throwable) {
            }
        }

        private fun emitState() {
            if (released) return
            try {
                val duration = player.duration.let { if (it == C.TIME_UNSET || it < 0) 0L else it }
                val position = player.currentPosition.coerceAtLeast(0L)
                val buffered = (player.bufferedPosition - position).coerceAtLeast(0L)
                send(
                    "state",
                    mapOf(
                        "playing" to player.isPlaying,
                        "buffering" to (player.playbackState == Player.STATE_BUFFERING),
                        "completed" to (player.playbackState == Player.STATE_ENDED),
                        "position" to position,
                        "duration" to duration,
                        "buffered" to buffered,
                        "rate" to player.playbackParameters.speed.toDouble(),
                        "volume" to player.volume.toDouble(),
                        "dropped" to dropped,
                    ),
                )
            } catch (_: Throwable) {
            }
        }

        fun open(call: MethodCall, result: MethodChannel.Result) {
            val url = call.argument<String>("url").orEmpty()
            if (url.isEmpty()) {
                result.success(null)
                return
            }
            val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
            val start = call.argument<Number>("start")?.toLong() ?: 0L
            val play = call.argument<Boolean>("play") ?: true
            val key = call.argument<String>("key").orEmpty()
            val rows = call.argument<List<Map<*, *>>>("sources").orEmpty()
            wantPlay = play
            val candidates = rows.mapNotNull { row ->
                val sourceUrl = (row["url"] as? String).orEmpty()
                if (sourceUrl.isEmpty()) return@mapNotNull null
                Source(
                    url = sourceUrl,
                    headers = (row["headers"] as? Map<*, *>)?.entries
                        ?.associate { it.key.toString() to it.value.toString() }
                        ?: emptyMap(),
                    key = (row["decryptionKey"] as? String).orEmpty(),
                    quality = (row["quality"] as? Number)?.toInt() ?: 0,
                    codec = (row["codec"] as? String).orEmpty(),
                    width = (row["width"] as? Number)?.toInt() ?: 0,
                    height = (row["height"] as? Number)?.toInt() ?: 0,
                )
            }.ifEmpty { listOf(Source(url, headers, key, 0, "", 0, 0)) }
            sources = orderForDevice(candidates)
            sourceIndex = 0
            downgrades = 0
            softChecked = false
            Log.i(
                TAG,
                "打开播放 收到 ${rows.size} 档，采用 " + sources.joinToString {
                    "${it.quality}P ${it.codec} ${it.width}x${it.height}"
                },
            )
            switchTo(0, start, play, result)
        }

        private fun orderForDevice(candidates: List<Source>): List<Source> {
            if (candidates.size <= 1) return candidates
            val sorted = candidates.sortedByDescending { it.quality }
            val playable = sorted.filter { CodecCapabilities.supports(it.codec, it.width, it.height) }
            if (playable.isEmpty()) {
                Log.w(TAG, "所有档位都超出解码能力，用最低档软解")
                return listOf(sorted.last())
            }
            if (playable.size != sorted.size) {
                Log.i(TAG, "跳过 ${sorted.size - playable.size} 个超出解码能力的档位")
            }
            val top = playable.first()
            if (CodecCapabilities.hardwareReady(top.codec, top.width, top.height)) {
                return playable
            }
            val light = playable.filter { it.quality in 1..720 }
            if (light.isEmpty()) {
                Log.w(TAG, "${top.codec} 没有硬解器，可降档位为空，仍用 ${top.quality}P 软解")
                return playable
            }
            Log.i(
                TAG,
                "${top.codec} 没有硬解器，直接选 ${light.first().quality}P 起播（跳过 ${top.quality}P）",
            )
            return light
        }

        private fun switchTo(
            index: Int,
            start: Long,
            play: Boolean,
            result: MethodChannel.Result?,
        ) {
            val source = sources.getOrNull(index)
            if (source == null) {
                result?.success(null)
                return
            }
            sourceIndex = index
            worker.execute {
                val started = System.currentTimeMillis()
                val media = try {
                    buildSource(source.url, source.headers, source.key, localSource(source.url))
                } catch (error: Throwable) {
                    main.post {
                        send("error", mapOf("message" to (error.message ?: "播放地址解析失败")))
                        result?.success(null)
                    }
                    return@execute
                }
                Log.i(TAG, "构建媒体源 ${System.currentTimeMillis() - started}ms")
                main.post {
                    if (released) {
                        result?.success(null)
                        return@post
                    }
                    try {
                        player.setMediaSource(media)
                        player.prepare()
                        if (start > 0) player.seekTo(start)
                        player.playWhenReady = play
                        emitState()
                    } catch (error: Throwable) {
                        send("error", mapOf("message" to (error.message ?: "无法开始播放")))
                    }
                    result?.success(null)
                }
            }
        }

        private fun localSource(url: String): Boolean {
            val scheme = Uri.parse(url).scheme.orEmpty()
            return scheme == "file" || scheme.isEmpty()
        }

        private fun buildSource(
            url: String,
            headers: Map<String, String>,
            key: String,
            local: Boolean,
        ): MediaSource {
            val parsed = Uri.parse(url)
            val scheme = parsed.scheme.orEmpty()
            val file = local || scheme == "file" || scheme.isEmpty()
            if (key.isNotEmpty() && !file) {
                val video = RemoteVideo(url, headers, hexToBytes(key)).prepare()
                return ProgressiveMediaSource.Factory(CencDataSource.Factory(video))
                    .createMediaSource(MediaItem.fromUri(parsed))
            }
            val item = if (file && scheme.isEmpty()) {
                MediaItem.fromUri(Uri.fromFile(java.io.File(url)))
            } else {
                MediaItem.fromUri(parsed)
            }
            val http = DefaultHttpDataSource.Factory()
                .setDefaultRequestProperties(headers)
                .setAllowCrossProtocolRedirects(true)
            val dataSource = if (file) DefaultDataSource.Factory(context, http) else http
            return if (parsed.path?.endsWith(".m3u8") == true) {
                HlsMediaSource.Factory(dataSource).createMediaSource(item)
            } else {
                ProgressiveMediaSource.Factory(dataSource).createMediaSource(item)
            }
        }

        private fun isSoftwareDecoder(name: String) = CodecCapabilities.softwareName(name)

        private fun softDowngradeIfNeeded(decoderName: String) {
            if (softChecked) return
            softChecked = true
            if (!isSoftwareDecoder(decoderName)) return
            val current = sources.getOrNull(sourceIndex) ?: return
            val tiers = sources.map { it.quality }.distinct().sortedDescending()
            if (tiers.size <= 1) return
            val target = tiers.firstOrNull { it in 1..720 } ?: return
            if (current.quality <= target) return
            val index = sources.indexOfFirst { it.quality == target }
            if (index < 0) return
            val position = runCatching { player.currentPosition }.getOrDefault(0L)
            Log.i(TAG, "软解 ${current.quality}P 压力过大，自动降到 ${target}P 从 ${position}ms 继续")
            send("downgrade", mapOf("quality" to target, "codec" to sources[index].codec))
            main.post { switchTo(index, position, wantPlay, null) }
        }

        private fun fallbackToLowerSource(error: PlaybackException): Boolean {
            val decoderProblem =
                error.errorCode in PlaybackException.ERROR_CODE_DECODER_INIT_FAILED..
                    PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED
            if (!decoderProblem) return false
            if (downgrades >= 3 || sourceIndex + 1 >= sources.size) return false
            val current = sources.getOrNull(sourceIndex) ?: return false
            CodecCapabilities.learnFailure(current.codec, current.width, current.height)
            val position = runCatching { player.currentPosition }.getOrDefault(0L)
            downgrades++
            val next = sources[sourceIndex + 1]
            Log.w(
                TAG,
                "解码失败，降到 ${next.quality}P ${next.codec} ${next.width}x${next.height} 从 ${position}ms 继续",
            )
            send("downgrade", mapOf("quality" to next.quality, "codec" to next.codec))
            switchTo(sourceIndex + 1, position, wantPlay, null)
            return true
        }

        fun attachPlatformView(view: PlayerView) {
            platformView = view
        }

        fun detachPlatformView(view: PlayerView) {
            if (platformView === view) platformView = null
            if (view.player === player) view.player = null
        }

        fun release() {
            if (released) return
            released = true
            try {
                platformView?.let { view -> if (view.player === player) view.player = null }
            } catch (_: Throwable) {
            }
            platformView = null
            ticker?.let { main.removeCallbacks(it) }
            ticker = null
            try {
                player.release()
            } catch (_: Throwable) {
            }
            try {
                attached?.release()
            } catch (_: Throwable) {
            }
            attached = null
            try {
                producer.release()
            } catch (_: Throwable) {
            }
        }
    }
}

private data class Source(
    val url: String,
    val headers: Map<String, String>,
    val key: String,
    val quality: Int,
    val codec: String,
    val width: Int,
    val height: Int,
)

private class PlaybackViewFactory(private val host: ExoPlaybackHost) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *>
        val id = (params?.get("id") as? Number)?.toInt() ?: 0
        val fit = (params?.get("fit") as? Number)?.toInt() ?: 0
        return host.platformView(context, id, fit)
    }
}
