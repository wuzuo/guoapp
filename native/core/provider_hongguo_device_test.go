package core

import (
	"bytes"
	"compress/gzip"
	"crypto/aes"
	"crypto/cipher"
	"crypto/sha512"
	"encoding/json"
	"io"
	"net/http"
	"testing"
	"time"
)

func hongguoRegisterPlain(t *testing.T, body []byte) []byte {
	t.Helper()
	if !bytes.HasPrefix(body, hongguoRegisterMagic) {
		t.Fatalf("注册请求体缺少 ttEncrypt 前缀：%x", body[:min(len(body), 8)])
	}
	rest := body[len(hongguoRegisterMagic):]
	if len(rest) < 48 || (len(rest)-32)%16 != 0 {
		t.Fatalf("注册请求体长度异常：%d", len(body))
	}
	random := rest[:32]
	key, iv, err := hongguoTTAESMaterial(random)
	if err != nil {
		t.Fatalf("派生密钥失败：%v", err)
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		t.Fatalf("创建解密器失败：%v", err)
	}
	plain := make([]byte, len(rest)-32)
	cipher.NewCBCDecrypter(block, iv).CryptBlocks(plain, rest[32:])
	padding := int(plain[len(plain)-1])
	if padding < 1 || padding > 16 || padding > len(plain) {
		t.Fatalf("PKCS7 填充异常：%d", padding)
	}
	plain = plain[:len(plain)-padding]
	if len(plain) <= sha512.Size {
		t.Fatalf("明文长度异常：%d", len(plain))
	}
	digest := sha512.Sum512(plain[sha512.Size:])
	if !bytes.Equal(digest[:], plain[:sha512.Size]) {
		t.Fatal("明文摘要与 SHA-512 不符")
	}
	return plain[sha512.Size:]
}

func TestHongguoRegisterPayloadMatchesProtocol(t *testing.T) {
	payload, err := hongguoRegisterPayload(time.UnixMilli(1_760_000_000_000))
	if err != nil {
		t.Fatalf("生成注册载荷失败：%v", err)
	}
	reader, err := gzip.NewReader(bytes.NewReader(payload))
	if err != nil {
		t.Fatalf("注册载荷不是 gzip：%v", err)
	}
	raw, err := io.ReadAll(reader)
	if err != nil {
		t.Fatalf("解压注册载荷失败：%v", err)
	}
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.UseNumber()
	var document map[string]any
	if err := decoder.Decode(&document); err != nil {
		t.Fatalf("注册载荷不是 JSON：%v", err)
	}
	if mapString(document, "magic_tag") != "ss_app_log" {
		t.Fatalf("magic_tag 异常：%v", document["magic_tag"])
	}
	if mapString(document, "_gen_time") != "1760000000000" {
		t.Fatalf("_gen_time 异常：%v", document["_gen_time"])
	}
	header := nestedMap(document, "header")
	if mapString(header, "aid") != "8662" || mapString(header, "device_platform") != "android" {
		t.Fatalf("注册头字段异常：%v", header)
	}
	if _, ok := header["os_version"].(string); !ok {
		t.Fatalf("os_version 必须是字符串：%T", header["os_version"])
	}
	if mapString(header, "package") != "com.phoenix.read" {
		t.Fatalf("包名异常：%v", header["package"])
	}
	if mapString(header, "sig_hash") == "" {
		t.Fatal("缺少 sig_hash")
	}
	if _, exists := header["device_id"]; exists {
		t.Fatal("首次注册不应携带 device_id")
	}
}

func TestHongguoTTEncryptRoundTrip(t *testing.T) {
	payload := []byte("red fruit device register payload")
	body, err := hongguoTTEncrypt(payload)
	if err != nil {
		t.Fatalf("加密失败：%v", err)
	}
	if got := hongguoRegisterPlain(t, body); !bytes.Equal(got, payload) {
		t.Fatalf("解密结果不一致：%q", got)
	}
	second, err := hongguoTTEncrypt(payload)
	if err != nil {
		t.Fatalf("加密失败：%v", err)
	}
	if bytes.Equal(body, second) {
		t.Fatal("两次加密使用了相同的随机数")
	}
}

func TestParseHongguoRegistration(t *testing.T) {
	registration, err := parseHongguoRegistration([]byte(`{"device_id":7111111111111111111,"install_id":"7222222222222222222","device_token":"token","new_user":1}`), []*http.Cookie{
		{Name: "install_id", Value: "7222222222222222222"},
		{Name: "ttreq", Value: "1.abc"},
		{Name: "empty", Value: ""},
	})
	if err != nil {
		t.Fatalf("解析注册响应失败：%v", err)
	}
	if registration.DeviceID != "7111111111111111111" || registration.InstallID != "7222222222222222222" {
		t.Fatalf("设备身份异常：%+v", registration)
	}
	if registration.DeviceToken != "token" {
		t.Fatalf("device_token 异常：%q", registration.DeviceToken)
	}
	if registration.Cookies["ttreq"] != "1.abc" || len(registration.Cookies) != 2 {
		t.Fatalf("注册 Cookie 异常：%v", registration.Cookies)
	}
	if header := hongguoCookieHeader(registration.Cookies); header != "install_id=7222222222222222222; ttreq=1.abc" {
		t.Fatalf("Cookie 头异常：%q", header)
	}
}

func TestParseHongguoRegistrationRejectsRejectedDevice(t *testing.T) {
	for _, body := range []string{
		`{"device_id":0,"install_id":0}`,
		`{"device_id":"0","install_id":"0"}`,
		`{}`,
		`not json`,
		`{"device_id":"abc","install_id":"723"}`,
	} {
		if _, err := parseHongguoRegistration([]byte(body), nil); err == nil {
			t.Fatalf("应当拒绝注册响应：%s", body)
		}
	}
	if hongguoCookieHeader(nil) != "" {
		t.Fatal("空 Cookie 应生成空头")
	}
}
