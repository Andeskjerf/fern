# Useful commands to debug & work with the worker NixOS images

## Checking the size of an image

We can check the size of them by doing the following

```sh
du -sh $(nix -L build .#image --print-out-paths)/image.raw
354M    .
```

# Tracking down dependencies and how they are set

Using the following command, we get a list of ALL (transitive) dependencies for a build. This can be expanded later to also show the size of each dependency, and what adds it.

```sh
nix-store --query --requisites $(nix build --print-out-paths .#nixosConfigurations.x86_64-linux.fern-worker.config.system.build.toplevel)
```

Using the `nix-store` command, we can get even more detailed information about each of these dependencies

```sh
nix-store --query --requisites \
  $(nix build --print-out-paths .#nixosConfigurations.x86_64-linux.fern-worker.config.system.build.toplevel) \
  | xargs du -sm | sort -n | tail -n 10

```

`nix why-depends` gives us a nice dependency tree of why a certain thing is pulled in by a dependency. By pointing the command at a store path, we get to see the tree!

```sh
nix why-depends \
  $(nix build --print-out-paths .#nixosConfigurations.x86_64-linux.fern-worker.config.system.build.toplevel) \
  /nix/store/589lm73dyk97hjibk8yv62yvaci0vqaj-source
/nix/store/4dwqk8vcvx6plkli7mrh7zyfwrx7xysx-nixos-system-fern-worker-26.11.20260904.801bef6
└───/nix/store/ql5vzmay5v2ci4qrv8v3zqfjx9bqfpn1-etc
    └───/nix/store/ajwvin7cj01rvzsarhl4ik0fn67ny8vp-system-units
        └───/nix/store/prc6hphgahp9v10z70wlm3zsi419jyxg-unit-growpart.service
            └───/nix/store/1kn2s0chs4k7c8b4qmy13grxdqlq4jh1-unit-script-growpart-start
                └───/nix/store/7p8rfcnd17kmarapb9nrvr6i17mgvy71-cloud-utils-0.33-guest
                    └───/nix/store/b5bpi6zfajzzrwwpgba2q6li3nnya4bs-python3-3.14.7
```

We can then look in the `nixpkgs` repo to see why that dependency is pulled in

```sh
cd ~/src/nixpkgs
cd nixos/modules
git grep cloud-utils
system/boot/grow-partition.nix:        "${pkgs.cloud-utils.guest}/bin/growpart" "$parentDevice" "$partNum"
virtualisation/azure-image.nix:        ${lib.getExe' pkgs.cloud-utils "growpart"} "$out/${config.image.fileName}" 1...
```

To figure out if the attribute is set or not, we can use `nix repl`

```sh
nix repl
nix-repl> :lf .
nix-repl> nixosConfigurations.<name>.config.boot.growPartition
true
```

This only tells us that is set, but not by what. To do that, we can use `definitionsWithLocations`

```sh
``nix-repl> :p nixosConfigurations.<name>.options.boot.growPartition.definitionsWithLocations
[
  {
    file = "/nix/store/xl24m105dhi3p265yazyxmcn2dpraw4p-source/nixos/fern-worker.nix";
    value = true;
  }
]`
