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
        # appliance scaffold; it keeps its own nixpkgs pin because its modules
        # use lib.literalExample, dropped from this flake's nixos-unstable pin
        applianceConfig =
          (import "${appliance}/default.nix" {
            nixpkgs = "${appliance.inputs.nixpkgs}";
            system = "x86_64-linux";
            configuration = import ./nixos/fern.nix {
              fern = self.packages.${system}.default;
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
          image = pkgs.callPackage ./nixos/disk-image.nix {
            inherit (applianceConfig.system.build) kernel initialRamdisk squashfs;
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
            initrd = self.packages.${system}.image.passthru.initialRamdisk;
          };
        };
      }
    );
}
