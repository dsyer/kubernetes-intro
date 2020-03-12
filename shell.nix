with import <nixpkgs> {};
pkgs.mkShell {
  name = "env";
  buildInputs = [ (import ./default.nix { inherit pkgs; }) ];
  shellHook = ''
    figlet ":smile:"
    ./.github/workflows/kind-setup.sh
    kubectl get all
'';
} 