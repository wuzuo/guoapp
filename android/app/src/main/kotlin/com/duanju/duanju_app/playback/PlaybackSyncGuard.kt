package com.duanju.duanju_app.playback

import kotlin.math.abs

/**
 * 音画同步保护：累计视频帧相对音频时钟的偏移，超过阈值且过了冷却期就建议重新对齐一次，
 * 避免长时间播放后画面落后于声音。
 */
class PlaybackSyncGuard(
    private val thresholdUs: Long = 150_000,
    private val minFrames: Int = 120,
    private val cooldownMs: Long = 30_000,
) {
    private var offsetUs = 0L
    private var frames = 0
    private var lastResyncAt = System.currentTimeMillis()

    fun offer(totalOffsetUs: Long, frameCount: Int, playing: Boolean): Boolean {
        if (frameCount <= 0) return false
        offsetUs += totalOffsetUs
        frames += frameCount
        if (frames < minFrames) return false
        val average = offsetUs / frames
        offsetUs = 0
        frames = 0
        val now = System.currentTimeMillis()
        if (!playing || abs(average) < thresholdUs || now - lastResyncAt < cooldownMs) return false
        lastResyncAt = now
        return true
    }
}
