{
  inputs = {
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    appliance.url = "github:cleverca22/not-os";
  };

  outputs =
    {
      self,
      fenix,
      nixpkgs,
      flake-utils,
      appliance,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        devToolchain = fenix.packages.${system}.stable.withComponents [
          "cargo"
          "clippy"
          "rust-src"
          "rustc"
          "rustfmt"
          "rust-analyzer"
        ];
        buildToolchain = fenix.packages.${system}.stable.minimalToolchain;
        rustPlatform = pkgs.makeRustPlatform {
          cargo = buildToolchain;
          rustc = buildToolchain;
        };
        # static musl build for the image; packages.default stays dynamic for dev.
        # fenix provides the musl std for the GNU-hosted rustc; the cross pkgs'
        # musl stdenv supplies the linker (hooks inject --target from the
        # stdenv target platform, env overrides don't stick)
        muslRustPlatform = pkgs.pkgsStatic.makeRustPlatform {
          cargo = fenix.packages.${system}.combine [
            buildToolchain
            fenix.packages.${system}.targets.x86_64-unknown-linux-musl.stable.rust-std
          ];
          rustc = fenix.packages.${system}.combine [
            buildToolchain
            fenix.packages.${system}.targets.x86_64-unknown-linux-musl.stable.rust-std
          ];
        };
        fern-static = muslRustPlatform.buildRustPackage {
          pname = "fern";
          version = "0.1.0";
          src = ./.;
          cargoLock.lockFile = ./Cargo.lock;
          CARGO_PROFILE_RELEASE_LTO = "true";
          CARGO_PROFILE_RELEASE_CODEGEN_UNITS = "1";
          CARGO_PROFILE_RELEASE_OPT_LEVEL = "z";
        };
        # appliance scaffold; it keeps its own nixpkgs pin because its modules
        # use lib.literalExample, dropped from this flake's nixos-unstable pin.
        # the pin is patched to drop util-linux/shadow from the activation
        # PATH (the only place util-linux-bin was referenced at all)
        applianceNixpkgs = pkgs.applyPatches {
          name = "appliance-nixpkgs";
          src = appliance.inputs.nixpkgs;
          patches = [ ./nixos/appliance-activation-path.patch ];
        };
        applianceConfig =
          (import "${appliance}/default.nix" {
            nixpkgs = "${applianceNixpkgs}";
            system = "x86_64-linux";
            configuration = import ./nixos/fern.nix {
              fern = self.packages.${system}.fern-static;
              # needed to reuse the appliance's stage-2-init.sh (bootStage2
              # is re-generated with a busybox sh shebang)
              appliance = appliance;
            };
          }).config;
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [ devToolchain ];
        };

        packages.default = rustPlatform.buildRustPackage {
          pname = "fern";
          version = "0.1.0";
          src = ./.;
          cargoLock.lockFile = ./Cargo.lock;
        };

        packages = {
          inherit fern-static;
          image = pkgs.callPackage ./nixos/disk-image.nix {
            inherit (applianceConfig.system.build) kernel squashfs;
            kernelParams = toString applianceConfig.boot.kernelParams;
          };
          image-qcow2 = pkgs.runCommand "fern-image.qcow2" { } ''
            ${pkgs.qemu-utils}/bin/qemu-img convert -f raw -O qcow2 -c \
              ${self.packages.${system}.image} $out
          '';
          run-image = pkgs.callPackage ./run-image.nix {
            inherit (self.packages.${system}.image.passthru)
              kernel
              squashfs
              kernelParams
              ;
          };
        };
      }
    );
}
