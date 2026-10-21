package core

// hgSm3 实现标准 SM3 哈希（GB/T 32905 / ISO/IEC 10118-3），对齐 HGTV-main 的 sm3()。
// SM3 是红果接口 X-Medusa 签名所需的摘要算法，Go 标准库未提供，故在此自行实现。

func hgSm3(data []byte) []byte {
	iv := [8]uint32{
		0x7380166f, 0x4914b2b9, 0x172442d7, 0xda8a0600,
		0xa96f30bc, 0x163138aa, 0xe38dee4d, 0xb0fb0e4e,
	}
	const t0 = uint32(0x79cc4519)
	const t1 = uint32(0x7a879d8a)
	rotl := func(x uint32, n int) uint32 { return (x << (n & 31)) | (x >> ((32 - n) & 31)) }
	p0 := func(x uint32) uint32 { return x ^ rotl(x, 9) ^ rotl(x, 17) }
	p1 := func(x uint32) uint32 { return x ^ rotl(x, 15) ^ rotl(x, 23) }
	ff := func(x, y, z uint32, j int) uint32 {
		if j < 16 {
			return x ^ y ^ z
		}
		return (x & y) | (x & z) | (y & z)
	}
	gg := func(x, y, z uint32, j int) uint32 {
		if j < 16 {
			return x ^ y ^ z
		}
		return (x & y) | (^x & z)
	}

	// 填充：追加 0x80，补 0 到 56 字节对齐，再以大端写入原始比特长度。
	msg := append([]byte(nil), data...)
	l := uint64(len(data)) * 8
	msg = append(msg, 0x80)
	for len(msg)%64 != 56 {
		msg = append(msg, 0x00)
	}
	var tail [8]byte
	for i := 0; i < 8; i++ {
		tail[i] = byte(l >> (56 - 8*i))
	}
	msg = append(msg, tail[:]...)

	for len(msg) >= 64 {
		block := msg[:64]
		msg = msg[64:]

		var w [68]uint32
		for i := 0; i < 16; i++ {
			w[i] = uint32(block[i*4])<<24 | uint32(block[i*4+1])<<16 | uint32(block[i*4+2])<<8 | uint32(block[i*4+3])
		}
		for i := 16; i < 68; i++ {
			w[i] = p1(w[i-16]^w[i-9]^rotl(w[i-3], 15)) ^ rotl(w[i-13], 7) ^ w[i-6]
		}
		var w1 [64]uint32
		for i := 0; i < 64; i++ {
			w1[i] = w[i] ^ w[i+4]
		}

		a, b, c, d, e, f, g, h := iv[0], iv[1], iv[2], iv[3], iv[4], iv[5], iv[6], iv[7]
		for i := 0; i < 64; i++ {
			tj := t0
			if i >= 16 {
				tj = t1
			}
			ss1 := rotl((rotl(a, 12)+e+rotl(tj, i))&0xffffffff, 7)
			ss2 := ss1 ^ rotl(a, 12)
			tt1 := (ff(a, b, c, i) + d + ss2 + w1[i]) & 0xffffffff
			tt2 := (gg(e, f, g, i) + h + ss1 + w[i]) & 0xffffffff
			d = c
			c = rotl(b, 9)
			b = a
			a = tt1
			h = g
			g = rotl(f, 19)
			f = e
			e = p0(tt2)
		}
		iv[0] ^= a
		iv[1] ^= b
		iv[2] ^= c
		iv[3] ^= d
		iv[4] ^= e
		iv[5] ^= f
		iv[6] ^= g
		iv[7] ^= h
	}

	out := make([]byte, 32)
	for i := 0; i < 8; i++ {
		v := iv[i]
		out[i*4] = byte(v >> 24)
		out[i*4+1] = byte(v >> 16)
		out[i*4+2] = byte(v >> 8)
		out[i*4+3] = byte(v)
	}
	return out
}
