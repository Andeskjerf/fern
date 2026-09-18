{
  inputs = {
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    appliance.url = "github:cleverca22/not-os";
    # NB: crane's flake has no inputs of its own; mkLib takes pkgs explicitly
    crane.url = "github:ipetkov/crane";
  };

  outputs =
    {
      self,
      crane,
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
        # crane splits dependency builds (cargoArtifacts) into their own
        # derivations, so crate-source edits only rebuild the crate
        craneLib = (crane.mkLib pkgs).overrideToolchain (p: buildToolchain);
        # static musl build for the image; packages.default stays dynamic for
        # dev. crane is bound to the cross pkgsStatic set so its cross env
        # wires CARGO_BUILD_TARGET / linker / cc vars from the musl stdenv
        # (aws-lc-sys + ring need a musl C toolchain); fenix provides the
        # musl std for the GNU-hosted rustc
        muslCraneLib = (crane.mkLib pkgs.pkgsStatic).overrideToolchain (
          p:
          fenix.packages.${system}.combine [
            buildToolchain
            fenix.packages.${system}.targets.x86_64-unknown-linux-musl.stable.rust-std
          ]
        );
        # cargo sources only: edits to nixos/, README, run-image.nix etc.
        # don't invalidate the Rust builds (the appliance/image code keeps
        # using unfiltered ./. paths, untouched)
        fernSrc = craneLib.cleanCargoSource ./.;
        fern-static = muslCraneLib.buildPackage {
          pname = "fern";
          version = "0.1.0";
          src = fernSrc;
          strictDeps = true;
          CARGO_PROFILE_RELEASE_LTO = "true";
          CARGO_PROFILE_RELEASE_CODEGEN_UNITS = "1";
          CARGO_PROFILE_RELEASE_OPT_LEVEL = "z";
          # appliance image: symbol table is dead weight in the squashfs;
          # cargo's -Cstrip=symbols leaves .symtab behind with musl+LTO, and
          # the cross stdenv ships no strip, so pull binutils in and strip
          # in postInstall
          nativeBuildInputs = [ pkgs.binutils ];
          postInstall = ''
            strip "$out/bin/fern"
          '';
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

        apps.fern-with-image = {
          type = "app";
          # fern only reads the image (uploads it to the provider), so the
          # read-only store path is enough; referencing it makes nix build
          # image-qcow2 before the app runs
          program = toString (
            pkgs.writeShellScriptBin "fern-with-image" ''
              exec ${self.packages.${system}.fern-static}/bin/fern \
                ${self.packages.${system}.image-qcow2}
            ''
          );
        };

        packages.default = craneLib.buildPackage {
          pname = "fern";
          version = "0.1.0";
          src = fernSrc;
          strictDeps = true;
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
