with import <nixpkgs> { };
let
  extensions = vscode-utils.extensionsFromVscodeMarketplace
    (import ./nix/extensions.nix).extensions;
  vscode-with-extensions =
    pkgs.vscode-with-extensions.override { vscodeExtensions = extensions; };
in mkShell {
  name = "env";
  buildInputs = [
    (import ./default.nix { inherit pkgs; })
    figlet
    vscode-with-extensions
  ];
  shellHook = ''
    figlet ":smile:"
    kind-setup
    kubectl get all
  '';
}
