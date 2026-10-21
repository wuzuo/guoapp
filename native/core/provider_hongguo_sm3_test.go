package core

import (
	"encoding/hex"
	"testing"
)

func TestHgSm3Vectors(t *testing.T) {
	cases := []struct {
		input string
		want  string
	}{
		{"", "1ab21d8355cfa17f8e61194831e81a8f22bec8c728fefb747ed035eb5082aa2b"},
		{"abc", "66c7f0f462eeedd9d1f2d46bdc10e4e24167c4875cf2f7a2297da02b8f4ba8e0"},
	}
	for _, c := range cases {
		got := hex.EncodeToString(hgSm3([]byte(c.input)))
		if got != c.want {
			t.Errorf("hgSm3(%q) = %s, want %s", c.input, got, c.want)
		}
	}
}
