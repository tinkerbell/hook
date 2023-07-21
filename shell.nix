let _pkgs = import <nixpkgs> { };
in { pkgs ? import (_pkgs.fetchFromGitHub {
  owner = "NixOS";
  repo = "nixpkgs";
  #branch@date: nixpkgs-unstable@2023-03-11T16:44:21-05:00
  rev = "8ad5e8132c5dcf977e308e7bf5517cc6cc0bf7d8";
  sha256 = "17v6wigks04x1d63a2wcd7cc4z9ca6qr0f4xvw1pdw83f8a3c0nj";
}) { } }:

with pkgs;
let

in mkShell {
  buildInputs = [
    docker
    git
    gnumake
    gnused
    go
    linuxkit
    ncurses
    nixfmt
    nodePackages.prettier
    pigz
    python3Packages.pip
    python3Packages.setuptools
    python3Packages.wheel
    shfmt
    util-linux
    curl
  ];
}
