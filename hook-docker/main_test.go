package main

import (
	"bytes"
	"errors"
	"os"
	"testing"
)

func TestWriteToDisk(t *testing.T) {
	tests := map[string]struct {
		cfg     dockerConfig
		want    []byte
		wantErr error
	}{
		"success":                {cfg: dockerConfig{Debug: false, LogDriver: "json-file"}, want: []byte(`{"debug":false,"log-driver":"json-file"}`)},
		"success - empty struct": {cfg: dockerConfig{}, want: []byte(`{"debug":false}`)},
	}
	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			// Create a temporary directory
			dir, err := os.MkdirTemp("", "hook-docker")
			if err != nil {
				t.Fatal(err)
			}
			defer os.RemoveAll(dir)
			loc := dir + "daemon.json"

			err = tt.cfg.writeToDisk(loc)
			if !errors.Is(err, tt.wantErr) {
				t.Fatalf("got err %v, want %v", err, tt.wantErr)
			}

			if tt.wantErr == nil {
				got, err := os.ReadFile(loc)
				if err != nil {
					t.Fatal(err)
				}

				if !bytes.Equal(got, tt.want) {
					t.Fatalf("\ngot:\n %s\nwant:\n %s", got, tt.want)
				}
			}
		})
	}
}
