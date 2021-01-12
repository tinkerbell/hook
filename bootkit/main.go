package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"io/ioutil"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/docker/docker/api/types"
	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/api/types/mount"
	"github.com/docker/docker/client"
)

type tinkConfig struct {
	// Registry configuration
	registry string
	username string
	password string

	// Tinkerbell server configuration
	baseURL    string
	tinkerbell string

	// Grpc stuff (dunno)
	grpcAuthority string
	grpcCertURL   string

	// Worker ID(s) .. why are there two?
	workerID string
	ID       string
}

func main() {
	fmt.Println("Starting BootKit")

	// // Read entire file content, giving us little control but
	// // making it very simple. No need to close the file.

	content, err := ioutil.ReadFile("/proc/cmdline")
	if err != nil {
		panic(err)
	}

	cmdlines := strings.Split(string(content), " ")
	cfg, _ := parsecmdline(cmdlines)

	// Generate the path to the tink-worker
	imageName := fmt.Sprintf("%s/tink-worker:latest", cfg.registry)

	// Generate the configuration of the container
	tinkContainer := &container.Config{
		Image: imageName,
		Env: []string{
			fmt.Sprintf("DOCKER_REGISTRY=%s", cfg.registry),
			fmt.Sprintf("REGISTRY_USERNAME=%s", cfg.username),
			fmt.Sprintf("REGISTRY_PASSWORD=%s", cfg.password),
			fmt.Sprintf("TINKERBELL_GRPC_AUTHORITY=%s", cfg.grpcAuthority),
			fmt.Sprintf("TINKERBELL_CERT_URL=%s", cfg.grpcCertURL),
			fmt.Sprintf("WORKER_ID=%s", cfg.workerID),
			fmt.Sprintf("ID=%s", cfg.workerID),
		},
		AttachStdout: true,
		AttachStderr: true,
	}

	tinkHostConfig := &container.HostConfig{
		Mounts: []mount.Mount{
			{
				Type:   mount.TypeBind,
				Source: "/worker",
				Target: "/worker",
			},
			{
				Type:   mount.TypeBind,
				Source: "/var/run/docker.sock",
				Target: "/var/run/docker.sock",
			},
		},
		NetworkMode: "host",
		Privileged:  true,
	}

	jsonBytes, _ := json.Marshal(map[string]string{
		"username": cfg.username,
		"password": cfg.password,
	})

	pullOpts := &types.ImagePullOptions{
		RegistryAuth: base64.StdEncoding.EncodeToString(jsonBytes),
	}

	// Give time to Docker to start
	// Alternatively we watch for the socket being created
	time.Sleep(time.Second * 3)
	fmt.Println("Starting Communication with Docker Engine")

	ctx := context.Background()
	cli, err := client.NewClientWithOpts(client.FromEnv, client.WithAPIVersionNegotiation())
	if err != nil {
		panic(err)
	}

	fmt.Printf("Pulling image [%s]", imageName)

	out, err := cli.ImagePull(ctx, imageName, *pullOpts)
	if err != nil {
		panic(err)
	}
	io.Copy(os.Stdout, out)

	resp, err := cli.ContainerCreate(ctx, tinkContainer, tinkHostConfig, nil, nil, "")
	if err != nil {
		panic(err)
	}

	if err := cli.ContainerStart(ctx, resp.ID, types.ContainerStartOptions{}); err != nil {
		panic(err)
	}

	fmt.Println(resp.ID)
}

func parsecmdline(cmdlines []string) (cfg tinkConfig, err error) {

	for i := range cmdlines {
		cmdline := strings.Split(cmdlines[i], "=")
		if len(cmdline) != 0 {

			// Find Registry configuration
			if cmdline[0] == "docker_registry" {
				cfg.registry = cmdline[1]
			}
			if cmdline[0] == "registry_username" {
				cfg.registry = cmdline[1]
			}
			if cmdline[0] == "registry_password" {
				cfg.registry = cmdline[1]
			}

			// Find Tinkerbell servers settings
			if cmdline[0] == "packet_base_url" {
				cfg.baseURL = cmdline[1]
			}
			if cmdline[0] == "tinkerbell" {
				cfg.tinkerbell = cmdline[1]
			}

			// Find GRPC configuration
			if cmdline[0] == "grpc_authority" {
				cfg.grpcAuthority = cmdline[1]
			}
			if cmdline[0] == "grpc_cert_url" {
				cfg.grpcCertURL = cmdline[1]
			}

			// Find the worker configuration
			if cmdline[0] == "worker_id" {
				cfg.workerID = cmdline[1]
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
