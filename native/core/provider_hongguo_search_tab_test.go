package core

import (
	"encoding/json"
	"testing"
)

func TestHongguoParseSearchTabExtractsDramasAndCursor(t *testing.T) {
	lynx := `{"cell_data":[{"book_id":"1002","cell_name":"testB","video_data":[{"series_id":"1002","title":"testB","cover":"https://example.test/b.jpg","episode_cnt":0}]}]}`
	tab := map[string]any{
		"tab_type":    "11",
		"search_id":   "sid-1",
		"passback":    "pb-1",
		"next_offset": "20",
		"has_more":    true,
		"data": []any{
			map[string]any{
				"book_id": "1001",
				"cell_name": "testA",
				"video_data": []any{
					map[string]any{
						"series_id":    "1001",
						"title":        "testA",
						"cover_url":    "https://example.test/a.jpg",
						"episode_cnt": 80,
						"video_desc":   "descA",
						"sub_title":    "short",
					},
				},
			},
			map[string]any{
				"lynx_data": lynx,
			},
		},
	}
	dramas, hasMore, next := hongguoParseSearchTab(tab)
	if !hasMore {
		t.Error("has_more should be true")
	}
	if next == nil || next.searchID != "sid-1" || next.passback != "pb-1" || next.offset != 20 {
		t.Fatalf("cursor wrong: %#v", next)
	}
	if len(dramas) != 2 {
		t.Fatalf("expected 2 dramas, got %d: %#v", len(dramas), dramas)
	}
	byID := map[string]Drama{}
	for _, d := range dramas {
		byID[d.SourceID] = d
	}
	first := byID["1001"]
	if first.Title != "testA" || first.Remark != "全 80 集" || first.CoverURL != "https://example.test/a.jpg" {
		t.Errorf("first drama wrong: %#v", first)
	}
	second := byID["1002"]
	if second.Title != "testB" || second.CoverURL != "https://example.test/b.jpg" {
		t.Errorf("second drama wrong: %#v", second)
	}
}

func TestHongguoTruthyAndAtoi(t *testing.T) {
	if !hongguoTruthy(true) || hongguoTruthy(false) {
		t.Error("hongguoTruthy bool wrong")
	}
	if !hongguoTruthy("true") || hongguoTruthy("false") || hongguoTruthy("0") {
		t.Error("hongguoTruthy string wrong")
	}
	if !hongguoTruthy(float64(1)) {
		t.Error("hongguoTruthy 1 wrong")
	}
	if !hongguoTruthy(float64(0.5)) {
		t.Error("hongguoTruthy 0.5 wrong")
	}
	if hongguoTruthy(float64(0)) {
		t.Error("hongguoTruthy 0 wrong")
	}
	if !hongguoTruthy(json.Number("1")) {
		t.Error("hongguoTruthy json.Number 1 wrong")
	}
	if hongguoTruthy(json.Number("0")) {
		t.Error("hongguoTruthy json.Number 0 wrong")
	}
	if atoiOrZero("") != 0 || atoiOrZero("20") != 20 || atoiOrZero("x") != 0 {
		t.Error("atoiOrZero wrong")
	}
}
