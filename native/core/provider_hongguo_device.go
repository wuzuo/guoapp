package core

import (
	"bytes"
	"compress/gzip"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/md5"
	"crypto/rand"
	"crypto/sha512"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"
)

const hongguoRegisterEndpoint = "https://log5-applog-lf.fqnovel.com/service/2/device_register/?tt_data=a&cronet_version=8d40f833_2026-03-03&ttnet_version=4.2.243.31-douyin&use_store_region_cookie=1"

const hongguoRegisterSaltHex = "4dd4c2e6b83162090e52b3c7a6733ba41cb2462b829ab58a196b39db57177524f49baf7f08e8d68d26a72e37c1a95a2f1f05a51892aef2949732b62a38aadd58"

const hongguoRegisterRetryInterval = 10 * time.Minute

var hongguoRegisterMagic = []byte{0x74, 0x63, 0x05, 0x10, 0x00, 0x00}

type hongguoRegistration struct {
	DeviceID    string
	InstallID   string
	DeviceToken string
	Cookies     map[string]string
}

func newHongguoUUID() string {
	var raw [16]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return strconv.FormatInt(time.Now().UnixNano(), 10)
	}
	raw[6] = raw[6]&0x0f | 0x40
	raw[8] = raw[8]&0x3f | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", raw[0:4], raw[4:6], raw[6:8], raw[8:10], raw[10:16])
}

func newHongguoShortID(length int) string {
	return strings.ReplaceAll(newHongguoUUID(), "-", "")[:length]
}

func hongguoTTAESMaterial(random []byte) ([]byte, []byte, error) {
	salt, err := hex.DecodeString(hongguoRegisterSaltHex)
	if err != nil {
		return nil, nil, err
	}
	inner := sha512.Sum512(random)
	outer := sha512.Sum512(append(inner[:], salt...))
	return outer[:16], outer[16:32], nil
}

func hongguoTTEncrypt(payload []byte) ([]byte, error) {
	random := make([]byte, 32)
	if _, err := rand.Read(random); err != nil {
		return nil, err
	}
	key, iv, err := hongguoTTAESMaterial(random)
	if err != nil {
		return nil, err
	}
	sum := sha512.Sum512(payload)
	body := append(sum[:], payload...)
	padding := 16 - len(body)%16
	padded := append(body, bytes.Repeat([]byte{byte(padding)}, padding)...)
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	encrypted := make([]byte, len(padded))
	cipher.NewCBCEncrypter(block, iv).CryptBlocks(encrypted, padded)
	result := make([]byte, 0, len(hongguoRegisterMagic)+len(random)+len(encrypted))
	result = append(result, hongguoRegisterMagic...)
	result = append(result, random...)
	return append(result, encrypted...), nil
}

func hongguoRegisterPayload(now time.Time) ([]byte, error) {
	millis := now.UnixMilli()
	header := map[string]any{
		"display_name":             "红果免费短剧",
		"update_version_code":      73932,
		"manifest_version_code":    73932,
		"app_version_minor":        "7.3.9.32",
		"aid":                      8662,
		"channel":                  "69310258a",
		"package":                  "com.phoenix.read",
		"app_version":              "7.3.9.32",
		"version_code":             73932,
		"sdk_version":              "3.7.0-rc.34-fanqie-xiaoshuo",
		"sdk_target_version":       29,
		"git_hash":                 "3a88f4e",
		"os":                       "Android",
		"os_version":               "16",
		"os_api":                   36,
		"device_model":             "25053RT47C",
		"device_brand":             "Redmi",
		"device_manufacturer":      "Xiaomi",
		"cpu_abi":                  "arm64-v8a",
		"release_build":            "b5e187f",
		"density_dpi":              520,
		"display_density":          "mdpi",
		"resolution":               "1280x2772",
		"language":                 "zh",
		"timezone":                 8,
		"access":                   "wifi",
		"not_request_sender":       0,
		"carrier":                  "CHINA MOBILE",
		"mcc_mnc":                  "46000",
		"rom":                      "eng.root.20231116.160340",
		"rom_version":              "W528JS release-keys",
		"cdid":                     newHongguoUUID(),
		"sig_hash":                 "56a962410c494bbaf0b58dba20cae56f",
		"openudid":                 newHongguoShortID(16),
		"clientudid":               newHongguoUUID(),
		"ipv6_list":                []any{},
		"region":                   "CN",
		"tz_name":                  "Asia/Shanghai",
		"tz_offset":                28800,
		"sim_region":               "cn",
		"sim_serial_number":        []any{},
		"oaid_may_support":         false,
		"req_id":                   newHongguoUUID(),
		"device_platform":          "android",
		"custom":                   map[string]any{"account_region_src": "fallback", "host_bit": 64, "account_region": "cn", "dragon_device_type": "pad"},
		"pre_installed_channel":    "",
		"apk_first_install_time":   millis,
		"is_system_app":            0,
		"sdk_flavor":               "china",
		"guest_mode":               0,
	}
	document := map[string]any{"magic_tag": "ss_app_log", "header": header, "_gen_time": millis}
	raw, err := json.Marshal(document)
	if err != nil {
		return nil, err
	}
	var compressed bytes.Buffer
	writer := gzip.NewWriter(&compressed)
	if _, err := writer.Write(raw); err != nil {
		return nil, err
	}
	if err := writer.Close(); err != nil {
		return nil, err
	}
	return compressed.Bytes(), nil
}

type hongguoCookieKey struct{}

func (downloader *Downloader) ensureHongguoDevice(ctx context.Context) error {
	client := downloader.hongguoClient()
	client.mu.Lock()
	if client.state.Registered && hongguoNumericID.MatchString(client.state.DeviceID) && hongguoNumericID.MatchString(client.state.InstallID) {
		client.mu.Unlock()
		return nil
	}
	if client.registering {
		done := client.registerDone
		client.mu.Unlock()
		select {
		case <-done:
			client.mu.Lock()
			registered, failure := client.state.Registered, client.registerErr
			client.mu.Unlock()
			if registered || failure == nil {
				return nil
			}
			return failure
		case <-ctx.Done():
			return ctx.Err()
		}
	}
	if failure := client.registerErr; failure != nil && !client.registerAt.IsZero() && time.Since(client.registerAt) < hongguoRegisterRetryInterval {
		client.mu.Unlock()
		return failure
	}
	client.registering = true
	client.registerDone = make(chan struct{})
	client.registerAt = time.Now()
	client.registerErr = nil
	client.mu.Unlock()

	registration, err := downloader.registerHongguoDevice(ctx)

	client.mu.Lock()
	client.registering = false
	close(client.registerDone)
	if err != nil {
		if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
			client.registerAt = time.Time{}
		} else {
			client.registerErr = err
		}
	} else {
		client.state.Registered = true
		client.state.DeviceID = registration.DeviceID
		client.state.InstallID = registration.InstallID
		client.state.DeviceToken = registration.DeviceToken
		client.state.Cookies = registration.Cookies
		client.state.Feeds = map[string]hongguoCatalogCursor{}
		client.registerErr = nil
	}
	client.mu.Unlock()
	return err
}

func (downloader *Downloader) registerHongguoDevice(ctx context.Context) (hongguoRegistration, error) {
	payload, err := hongguoRegisterPayload(time.Now())
	if err != nil {
		return hongguoRegistration{}, err
	}
	body, err := hongguoTTEncrypt(payload)
	if err != nil {
		return hongguoRegistration{}, err
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, hongguoRegisterEndpoint, bytes.NewReader(body))
	if err != nil {
		return hongguoRegistration{}, err
	}
	now := time.Now()
	sum := md5.Sum(body)
	request.Header.Set("User-Agent", hongguoAppUA)
	request.Header.Set("Content-Type", "application/octet-stream;tt-data=a")
	request.Header.Set("log-encode-type", "gzip")
	request.Header.Set("x-ss-dp", "8662")
	request.Header.Set("x-ss-req-ticket", strconv.FormatInt(now.UnixMilli(), 10))
	request.Header.Set("x-vc-bdturing-sdk-version", "4.0.3.cn")
	request.Header.Set("lc", "101")
	request.Header.Set("sdk-version", "2")
	request.Header.Set("passport-sdk-version", "5051452")
	request.Header.Set("x-neptune", "-8|50:51:59:30:40:47:49:39")
	request.Header.Set("x-ss-stub", strings.ToUpper(hex.EncodeToString(sum[:])))
	response, err := downloader.doPreparedCatalogRequest(request, 15*time.Second, nil)
	if err != nil {
		return hongguoRegistration{}, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return hongguoRegistration{}, fmt.Errorf("设备注册 HTTP %d", response.StatusCode)
	}
	content, err := io.ReadAll(io.LimitReader(response.Body, 1<<20))
	if err != nil || len(content) == 0 {
		return hongguoRegistration{}, errors.New("设备注册未返回有效数据")
	}
	return parseHongguoRegistration(content, response.Cookies())
}

func parseHongguoRegistration(content []byte, cookies []*http.Cookie) (hongguoRegistration, error) {
	decoder := json.NewDecoder(bytes.NewReader(content))
	decoder.UseNumber()
	var result map[string]any
	if err := decoder.Decode(&result); err != nil || result == nil {
		return hongguoRegistration{}, errors.New("设备注册返回格式异常")
	}
	identity := func(prefix string) string {
		for _, key := range []string{prefix + "_str", prefix} {
			value := strings.TrimSpace(mapString(result, key))
			if value != "" && value != "0" {
				return value
			}
		}
		return ""
	}
	deviceID, installID := identity("device_id"), identity("install_id")
	if !hongguoNumericID.MatchString(deviceID) || !hongguoNumericID.MatchString(installID) {
		return hongguoRegistration{}, errors.New("设备注册被服务端拒绝")
	}
	registration := hongguoRegistration{DeviceID: deviceID, InstallID: installID, Cookies: map[string]string{}}
	registration.DeviceToken = mapString(result, "device_token")
	for _, cookie := range cookies {
		if cookie.Name == "" || cookie.Value == "" {
			continue
		}
		registration.Cookies[cookie.Name] = cookie.Value
	}
	return registration, nil
}

func hongguoCookieHeader(cookies map[string]string) string {
	if len(cookies) == 0 {
		return ""
	}
	names := make([]string, 0, len(cookies))
	for name := range cookies {
		names = append(names, name)
	}
	sort.Strings(names)
	pairs := make([]string, 0, len(names))
	for _, name := range names {
		pairs = append(pairs, name+"="+cookies[name])
	}
	return strings.Join(pairs, "; ")
}
