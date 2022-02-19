let _pkgs = import <nixpkgs> { };
in
{ pkgs ?
  import
    (_pkgs.fetchFromGitHub {
      owner = "NixOS";
      repo = "nixpkgs";
      #branch@date: nixpkgs-unstable@2021-01-25
      rev = "ce7b327a52d1b82f82ae061754545b1c54b06c66";
      sha256 = "1rc4if8nmy9lrig0ddihdwpzg2s8y36vf20hfywb8hph5hpsg4vj";
    }) { }
}:

with pkgs;
let
  docker-ov = docker.override {
    buildxSupport = true;
  };

  linuxkit-ov = linuxkit.overrideAttrs (oldAttrs: rec {
    version = "unstable-g${builtins.substring 0 9 src.rev}";
    src = fetchFromGitHub {
      owner = "linuxkit";
      repo = "linuxkit";
      rev = "ccece6a4889e15850dfbaf6d5170939c83edb103";
      sha256 = "1hx5k0l9gniz9aj9li8dkiniqs77pyfcl979y75yqm3mynrdz9ca";
    };
  });
in
mkShell {
  buildInputs = [
    docker-ov
    git
    gnumake
    gnused
    linuxkit-ov
    ncurses
    s3cmd
    util-linux
  ];
}
