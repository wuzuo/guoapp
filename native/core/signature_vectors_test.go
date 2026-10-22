package core

import (
	"bytes"
	"crypto/md5"
	"encoding/hex"
	"encoding/json"
	"os"
	"testing"
)

// 回归：签名核心（branch / hashF13 / gorgon）必须与参考实现的固定向量逐字节一致。
// 这三者错了不会让播放立刻失败（播放端宽松），但评论等严格校验接口会回 110001。
func TestSignerMatchesReferenceVectors(t *testing.T) {
	raw, err := os.ReadFile("testdata/signing.json")
	if err != nil { t.Fatal(err) }
	type row struct {
		TS     int    `json:"ts"`
		URL    string `json:"url"`
		Body   any    `json:"body"`
		Hash   string `json:"hash"`
		Gorgon string `json:"gorgon"`
	}
	var rows []row
	if err := json.Unmarshal(raw, &rows); err != nil { t.Fatal(err) }
	if len(rows) == 0 { t.Fatal("no vectors") }
	for i, r := range rows {
		q := r.URL[bytes.IndexByte([]byte(r.URL), 0x3f)+1:]
		var body []byte
		if s, ok := r.Body.(string); ok { body = []byte(s) }
		if got := hgBranch(q, body, r.TS); got != 0 { t.Errorf("row %d branch=%d", i, got) }
		bm := make([]byte, 16)
		if body != nil { m := md5.Sum(body); bm = m[:] }
		h := hex.EncodeToString(hgHashF13(hgSm3([]byte(q)), bm, r.TS))
		if h != r.Hash { t.Errorf("row %d hash got=%s want=%s", i, h, r.Hash) }
		g := hgGorgon(q, body, r.TS, 42131)
		if g != r.Gorgon { t.Errorf("row %d gorgon got=%s want=%s", i, g, r.Gorgon) }
	}
}
