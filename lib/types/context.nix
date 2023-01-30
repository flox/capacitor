ctx @ {
  # The final flake as seen by other flakes and the cli
  self,
  /*
  Library functions from
  - nixpkgs.lib
  - capacitor.lib
  - [input <: all flake inputs | input.lib]

  Shared BY ALL PROTO-X in the same flake.
  */
  lib,
  /*
  The nixpkgs pacakge set.
  This is the base package set, from which all packages shall base upon.

  This value is shared BY ALL FLAKES,
  either included via `config.projects` or `context.capacitated.*`

  If the root flake defines `nixpkgs` explicitly, this set is used.
  Otherwise, the `nixpkgs` input of capacitor is used.

  Note: if used through floxpkgs, floxpkgs takes responsibility
        to the correct nixpkgs
  */
  nixpkgs,
  /*
  The systems that all packages will be provided for.

  Can be overridden through

  ```nix
  # file: flake.nix
  capacitor args (context: {
    config.systems = [ <systems> ... ];
  })
  ```

  in the _root flake's_ definition.

  This value is shared BY ALL FLAKES,
  */
  systems,
  /*
  An automatically managed overlay applied on top of nixpkgs to provide a
  single package set namespace.
  Combines the package sets of all imported flakes.

  Flakes can be imported through

  ```nix
  # file: flake.nix
  capacitor args (context: {
    config.projects = {
      inherit (context.inputs) my-flake;
    };
  })
  ```

  Transitive imports are included recursively.
  */
  # overlay is null for the root flake
  # the root flake uses compose to flatten the input graph
  # this produces an overlay that is passed to the children via the context
  overlay,
  /*
  The inputs as defined in the flakes `flake.nix`
  Includes `self` - a reference to the evalauted flake.
  */
  inputs,
  /*
  The inputs as defined in the flakes `flake.nix`
  ! evaluated with the shared package set.

  Requires potential rebuilds of attributes that are originally built with
  a different set of packages.
  */
  capacitated,
  # probably deprecated
  auto,
  # internal
  config,
  /*
  The sequence fo flakes if transitively imported
  */
  # internal
  flakePath,
  /*
  closures:: type -> [closure]

  function to list all closures of a `type`, e.g. `pacakges` or `lib`, ...
  */
  # internal
  closures,
  /*
  A function to call files with `context`
  */
  callPackageWith,
  # deprecated
  withRev,
  /*
  context':: system -> specialized context

  Provides specialized versions of context items (if applicable)
  */
  context',
  /*
  The `context` itself

  Useful when specializing the context with

  ```nix
  context // (context.context' system)
  ```

  to retrieve back unspecialized values
  */
  context,
}:
ctx
