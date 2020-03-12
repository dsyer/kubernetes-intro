with import <nixpkgs> {};
stdenv.mkDerivation {
  name = "env";
  buildInputs = [
    jdk11
    kind
    kubectl
    kustomize
    figlet
  ];
  shellHook = ''
    figlet ":smile:"
   ./.github/workflows/kind-setup.sh
   kubectl get all
'';
} 