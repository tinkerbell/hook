package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path"
	"strings"
	"time"

	"github.com/cenkalti/backoff/v4"
	"github.com/docker/docker/api/types"
	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/api/types/mount"
	"github.com/docker/docker/api/types/registry"
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

	// Worker ID(s) .. why are there two?
	workerID string
	ID       string

	// tinkWorkerImage is the Tink worker image location.
	tinkWorkerImage string

	// tinkServerTLS is whether or not to use TLS for tink-server communication.
	tinkServerTLS string
	httpProxy     string
	httpsProxy    string
	noProxy       string
}

const maxRetryAttempts = 20

func main() {
	fmt.Println("Starting BootKit")

	// // Read entire file content, giving us little control but
	// // making it very simple. No need to close the file.

	content, err := os.ReadFile("/proc/cmdline")
	if err != nil {
		panic(err)
	}

	cmdLines := strings.Split(string(content), " ")
	cfg := parseCmdLine(cmdLines)

	// Generate the path to the tink-worker
	var imageName string
	if cfg.registry != "" {
		imageName = path.Join(cfg.registry, "tink-worker:latest")
	}
	if cfg.tinkWorkerImage != "" {
		imageName = cfg.tinkWorkerImage
	}
	if imageName == "" {
		// TODO(jacobweinstock): Don't panic, ever. This whole main function should ideally be a control loop that never exits.
		// Just keep trying all the things until they work. Similar idea to controllers in Kubernetes. Doesn't need to be that heavy though.
		panic("cannot pull image for tink-worker, 'docker_registry' and/or 'tink_worker_image' NOT specified in /proc/cmdline")
	}

	// Generate the configuration of the container
	tinkContainer := &container.Config{
		Image: imageName,
		Env: []string{
			fmt.Sprintf("DOCKER_REGISTRY=%s", cfg.registry),
			fmt.Sprintf("REGISTRY_USERNAME=%s", cfg.username),
			fmt.Sprintf("REGISTRY_PASSWORD=%s", cfg.password),
			fmt.Sprintf("TINKERBELL_GRPC_AUTHORITY=%s", cfg.grpcAuthority),
			fmt.Sprintf("TINKERBELL_TLS=%s", cfg.tinkServerTLS),
			fmt.Sprintf("WORKER_ID=%s", cfg.workerID),
			fmt.Sprintf("ID=%s", cfg.workerID),
			fmt.Sprintf("HTTP_PROXY=%s", cfg.httpProxy),
			fmt.Sprintf("HTTPS_PROXY=%s", cfg.httpsProxy),
			fmt.Sprintf("NO_PROXY=%s", cfg.noProxy),
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

	authConfig := registry.AuthConfig{
		Username: cfg.username,
		Password: strings.TrimSuffix(cfg.password, "\n"),
	}

	encodedJSON, err := json.Marshal(authConfig)
	if err != nil {
		panic(err)
	}

	authStr := base64.URLEncoding.EncodeToString(encodedJSON)

	pullOpts := types.ImagePullOptions{
		RegistryAuth: authStr,
	}

	// Give time to Docker to start
	// Alternatively we watch for the socket being created
	time.Sleep(time.Second * 3)
	fmt.Println("Starting Communication with Docker Engine")

	os.Setenv("HTTP_PROXY", cfg.httpProxy)
	os.Setenv("HTTPS_PROXY", cfg.httpsProxy)
	os.Setenv("NO_PROXY", cfg.noProxy)

	// Create Docker client with API (socket)
	ctx := context.Background()
	cli, err := client.NewClientWithOpts(client.FromEnv, client.WithAPIVersionNegotiation())
	if err != nil {
		panic(err)
	}

	fmt.Printf("Pulling image [%s]", imageName)

	// TODO: Ideally if this function becomes a loop that runs forever and keeps retrying
	// anything that failed, this retry would not be needed. For now, this addresses the specific
	// race condition case of when the linuxkit network or dns is in the process of, but not quite
	// fully set up yet.

	var out io.ReadCloser
	imagePullOperation := func() error {
		out, err = cli.ImagePull(ctx, imageName, pullOpts)
		if err != nil {
			fmt.Printf("Image pull failure %s, %v\n", imageName, err)
			return err
		}
		return nil
	}
	if err = backoff.Retry(imagePullOperation, backoff.WithMaxRetries(backoff.NewExponentialBackOff(), maxRetryAttempts)); err != nil {
		panic(err)
	}

	if _, err = io.Copy(os.Stdout, out); err != nil {
		panic(err)
	}

	if err = out.Close(); err != nil {
		fmt.Printf("error closing io.ReadCloser out: %s", err)
	}

	resp, err := cli.ContainerCreate(ctx, tinkContainer, tinkHostConfig, nil, nil, "")
	if err != nil {
		panic(err)
	}

	if err := cli.ContainerStart(ctx, resp.ID, types.ContainerStartOptions{}); err != nil {
		panic(err)
	}

	fmt.Println(resp.ID)
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
		case "registry_username":
			cfg.username = cmdLine[1]
		case "registry_password":
			cfg.password = cmdLine[1]
		// Find Tinkerbell servers settings
		case "packet_base_url":
			cfg.baseURL = cmdLine[1]
		case "tinkerbell":
			cfg.tinkerbell = cmdLine[1]
		// Find GRPC configuration
		case "grpc_authority":
			cfg.grpcAuthority = cmdLine[1]
		// Find the worker configuration
		case "worker_id":
			cfg.workerID = cmdLine[1]
		case "tink_worker_image":
			cfg.tinkWorkerImage = cmdLine[1]
		case "tinkerbell_tls":
			cfg.tinkServerTLS = cmdLine[1]
		case "HTTP_PROXY":
			cfg.httpProxy = cmdLine[1]
		case "HTTPS_PROXY":
			cfg.httpsProxy = cmdLine[1]
		case "NO_PROXY":
			cfg.noProxy = cmdLine[1]
		}
	}
	return cfg
}
