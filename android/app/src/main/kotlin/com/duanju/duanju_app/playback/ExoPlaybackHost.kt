package com.duanju.duanju_app.playback

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.util.concurrent.Executors

@androidx.annotation.OptIn(UnstableApi::class)
class ExoPlaybackHost(
    private val engine: FlutterEngine,
    private val context: Context,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "duanju/playback")
    private val sessions = mutableMapOf<Int, Session>()
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var nextId = 1

    init {
        channel.setMethodCallHandler(this)
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
        private val producer: TextureRegistry.SurfaceProducer = engine.renderer.createSurfaceProducer()
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

        private var ticker: Runnable? = null
        private var released = false

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
                override fun onSurfaceAvailable() {
                    if (released) return
                    try {
                        player.setVideoSurface(producer.surface)
                    } catch (_: Throwable) {
                    }
                }

                override fun onSurfaceCleanup() {
                    if (released) return
                    try {
                        player.setVideoSurface(null)
                    } catch (_: Throwable) {
                    }
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

                override fun onVideoSizeChanged(videoSize: VideoSize) {
                    if (videoSize.width <= 0 || videoSize.height <= 0) return
                    send(
                        "video",
                        mapOf("width" to videoSize.width, "height" to videoSize.height),
                    )
                }

                override fun onPlayerError(error: PlaybackException) {
                    send("error", mapOf("message" to (error.message ?: error.errorCodeName)))
                }
            })
            startTicker()
        }

        private fun startTicker() {
            val runnable = object : Runnable {
                override fun run() {
                    if (released) return
                    emitState()
                    main.postDelayed(this, 40)
                }
            }
            ticker = runnable
            main.postDelayed(runnable, 40)
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
            val local = call.argument<Boolean>("local") ?: false
            worker.execute {
                val source = try {
                    buildSource(url, headers, key, local)
                } catch (error: Throwable) {
                    main.post {
                        send("error", mapOf("message" to (error.message ?: "播放地址解析失败")))
                        result.success(null)
                    }
                    return@execute
                }
                main.post {
                    if (released) {
                        result.success(null)
                        return@post
                    }
                    try {
                        player.setMediaSource(source)
                        player.prepare()
                        if (start > 0) player.seekTo(start)
                        player.playWhenReady = play
                        emitState()
                    } catch (error: Throwable) {
                        send("error", mapOf("message" to (error.message ?: "无法开始播放")))
                    }
                    result.success(null)
                }
            }
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

        fun release() {
            if (released) return
            released = true
            ticker?.let { main.removeCallbacks(it) }
            ticker = null
            try {
                player.release()
            } catch (_: Throwable) {
            }
            try {
                producer.release()
            } catch (_: Throwable) {
            }
        }
    }
}
