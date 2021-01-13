let _pkgs = import <nixpkgs> { };
in
{ pkgs ?
  import
    (_pkgs.fetchFromGitHub {
      owner = "NixOS";
      repo = "nixpkgs-channels";
      #branch@date: nixpkgs-unstable@2020-09-11
      rev = "6d4b93323e7f78121f8d6db6c59f3889aa1dd931";
      sha256 = "0g2j41cx2w2an5d9kkqvgmada7ssdxqz1zvjd7hi5vif8ag0v5la";
    }) { }
}:
with pkgs;
let
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
  ];
  shellHook =
    ''
    '';
}
