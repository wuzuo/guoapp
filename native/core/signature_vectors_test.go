package core

import (
	"bytes"
	"crypto/md5"
	"encoding/hex"
	"encoding/json"
	"os"
	"testing"
)

// 参考实现的随机数发生器：seed=(seed*1664525+1013904223) & 0xffffffff。
type hgLCG struct{ seed uint32 }

func (l *hgLCG) uint32() uint32 { l.seed = l.seed*1664525 + 1013904223; return l.seed }
func (l *hgLCG) float() float64 { return float64(l.uint32()) / 4294967296.0 }

// 回归：签名核心（branch / hashF13 / gorgon / helios / medusa）必须与参考实现的固定向量逐字节一致。
func TestSignerMatchesReferenceVectors(t *testing.T) {
	raw, err := os.ReadFile("testdata/signing.json")
	if err != nil { t.Fatal(err) }
	type row struct {
		TS     int    `json:"ts"`
		URL    string `json:"url"`
		Body   any    `json:"body"`
		Hash   string `json:"hash"`
		Gorgon string `json:"gorgon"`
		Helios string `json:"helios"`
		Medusa string `json:"medusa"`
	}
	var rows []row
	if err := json.Unmarshal(raw, &rows); err != nil { t.Fatal(err) }
	if len(rows) == 0 { t.Fatal("no vectors") }
	oldU, oldF := hgRandUint32, hgRandFloat
	defer func() { hgRandUint32, hgRandFloat = oldU, oldF }()
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

		lcg := &hgLCG{seed: 17}
		hgRandUint32 = lcg.uint32
		hgRandFloat = lcg.float
		helios := hgHelios(r.TS)
		if helios != r.Helios { t.Errorf("row %d helios got=%s want=%s", i, helios, r.Helios) }
		medusa := hgMedusa(r.URL, body, r.TS, "1905892595378490", "7.1.3.32")
		if medusa != r.Medusa { t.Errorf("row %d medusa got=%s want=%s", i, medusa, r.Medusa) }
		hgRandUint32, hgRandFloat = oldU, oldF
	}
}
