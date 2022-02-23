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
	"path"        
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
	certURL string
	registryCertRequired string
	useAbsoluteImageURI string

	// Tinkerbell server configuration
	baseURL    string
	tinkerbell string

	// Grpc stuff (dunno)
	grpcAuthority string
	grpcCertURL   string

	// Worker ID(s) .. why are there two?
	workerID string
	ID       string

	// Metadata ID ... plus the other IDs :shrug:
	MetadataID string `json:"id"`

	// tinkWorkerImage is the Tink worker image location.
	// This must contain the absolute URI to Tink worker image.
	tinkWorkerImage string

	// tinkServerTLS is whether or not to use TLS for tink-server communication.
	tinkServerTLS string
}

func main() {
	fmt.Println("Starting BootKit")

	// // Read entire file content, giving us little control but
	// // making it very simple. No need to close the file.

	content, err := ioutil.ReadFile("/proc/cmdline")
	if err != nil {
		panic(err)
	}

	cmdLines := strings.Split(string(content), " ")
	cfg := parseCmdLine(cmdLines)

	// Get the ID from the metadata service
	err = cfg.metaDataQuery()
	if err != nil {
		panic(err)
	}

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
			fmt.Sprintf("REGISTRY_CERT_URL=%s", cfg.certURL),
			fmt.Sprintf("REGISTRY_CERT_REQUIRED=%s", cfg.registryCertRequired),
			fmt.Sprintf("USE_ABSOLUTE_IMAGE_URI=%s", cfg.useAbsoluteImageURI),
			fmt.Sprintf("TINKERBELL_GRPC_AUTHORITY=%s", cfg.grpcAuthority),
			fmt.Sprintf("TINKERBELL_CERT_URL=%s", cfg.grpcCertURL),
			fmt.Sprintf("TINKERBELL_TLS=%s", cfg.tinkServerTLS),
			fmt.Sprintf("WORKER_ID=%s", cfg.workerID),
			fmt.Sprintf("ID=%s", cfg.workerID),
			fmt.Sprintf("container_uuid=%s", cfg.MetadataID),
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

	authConfig := types.AuthConfig{
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

	// Create Docker client with API (socket)
	ctx := context.Background()
	cli, err := client.NewClientWithOpts(client.FromEnv, client.WithAPIVersionNegotiation())
	if err != nil {
		panic(err)
	}

	fmt.Printf("Pulling image [%s]", imageName)

	out, err := cli.ImagePull(ctx, imageName, pullOpts)
	if err != nil {
		panic(err)
	}

	_, err = io.Copy(os.Stdout, out)
	if err != nil {
		panic(err)
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
		case "registry_cert_url":
			cfg.certURL = cmdLine[1]
		case "registry_cert_required":
			cfg.registryCertRequired = cmdLine[1]
		case "use_absolute_image_uri":
			cfg.useAbsoluteImageURI = cmdLine[1]
		// Find Tinkerbell servers settings
		case "packet_base_url":
			cfg.baseURL = cmdLine[1]
		case "tinkerbell":
			cfg.tinkerbell = cmdLine[1]
		// Find GRPC configuration
		case "grpc_authority":
			cfg.grpcAuthority = cmdLine[1]
		case "grpc_cert_url":
			cfg.grpcCertURL = cmdLine[1]
		// Find the worker configuration
		case "worker_id":
			cfg.workerID = cmdLine[1]
		case "tink_worker_image":
			cfg.tinkWorkerImage = cmdLine[1]
		case "tinkerbell_tls":
			cfg.tinkServerTLS = cmdLine[1]
		}
	}
	return cfg
}

// metaDataQuery will query the metadata.
func (cfg *tinkConfig) metaDataQuery() error {
	spaceClient := http.Client{
		Timeout: time.Second * 60, // Timeout after 60 seconds (seems massively long is this dial-up?)
	}

	req, err := http.NewRequest(http.MethodGet, fmt.Sprintf("%s:50061/metadata", cfg.tinkerbell), nil)
	if err != nil {
		return err
	}

	req.Header.Set("User-Agent", "bootkit")

	res, getErr := spaceClient.Do(req)
	if getErr != nil {
		return err
	}

	if res.Body != nil {
		defer res.Body.Close()
	}

	body, readErr := ioutil.ReadAll(res.Body)
	if readErr != nil {
		return err
	}

	var metadata struct {
		ID string `json:"id"`
	}

	jsonErr := json.Unmarshal(body, &metadata)
	if jsonErr != nil {
		return err
	}

	cfg.MetadataID = metadata.ID
	return err
}
