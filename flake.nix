{
  description = "A Nix flake for Stable Diffusion WebUI with Python 3.10";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    sd-webui-src = {
      url = "github:AUTOMATIC1111/stable-diffusion-webui";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      sd-webui-src,
      ...
    }:
    let
      # Version is derived from flake.lock (updated via `nix flake update`)
      sdWebuiVersion = sd-webui-src.shortRev or "HEAD";
    in
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        # Allow unfree packages
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            allowUnsupportedSystem = true;
          };
        };

        # Python environment with minimal dependencies for bootstrapping
        # All SD WebUI dependencies are installed via pip in the virtual environment
        pythonEnv = pkgs.python310.buildEnv.override {
          extraLibs = with pkgs.python310Packages; [
            setuptools
            wheel
            pip
          ];
          ignoreCollisions = true;
        };

        # Process each script file individually using replaceVars
        # Only replace variables that actually exist in each script
        configScript = pkgs.replaceVars ./scripts/config.sh {
          inherit pythonEnv sdWebuiVersion;
          sdWebuiSrc = sd-webui-src;
        };

        # Main launcher script with substitutions
        launcherScript = pkgs.replaceVars ./scripts/launcher.sh {
          libPath = pkgs.lib.makeLibraryPath [
            pkgs.stdenv.cc.cc.lib
            pkgs.libGL
            pkgs.libGLU
            pkgs.glib
            pkgs.zlib
          ];
        };

        # Create a directory with all launcher scripts
        # Named nix-launcher to avoid conflict with SD WebUI's scripts directory
        scriptDir = pkgs.runCommand "sd-webui-launcher-scripts" { } ''
          mkdir -p $out
          cp ${configScript} $out/config.sh
          cp ${./scripts/logger.sh} $out/logger.sh
          cp ${./scripts/install.sh} $out/install.sh
          cp ${./scripts/persistence.sh} $out/persistence.sh
          cp ${./scripts/runtime.sh} $out/runtime.sh
          cp ${launcherScript} $out/launcher.sh
          chmod +x $out/*.sh
        '';

        # Define all packages in one attribute set
        packages = rec {
          default = pkgs.stdenv.mkDerivation {
            pname = "sd-webui";
            version = sdWebuiVersion;

            src = sd-webui-src;

            # Passthru for scripting and testing
            passthru = {
              inherit sd-webui-src;
              version = sdWebuiVersion;
            };

            nativeBuildInputs = [
              pkgs.makeWrapper
              pythonEnv
            ];
            buildInputs = [
              pkgs.libGL
              pkgs.libGLU
              pkgs.stdenv.cc.cc.lib
            ];

            # Skip build and configure phases
            dontBuild = true;
            dontConfigure = true;

            installPhase = ''
              # Create directories
              mkdir -p "$out/bin"
              mkdir -p "$out/share/sd-webui"

              # Copy SD WebUI files
              cp -r ${sd-webui-src}/* "$out/share/sd-webui/"

              # Create nix-launcher directory (separate from SD WebUI's scripts)
              mkdir -p "$out/share/sd-webui/nix-launcher"

              # Copy all launcher script files
              cp -r ${scriptDir}/* "$out/share/sd-webui/nix-launcher/"

              # Install the launcher script
              ln -s "$out/share/sd-webui/nix-launcher/launcher.sh" "$out/bin/sd-webui-launcher"
              chmod +x "$out/bin/sd-webui-launcher"

              # Create a symlink to the launcher
              ln -s "$out/bin/sd-webui-launcher" "$out/bin/sd-webui"
            '';

            meta = with pkgs.lib; {
              description = "Stable Diffusion WebUI - A browser interface for Stable Diffusion";
              homepage = "https://github.com/AUTOMATIC1111/stable-diffusion-webui";
              license = licenses.agpl3Only;
              platforms = platforms.all;
              mainProgram = "sd-webui";
            };
          };

          # Docker image for SD WebUI (CPU)
          dockerImage = pkgs.dockerTools.buildImage {
            name = "sd-webui";
            tag = "latest";

            # Include essential utilities and core dependencies
            copyToRoot = pkgs.buildEnv {
              name = "root";
              paths = [
                pkgs.bash
                pkgs.coreutils
                pkgs.netcat
                pkgs.git
                pkgs.curl
                pkgs.cacert
                pkgs.libGL
                pkgs.libGLU
                pkgs.stdenv.cc.cc.lib
                default
              ];
              pathsToLink = [
                "/bin"
                "/etc"
                "/lib"
                "/share"
              ];
            };

            # Set up volumes and ports
            config = {
              Cmd = [
                "/bin/bash"
                "-c"
                "export SD_WEBUI_USER_DIR=/data && mkdir -p /data && /bin/sd-webui --listen"
              ];
              Env = [
                "SD_WEBUI_USER_DIR=/data"
                "PATH=/bin:/usr/bin"
                "PYTHONUNBUFFERED=1"
                "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                "LD_LIBRARY_PATH=${pkgs.stdenv.cc.cc.lib}/lib"
                "CUDA_VERSION=cpu"
              ];
              ExposedPorts = {
                "7860/tcp" = { };
              };
              WorkingDir = "/data";
              Volumes = {
                "/data" = { };
              };
              Healthcheck = {
                Test = [
                  "CMD"
                  "nc"
                  "-z"
                  "localhost"
                  "7860"
                ];
                Interval = 30000000000; # 30 seconds in nanoseconds
                Timeout = 5000000000; # 5 seconds in nanoseconds
                Retries = 3;
                StartPeriod = 60000000000; # 60 seconds grace period for startup
              };
              Labels = {
                "org.opencontainers.image.title" = "Stable Diffusion WebUI";
                "org.opencontainers.image.description" =
                  "Stable Diffusion WebUI - A browser interface for Stable Diffusion";
                "org.opencontainers.image.version" = sdWebuiVersion;
                "org.opencontainers.image.source" = "https://github.com/utensils/stable-diffusion-webui-nix";
                "org.opencontainers.image.licenses" = "AGPL-3.0";
              };
            };
          };

          # Docker image for SD WebUI with CUDA support
          dockerImageCuda = pkgs.dockerTools.buildImage {
            name = "sd-webui";
            tag = "cuda";

            # Include essential utilities, core dependencies, and CUDA libraries
            copyToRoot = pkgs.buildEnv {
              name = "root";
              paths = [
                pkgs.bash
                pkgs.coreutils
                pkgs.netcat
                pkgs.git
                pkgs.curl
                pkgs.cacert
                pkgs.libGL
                pkgs.libGLU
                pkgs.stdenv.cc.cc.lib
                default
              ];
              pathsToLink = [
                "/bin"
                "/etc"
                "/lib"
                "/share"
              ];
            };

            # Set up volumes and ports
            config = {
              Cmd = [
                "/bin/bash"
                "-c"
                "export SD_WEBUI_USER_DIR=/data && mkdir -p /data && /bin/sd-webui --listen"
              ];
              Env = [
                "SD_WEBUI_USER_DIR=/data"
                "PATH=/bin:/usr/bin"
                "PYTHONUNBUFFERED=1"
                "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                "LD_LIBRARY_PATH=${pkgs.stdenv.cc.cc.lib}/lib"
                "NVIDIA_VISIBLE_DEVICES=all"
                "NVIDIA_DRIVER_CAPABILITIES=compute,utility"
                "CUDA_VERSION=cu124"
              ];
              ExposedPorts = {
                "7860/tcp" = { };
              };
              WorkingDir = "/data";
              Volumes = {
                "/data" = { };
              };
              Healthcheck = {
                Test = [
                  "CMD"
                  "nc"
                  "-z"
                  "localhost"
                  "7860"
                ];
                Interval = 30000000000; # 30 seconds in nanoseconds
                Timeout = 5000000000; # 5 seconds in nanoseconds
                Retries = 3;
                StartPeriod = 60000000000; # 60 seconds grace period for startup
              };
              Labels = {
                "org.opencontainers.image.title" = "Stable Diffusion WebUI CUDA";
                "org.opencontainers.image.description" =
                  "Stable Diffusion WebUI with CUDA support for GPU acceleration";
                "org.opencontainers.image.version" = sdWebuiVersion;
                "org.opencontainers.image.source" = "https://github.com/utensils/stable-diffusion-webui-nix";
                "org.opencontainers.image.licenses" = "AGPL-3.0";
                "com.nvidia.volumes.needed" = "nvidia_driver";
              };
            };
          };
        };
      in
      {
        # Export packages
        inherit packages;

        # Define apps
        apps = rec {
          default = {
            type = "app";
            program = "${packages.default}/bin/sd-webui";
            meta = {
              description = "Run Stable Diffusion WebUI";
            };
          };

          # App with API enabled
          api = {
            type = "app";
            program = toString (
              pkgs.writeShellScript "sd-webui-api" ''
                exec ${packages.default}/bin/sd-webui --api "$@"
              ''
            );
            meta = {
              description = "Run SD WebUI with API enabled";
            };
          };

          # App with network listening enabled
          listen = {
            type = "app";
            program = toString (
              pkgs.writeShellScript "sd-webui-listen" ''
                exec ${packages.default}/bin/sd-webui --listen "$@"
              ''
            );
            meta = {
              description = "Run SD WebUI with network listening enabled";
            };
          };

          # App with network listening and authentication (for remote access)
          remote = {
            type = "app";
            program = toString (
              pkgs.writeShellScript "sd-webui-remote" ''
                # Default credentials - override with --gradio-auth user:pass
                GRADIO_AUTH="''${SD_WEBUI_AUTH:-admin:admin}"
                echo "Starting SD WebUI for remote access with authentication"
                echo "Default login: admin / admin (set SD_WEBUI_AUTH=user:pass to change)"
                exec ${packages.default}/bin/sd-webui --listen --gradio-auth "$GRADIO_AUTH" "$@"
              ''
            );
            meta = {
              description = "Run SD WebUI with network listening and authentication for remote access";
            };
          };

          # App with Gradio public sharing (creates a public tunnel URL)
          # This is the most reliable way to access SD WebUI remotely
          share = {
            type = "app";
            program = toString (
              pkgs.writeShellScript "sd-webui-share" ''
                echo "Starting SD WebUI with Gradio sharing enabled..."
                echo "A public URL will be generated (format: https://xxxxx.gradio.live)"
                echo "Note: The share link expires after 72 hours."
                exec ${packages.default}/bin/sd-webui --share "$@"
              ''
            );
            meta = {
              description = "Run SD WebUI with Gradio sharing for remote access via public tunnel";
            };
          };

          # Add a buildDocker command
          buildDocker =
            let
              script = pkgs.writeShellScriptBin "build-docker" ''
                echo "Building Docker image for SD WebUI..."
                # Load the Docker image directly
                ${pkgs.docker}/bin/docker load < ${self.packages.${system}.dockerImage}
                echo "Docker image built successfully! You can now run it with:"
                echo "docker run -p 7860:7860 -v \$PWD/data:/data sd-webui:latest"
              '';
            in
            {
              type = "app";
              program = "${script}/bin/build-docker";
              meta = {
                description = "Build SD WebUI Docker image (CPU)";
              };
            };

          # Add a buildDockerCuda command
          buildDockerCuda =
            let
              script = pkgs.writeShellScriptBin "build-docker-cuda" ''
                echo "Building Docker image for SD WebUI with CUDA support..."
                # Load the Docker image directly
                ${pkgs.docker}/bin/docker load < ${self.packages.${system}.dockerImageCuda}
                echo "CUDA-enabled Docker image built successfully! You can now run it with:"
                echo "docker run --gpus all -p 7860:7860 -v \$PWD/data:/data sd-webui:cuda"
                echo ""
                echo "Note: Requires nvidia-container-toolkit and Docker GPU support."
              '';
            in
            {
              type = "app";
              program = "${script}/bin/build-docker-cuda";
              meta = {
                description = "Build SD WebUI Docker image with CUDA support";
              };
            };

          # Update helper script
          update = {
            type = "app";
            program = toString (
              pkgs.writeShellScript "update-sd-webui" ''
                set -e
                echo "Fetching latest SD WebUI release..."
                LATEST=$(curl -s https://api.github.com/repos/AUTOMATIC1111/stable-diffusion-webui/releases/latest | ${pkgs.jq}/bin/jq -r '.tag_name')
                echo "Latest version: $LATEST"
                echo ""
                echo "To update, run: nix flake update sd-webui-src"
                echo "This will fetch the latest commit from GitHub."
              ''
            );
            meta = {
              description = "Check for SD WebUI updates";
            };
          };

          # Linting and formatting apps
          lint =
            let
              script = pkgs.writeShellScriptBin "lint" ''
                echo "Running ruff linter..."
                ${pkgs.ruff}/bin/ruff check --no-cache .
              '';
            in
            {
              type = "app";
              program = "${script}/bin/lint";
              meta = {
                description = "Run ruff linter on Python code";
              };
            };

          format =
            let
              script = pkgs.writeShellScriptBin "format" ''
                echo "Formatting code with ruff..."
                ${pkgs.ruff}/bin/ruff format --no-cache .
              '';
            in
            {
              type = "app";
              program = "${script}/bin/format";
              meta = {
                description = "Format Python code with ruff";
              };
            };

          lint-fix =
            let
              script = pkgs.writeShellScriptBin "lint-fix" ''
                echo "Running ruff linter with auto-fix..."
                ${pkgs.ruff}/bin/ruff check --no-cache --fix .
              '';
            in
            {
              type = "app";
              program = "${script}/bin/lint-fix";
              meta = {
                description = "Run ruff linter with auto-fix";
              };
            };

          type-check =
            let
              script = pkgs.writeShellScriptBin "type-check" ''
                echo "Running pyright type checker..."
                ${pkgs.pyright}/bin/pyright .
              '';
            in
            {
              type = "app";
              program = "${script}/bin/type-check";
              meta = {
                description = "Run pyright type checker on Python code";
              };
            };

          check-all =
            let
              script = pkgs.writeShellScriptBin "check-all" ''
                echo "Running all checks..."
                echo ""
                echo "==> Running ruff linter..."
                ${pkgs.ruff}/bin/ruff check --no-cache .
                RUFF_EXIT=$?
                echo ""
                echo "==> Running pyright type checker..."
                ${pkgs.pyright}/bin/pyright .
                PYRIGHT_EXIT=$?
                echo ""
                if [ $RUFF_EXIT -eq 0 ] && [ $PYRIGHT_EXIT -eq 0 ]; then
                  echo "All checks passed!"
                  exit 0
                else
                  echo "Some checks failed."
                  exit 1
                fi
              '';
            in
            {
              type = "app";
              program = "${script}/bin/check-all";
              meta = {
                description = "Run all Python code checks (ruff + pyright)";
              };
            };
        };

        # Define development shell
        devShells.default = pkgs.mkShell {
          packages = [
            pythonEnv
            pkgs.stdenv.cc
            pkgs.libGL
            pkgs.libGLU
            # Development tools
            pkgs.git
            pkgs.shellcheck
            pkgs.shfmt
            pkgs.nixfmt-rfc-style
            # Python linting and type checking
            pkgs.ruff
            pkgs.pyright
            # Utilities
            pkgs.jq
            pkgs.curl
          ]
          ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
            # macOS-specific tools
            pkgs.darwin.apple_sdk.frameworks.Metal
          ];

          shellHook = ''
            echo "Stable Diffusion WebUI development environment activated"
            echo "  SD WebUI version: ${sdWebuiVersion}"
            export SD_WEBUI_USER_DIR="$HOME/.config/sd-webui"
            mkdir -p "$SD_WEBUI_USER_DIR"
            echo "User data will be stored in $SD_WEBUI_USER_DIR"
            export PYTHONPATH="$PWD:$PYTHONPATH"
          '';
        };

        # Formatter for `nix fmt`
        formatter = pkgs.nixfmt-rfc-style;

        # Checks for CI (run with `nix flake check`)
        checks = {
          # Verify the package builds
          package = packages.default;

          # Shell script linting with cross-file analysis
          shellcheck =
            pkgs.runCommand "shellcheck"
              {
                nativeBuildInputs = [ pkgs.shellcheck ];
                src = ./.;
              }
              ''
                cp -r $src source
                chmod -R u+w source
                cd source/scripts
                # Check launcher.sh with -x to follow all source statements
                # This allows shellcheck to see variables defined in config.sh and used in install.sh
                shellcheck -x launcher.sh
                # Also check individual utility scripts
                shellcheck logger.sh runtime.sh persistence.sh
                touch $out
              '';

          # Nix formatting check
          nixfmt =
            pkgs.runCommand "nixfmt-check"
              {
                nativeBuildInputs = [ pkgs.nixfmt-rfc-style ];
                src = ./.;
              }
              ''
                cp -r $src source
                chmod -R u+w source
                cd source
                nixfmt --check flake.nix
                touch $out
              '';
        };
      }
    )
    // {
      # Overlay for integrating with other flakes
      overlays.default = final: prev: {
        sd-webui = self.packages.${final.system}.default;
      };
    };
}
