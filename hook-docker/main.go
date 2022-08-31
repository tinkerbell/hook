package main

import (
	"encoding/json"
	"fmt"
	"io"
	"io/ioutil"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"time"
)

type tinkConfig struct {
	registry      string
	baseURL       string
	tinkerbell    string
	syslogHost    string
	tinkServerTLS bool

	// TODO add others
}

type dockerConfig struct {
	Debug     bool              `json:"debug"`
	LogDriver string            `json:"log-driver,omitempty"`
	LogOpts   map[string]string `json:"log-opts,omitempty"`
}

func main() {
	fmt.Println("Starting Tink-Docker")
	go rebootWatch()

	// Parse the cmdline in order to find the urls for the repository and path to the cert
	content, err := ioutil.ReadFile("/proc/cmdline")
	if err != nil {
		panic(err)
	}
	cmdLines := strings.Split(string(content), " ")
	cfg := parseCmdLine(cmdLines)

	// if tinkServerTLS is not enabled, skip downloading the certs
	if cfg.tinkServerTLS {
		path := fmt.Sprintf("/etc/docker/certs.d/%s/", cfg.registry)

		// Create the directory
		err = os.MkdirAll(path, os.ModeDir)
		if err != nil {
			panic(err)
		}
		// Download the configuration
		err = downloadFile(path+"ca.crt", cfg.baseURL+"/ca.pem")
		if err != nil {
			panic(err)
		}
		fmt.Println("Downloaded the repository certificates, starting the Docker Engine")
	}

	d := dockerConfig{
		Debug:     true,
		LogDriver: "syslog",
		LogOpts: map[string]string{
			"syslog-address": fmt.Sprintf("udp://%v:514", cfg.syslogHost),
		},
	}
	if err := d.writeToDisk("/etc/docker/daemon.json"); err != nil {
		fmt.Println("Failed to write docker config:", err)
	}

	// Build the command, and execute
	cmd := exec.Command("/usr/local/bin/docker-init", "/usr/local/bin/dockerd")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	err = cmd.Run()
	if err != nil {
		panic(err)
	}
}

// writeToDisk writes the dockerConfig to loc.
func (d dockerConfig) writeToDisk(loc string) error {
	b, err := json.Marshal(d)
	if err != nil {
		return fmt.Errorf("unable to marshal docker config: %w", err)
	}
	if err := ioutil.WriteFile(loc, b, 0o600); err != nil {
		return fmt.Errorf("error writing daemon.json: %w", err)
	}

	return nil
}

// parseCmdLine will parse the command line.
func parseCmdLine(cmdLines []string) (cfg tinkConfig) {
	for i := range cmdLines {
		cmdLine := strings.Split(cmdLines[i], "=")
		if len(cmdLine) == 0 {
			continue
		}

		switch cmd := cmdLine[0]; cmd {
		// Find Registry configuration
		case "docker_registry":
			cfg.registry = cmdLine[1]
		case "packet_base_url":
			cfg.baseURL = cmdLine[1]
		case "tinkerbell":
			cfg.tinkerbell = cmdLine[1]
		case "syslog_host":
			cfg.syslogHost = cmdLine[1]
		}
	}
	return cfg
}

// downloadFile will download a url to a local file. It's efficient because it will
// write as it downloads and not load the whole file into memory.
func downloadFile(filepath string, url string) error {
	// As all functions in the LinuxKit services run in parallel, ensure that we can fail
	// successfully until we accept that networking is actually broken

	var maxRetryCount int
	var timeOut time.Duration
	maxRetryCount = 10
	timeOut = time.Millisecond * 500 // 0.5 seconds
	var resp *http.Response
	var err error

	// Retry this task
	for retries := 0; retries < maxRetryCount; retries++ {
		// Get the data
		resp, err = http.Get(url)
		if err == nil {
			break
		}
		resp.Body.Close()

		if retries == maxRetryCount-1 {
			return err
		}
		time.Sleep(timeOut)
	}
	defer resp.Body.Close()

	// Create the file
	out, err := os.Create(filepath)
	if err != nil {
		return err
	}
	defer out.Close()

	// Write the body to file
	_, err = io.Copy(out, resp.Body)
	return err
}

func rebootWatch() {
	fmt.Println("Starting Reboot Watcher")

	// Forever loop
	for {
		if fileExists("/worker/reboot") {
			cmd := exec.Command("/sbin/reboot")
			cmd.Stdout = os.Stdout
			cmd.Stderr = os.Stderr
			err := cmd.Run()
			if err != nil {
				panic(err)
			}
			break
		}
		// Wait one second before looking for file
		time.Sleep(time.Second)
	}
	fmt.Println("Rebooting")
}

func fileExists(filename string) bool {
	info, err := os.Stat(filename)
	if os.IsNotExist(err) {
		return false
	}
	return !info.IsDir()
}
