package core

// 本文件移植自 HGTV-main 的 Signer.kt / AesV3.kt / VendorConstants.kt（drpys 22261ad 派生，GPL-3.0）。
// 红果内容接口（搜索 / 详情 / 播放 / 弹幕）依赖这套签名：X-Gorgon / X-Khronos / X-Ladon /
// X-Argus / X-Helios / X-Medusa。其中 X-Medusa 使用 SM3（见 provider_hongguo_sm3.go）与
// 自定义 AesV3 变换；服务端逐字段校验，签名不对即被拒（表现为 200+0 字节 / 101000）。

import (
	"bytes"
	"crypto/md5"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"fmt"
	"math"
	"math/bits"
	"math/rand"
	"strconv"
	"strings"
	"time"
)

var hgRand = rand.New(rand.NewSource(time.Now().UnixNano()))

// hgSboxBase64 与 hgHashTable 取自 VendorConstants.kt，AesV3 的盒与 hashF13 的混淆表。
const hgSboxBase64 = "+n0Ia5xZs0sEXznQOEqRmQBnpiCf9U2Ccybu3xhmgzOAAxn72f6uqqmwUsYL83klTni0NqxdGieeiNu9PGPsSRXBMB/cuFbUbM3KCUPINaPvHvSW0vwOcnuUhNHqRVpiAj/TEoE0K91+5ijypUYTATsh9mE3KSoN7Yyvv51cuyR2D3XkU4nhmI2xmmVwT1RMWKtub4sjxAcRDLrPoKSO2AU9FLLadMPX577Wf95IFj6FkKFVt3dCIsmGUC4X+WQxLJvxbRxEaOPpqJOXyzJX6+Vxaq3AzMfF/WAdoi1Hp+JRaV56zgpBtpWP97mH4DoGEIq1+FvV8LyS/3wvwugbQOwb2r26mJEMsiuDQTRn+wrYdrVGBVlhI3WQhyrjUBVMrLF5667llUcEaPCGPVGLD8qO5LlO8hKCvA7V9+8oJc9bXelqVQLhM76T5/WtnT45JKji+hdX0HoNCDDWuKON/QeaxB5uImSX0h2wv0VmP2zd2yeApxHcpsVS+MC2yFwAc2B7oBkTqsk1SEvTpM2fmfMQREBUfin0Bh+iq6EvPPavhWI2IX9e3yAas7Tm/3KEj2UmlFp36kN4x0rMLBRrxuh0U/zUHM4xcAMYjJY4MonxOl/X+alpt2M3WMI7w3HLnpIBigtNiJu7T21v4P6lSd5WFgntnMEt7oF92XzRLkJbTcGmXepE/UVOG6E/0YnhfS+q26utWcuxzpooyeD2cDlK1/8w9d28VzsRjbLuALbmGlp8+d7EzS6Au7lMpZ+ECMZvQmzwJ+eLOpxR+2chdUExp8ogQyq3v9l68rX4jCwjg0+PYKAEEzcU4wHFY2ZcdIHfWL1okD3SszT0GZMyKdZJrg1L2AeerB4tC0C4crp2EHGo5FYdSP7lwkeR2ocmnR+Ia8CYviUJlzOjhRZef9xuVOn3qcjow3fQgivsAmKKkg4+sA8F8/GWeDiGNhg8JM8KtFPMYWWkx5TVFX5t73kiNRJqjlIGVXtGZFCV4gzt0xcDopuZ6xz8r9Rzafpf9ywev8jh8592gHFIqpStZPuJxmDDMrNN0uBE3V+oscdoIzTJbRJ/t+sVvqnReJOgDJKk10fjisJwqyZBmnmn2BSFj8BvVtCMEbkuPOKdzw7eA11GPs04Qw8zWtkaZWwiO/wwpojqN6K0jY5RnNZA7vn4hPSul+nKCkVnVwQvg1zVxcSCtqORmB9KrJaBbssbCQivGJVJfVTt+hYxOtq4ZvWl8f4QAQZ0zGPffCgl9s6yT4vlvIdpu4YhBwA25wtQWZsc6GJYGWHyvSdeuh3mmUI9DSq13Fsp8C1MU3tqc04/df9LoTUXVXI5INOw/e8C7Hd+5CvbkMEFnnrUUmskEw=="

var hgSbox []byte

var hgHashTable = []uint32{
	0xebb64faf, 0x7aadcc2, 0xcf3187bf, 0xe01138ff, 0x6d0bfcff, 0x5a30a3be, 0xb41ad638, 0x34180eb8,
	0xf233eb6f, 0xb1a584cc, 0xccc30dc7, 0x47d1db51, 0xd55653de, 0x70a84fa1, 0x57473c12, 0xf76f0288,
	0x2c077f0a, 0xda0dcad0, 0xfbb86f6c, 0xfdc4cf00, 0x688a020d, 0xe676c6a6, 0x8cd6338b, 0x1a3c8d0e,
	0xcce8b06b, 0x6ad0ed0b, 0xa0522717, 0xdc71ac83, 0x2285db71, 0xd5b4dda6, 0x736f8650, 0x6560306c,
	0x617ce2a6, 0xe423417e, 0xa40e143, 0x544e4032, 0x88dffb2a, 0x716c1ae0, 0x4c467a88, 0x5b23bb3,
	0xe1d0b866, 0xbaa3dcb8, 0xae3374d3, 0xc3381a50, 0x1702f75b, 0xfe6da368, 0xf0b4cf48, 0x4e0ffbb8,
	0x72aad10d, 0x26c53a3d, 0xf2bce0f6, 0xb4557581, 0x4a257fdd, 0x8c3182a2, 0xab0b3b86, 0x3d5dfb14,
	0x4f103634, 0xd37b52d7, 0x444eff16, 0xeb0a33d1, 0x6ca86f6e, 0x284ba7, 0x8387cfa, 0x5fb37586,
}

func init() {
	decoded, err := base64.StdEncoding.DecodeString(strings.ReplaceAll(strings.ReplaceAll(hgSboxBase64, "-", "+"), "_", "/"))
	if err == nil {
		hgSbox = decoded
	}
}

func hgLe32(v uint32) []byte { return []byte{byte(v), byte(v >> 8), byte(v >> 16), byte(v >> 24)} }
func hgBe32(v uint32) []byte { return []byte{byte(v >> 24), byte(v >> 16), byte(v >> 8), byte(v)} }
func hgLe64(v uint64) []byte {
	return []byte{byte(v), byte(v >> 8), byte(v >> 16), byte(v >> 24), byte(v >> 32), byte(v >> 40), byte(v >> 48), byte(v >> 56)}
}
func hgHex(s string) []byte { b, _ := hex.DecodeString(s); return b }

// hgVarint 编码 zigzag 之后的正整数（protobuf 风格）。
func hgVarint(value int64) []byte {
	n := uint64(value)
	var out []byte
	for n > 127 {
		out = append(out, byte((n&127)|128))
		n >>= 7
	}
	out = append(out, byte(n))
	return out
}

// hgField 是 protobuf 字段的 Go 表示。
type hgField struct {
	tag  int
	kind int // 0=字节串/字符串, 1=sint(锯齿), 2=float32
	n    int64
	s    string
	b    []byte
}

func hgFBytes(tag int, b []byte) hgField    { return hgField{tag: tag, kind: 0, b: b} }
func hgFStr(tag int, s string) hgField       { return hgField{tag: tag, kind: 0, s: s} }
func hgFSint(tag int, n int64) hgField        { return hgField{tag: tag, kind: 1, n: n} }
func hgFFloat(tag int, f float64) hgField     { return hgField{tag: tag, kind: 2, n: int64(math.Float32bits(float32(f)))} }

func hgProto(fields ...hgField) []byte {
	var buf bytes.Buffer
	for _, f := range fields {
		var typeCode int
		switch f.kind {
		case 1:
			typeCode = 0
		case 0:
			typeCode = 2
		case 2:
			typeCode = 5
		}
		buf.Write(hgVarint(int64(f.tag)<<3 | int64(typeCode)))
		switch f.kind {
		case 1:
			m := f.n
			var z int64
			if m < 0 {
				z = -m*2 - 1
			} else {
				z = m * 2
			}
			buf.Write(hgVarint(z))
		case 2:
			var fb [4]byte
			binary.LittleEndian.PutUint32(fb[:], uint32(f.n))
			buf.Write(fb[:])
		default:
			var data []byte
			if f.b != nil {
				data = f.b
			} else {
				data = []byte(f.s)
			}
			if len(data) > 0 {
				buf.Write(hgVarint(int64(len(data))))
				buf.Write(data)
			}
		}
	}
	return buf.Bytes()
}

func hgGetIv(initial uint32, data []byte) uint32 {
	value := initial
	for i := 0; i < len(data); i++ {
		di := uint32(data[i])
		if i&1 == 0 {
			value = (value >> 4) ^ value ^ (value << 6) ^ di
		} else {
			t := ((value >> 7) ^ value ^ (di | (value << 12)))
			value = ^t
		}
	}
	return value
}

func hgIv(query, body []byte, ts int) uint32 {
	return hgGetIv(hgGetIv(hgGetIv(0x20230928, query), body), hgLe32(uint32(ts)))
}

// hgBranch 选一个能让 hashF13 通过的 _rticket 偏移（参考 Signer.branch）。
func hgBranch(queryStr string, body []byte, ts int) int {
	var bodyMd5 []byte
	if body != nil {
		m := md5.Sum(body)
		bodyMd5 = m[:]
	} else {
		bodyMd5 = make([]byte, 16)
	}
	q := hgSm3([]byte(queryStr))
	v := hgIv(q, bodyMd5, ts)
	return int((v & 15) % 3)
}

func hgSumMd5(data []byte) uint32 {
	check := uint32(0x20220420)
	for i := 0; i < 12; i++ {
		var temp uint32
		if i&1 == 0 {
			temp = (check >> 3) ^ check
		} else {
			temp = (check >> 5) ^ check
		}
		if i&1 == 0 {
			check = uint32(data[i]) ^ (check << 7)
		} else {
			check = ^(uint32(data[i]) | (check << 11))
		}
		check = check ^ temp
	}
	return (check | 4) ^ 0x1000000
}

func hgHashF13(query, body []byte, ts int) []byte {
	iv := hgIv(query, body, ts)
	index := int((iv & 15) / 3)
	ivV1u := []uint32{0xc4a78580, 0xb3c0fd39, 0xc58c5686, 0xc9aa3ba7, 0xf5a7adf2, 0x963c2ed1}[index]
	ivV1 := int32(ivV1u)
	count := ivV1 + int32(ts)
	tt := make([]uint32, len(hgHashTable))
	for i, h := range hgHashTable {
		tt[i] = bits.RotateLeft32(h, int((count+1)&255))
	}
	shift := int((count + 2) & 7)
	padVals := []int{0xfa, 0x45, 0x61, 0xd7}
	pad := make([]byte, 4)
	for i, pv := range padVals {
		pad[i] = byte((((pv | (pv << 8)) >> shift) & 255))
	}
	data := append(append(append([]byte{}, query...), body...), hgLe32(uint32(ts))...)
	data = append(data, pad...)
	data = append(data, hgHex("00000000000001a0")...)
	di := make([]uint32, 0, len(data)/4+112)
	for i := 0; i+4 <= len(data); i += 4 {
		di = append(di, binary.LittleEndian.Uint32(data[i:]))
	}
	for i := 0; i < 112; i++ {
		x := di[i+1]
		y := di[i+14]
		di = append(di, di[i]+di[i+9]+(bits.RotateLeft32(x,14)^bits.RotateLeft32(x,25)^(x>>3))+(bits.RotateLeft32(y,13)^bits.RotateLeft32(y,15)^(y>>10)))
	}
	rawInitial := []uint32{0x7aba4fc8, 0x67166507, 0x6403fa00, 0x340f512f, 0x3aa0b6b0, 0xb2f083fa, 0xab3d3f6d, 0x8036c890}
	initial := make([]uint32, len(rawInitial))
	for i, h := range rawInitial {
		initial[i] = bits.RotateLeft32(h, -int(count))
	}
	chosen := [][]int{
		{101, 5, 7, 6, 3, 2, 1, 0, 5, 4, 3},
		{96, 0, 6, 7, 5, 3, 2, 1, 5, 4, 4},
		{96, 7, 6, 2, 1, 4, 0, 5, 4, 3, 5},
		{99, 3, 6, 2, 4, 5, 1, 0, 0, 7, 6},
		{96, 0, 5, 6, 7, 3, 1, 2, 5, 4, 4},
		{100, 2, 0, 3, 5, 4, 6, 7, 2, 1, 5},
	}[index]
	d := make([]uint32, len(initial))
	copy(d, initial)
	for i := 0; i < chosen[0]; i++ {
		base := ivV1 + int32(i)
		n1 := ((d[chosen[3]] ^ d[chosen[4]]) & d[chosen[1]]) ^ d[chosen[3]]
		n2 := bits.RotateLeft32(d[chosen[1]], 26) ^ bits.RotateLeft32(d[chosen[1]], 21) ^ bits.RotateLeft32(d[chosen[1]], 7)
		n4 := di[int(base)&127] + n1 + n2 + tt[int(base)&63] + d[chosen[5]]
		n5 := bits.RotateLeft32(d[chosen[2]], 30) ^ bits.RotateLeft32(d[chosen[2]], 19) ^ bits.RotateLeft32(d[chosen[2]], 10)
		n6 := (d[chosen[2]] & d[chosen[6]]) | ((d[chosen[2]] | d[chosen[6]]) & d[chosen[7]])
		old := d[chosen[9]]
		removed := d[7]
		d = append([]uint32{removed}, d[:7]...)
		d[chosen[10]] = n5 + n6 + n4
		d[chosen[8]] = old + n4
	}
	ret := make([]byte, 0, 32)
	for i := 0; i < 8; i++ {
		v := d[i] + initial[i]
		ret = append(ret, hgBe32(v)...)
	}
	folded := make([]byte, 16)
	for i := 0; i < 16; i++ {
		folded[i] = ret[i] ^ ret[i+16]
	}
	return append(folded, hgLe32(hgSumMd5(folded))...)
}

func hgGorgon(queryStr string, body []byte, ts int, random int) string {
	queryMd5 := md5.Sum([]byte(queryStr))
	var bodyMd5 []byte
	if body != nil {
		m := md5.Sum(body)
		bodyMd5 = m[:]
	} else {
		bodyMd5 = make([]byte, 16)
	}
	input := make([]byte, 0, 20)
	input = append(input, queryMd5[:4]...)
	input = append(input, bodyMd5[:4]...)
	input = append(input, make([]byte, 4)...)
	input = append(input, hgLe32(uint32(67503104))...)
	input = append(input, hgBe32(uint32(ts))...)
	key := []byte{0x4a, 0x40, 0x16, byte((random >> 8) & 255), 0x47, 0x6c, 1, byte(random & 255)}
	s := make([]int, 256)
	for i := range s {
		s[i] = i
	}
	j := 0
	for i := 0; i <= 255; i++ {
		j = (j + s[i] + int(key[i%8])) & 255
		s[i], s[j] = s[j], s[i]
	}
	j = 0
	out := make([]byte, len(input))
	for n := 0; n < len(input); n++ {
		i := n + 1
		j += s[i]
		j &= 255
		y := s[j&255]
		s[i] = y
		out[n] = byte(uint32(input[n]) ^ uint32(s[(y+y)&255]))
	}
	for i := 0; i < len(out); i++ {
		value := ((uint32(out[i]) >> 4) | (uint32(out[i]) << 4)) & 255
		next := uint32(out[0])
		if i+1 < len(out) {
			next = uint32(out[i+1])
		}
		reversed := bits.Reverse32(uint32((next^value)&255)) >> 24
		out[i] = byte(^(reversed ^ 20) & 255)
	}
	header := []byte{0x84, 0x04, byte(random & 255), byte((random >> 8) & 255), 0x40, 0x01}
	full := append(header, out...)
	return hex.EncodeToString(full)
}

func hgHelios(ts int) string {
	r := hgRand.Uint32()
	asciiSum := md5.Sum(append(hgLe32(r), []byte("8662")...))
	ascii := []byte(hex.EncodeToString(asciiSum[:]))
	words := make([]uint64, 0, 4)
	for i := 0; i < 4; i++ {
		words = append(words, binary.LittleEndian.Uint64(ascii[i*8:]))
	}
	table := []uint64{words[0]}
	b0 := words[0]
	b8 := words[1]
	words = words[2:]
	for i := 0; i < 34; i++ {
		x8 := (bits.RotateLeft64(b8, -8) + b0) ^ uint64(i)
		words = append(words, x8)
		x8 = x8 ^ bits.RotateLeft64(b0, -61)
		table = append(table, x8)
		b0 = x8
		b8 = words[0]
		words = words[1:]
	}
	text := []byte(fmt.Sprintf("%d-1588093228-8662", ts))
	padding := 16 - len(text)%16
	data := append([]byte{}, text...)
	for i := 0; i < padding; i++ {
		data = append(data, byte(padding))
	}
	output := hgLe32(r)
	for at := 0; at+16 <= len(data); at += 16 {
		a := binary.LittleEndian.Uint64(data[at:])
		b := binary.LittleEndian.Uint64(data[at+8:])
		for i := 0; i < 34; i++ {
			b = table[i] ^ (a + bits.RotateLeft64(b, -8))
			a = b ^ bits.RotateLeft64(a, -61)
		}
		output = append(output, hgLe64(a)...)
		output = append(output, hgLe64(b)...)
	}
	return base64.StdEncoding.EncodeToString(output)
}

func hgXmxor(data, key []byte) []byte {
	encoded := make([]int, len(data))
	for i := 0; i < len(data); i++ {
		at := (i * 4) & 28
		d0 := uint32(key[at])
		d1 := uint32(key[at+1])
		v := uint32(data[i])
		d2 := ((((v << 4) | (v >> 4)) & 255) + d0)
		d2 = ^d2 & 255
		d2 ^= d1
		d2 = (((d2 & 255) << 3) | ((d2 & 255) >> 5)) & 255
		d2 = (d2 + d1) & 255
		d2 = (d2 ^ d0) & 255
		encoded[len(data)-i-1] = int((^d2) & 255)
	}
	last := encoded[len(encoded)-1] ^ encoded[len(encoded)-2]
	first := encoded[0]
	encoded[0] = int((^(last) + first) & 255)
	encoded[1] = int((((encoded[0] ^ encoded[len(encoded)-1] ^ 254) + encoded[1]) & 255))
	encoded[2] = int((encoded[2] + ((last - first) ^ ((((encoded[1] << 3) | (encoded[1] >> 5)) & 255) ^ 2)) & 255))
	for i := 0; i < len(encoded)-4; i++ {
		temp := ((((encoded[i+2] << 3) | (encoded[i+2] >> 5)) & 255) ^ encoded[i+1] ^ (i + 3))
		encoded[i+3] = int((^(temp) + encoded[i+3]) & 255)
	}
	encoded[len(encoded)-1] = encoded[len(encoded)-1] ^ encoded[len(encoded)-2]
	encoded[0] = int((((encoded[0] ^ encoded[1]) + sumEncoded(encoded[1:])) & 255))
	out := make([]byte, len(encoded))
	for i := range encoded {
		out[i] = byte(encoded[i])
	}
	return out
}

func sumEncoded(s []int) int {
	var sum int
	for _, e := range s {
		sum += e
	}
	return sum
}

func hgAesV3Encrypt(key []byte, ts int32, source, ivb []byte) []byte {
	if len(source) < 248 {
		padded := make([]byte, 248)
		copy(padded, source)
		source = padded
	}
	word := int(ts) & 3
	box := hgSbox[word*256 : (word+1)*256]
	con := [][]int{{1, 0, 2, 3}, {2, 0, 3, 1}, {0, 1, 3, 2}, {1, 0, 2, 3}}[word]
	order := [][]int{
		{0, 9, 14, 11, 4, 13, 2, 7, 8, 1, 6, 15, 12, 5, 10, 3},
		{0, 9, 14, 15, 4, 13, 2, 7, 8, 1, 6, 3, 12, 5, 10, 11},
		{0, 9, 14, 7, 4, 13, 2, 11, 8, 1, 6, 3, 12, 5, 10, 15},
		{0, 9, 14, 11, 4, 13, 2, 7, 8, 1, 6, 15, 12, 5, 10, 3},
	}[word]
	initial4 := []uint32{0xca025ddc, 0x823dc546, 0xc9420583, 0xc298225f}[word]
	le4 := hgLe32(initial4)
	expandedBytes := make([]byte, 0, 48)
	expandedBytes = append(expandedBytes, le4...)
	expandedBytes = append(expandedBytes, le4...)
	expandedBytes = append(expandedBytes, le4...)
	expandedBytes = append(expandedBytes, le4...)
	for i := 0; i < 16; i++ {
		expandedBytes[i] ^= key[i]
	}
	expandedBytes = append(expandedBytes, make([]byte, 32)...)
	expanded := make([]uint32, 48)
	for i := 0; i < 48; i++ {
		expanded[i] = uint32(expandedBytes[i])
	}
	rounds := 8
	for i := 4; i < 12; i++ {
		at := 4 * (i - 1)
		a, b, c, d := expanded[at], expanded[at+1], expanded[at+2], expanded[at+3]
		if i&3 == 0 {
			t := ((uint32(initial4) >> (rounds & 24)) ^ uint32(box[b])) & 255
			b2 := uint32(box[c])
			c2 := uint32(box[d])
			d2 := uint32(box[a])
			a, b, c, d = t, b2, c2, d2
		}
		rounds += 2
		expanded[at+4] = a ^ expanded[at-12]
		expanded[at+5] = b ^ expanded[at-11]
		expanded[at+6] = c ^ expanded[at-10]
		expanded[at+7] = d ^ expanded[at-9]
	}
	keys := make([][4]uint32, 12)
	for k := 0; k < 12; k++ {
		keys[k] = [4]uint32{expanded[k*4], expanded[k*4+1], expanded[k*4+2], expanded[k*4+3]}
	}
	block := func(value []byte) []byte {
		rows := [4][4]uint32{}
		for i := 0; i < 4; i++ {
			for j := 0; j < 4; j++ {
				rows[i][j] = uint32(value[i*4+j])
			}
		}
		addCon := func(off int) {
			for i := 0; i < 4; i++ {
				for j := 0; j < 4; j++ {
				rows[i][j] ^= keys[off+i][con[j]]
			}
			}
		}
		addCon(0)
		for round := 1; round <= 2; round++ {
			for i := 0; i < 4; i++ {
				for j := 0; j < 4; j++ {
				rows[i][j] = uint32(box[rows[i][j]&255])
			}
			}
			var before [4][4]uint32
			for i := 0; i < 4; i++ {
				before[i] = rows[i]
			}
			for i := 0; i < 4; i++ {
				rows[i] = before[con[i]]
			}
			var flat [16]uint32
			idx := 0
			for i := 0; i < 4; i++ {
				for j := 0; j < 4; j++ {
				flat[idx] = rows[i][j]
				idx++
			}
			}
			for i := 0; i < 16; i++ {
				rows[i/4][i%4] = flat[order[i]]
			}
			if round == 1 {
				var old2 [4][4]uint32
				for i := 0; i < 4; i++ {
					old2[i] = rows[i]
				}
				for i := 0; i < 4; i++ {
					for j := 0; j < 4; j++ {
					rows[i][j] = old2[con[j]][j]
				}
			}
				xt := func(x uint32) uint32 {
					if x&128 != 0 {
						return ((x << 1) ^ 0x1b) & 255
					}
					return (x << 1) & 255
				}
				for i := 0; i < 4; i++ {
					t := rows[0][i] ^ rows[1][i] ^ rows[2][i] ^ rows[3][i]
					u := rows[0][i]
					rows[0][i] = rows[0][i] ^ t ^ xt(rows[0][i]^rows[1][i])
					rows[1][i] = rows[1][i] ^ t ^ xt(rows[1][i]^rows[2][i])
					rows[2][i] = rows[2][i] ^ t ^ xt(rows[2][i]^rows[3][i])
					rows[3][i] = rows[3][i] ^ t ^ xt(rows[3][i]^u)
				}
			}
			addCon(round * 4)
		}
		for i := 0; i < 4; i++ {
			for j := 0; j < 4; j++ {
				rows[i][j] ^= keys[4+i][j]
			}
		}
		out := make([]byte, 16)
		idx := 0
		for i := 0; i < 4; i++ {
			for j := 0; j < 4; j++ {
				out[idx] = byte(rows[i][j])
				idx++
			}
		}
		return out
	}
	plaintext := make([]byte, 32)
	for i := 0; i < 31; i++ {
		at := i * 8
		plaintext[i] = byte((((uint32(source[at]) >> 4) & 2) | (uint32(source[at+1]) & 64) | ((uint32(source[at+2]) >> 2) & 1) | ((uint32(source[at+3]) << 3) & 128) | ((uint32(source[at+4]) >> 1) & 4) | ((uint32(source[at+5]) << 3) & 16) | ((uint32(source[at+6]) << 5) & 32) | ((uint32(source[at+7]) >> 4) & 8)))
	}
	plaintext[31] = 1
	first := block(hgXor(plaintext[0:16], ivb))
	second := block(hgXor(plaintext[16:32], first))
	key16 := append(first, second...)
	out := make([]byte, len(source))
	copy(out, source)
	for i := 0; i < 31; i++ {
		at := i * 8
		k := uint32(key16[i])
		out[at] = byte((uint32(out[at]) & 0xdf) | ((k << 4) & 32))
		out[at+1] = byte((uint32(out[at+1]) & 0xbf) | (k & 64))
		out[at+2] = byte((uint32(out[at+2]) & 0xfb) | ((k << 2) & 4))
		out[at+3] = byte((uint32(out[at+3]) & 0xef) | ((k >> 3) & 16))
		out[at+4] = byte((uint32(out[at+4]) & 0xf7) | ((k + k) & 8))
		out[at+5] = byte((uint32(out[at+5]) & 0xfd) | ((k >> 3) & 2))
		out[at+6] = byte((uint32(out[at+6]) & 0xfe) | ((k >> 5) & 1))
		out[at+7] = byte((uint32(out[at+7]) & 0x7f) | ((k << 4) & 128))
	}
	return append([]byte{key16[len(key16)-1]}, out...)
}

func hgXor(a, b []byte) []byte {
	n := len(a)
	if len(b) < n {
		n = len(b)
	}
	out := make([]byte, n)
	for i := 0; i < n; i++ {
		out[i] = a[i] ^ b[i]
	}
	return out
}

func hgDeviceProto(deviceID string) []byte {
	return hgProto(
		hgFSint(1, 1), hgFSint(2, 2), hgFStr(3, "8662"), hgFStr(4, deviceID),
		hgFStr(5, "Ai6svO3PyrwDOUSmO6ZcResxu"), hgFStr(6, "!noperm!"),
		hgFSint(7, -888888), hgFSint(8, -888888), hgFSint(9, 3), hgFSint(10, -888888),
		hgFStr(11, "!notset!"), hgFStr(12, "Asia/Shanghai,8"), hgFStr(13, "zh_CN"),
		hgFSint(14, 4), hgFFloat(16, 255.24993896484375), hgFFloat(17, 35.58599090576172),
		hgFFloat(18, 3.467449188232422), hgFFloat(19, 3.467449188232422), hgFFloat(20, 255.1754913330078),
		hgFFloat(21, 42.17544174194336), hgFStr(22, "16"), hgFSint(23, 41), hgFSint(24, 36),
		hgFSint(25, 1728388016635), hgFSint(26, 1728388016635), hgFSint(27, 1728388016635),
		hgFSint(28, 1728388016637), hgFSint(29, -1), hgFStr(30, "25053RT47C"), hgFStr(31, "Redmi"),
		hgFStr(32, "25053RT47C"), hgFStr(33, "25053RT47C"), hgFStr(34, "Xiaomi"), hgFStr(35, "Redmi"),
		hgFStr(36, "Redmi"), hgFSint(38, 31),
	)
}

func hgMedusa(urlStr string, body []byte, ts int, deviceID, version string) string {
	var bodyMd5 []byte
	if body != nil {
		m := md5.Sum(body)
		bodyMd5 = m[:]
	} else {
		bodyMd5 = make([]byte, 16)
	}
	qi := strings.IndexByte(urlStr, '?')
	var queryBytes []byte
	if qi >= 0 {
		queryBytes = []byte(urlStr[qi+1:])
	} else {
		queryBytes = []byte(urlStr)
	}
	querySm3 := hgSm3(queryBytes)
	queryBodyTs := hgHashF13(querySm3, bodyMd5, ts)
	nested := hgProto(hgFSint(1, 111), hgFSint(2, 10), hgFSint(3, 694367), hgFSint(5, 586952199))
	messageRand := hgRand.Uint32()
	envLaunch := int(hgRand.Float64()*21) + 100
	envPid := int(hgRand.Float64()*2000) + 10001
	env := hgProto(
		hgFSint(1, int64(envLaunch)), hgFSint(2, 146331399), hgFSint(3, 146331396), hgFSint(5, 7),
		hgFStr(6, "v04.06.04.03-bugfix"), hgFSint(7, int64(envPid)),
		hgFBytes(12, hgDeviceProto(deviceID)),
		hgFBytes(13, hgProto(hgFSint(1, int64(ts)), hgFSint(2, -2), hgFSint(4, 200))),
		hgFStr(14, version),
	)
	queryHash := hgSm3(append(append(append([]byte{}, queryBytes...), bodyMd5...), []byte("none")...))
	r := hgRand.Uint32()
	signKey := hgHex("8ebdfa3806ecc5cee79423e6029ed82540bc2218bb7eaef71cb691f7aa8aa2f5")
	hash := hgSm3(append(append(append([]byte{}, signKey...), hgLe32(r)...), signKey...))
	d1 := (r >> 16) & 255
	seed := hgLe32(^(((d1 << 11) | (r >> 24)) ^ (d1 >> 5) ^ d1))
	message := hgProto(
		hgFBytes(1, hgHex("f7e85ffad7d7dc3bd62ac87057cf6118")),
		hgFSint(2, 3), hgFSint(3, int64(messageRand)), hgFStr(4, "8662"), hgFStr(5, deviceID),
		hgFStr(6, "1588093228"), hgFStr(7, version), hgFStr(8, "v04.06.04-ml-android"),
		hgFSint(9, 67503104), hgFBytes(10, hgHex("4001000000000000")),
		hgFSint(12, int64(ts)), hgFBytes(13, queryBodyTs), hgFBytes(14, querySm3[:6]),
		hgFBytes(15, nested), hgFStr(16, "AXYQOS6n2m60x1fVZHIrH3iol"), hgFSint(17, int64(ts)),
		hgFBytes(19, queryHash), hgFStr(20, "none"), hgFSint(21, 312), hgFBytes(23, env),
		hgFStr(24, `{"cmr":16777216,"cmr2":16777216,"un_h":1879194040,"vpn":0,"kd":0,"fkd":3672518972,"pd":-1872573247,"dyn":"","do":0,"tk":true}`),
	)
	transformed := append(hgHex("4001000000000000"), hgXmxor(message, hash)...)
	for i := range transformed {
		transformed[i] = byte(uint32(transformed[i]) ^ uint32(seed[(^i)&3]))
	}
	check := ((uint32(querySm3[0]) & 63) << 14) | 0x18000001 | ((uint32(queryBodyTs[0]) & 63) << 8)
	r2 := hgRand.Uint32()
	packed := []byte{0x35}
	packed = append(packed, hgLe32(r2)...)
	packed = append(packed, hgLe32(uint32(check))...)
	packed = append(packed, transformed...)
	packed = append(packed, byte((r>>16)&255), byte((r>>24)&255))
	aesKey := hgHex("f1593376766ea98d34f31b057a9d5be4")
	ivBytes := hgHex("1fe109a4125283f418de9e051a969e12")
	encrypted := hgAesV3Encrypt(aesKey, int32(ts), packed, ivBytes)
	versionBytes := hgHex("03000000f7e85ffad7d7dc3bd62ac87057cf6118")
	prefix := make([]byte, 0, 20)
	for i := 0; i < 20; i += 4 {
		v := uint32(versionBytes[i]) | uint32(versionBytes[i+1])<<8 | uint32(versionBytes[i+2])<<16 | uint32(versionBytes[i+3])<<24
		prefix = append(prefix, hgLe32(v^uint32(ts))...)
	}
	final := append([]byte{}, prefix...)
	final = append(final, byte(r&255), byte((r>>8)&255), 0, 1)
	final = append(final, encrypted...)
	return base64.StdEncoding.EncodeToString(final)
}

// hgEncodeQuery 把有序的键值对编码成 URL query（与参考 Signer.encode 一致：
// 字母数字与 -_.~ 不编码，其余按 %XX 大写；空格 → %20）。
func hgEncodeQuery(pairs [][2]string) string {
	var b strings.Builder
	for idx, p := range pairs {
		if idx > 0 {
			b.WriteByte('&')
		}
		b.WriteString(hgEncodeValue(p[0]))
		b.WriteByte('=')
		b.WriteString(hgEncodeValue(p[1]))
	}
	return b.String()
}

func hgEncodeValue(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		c := s[i]
		if (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' || c == '~' {
			b.WriteByte(c)
		} else {
			b.WriteString(fmt.Sprintf("%%%02X", c))
		}
	}
	return b.String()
}

// hgDeviceQuery 返回与 VendorConstants.device 顺序一致的设备参数字典（含已注册 device_id/iid）。
func hgDeviceQuery(deviceID, installID, versionCode, versionName string) [][2]string {
	return [][2]string{
		{"iid", installID},
		{"device_id", deviceID},
		{"ac", "wifi"},
		{"channel", "update_64"},
		{"aid", "8662"},
		{"app_name", "novelread"},
		{"version_code", versionCode},
		{"version_name", versionName},
		{"device_platform", "android"},
		{"os", "android"},
		{"ssmix", "a"},
		{"device_type", "25053RT47C"},
		{"device_brand", "Redmi"},
		{"language", "zh"},
		{"os_api", "36"},
		{"os_version", "16"},
		{"manifest_version_code", versionCode},
		{"resolution", "1280*2772"},
		{"dpi", "520"},
		{"update_version_code", versionCode},
		{"host_abi", "arm64-v8a"},
		{"dragon_device_type", "phone"},
		{"pv_player", versionCode},
		{"compliance_status", "0"},
		{"need_personal_recommend", "1"},
		{"player_so_load", "1"},
		{"is_android_pad_screen", "0"},
	}
}

// hgSignRequest 对齐参考 Signer.sign：构造带 device profile 的查询串，按 branch==0 选 _rticket
// 偏移，并计算全部签名头（X-Gorgon / X-Khronos / X-Ladon / X-Argus / X-Helios / X-Medusa）。
// body 非空表示播放/写接口，User-Agent 用 VIDEO_UA；否则用 APP_UA。
func hgSignRequest(base, path string, profile [][2]string, body []byte, isVideo bool, deviceID, version string) (string, map[string]string, error) {
	now := time.Now().UnixMilli()
	ts := int(now / 1000)
	var qstr string
	var ticket int64
	found := false
	for offset := 0; offset <= 127; offset++ {
		t := now + int64(offset)
		pairs := make([][2]string, 0, len(profile)+2)
		pairs = append(pairs, profile...)
		pairs = append(pairs, [2]string{"ts", strconv.Itoa(ts)}, [2]string{"_rticket", strconv.FormatInt(t, 10)})
		qs := hgEncodeQuery(pairs)
		if hgBranch(qs, body, ts) == 0 {
			qstr = qs
			ticket = t
			found = true
			break
		}
	}
	if !found {
		return "", nil, errors.New("无法生成红果请求签名")
	}
	url := base + path + "?" + qstr
	gorRandom := int(hgRand.Uint32() % 65536)
	headers := map[string]string{
		"User-Agent":             hgUA(isVideo),
		"Accept":                 "application/json; charset=utf-8,application/x-protobuf",
		"Accept-Language":        "zh-CN,zh;q=0.9",
		"x-ss-req-ticket":        strconv.FormatInt(ticket, 10),
		"x-tt-request-tag":       "t=0;n=0",
		"sdk-version":            "2",
		"passport-sdk-version":   "50561",
		"x-xs-from-web":          "0",
		"x-khronos":             strconv.Itoa(ts),
		"x-ladon":               base64.StdEncoding.EncodeToString(hgBe32(uint32(ts))),
		"x-argus":               base64.StdEncoding.EncodeToString(hgLe32(uint32(ts))),
		"x-gorgon":              hgGorgon(qstr, body, ts, gorRandom),
		"x-helios":              hgHelios(ts),
		"x-medusa":              hgMedusa(url, body, ts, deviceID, version),
		"x-tt-dt":               "",
	}
	if body != nil {
		headers["Content-Type"] = "application/json; charset=UTF-8"
		headers["x-vc-bdturing-sdk-version"] = "3.7.2.cn"
		mh := md5.Sum(body)
		headers["x-ss-stub"] = strings.ToUpper(hex.EncodeToString(mh[:]))
	}
	return url, headers, nil
}

func hgUA(isVideo bool) string {
	if isVideo {
		return hongguoVideoUA
	}
	return hongguoAppUA
}
