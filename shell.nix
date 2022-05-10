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
      rev = "ccece6a4889e15850dfbaf6d5170939c83edb103";
      sha256 = "1hx5k0l9gniz9aj9li8dkiniqs77pyfcl979y75yqm3mynrdz9ca";
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
    python3Packages.pip
    python3Packages.setuptools
    python3Packages.wheel
    s3cmd
    shfmt
    util-linux
  ];
}
