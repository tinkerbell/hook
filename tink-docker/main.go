package main

import (
	"fmt"
	"io"
	"io/ioutil"
	"net/http"
	"os"
	"os/exec"
	"strings"
)

type tinkConfig struct {
	registry   string
	baseURL    string
	tinkerbell string

	// TODO add others
}

func main() {
	fmt.Println("Starting Tink-Docker")

	// Parse the cmdline in order to find the urls for the repostiory and path to the cert
	content, err := ioutil.ReadFile("/proc/cmdline")
	if err != nil {
		panic(err)
	}
	cmdlines := strings.Split(string(content), " ")
	cfg, _ := parsecmdline(cmdlines)

	path := fmt.Sprintf("/etc/docker/certs.d/%s/", cfg.registry)

	// Create the directory
	err = os.MkdirAll(path, os.ModeDir)
	if err != nil {
		panic(err)
	}
	// Download the configuration
	err = DownloadFile(path+"ca.crt", cfg.baseURL+"/ca.pem")
	if err != nil {
		panic(err)
	}
	fmt.Println("Downloaded the repository certificates, starting the Docker Engine")

	// Build the command, and execute
	cmd := exec.Command("/usr/local/bin/docker-init", "/usr/local/bin/dockerd")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	err = cmd.Run()
	if err != nil {
		panic(err)
	}
}

func parsecmdline(cmdlines []string) (cfg tinkConfig, err error) {

	for i := range cmdlines {
		cmdline := strings.Split(cmdlines[i], "=")
		if len(cmdline) != 0 {
			if cmdline[0] == "docker_registry" {
				cfg.registry = cmdline[1]
			}
			if cmdline[0] == "packet_base_url" {
				cfg.baseURL = cmdline[1]
			}
			if cmdline[0] == "tinkerbell" {
				cfg.tinkerbell = cmdline[1]
			}
		}
	}
	return
}

// DownloadFile will download a url to a local file. It's efficient because it will
// write as it downloads and not load the whole file into memory.
func DownloadFile(filepath string, url string) error {

	// Get the data
	resp, err := http.Get(url)
	if err != nil {
		return err
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
