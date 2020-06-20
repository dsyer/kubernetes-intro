{ pkgs ? import <nixpkgs> {} }:

with pkgs;

let

  kindSetup = pkgs.writeShellScriptBin "kind-setup" "./.github/workflows/kind-setup.sh";

  skaffold = stdenv.mkDerivation {
    pname = "skaffold";
    version = "1.11.0";
    src = fetchurl {
      # nix-prefetch-url this URL to find the hash value
      url =
        "https://storage.googleapis.com/skaffold/releases/v1.11.0/skaffold-linux-amd64";
      sha256 = "0r7r505r1zyqqfid4s6wd6mpi01bksazri094h8p9nmqhk4xa8yb";
    };
    phases = [ "installPhase" "patchPhase" ];
    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/skaffold
    '';
    patchPhase = ''
      chmod +x $out/bin/skaffold
    '';
  };

in buildEnv {
  name = "env";
  paths = [
    jdk11
    apacheHttpd
    kind
    kubectl
    kustomize
    skaffold
    kindSetup
  ];
}