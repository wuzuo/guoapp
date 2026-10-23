package com.duanju.duanju_app.playback

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.BaseDataSource
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import java.io.EOFException
import java.io.IOException

@androidx.annotation.OptIn(UnstableApi::class)
class CencDataSource(private val video: RemoteVideo) : BaseDataSource(true) {
    private var position = 0L
    private var remaining = 0L
    private var buffer = ByteArray(0)
    private var offset = 0
    private var opened = false
    private var uri: Uri? = null

    override fun open(spec: DataSpec): Long {
        transferInitializing(spec)
        uri = spec.uri
        position = spec.position
        if (position > video.total) throw IOException("读取位置超出视频长度")
        remaining = if (spec.length == C.LENGTH_UNSET.toLong()) {
            video.total - position
        } else {
            minOf(spec.length, video.total - position)
        }
        buffer = ByteArray(0)
        offset = 0
        opened = true
        transferStarted(spec)
        return remaining
    }

    override fun read(target: ByteArray, targetOffset: Int, length: Int): Int {
        if (length == 0) return 0
        if (remaining == 0L) return C.RESULT_END_OF_INPUT
        if (offset >= buffer.size) {
            buffer = video.read(position, minOf(512 * 1024L, remaining).toInt())
            offset = 0
        }
        if (buffer.isEmpty()) throw EOFException("视频分段意外结束")
        val count = minOf(length, buffer.size - offset, remaining.toInt())
        buffer.copyInto(target, targetOffset, offset, offset + count)
        offset += count
        position += count
        remaining -= count
        bytesTransferred(count)
        return count
    }

    override fun getUri(): Uri? = uri

    override fun close() {
        buffer = ByteArray(0)
        uri = null
        if (opened) {
            opened = false
            transferEnded()
        }
    }

    class Factory(private val video: RemoteVideo) : DataSource.Factory {
        override fun createDataSource(): DataSource = CencDataSource(video)
    }
}
