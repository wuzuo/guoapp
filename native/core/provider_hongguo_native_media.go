package core

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"
)

const hongguoPlaybackBlankRetries = 1

// hongguoPlaybackBizParam 与参考实现 hgtv-tv 的取流 biz_param 对齐。
func hongguoPlaybackBizParam() map[string]any {
	return map[string]any{
		"detail_page_version":       0,
		"device_level":              3,
		"disable_digg_stat":         false,
		"need_all_video_definition": true,
		"need_mp4_align":            false,
		"use_os_player":             false,
		"use_server_dns":            false,
		"video_platform":            1024,
	}
}

// resolveHongguoAppMedia 按候选端点顺序取播放模型，取第一个能拿到 video_model 的。
// 平台 2026-10 两次改版后：带场景段的 multi_video_model 一律 200+0 字节，旧 multi_video_model/v1
// 回 110001；当前可用的是 video_model/v1（video_id 单值）。网关偶发 200+0 字节（匿名/风控），
// 因此空响应原地重试几次再换下一条，避免把唯一能用的路径跳过去。
func (downloader *Downloader) resolveHongguoAppMedia(ctx context.Context, videoID string) (providerMedia, error) {
	if !hongguoNumericID.MatchString(videoID) {
		return providerMedia{}, errors.New("红果视频 ID 无效")
	}
	ctx = context.WithValue(ctx, hongguoCookieKey{}, true)
	biz := hongguoPlaybackBizParam()
	videoModelBody := map[string]any{"video_id": videoID, "biz_param": biz}
	mixedBody := map[string]any{"biz_param": biz, "mixed_video_id_map": map[string]any{"1004": []string{videoID}}}
	candidates := []struct {
		path string
		body any
	}{
		{"/novel/player/video_model/v1/", videoModelBody},
		{"/novel/player/multi_video_model/preload/v1/", mixedBody},
		{"/novel/player/multi_video_model/default/v1/", mixedBody},
		{"/novel/player/multi_video_model/detail/v1/", mixedBody},
		{"/novel/player/multi_video_model/v1/", mixedBody},
	}
	var lastErr error
	for _, candidate := range candidates {
		var result map[string]any
		var err error
		// 空响应（网关挡请求）原地重试，避免把唯一能用的路径跳过。
		for attempt := 0; attempt < hongguoPlaybackBlankRetries; attempt++ {
			result, err = downloader.hongguoAppRequest(ctx, http.MethodPost, candidate.path, nil, candidate.body)
			if err == nil {
				break
			}
			if !isHongguoBlankResponseError(err) {
				break
			}
			if attempt < hongguoPlaybackBlankRetries-1 {
				select {
				case <-time.After(time.Duration(attempt+1) * 200 * time.Millisecond):
				case <-ctx.Done():
					return providerMedia{}, ctx.Err()
				}
			}
		}
		if err != nil {
			lastErr = err
			continue
		}
		model := hongguoExtractVideoModel(result, videoID)
		if len(model) == 0 {
			lastErr = errors.New("红果 App 未返回该集播放信息")
			continue
		}
		return selectHongguoAppMedia(model)
	}
	if lastErr == nil {
		lastErr = errors.New("红果 App 未返回该集播放信息")
	}
	return providerMedia{}, lastErr
}

// hongguoExtractVideoModel 从播放接口响应里取出 video_model：
// 新路由挂在 data.video_model，带场景段/旧路径挂在 data[<vid>].video_model；
// video_model 可能是对象或字符串化的 JSON，两种都处理（对齐参考实现 videoModelOf）。
func hongguoExtractVideoModel(result map[string]any, videoID string) map[string]any {
	data, _ := result["data"].(map[string]any)
	if data == nil {
		return nil
	}
	if model := hongguoVideoModelValue(data["video_model"]); model != nil {
		return model
	}
	if entry, ok := data[videoID].(map[string]any); ok {
		if model := hongguoVideoModelValue(entry["video_model"]); model != nil {
			return model
		}
	}
	for _, value := range data {
		if entry, ok := value.(map[string]any); ok {
			if model := hongguoVideoModelValue(entry["video_model"]); model != nil {
				return model
			}
		}
	}
	return nil
}

func hongguoVideoModelValue(value any) map[string]any {
	switch v := value.(type) {
	case map[string]any:
		return v
	case string:
		if v == "" || v == "null" {
			return nil
		}
		decoder := json.NewDecoder(strings.NewReader(v))
		decoder.UseNumber()
		var decoded map[string]any
		if err := decoder.Decode(&decoded); err == nil {
			return decoded
		}
	}
	return nil
}

// isHongguoBlankResponseError 判断是否为「网关挡请求返回空体」类错误，
// 这类错误需要原地重试，而不是立即换下一条候选路径。
func isHongguoBlankResponseError(err error) bool {
	if err == nil {
		return false
	}
	return errors.Is(err, errHongguoBlankResponse) || strings.Contains(err.Error(), "未返回有效数据")
}

func selectHongguoAppMedia(model map[string]any) (providerMedia, error) {
	variants := anyList(model["video_list"])
	if rows, ok := model["video_list"].(map[string]any); ok && len(variants) == 0 {
		keys := make([]string, 0, len(rows))
		for key := range rows {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		for _, key := range keys {
			variants = append(variants, rows[key])
		}
	}
	duration, _ := strconv.ParseFloat(mapString(model, "video_duration", "duration"), 64)
	var keyErr error
	type scoredMedia struct {
		media providerMedia
		score int
	}
	var choices []scoredMedia
	for _, row := range variants {
		variant, _ := row.(map[string]any)
		meta := nestedMap(variant, "video_meta")
		codec := strings.ToLower(mapString(meta, "codec_type"))
		if codec == "bytevc2" || strings.Contains(strings.ToLower(mapString(variant, "gear_des_key")), "bytevc2") {
			continue
		}
		addresses := hongguoMediaAddresses(variant)
		if len(addresses) == 0 {
			continue
		}
		media := providerMedia{Referer: "https://novel.snssdk.com/", Duration: time.Duration(duration * float64(time.Second))}
		encryption := nestedMap(variant, "encrypt_info")
		spade := mapString(encryption, "spade_a")
		if spade != "" || encryption["encrypt"] == true || mapString(encryption, "encryption_method") == "cenc-aes-ctr" {
			var err error
			media.CENCKey, err = hongguoContentKey(spade)
			if err != nil {
				keyErr = err
				continue
			}
		}
		width, _ := strconv.Atoi(mapString(meta, "vwidth"))
		height, _ := strconv.Atoi(mapString(meta, "vheight"))
		if definition, err := strconv.Atoi(hongguoQualityNumber.FindString(mapString(meta, "definition"))); err == nil && definition > 0 {
			height = definition
		} else if width > 0 && (height == 0 || width < height) {
			height = width
		}
		media.Quality = height
		media.Width = width
		media.Height = height
		media.Codec = codec
		quality := height * 10
		if codec == "h264" || codec == "avc1" {
			quality++
		}
		for _, address := range addresses {
			media.URL = address
			choices = append(choices, scoredMedia{media: media, score: quality})
		}
	}
	if len(choices) > 0 {
		sort.SliceStable(choices, func(i, j int) bool { return choices[i].score > choices[j].score })
		selected := choices[0].media
		for _, choice := range choices {
			selected.Variants = append(selected.Variants, choice.media)
		}
		return selected, nil
	}
	if keyErr != nil {
		return providerMedia{}, fmt.Errorf("红果 App 媒体密钥不可用: %w", keyErr)
	}
	return providerMedia{}, errors.New("红果 App 未返回兼容的媒体，已跳过不支持的编码")
}

func hongguoMediaAddresses(info map[string]any) []string {
	var addresses []string
	seen := map[string]bool{}
	var add func(any)
	add = func(value any) {
		switch value := value.(type) {
		case string:
			address := strings.TrimSpace(value)
			if len(address) > 8192 {
				return
			}
			if !isProviderHTTPMediaURL(address) {
				decoded, err := decodeHongguoBase64(address)
				if err != nil {
					return
				}
				address = strings.TrimSpace(string(decoded))
			}
			if isProviderHTTPMediaURL(address) && !seen[address] {
				seen[address] = true
				addresses = append(addresses, address)
			}
		case []any:
			for _, item := range value {
				add(item)
			}
		}
	}
	for _, key := range []string{"main_url", "backup_url", "backup_url_1", "backup_url_2", "backup_urls", "url_list"} {
		add(info[key])
	}
	return addresses
}
