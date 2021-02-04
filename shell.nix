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

  manifest-tool = pkgs.buildGoModule rec {
    pname = "manifest-tool";
    version = "unstable-${builtins.substring 0 9 src.rev}";
    src = pkgs.fetchFromGitHub {
      owner = "estesp";
      repo = "manifest-tool";
      rev = "2d360eeba276afaf63ab22270b7c6b4f8447e261";
      sha256 = "1895hj6r10cd865vnpfj0v6r26x0ywlwlc2ygimg8a2cwi7q5h99";
    };
    subPackages = [ "cmd/manifest-tool" ];
    buildFlagsArray = [ "-ldflags=-X main.gitCommit=${version}" ];
    vendorSha256 = null;
    CGO_ENABLED = 0;
  };

  linuxkit = buildGoPackage rec {
    pname = "linuxkit";
    version = "1ec1768d18ad7a5cd2d6e5c2125a14324ff6f57f";

    goPackagePath = "github.com/linuxkit/linuxkit";

    src = fetchFromGitHub {
      owner = "linuxkit";
      repo = "linuxkit";
      rev = "1ec1768d18ad7a5cd2d6e5c2125a14324ff6f57f";
      sha256 = "09qap7bfssbbqhrvjqpplahpldci956lbfdwxy9nwzml3aw18r42";
    };

    subPackages = [ "src/cmd/linuxkit" ];

    buildFlagsArray = [ "-ldflags=-s -w -X ${goPackagePath}/src/cmd/linuxkit/version.GitCommit=${src.rev} -X ${goPackagePath}/src/cmd/linuxkit/version.Version=${version}" ];

    meta = with lib; {
      description = "A toolkit for building secure, portable and lean operating systems for containers";
      license = licenses.asl20;
      homepage = "https://github.com/linuxkit/linuxkit";
      maintainers = [ maintainers.nicknovitski ];
      platforms = platforms.unix;
    };
  };
in
mkShell {
  buildInputs = [
    git
    linuxkit
    s3cmd
    docker-ov
    manifest-tool
  ];
  shellHook =
    ''
    '';
}
