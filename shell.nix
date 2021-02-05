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

  linuxkit = buildGoPackage rec {
    pname = "linuxkit";
    version = "4cdf6bc56dd43227d5601218eaccf53479c765b9";

    goPackagePath = "github.com/linuxkit/linuxkit";

    src = fetchFromGitHub {
      owner = "linuxkit";
      repo = "linuxkit";
      rev = "4cdf6bc56dd43227d5601218eaccf53479c765b9";
      sha256 = "1w4ly0i8mx7p5a3y25ml6j4vxz42vdcacx0fbv23najcz7qh3810";
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
  ];
  shellHook =
    ''
    '';
}
