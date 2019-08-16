let
    nixpkgs = import <nixpkgs> {};
    nixpkgs32 = nixpkgs.pkgsi686Linux;
in nixpkgs32.stdenv.mkDerivation rec {
    name = "test";
    src = ./src;
    ldc2 = nixpkgs32.callPackage /etc/nixos/overlays/ldc {};
    dub = nixpkgs32.callPackage /etc/nixos/overlays/dub {};
    buildInputs = [ ldc2 dub ] ++ (with nixpkgs; [
        doxygen doxygen_gui git-lfs linuxPackages.perf plantuml
    ]) ++ (with nixpkgs32; [
        openssl
        zlib
    ]);
    buildPhase = ''
        ldc2 -unittest -g -oftest $(find -name \*.d)
    '';
    installPhase = ''
        mv test $out
    '';
}
