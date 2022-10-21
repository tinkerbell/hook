let _pkgs = import <nixpkgs> { };
in { pkgs ? import (_pkgs.fetchFromGitHub {
  owner = "NixOS";
  repo = "nixpkgs";
  #branch@date: nixpkgs-unstable@2022-05-09
  rev = "51d859cdab1ef58755bd342d45352fc607f5e59b";
  sha256 = "02wi4nll9ninm3szny31r5a40lpg8vgmqr2n87gxyysb50c17w4i";
}) { } }:

with pkgs;
let
  docker-ov = docker.override { buildxSupport = true; };

  linuxkit-ov = linuxkit.overrideAttrs (oldAttrs: rec {
    version = "unstable-g${builtins.substring 0 9 src.rev}";
    src = fetchFromGitHub {
      owner = "linuxkit";
      repo = "linuxkit";
      rev = "b710224cdf9a8425a7129cdcb84fc1af00f926d7";
      sha256 = "sha256-UqPX+r3by7v+PL+/xUiSZVsB7EO7VUr3aDfVIhQDEgY=";
    };
  });

in mkShell {
  buildInputs = [
    docker-ov
    git
    gnumake
    gnused
    go
    linuxkit-ov
    ncurses
    nixfmt
    nodePackages.prettier
    pigz
    python3Packages.pip
    python3Packages.setuptools
    python3Packages.wheel
    shfmt
    util-linux
  ];
}
