package main

import (
	"bytes"
	"errors"
	"os"
	"testing"
)

func TestSyslogAddress(t *testing.T) {
	tests := map[string]struct {
		host string
		want string
	}{
		"empty host returns empty": {host: "", want: ""},
		"ipv4 host":                {host: "192.168.1.10", want: "udp://192.168.1.10:514"},
		"ipv6 host is bracketed":   {host: "fd00:80:66::1", want: "udp://[fd00:80:66::1]:514"},
		"ipv6 loopback":            {host: "::1", want: "udp://[::1]:514"},
		"hostname passes through":  {host: "syslog.example.com", want: "udp://syslog.example.com:514"},
	}
	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			if got := syslogAddress(tt.host); got != tt.want {
				t.Fatalf("syslogAddress(%q) = %q, want %q", tt.host, got, tt.want)
			}
		})
	}
}

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
