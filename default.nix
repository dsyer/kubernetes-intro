{ pkgs ? import <nixpkgs> {} }:

with pkgs;

let

  kindSetup = pkgs.writeShellScriptBin "kind-setup" "./.github/workflows/kind-setup.sh";

in buildEnv {
  name = "env";
  paths = [
    jdk11
    kind
    kubectl
    kustomize
    kindSetup
  ];
}