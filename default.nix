{ pkgs ? import <nixpkgs> {} }:

with pkgs;

buildEnv {
  name = "env";
  paths = [
    jdk11
    kind
    kubectl
    kustomize
    figlet
  ];
}