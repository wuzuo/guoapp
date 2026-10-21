package core

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// 红果 App 搜索接口按 tab_type 分 tab；短剧 / 真人剧为 11，漫剧为 19，AI 剧在 App 端没有对应 tab。
const (
	honghuoSearchTabShort = 11
	honghuoSearchTabComic = 19
	honghuoSearchCount    = 20
	honghuoSearchMaxPages = 5
)

// hongguoSearchCursor 是某一 tab 翻页所需的游标，按（tab、关键词、页码）缓存。
type hongguoSearchCursor struct {
	searchID string
	passback string
	offset   int
}

// hongguoAppSearchTab 调用 GET /reading/bookapi/search/tab/v 拉取某个 tab 的某一页。
// 返回该页的剧集、是否还有更多、以及下一页游标。空响应体（设备未注册）或 100103 间歇性错误
// 都会返回错误，由上层退回官网搜索 + 片库目录。
func (downloader *Downloader) hongguoAppSearchTab(ctx context.Context, keyword string, tabType, page int, cursor *hongguoSearchCursor) ([]Drama, bool, *hongguoSearchCursor, error) {
	extra := url.Values{
		"query":                 {keyword},
		"count":                 {strconv.Itoa(honghuoSearchCount)},
		"offset":                {strconv.Itoa((page - 1) * honghuoSearchCount)},
		"tab_type":              {strconv.Itoa(tabType)},
		"bookshelf_search_plan": {"4"},
		"use_correct":           {"true"},
		"user_is_login":         {"0"},
	}
	if cursor != nil {
		if cursor.searchID != "" {
			extra.Set("search_id", cursor.searchID)
		}
		if cursor.passback != "" {
			extra.Set("passback", cursor.passback)
		}
		if cursor.offset >= 0 {
			extra.Set("offset", strconv.Itoa(cursor.offset))
		}
	}
	searchCtx := context.WithValue(ctx, hongguoCookieKey{}, true)
	// 搜索与弹幕用 App 版本（7.2.2.32 / 72232），与播放器版本区分，避免被按旧客户端处理。
	searchCtx = context.WithValue(searchCtx, hongguoAppVersionKey{}, hongguoAppVersion{"72232", "7.2.2.32"})
	var result map[string]any
	var err error
	// 100103 是间歇性错误（同一设备约一半概率），短间隔重试几次即可。
	for attempt := 0; attempt <= 2; attempt++ {
		if attempt > 0 {
			select {
			case <-time.After(120 * time.Millisecond):
			case <-ctx.Done():
				return nil, false, nil, ctx.Err()
			}
		}
		result, err = downloader.hongguoAppRequest(searchCtx, http.MethodGet, "/reading/bookapi/search/tab/v", extra, nil)
		if err != nil {
			return nil, false, nil, err
		}
		if code := mapString(result, "code", "Code"); code == "100103" {
			continue
		}
		break
	}
	if err != nil {
		return nil, false, nil, err
	}
	if code := mapString(result, "code", "Code"); code != "" && code != "0" {
		return nil, false, nil, fmt.Errorf("红果搜索接口暂不可用（%s）", code)
	}
	data := nestedMap(result, "data")
	tabs := anyList(data["search_tabs"])
	if len(tabs) == 0 {
		tabs = anyList(result["search_tabs"])
	}
	var tab map[string]any
	for _, candidate := range tabs {
		m, ok := candidate.(map[string]any)
		if !ok {
			continue
		}
		if atoiOrZero(mapString(m, "tab_type")) == tabType {
			tab = m
			break
		}
	}
	if tab == nil {
		return nil, false, nil, fmt.Errorf("红果 %d 类搜索暂不可用", tabType)
	}
	dramas, hasMore, next := hongguoParseSearchTab(tab)
	return dramas, hasMore, next, nil
}

// hongguoParseSearchTab 解析单个搜索 tab 的响应：展开 cell 与 lynx_data，
// 抽出剧集、has_more 与下一页游标（纯解析，不发起网络请求）。
func hongguoParseSearchTab(tab map[string]any) ([]Drama, bool, *hongguoSearchCursor) {
	var dramas []Drama
	for _, cell := range anyList(tab["data"]) {
		cellMap, ok := cell.(map[string]any)
		if !ok {
			continue
		}
		rows := []map[string]any{cellMap}
		if lynx := mapString(cellMap, "lynx_data"); lynx != "" && lynx != "null" {
			if decoded, e := decodeHongguoJSONString(lynx); e == nil {
				for _, row := range anyList(decoded["cell_data"]) {
					if m, ok := row.(map[string]any); ok {
						rows = append(rows, m)
					}
				}
			}
		}
		for _, row := range rows {
			video := nestedMap(row, "video_data")
			if len(video) == 0 {
				if arr := anyList(row["video_data"]); len(arr) > 0 {
					if m, ok := arr[0].(map[string]any); ok {
						video = m
					}
				}
			}
			if len(video) == 0 {
				continue
			}
			id := firstNonEmpty(mapString(video, "series_id"), mapString(row, "book_id"), mapString(row, "search_result_id"))
			if !hongguoNumericID.MatchString(id) {
				continue
			}
			title := firstNonEmpty(hongguoHighlightTitle(row), mapString(video, "title"), mapString(row, "cell_name"))
			if title == "" {
				title = id
			}
			cover := firstNonEmpty(mapString(video, "cover"), mapString(video, "cover_url"))
			desc := mapString(video, "video_desc")
			count := atoiOrZero(mapString(video, "episode_cnt"))
			remark := mapString(video, "rec_text")
			if count > 0 {
				remark = fmt.Sprintf("全 %d 集", count)
			}
			genre := mapString(video, "sub_title")
			if genre == "" {
				genre = "短剧"
			}
			if drama := (Drama{
				ID:           providerDramaID(sourceHongguo, id),
				Source:       sourceHongguo,
				SourceID:     id,
				Title:        title,
				Name:         title,
				Desc:         desc,
				Intro:        desc,
				Cover:        cover,
				CoverURL:     cover,
				CategoryName: genre,
				ChannelName:  "红果",
				Remark:       remark,
				TotalEpisode: strconv.Itoa(count),
				EpisodeCount: strconv.Itoa(count),
			}); drama.ID != "" {
				dramas = append(dramas, drama)
			}
		}
	}
	next := &hongguoSearchCursor{
		searchID: mapString(tab, "search_id"),
		passback: mapString(tab, "passback"),
		offset:   atoiOrZero(mapString(tab, "next_offset")),
	}
	return dramas, hongguoTruthy(tab["has_more"]), next
}

// hongguoAppSearch 优先走 App 搜索接口：两个 tab（短剧、漫剧）各取一次后合并，
// 并按各 tab 的游标翻页直到没有更多或达到页数上限，从而覆盖完整结果。
func (downloader *Downloader) hongguoAppSearch(ctx context.Context, keyword string) ([]Drama, bool, error) {
	tabs := []int{honghuoSearchTabShort, honghuoSearchTabComic}
	cursors := make(map[int]*hongguoSearchCursor, len(tabs))
	var out []Drama
	seen := map[string]bool{}
	hasMore := false
	for page := 1; page <= honghuoSearchMaxPages; page++ {
		pageHasMore := false
		pageEmpty := true
		var tabErrs []error
		for _, tabType := range tabs {
			dramas, tabHasMore, next, err := downloader.hongguoAppSearchTab(ctx, keyword, tabType, page, cursors[tabType])
			if err != nil {
				tabErrs = append(tabErrs, err)
				continue
			}
			cursors[tabType] = next
			if tabHasMore {
				pageHasMore = true
			}
			for _, drama := range dramas {
				if !seen[drama.ID] {
					seen[drama.ID] = true
					out = append(out, drama)
				}
			}
			if len(dramas) > 0 {
				pageEmpty = false
			}
		}
		if len(tabErrs) == len(tabs) {
			return nil, false, errors.Join(tabErrs...)
		}
		if !pageHasMore || pageEmpty {
			break
		}
		hasMore = pageHasMore
	}
	return out, hasMore, nil
}

// fetchHongguoSearchResults 优先走 App 搜索（双 tab 合并、按游标翻页）；
// App 搜索不可用（设备未注册 / 接口关掉）时退回官网搜索第 1 页。
func (downloader *Downloader) fetchHongguoSearchResults(ctx context.Context, keyword string) (hongguoSearchEntry, error) {
	appDramas, appHasMore, appErr := downloader.hongguoAppSearch(ctx, keyword)
	if appErr == nil && len(appDramas) > 0 {
		return hongguoSearchEntry{Dramas: appDramas, Total: len(appDramas), Limited: appHasMore}, nil
	}
	webEntry, webErr := downloader.fetchHongguoSearchPage(ctx, keyword)
	if webErr != nil {
		if appErr != nil {
			return hongguoSearchEntry{}, errors.Join(appErr, webErr)
		}
		return hongguoSearchEntry{}, webErr
	}
	return webEntry, nil
}

func hongguoHighlightTitle(row map[string]any) string {
	highlight := nestedMap(row, "search_high_light", "title")
	if text := mapString(highlight, "text"); text != "" {
		return text
	}
	return ""
}

func hongguoTruthy(value any) bool {
	switch v := value.(type) {
	case bool:
		return v
	case string:
		return v == "true" || v == "1"
	case float64:
		return v != 0
	case json.Number:
		f, err := v.Float64()
		return err == nil && f != 0
	}
	return false
}

func atoiOrZero(value string) int {
	if value == "" {
		return 0
	}
	n, err := strconv.Atoi(strings.TrimSpace(value))
	if err != nil {
		return 0
	}
	return n
}

func decodeHongguoJSONString(value string) (map[string]any, error) {
	decoder := json.NewDecoder(strings.NewReader(value))
	decoder.UseNumber()
	var result map[string]any
	if err := decoder.Decode(&result); err != nil {
		return nil, err
	}
	return result, nil
}
