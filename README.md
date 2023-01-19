# Flox Capacitor

*Supercharge Flakes*

Capacitor implements an extensible interface for defining and managing flake outputs.

## Motivation

Nix flakes make it easy to create self-contained micro package sets with a common structure and interface.
However, being self-contained imposes limitations to the way flakes can be composed together.
As flakes grow by the number of packages,
they often become more difficult to reason about--especially for Nix newcomers--
and harder to refactor.

While flakes allow one to share package sets by overwriting inputs,
it is both easy to miss overrides and near impossible to share customizations to e.g. nixpkgs.
For example, assume one package set redefines `openssl` by applying a security patch
-- with Nix flakes, even sharing the nixpkgs input won't propagate the change to all packages in the set.
Nix allows such modifications using overlays but does little to ensure multiple overlays do not overlap.

Capacitor tries to solve these issues from the start;
you write simple, single files for packages and Capacitor will automatically import
and compose them across your project - requiring zero additional configuration.
Capacitor is designed to do all this for you:
- combine multiple independent package sets (e.g. projects, or groups of projects)
- merge all package sets recursively into a single unified package set
- detect and expose conflicts rather than ignore and override them

## Terminology

- **Proto-{Derivation,App,...}**
  A function that produces an element of some kind.
  An example of well known proto-derivations are derivations defined in nixpkgs

  ```nix
    {pkgs}:
    let
        # ...
    in
    pkgs.stdenv.mkDerivation {
        # ...
    }
  ```
  Capacitor expects flake outputs to be defined as proto-\* and manages the calling and composition of these functions.
  (see: [Proto functions](./docs/proto-x.md))

- **(to) capacitate**
  Capacitor produces a flake output from a given configuration.
  The impact to the structure of the flake is meant to be as small as possible; a minimal capacitated flake looks like this:

  ```nix 
  {
    outputs = { capacitor, ... } @ args: capacitor args (context: {
        packages.default = {pkgs,...}: pkgs.rustPlatform.buildRustPackage { /* ... */ };
    });
  }
  ```

  which is equivalent to:

  ```nix
  {
    outputs = { nixpkgs, ... }: {
        packages = nixpkgs.lib.genAttrs (system:
            let pkgs = nixpkgs.legacyPackages.${system};
            in
            {
                default = pkgs.rustPlatform.buildRustPackage { /* ... */ };
            }) [ /* systems */ ]
    };
  }
  ```

  (see: [lib](./docs/lib))

- **Plugin**
  Plugins define the structure of the final flake.
  In fact, capacitating a flake merely invokes builtin plugins.
  A plugin is itself another proto-function which receives a plugin context and returns a record.
  The output of all plugins is recursively merged to form the final output.
  In a way plugins are similar to `nixos-modules` stripped of its type system implementation.

  By default, capacitor ships with plugins to

  1. generate `packages`, `legacyPackages` (nested packages), `apps`, `devShells` and `lib` attributes
  2. import proto-* for any of the above from a given folder
  3. expose templates

  (see: [plugins](./docs/plugins.md))
