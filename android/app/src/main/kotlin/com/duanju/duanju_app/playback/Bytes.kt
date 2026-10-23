package com.duanju.duanju_app.playback

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

internal fun Byte.u() = toInt() and 255

internal fun hexToBytes(value: String): ByteArray {
    require(value.length % 2 == 0)
    return ByteArray(value.length / 2) { value.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
}

internal fun ByteArray.i32(at: Int): Int =
    ByteBuffer.wrap(this, at, 4).order(ByteOrder.BIG_ENDIAN).int

internal fun ByteArray.u32(at: Int): Long = i32(at).toLong() and 0xffffffffL

internal fun ByteArray.i64(at: Int): Long =
    ByteBuffer.wrap(this, at, 8).order(ByteOrder.BIG_ENDIAN).long

internal fun digest(algorithm: String, value: ByteArray): ByteArray =
    MessageDigest.getInstance(algorithm).digest(value)

internal fun aesCtr(key: ByteArray, iv: ByteArray, data: ByteArray): ByteArray =
    Cipher.getInstance("AES/CTR/NoPadding").run {
        init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
        doFinal(data)
    }
