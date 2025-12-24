# templates/python-project/flake.nix
{
  description = "Python project using laingville infrastructure";

  inputs = {
    infra.url = "github:mrdavidlaing/laingville-devcontainer-nix";
    nixpkgs.follows = "infra/nixpkgs";  # Critical for layer sharing!
  };

  outputs = { self, infra, nixpkgs }:
    let
      system = "x86_64-linux";
      sets = infra.packageSets.${system};
      lib = infra.lib.${system};
    in
    {
      # DevShell for local development (nix develop)
      devShells.${system}.default = infra.devShells.${system}.python;

      # Container images (built by CI, pushed to registry)
      packages.${system} = {
        devcontainer = lib.mkDevContainer {
          name = "ghcr.io/my-org/my-project/devcontainer";
          packages = sets.base ++ sets.nixTools ++ sets.devTools
                  ++ sets.python ++ sets.pythonDev;
        };

        runtime = lib.mkRuntime {
          name = "ghcr.io/my-org/my-project/runtime";
          packages = sets.base ++ sets.python;
        };
      };
    };
}
