{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-filter.url = "github:numtide/nix-filter";
    crane.url = "github:ipetkov/crane";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = {
    nixpkgs,
    crane,
    rust-overlay,
    nix-filter,
    ...
  }: let
    supportedSystems = [
      "x86_64-linux"
      "x86_64-darwin"
      "aarch64-linux"
      "aarch64-darwin"
    ];
    lib = nixpkgs.lib;
    overlays = [(import rust-overlay)];
    filter = import nix-filter;
    eachSystem = lib.genAttrs supportedSystems;

    # Release builds get their version from the tag: the release workflow
    # rewrites ./VERSION before `nix build`. Keeping it out of the crane source
    # filter below means a new version does not invalidate cargoArtifacts.
    version = lib.head (lib.splitString "\n" (builtins.readFile ./VERSION));

    toolchainFor = pkgs:
      pkgs.rust-bin.nightly.latest.minimal.override {
        extensions = ["clippy" "rust-src"];
      };
  in {
    packages = eachSystem (system: let
      pkgs = import nixpkgs {inherit system overlays;};
      craneLib = (crane.mkLib pkgs).overrideToolchain (toolchainFor pkgs);
      src = filter {
        root = ./.;
        include = [
          "src"
          "build.rs"
          "Cargo.toml"
          "Cargo.lock"
        ];
      };
      craneArgs = {
        inherit src;
        strictDeps = true;
        SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      };
      cargoArtifacts = craneLib.buildDepsOnly craneArgs;
    in {
      default = craneLib.buildPackage (craneArgs
        // {
          inherit cargoArtifacts version;
          pname = "brainpod-cli";
          BRAINPOD_VERSION = version;
          meta.mainProgram = "brainpod";
        });
    });

    devShells = eachSystem (system: let
      pkgs = import nixpkgs {inherit system overlays;};
      craneLib = (crane.mkLib pkgs).overrideToolchain (toolchainFor pkgs);
    in {
      default = craneLib.devShell {
        packages = with pkgs; [
          rustfmt
          rust-analyzer
        ];
      };
    });
  };
}
