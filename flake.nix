{
  inputs = {
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      fenix,
      nixpkgs,
      flake-utils,
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

        nixosConfigurations.fern-worker = nixpkgs.lib.nixosSystem {
          system = "${system}";
          modules = [ 
            ./nixos/fern-worker.nix
            { nixpkgs.hostPlatform = system; }
          ];
          specialArgs = { inherit (self.packages.${system}) default; };
        };

        packages = {
          inherit (self.nixosConfigurations.${system}.fern-worker.config.system.build) image;
          run-image = pkgs.callPackage ./run-image.nix {
            inherit (self.nixosConfigurations.${system}.fern-worker.config.system.build) image;
          };
        };
      }
    );
}
