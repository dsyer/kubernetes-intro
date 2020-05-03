{ pkgs ? import <nixpkgs> {} }:

with pkgs;

let

  kindSetup = pkgs.writeShellScriptBin "kind-setup" "./.github/workflows/kind-setup.sh";

  skaffold = stdenv.mkDerivation {
    pname = "skaffold";
    version = "1.8.0";
    src = fetchurl {
      # nix-prefetch-url this URL to find the hash value
      url =
        "https://storage.googleapis.com/skaffold/releases/latest/skaffold-linux-amd64";
      sha256 = "01aznjv8m12znf5y4v6xfqax5sdw290yp28i7p49gvn5b0d61k7z";
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