package core

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"
)

const hongguoAppBaseURL = "https://api5-normal-sinfonlineb.fqnovel.com"

// 红果 App 请求的 User-Agent 按是否带请求体区分（对齐参考实现 hgtv-tv）：
// 不带 body 的通用 App 接口（搜索/详情/目录/设备注册）用播放器 App 版 72232；
// 带 body 的播放取流接口用播放内核版 71332，平台对该路径的版本更敏感。
const hongguoAppUA = "com.phoenix.read/72232 (Linux; U; Android 16; zh_CN; 25053RT47C; Build/BP2A.250605.031.A3)"

const hongguoVideoUA = "com.phoenix.read/71332 (Linux; U; Android 16; zh_CN; 25053RT47C; Build/BP2A.250605.031.A3; Cronet/TTNetVersion:04657795 2026-01-23 QuicVersion:c67e9834 2025-09-08)"

// hongguoAppVersion 仅用于覆盖 App 接口的客户端版本号：
// 搜索与弹幕用 App 版本（7.2.2.32 / 72232），播放与详情用播放器版本（7.3.5.32 / 73532）。
// 混用会被平台按旧客户端处理，因此搜索在 ctx 里带上 App 版本。
// 搜索/弹幕与默认取流统一用 App 版本（7.1.3.32 / 72232），避免被平台按旧客户端处理。
type hongguoAppVersion struct{ code, name string }

type hongguoAppVersionKey struct{}

type hongguoCatalogCursor struct {
	Offset        int       `json:"offset"`
	SessionID     string    `json:"sessionId,omitempty"`
	LastID        string    `json:"lastId,omitempty"`
	PageSignature string    `json:"pageSignature,omitempty"`
	Initialized   bool      `json:"initialized"`
	Exhausted     bool      `json:"exhausted"`
	UpdatedAt     time.Time `json:"updatedAt"`
}

type hongguoCatalogState struct {
	Version     int                             `json:"version"`
	DeviceID    string                          `json:"deviceId"`
	InstallID   string                          `json:"installId"`
	Registered  bool                            `json:"registered,omitempty"`
	DeviceToken string                          `json:"deviceToken,omitempty"`
	Cookies     map[string]string               `json:"cookies,omitempty"`
	Feeds       map[string]hongguoCatalogCursor `json:"feeds"`
}

type hongguoAppClient struct {
	mu             sync.Mutex
	catalogMu      sync.Mutex
	baseURL        string
	state          hongguoCatalogState
	details        map[string]hongguoDetailEntry
	pending        map[string]*hongguoDetailCall
	searches       map[string]hongguoSearchEntry
	searchPending  map[string]*hongguoSearchCall
	suggestions    map[string]hongguoSuggestionEntry
	suggestPending map[string]*hongguoSuggestionCall
	danmaku        map[string]hongguoDanmakuCacheEntry
	danmakuPending map[string]*hongguoDanmakuCall

	registering  bool
	registerDone chan struct{}
	registerAt   time.Time
	registerErr  error
}

func (downloader *Downloader) hongguoClient() *hongguoAppClient {
	downloader.hongguoOnce.Do(func() {
		downloader.hongguo = &hongguoAppClient{
			baseURL: hongguoAppBaseURL,
			state:   hongguoCatalogState{Version: 1, DeviceID: newHongguoDeviceID(), InstallID: newHongguoDeviceID(), Feeds: map[string]hongguoCatalogCursor{}},
			details: map[string]hongguoDetailEntry{}, pending: map[string]*hongguoDetailCall{},
			searches: map[string]hongguoSearchEntry{}, searchPending: map[string]*hongguoSearchCall{},
			suggestions: map[string]hongguoSuggestionEntry{}, suggestPending: map[string]*hongguoSuggestionCall{},
		}
	})
	return downloader.hongguo
}

func cloneHongguoCatalogState(state *hongguoCatalogState) *hongguoCatalogState {
	if state == nil {
		return nil
	}
	cloned := *state
	cloned.Feeds = make(map[string]hongguoCatalogCursor, len(state.Feeds))
	for name, cursor := range state.Feeds {
		cloned.Feeds[name] = cursor
	}
	if state.Cookies != nil {
		cloned.Cookies = make(map[string]string, len(state.Cookies))
		for name, value := range state.Cookies {
			cloned.Cookies[name] = value
		}
	}
	return &cloned
}

func (downloader *Downloader) restoreHongguoCatalog(state *hongguoCatalogState) {
	if state == nil || state.Version != 1 || !hongguoNumericID.MatchString(state.DeviceID) || !hongguoNumericID.MatchString(state.InstallID) {
		return
	}
	cloned := cloneHongguoCatalogState(state)
	if !cloned.Registered || !hongguoNumericID.MatchString(cloned.DeviceID) || !hongguoNumericID.MatchString(cloned.InstallID) {
		cloned.Registered = false
		cloned.DeviceToken = ""
		cloned.Cookies = nil
	}
	if len(cloned.Cookies) > 16 {
		cloned.Cookies = nil
	}
	for name, value := range cloned.Cookies {
		if len(name) > 64 || len(value) > 512 {
			delete(cloned.Cookies, name)
		}
	}
	for name, cursor := range cloned.Feeds {
		known := false
		for _, genre := range hongguoAppGenres {
			known = known || name == genre.key || name == "category:"+genre.key
		}
		if !known || !cursor.Initialized || cursor.Offset < 0 || cursor.Offset > 1_000_000 || len(cursor.SessionID) > 4096 || len(cursor.LastID) > 256 || len(cursor.PageSignature) > 64 {
			delete(cloned.Feeds, name)
		}
	}
	client := downloader.hongguoClient()
	client.catalogMu.Lock()
	defer client.catalogMu.Unlock()
	client.mu.Lock()
	defer client.mu.Unlock()
	if len(client.state.Feeds) == 0 {
		client.state = *cloned
	}
}

func (downloader *Downloader) hongguoCatalogSnapshot() *hongguoCatalogState {
	client := downloader.hongguoClient()
	client.mu.Lock()
	defer client.mu.Unlock()
	return cloneHongguoCatalogState(&client.state)
}

func hongguoCatalogInitialized(state *hongguoCatalogState) bool {
	if state != nil && state.Version == 1 {
		for _, cursor := range state.Feeds {
			if cursor.Initialized {
				return true
			}
		}
	}
	return false
}

func hongguoCatalogHasMore(state *hongguoCatalogState) bool {
	for _, genre := range hongguoAppGenres {
		if state == nil || !state.Feeds[genre.key].Exhausted {
			return true
		}
	}
	return false
}

func (downloader *Downloader) hongguoAppRequest(ctx context.Context, method, path string, extra url.Values, payload any) (map[string]any, error) {
	_ = downloader.ensureHongguoDevice(ctx)
	client := downloader.hongguoClient()
	client.mu.Lock()
	base, deviceID, installID := client.baseURL, client.state.DeviceID, client.state.InstallID
	registered, cookies := client.state.Registered, client.state.Cookies
	client.mu.Unlock()
	cookie := ""
	if withCookie, _ := ctx.Value(hongguoCookieKey{}).(bool); withCookie && registered {
		cookie = hongguoCookieHeader(cookies)
	}
	query := url.Values{
		"aid": {"8662"}, "app_name": {"novelread"}, "version_code": {"72232"}, "version_name": {"7.1.3.32"},
		"manifest_version_code": {"72232"}, "update_version_code": {"72232"}, "channel": {"update_64"},
		"device_platform": {"android"}, "os": {"android"}, "ssmix": {"a"}, "device_type": {"25053RT47C"},
		"device_brand": {"Redmi"}, "language": {"zh"}, "os_api": {"36"}, "os_version": {"16"},
		"resolution": {"1280*2772"}, "dpi": {"520"}, "ac": {"wifi"}, "device_id": {deviceID}, "iid": {installID},
	}
	for key, values := range extra {
		query[key] = append([]string(nil), values...)
	}
	if version, ok := ctx.Value(hongguoAppVersionKey{}).(hongguoAppVersion); ok && version.code != "" {
		query.Set("version_code", version.code)
		query.Set("manifest_version_code", version.code)
		query.Set("update_version_code", version.code)
		query.Set("version_name", version.name)
	}
	var body []byte
	var err error
	if payload != nil {
		body, err = json.Marshal(payload)
		if err != nil {
			return nil, err
		}
	}
	attempts := downloader.cfg.Retries
	if attempts < 1 {
		attempts = 1
	}
	if attempts > 3 {
		attempts = 3
	}
	var lastErr error
	for attempt := 0; attempt < attempts; attempt++ {
		if attempt > 0 {
			select {
			case <-time.After(time.Duration(attempt) * time.Second):
			case <-ctx.Done():
				return nil, ctx.Err()
			}
		}
		request, err := http.NewRequestWithContext(ctx, method, strings.TrimRight(base, "/")+path, bytes.NewReader(body))
		if err != nil {
			return nil, err
		}
			// 播放取流接口带请求体，用播放内核版 UA；其余 App 接口用通用 App 版 UA。
			if payload != nil {
				request.Header.Set("User-Agent", hongguoVideoUA)
			} else {
				request.Header.Set("User-Agent", hongguoAppUA)
			}
			request.Header.Set("Accept", "application/json")
		request.Header.Set("X-XS-From-Web", "0")
		request.Header.Set("Sdk-Version", "2")
		comment, _ := ctx.Value(hongguoCommentKey{}).(bool)
		var commentNonce hongguoCommentNonce
		if comment {
			commentNonce, err = newHongguoCommentNonce()
			if err != nil {
				return nil, errors.New("无法准备红果文字请求")
			}
			request.Header.Set("Comment-Source", "601")
			request.Header.Set("Server-Channel", "1000")
		}
		if payload != nil {
			request.Header.Set("Content-Type", "application/json; charset=utf-8")
		}
		response, err := downloader.doPreparedCatalogRequest(request, 20*time.Second, func(prepared *http.Request) {
			now := time.Now()
			query.Set("_rticket", strconv.FormatInt(now.UnixMilli(), 10))
			prepared.URL.RawQuery = query.Encode()
			if comment {
				signHongguoCommentRequest(prepared, commentNonce, now)
			} else {
				signHongguoRequest(prepared, body, now)
			}
			if cookie != "" {
				prepared.Header.Set("Cookie", cookie)
			}
		})
		if err != nil {
			lastErr = err
			var backoff *requestBackoff
			if errors.As(err, &backoff) || ctx.Err() != nil {
				return nil, err
			}
			continue
		}
		content, readErr := io.ReadAll(io.LimitReader(response.Body, providerMaxBodyBytes+1))
		response.Body.Close()
		if readErr != nil {
			lastErr = readErr
			continue
		}
		if response.StatusCode != http.StatusOK {
			lastErr = fmt.Errorf("红果 App 接口 HTTP %d", response.StatusCode)
			if response.StatusCode >= 400 && response.StatusCode < 500 {
				return nil, lastErr
			}
			continue
		}
		if len(content) == 0 || len(content) > providerMaxBodyBytes {
			return nil, errors.New("红果 App 接口未返回有效数据")
		}
		var result map[string]any
		decoder := json.NewDecoder(bytes.NewReader(content))
		decoder.UseNumber()
		if err := decoder.Decode(&result); err != nil || result == nil {
			return nil, errors.New("红果 App 接口返回格式异常")
		}
		code := firstNonEmpty(mapString(result, "code", "Code", "status_code"), mapString(nestedMap(result, "BaseResp"), "StatusCode"))
		if code != "" && code != "0" {
			return nil, fmt.Errorf("红果 App 接口暂不可用（%s）", truncate(code, 20))
		}
		return result, nil
	}
	return nil, lastErr
}
