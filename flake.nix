{
  description = "Automatic recursive function transformer";

  inputs = {
    opam-nix.url = "github:tweag/opam-nix";
    nixpkgs.follows = "opam-nix/nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    opam-nix,
  }: let
    systems = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];

    forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
  in {
    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (opam-nix.lib.${system}) buildDuneProject;
      projectName = "Synduce";

      project =
        (buildDuneProject {} projectName ./. {
          ocaml-base-compiler = "*";
        })
        .${projectName};
    in {
      ${projectName} = project.overrideAttrs (final: prev: {
        preConfigure = ''
          mkdir -p $out
          cp -r $src/src $out

          bin_path_src_path=$PWD/src/utils/DepPath.ml
          rm $bin_path_src_path || true
          touch $bin_path_src_path

          echo "let cvc4_binary_path = Some(\"${pkgs.cvc4}/bin/cvc4\")" >> $bin_path_src_path
          echo "let cvc5_binary_path = Some(\"${pkgs.cvc5}/bin/cvc5\")" >> $bin_path_src_path
          echo "let z3_binary_path = \"${pkgs.z3}/bin/z3\"" >> $bin_path_src_path
        '';
      });
      default = self.packages.${system}.${projectName};
    });

    devShells = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      projectName = "Synduce";
    in {
      default = pkgs.mkShell {
        inputsFrom = [self.packages.${system}.${projectName}];

        packages = with pkgs; [python311]
          ++ lib.optionals stdenv.isDarwin [
            darwin.apple_sdk.frameworks.CoreServices
          ];

        shellHook = ''
          # opam init -n && eval $(opam env)
          # opam option --global depext=false

          # raco pkg install rosette
          # raco pkg install src/synthools

          # mkdir -p ~/.local/share/racket/8.10/pkgs/rosette/bin/
          # ln -s ${pkgs.z3}/bin/z3 ~/.local/share/racket/8.10/pkgs/rosette/bin/z3
        '';
      };
    });
  };
}
