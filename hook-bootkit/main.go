package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path"
	"strings"
	"syscall"
	"time"

	"github.com/cenkalti/backoff/v4"
	"github.com/docker/docker/api/types"
	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/api/types/mount"
	"github.com/docker/docker/api/types/registry"
	"github.com/docker/docker/client"
	"github.com/go-logr/logr"
	"github.com/go-logr/zerologr"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/pkgerrors"
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

// defaultLogger is a zerolog logr implementation.
func defaultLogger(level string) logr.Logger {
	zerolog.ErrorStackMarshaler = pkgerrors.MarshalStack
	zl := zerolog.New(os.Stdout)
	zl = zl.With().Stack().Caller().Timestamp().Logger()
	var l zerolog.Level
	switch level {
	case "debug":
		l = zerolog.DebugLevel
	default:
		l = zerolog.InfoLevel
	}
	zl = zl.Level(l)

	return zerologr.New(&zl)
}

func main() {
	ctx, done := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGHUP, syscall.SIGTERM)
	defer done()
	log := defaultLogger("debug")
	log.Info("starting BootKit: the tink-worker bootstrapper")

	for {
		if err := run(ctx, log); err != nil {
			log.Error(err, "error bootstrapping tink-worker")
			log.Info("will retry in 5 seconds")
			time.Sleep(5 * time.Second)
			continue
		}
		break
	}
	log.Info("BootKit: the tink-worker bootstrapper finished")
}

// TODO(jacobweinstock): clean up func run().
// 1. read /proc/cmdline
// 2. parse and populate tinkConfig from contents of /proc/cmdline
// 3. do validation/sanitization on tinkConfig
// 4. setup docker client
// 4. configure any registry auth
// 5. pull tink-worker image
// 6. remove any existing tink-worker container
// 7. setup tink-worker container config
// 8. create tink-worker container
// 9. start tink-worker container
// 10. check that the tink-worker container is running

func run(ctx context.Context, log logr.Logger) error {
	content, err := os.ReadFile("/proc/cmdline")
	if err != nil {
		return err
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
		return fmt.Errorf("cannot pull image for tink-worker, 'docker_registry' and/or 'tink_worker_image' NOT specified in /proc/cmdline")
	}

	// Give time for Docker to start
	// Alternatively we watch for the socket being created
	log.Info("setuping up the Docker client")

	os.Setenv("HTTP_PROXY", cfg.httpProxy)
	os.Setenv("HTTPS_PROXY", cfg.httpsProxy)
	os.Setenv("NO_PROXY", cfg.noProxy)
	// Create Docker client with API (socket)
	cli, err := client.NewClientWithOpts(client.FromEnv, client.WithAPIVersionNegotiation())
	if err != nil {
		return err
	}

	log.Info("Pulling image", "imageName", imageName)
	authConfig := registry.AuthConfig{
		Username: cfg.username,
		Password: strings.TrimSuffix(cfg.password, "\n"),
	}

	encodedJSON, err := json.Marshal(authConfig)
	if err != nil {
		return err
	}

	authStr := base64.URLEncoding.EncodeToString(encodedJSON)

	pullOpts := types.ImagePullOptions{
		RegistryAuth: authStr,
	}
	var out io.ReadCloser
	imagePullOperation := func() error {
		out, err = cli.ImagePull(ctx, imageName, pullOpts)
		if err != nil {
			log.Error(err, "Image pull failure", "imageName", imageName)
			return err
		}
		return nil
	}
	if err = backoff.Retry(imagePullOperation, backoff.NewExponentialBackOff()); err != nil {
		return err
	}

	if _, err = io.Copy(os.Stdout, out); err != nil {
		return err
	}

	if err = out.Close(); err != nil {
		log.Error(err, "error when closing image pull logs")
	}

	cs, err := cli.ContainerList(ctx, types.ContainerListOptions{All: true})
	if err != nil {
		return fmt.Errorf("error listing containers used for checking for an existing tink-worker container: %w", err)
	}
	for _, c := range cs {
		for _, n := range c.Names {
			if n == "/tink-worker" {
				log.Info("Removing existing tink-worker container")
				if err := cli.ContainerRemove(ctx, c.ID, types.ContainerRemoveOptions{Force: true}); err != nil {
					return fmt.Errorf("error removing existing tink-worker container: %w", err)
				}
			}
		}
	}
	log.Info("Creating tink-worker container")
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
		//AutoRemove:  true,
	}
	resp, err := cli.ContainerCreate(ctx, tinkContainer, tinkHostConfig, nil, nil, "tink-worker")
	if err != nil {
		return fmt.Errorf("error creating tink-worker container: %w", err)
	}

	log.Info("Starting tink-worker container")
	if err := cli.ContainerStart(ctx, resp.ID, types.ContainerStartOptions{}); err != nil {
		return fmt.Errorf("error starting tink-worker container: %w", err)
	}

	time.Sleep(time.Second * 3)
	// if tink-worker is not running return error so we try again
	if err := checkContainerRunning(ctx, cli, resp.ID); err != nil {
		return fmt.Errorf("error checking if tink-worker container is running: %w", err)
	}

	return nil
}

func checkContainerRunning(ctx context.Context, cli *client.Client, containerID string) error {
	inspect, err := cli.ContainerInspect(ctx, containerID)
	if err != nil {
		return err
	}
	if !inspect.State.Running {
		return fmt.Errorf("tink-worker container is not running")
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
