package com.duanju.duanju_app.playback

import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

class RemoteVideo(
    private val url: String,
    private val headers: Map<String, String>,
    private val key: ByteArray?,
) {
    private class Chunk(val bytes: ByteArray, val total: Long)

    var total: Long = 0
        private set

    private var prepared: MediaCrypto.Prepared? = null
    private var prefix: ByteArray = ByteArray(0)

    @Synchronized
    fun prepare(): RemoteVideo {
        if (prepared != null) return this
        val first = range(0, 256 * 1024 - 1)
        total = first.total
        prefix = first.bytes
        val end = MediaCrypto.headerEnd(first.bytes, total)
        val header = if (end > first.bytes.size) {
            first.bytes + range(first.bytes.size.toLong(), end - 1L).bytes
        } else {
            first.bytes.copyOf(end)
        }
        val parsed = MediaCrypto.prepare(header, key)
        if (parsed.samples.any { it.end > total }) throw IOException("视频样本超出资源大小")
        prepared = parsed
        return this
    }

    fun read(start: Long, length: Int): ByteArray {
        prepare()
        if (start >= total || length <= 0) return ByteArray(0)
        val end = minOf(start + length - 1, total - 1)
        val chunk = range(start, end)
        return MediaCrypto.decrypt(chunk.bytes, start, key, prepared!!)
    }

    private fun range(start: Long, end: Long): Chunk {
        require(start >= 0 && end >= start && end - start < 8L * 1024 * 1024)
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15000
            readTimeout = 20000
            requestMethod = "GET"
            setRequestProperty("Range", "bytes=$start-$end")
            setRequestProperty("Accept-Encoding", "identity")
            headers.forEach { (name, value) -> setRequestProperty(name, value) }
        }
        try {
            val code = connection.responseCode
            if (code != HttpURLConnection.HTTP_PARTIAL) throw IOException("视频服务器不支持分段读取（HTTP $code）")
            val header = connection.getHeaderField("Content-Range").orEmpty()
            val match = Regex("bytes (\\d+)-(\\d+)/(\\d+)").matchEntire(header)
                ?: throw IOException("视频分段响应异常")
            val (begin, finish, size) = match.destructured
            val full = size.toLong()
            val last = minOf(end, full - 1)
            if (begin.toLong() != start || finish.toLong() != last || full <= 0) throw IOException("视频分段范围不匹配")
            if (total != 0L && full != total) throw IOException("视频资源已变化，请重试")
            val count = (last - start + 1).toInt()
            val bytes = ByteArray(count)
            var offset = 0
            connection.inputStream.use { stream ->
                while (offset < count) {
                    val read = stream.read(bytes, offset, count - offset)
                    if (read <= 0) throw IOException("视频分段为空")
                    offset += read
                }
            }
            return Chunk(bytes, full)
        } finally {
            connection.disconnect()
        }
    }
}
