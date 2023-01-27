capacitorContext @ {
  lib,
  inputs,
}: {
  nixpkgs ? null,
  systems ? null,
  overlay ? null,
  flakePath ? [],
}:
# arguments to the flake
flakeArgs:
# flake function
mkFlake: let
  # args = inputs;
  # capacitate = lib.capacitor.capacitate;
  # self = capacitate.capacitate;
  # capacitorLib = inputs.self.lib.capacitor;
  # defaultPlugins = self.capacitor.plugins.importers.all;
  context = {
    # The final flake as seen by other flakes and the cli
    self = flakeArgs.self;

    /*
    Library functions from
    - nixpkgs.lib
    - capacitor.lib
    - [input <: all flake inputs | input.lib]

    Shared BY ALL PROTO-X in the same flake.
    */
    lib =
      lib
      // (builtins.mapAttrs (n: v: v.lib or {}) (context.inputs or {}))
      // {capacitor = inputs.self.lib.capacitor;};

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
    nixpkgs =
      if nixpkgs != null # passed by parent flake
      then nixpkgs
      else
        flakeArgs.nixpkgs # root flake's `nixpkgs` input
        or inputs.nixpkgs; # capacitor's `nixpkgs` input

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
    systems =
      if systems != null
      then systems
      else finalFlake.config.systems or ["aarch64-darwin" "aarch64-linux" "x86_64-darwin" "x86_64-linux"];

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
    overlay = system:
      if overlay != null
      then overlay system
      else lib.capacitor.plugins.compose.overlay context;

    /*
    The inputs as defined in the flakes `flake.nix`
    Includes `self` - a reference to the evalauted flake.
    */
    inputs = flakeArgs;

    /*
    The inputs as defined in the flakes `flake.nix`
    ! evaluated with the shared package set.

    Requires potential rebuilds of attributes that are originally built with
    a different set of packages.
    */
    capacitated =
      lib.mapAttrs (
        name: flake:
          if flake ? __reflect.recapacitate
          then
            flake.__reflect.recapacitate {
              inherit (context) systems nixpkgs;
              overlay =
                # TODO: pass overlay to all capacitated sources
                if (context.config.projects or {}) ? ${name}
                then context.overlay
                else null;
              flakePath = context.flakePath ++ [name];
            }
          else let
            flakePathStr = lib.showAttrPath context.flakePath;
          in
            throw "(${flakePathStr}): Input `${name}` is not a capacitated flake or uses an incompatible version of capacitor"
      )
      flakeArgs;

    # probably deprecated
    auto = lib.capacitor.capacitate.auto inputs;

    # internal
    config =
      {
        nixpkgs-config = {};
        projects = {};
      }
      // (finalFlake.config or {});

    /*
    The sequence fo flakes if transitively imported
    */
    # internal
    flakePath = flakePath;

    /*
    closures:: type -> [closure]

    function to list all closures of a `type`, e.g. `pacakges` or `lib`, ...
    */
    # internal
    closures = type: lib.flatten (map (lib.capacitor.capacitate.protoToClosure context) (lib.capacitor.capacitate.collectProtos (finalFlake.${type} or {})));

    /*
    A function to call files with `context`
    */
    callPackageWith = auto: fn: extra: lib.callPackageWith (context // auto) fn extra;

    # deprecated
    withRev = version:
      builtins.trace ''
        deprecation warning: please use `getRev` from `floxpkgs.lib`.
        Note that it expects src. Eg

            "0.0.0-$${getRev src}"
      ''
      "${version}-r${toString context.self.revCount or "dirty"}";

    /*
    context':: system -> specialized context

    Provides specialized versions of context items (if applicable)
    */
    context' = system: {
      system = system;
      nixpkgs = context.lib.callPackageWith {} context.nixpkgs {
        inherit system;
        config = context.config.nixpkgs-config;
        overlays = [(context.overlay system)];
      };
      self = lib.capacitor.capacitate.instantiate system flakeArgs.self;

      /*
      inputs as in `context` but with attributes for other systems removed

      context.inputs.<input>.<attribute>.<~~system~~>.*
      */
      # TODO: not recursive
      inputs = lib.mapAttrs (_: input: lib.capacitor.capacitate.instantiate system input) context.inputs;

      /*
      capacitated as in `context` but with attributes for other systems removed

      context.inputs.<input>.<attribute>.<~~system~~>.*
      */
      capacitated = lib.mapAttrs (_: input: lib.capacitor.capacitate.instantiate system input) context.capacitated;

      /*
      closures:: type -> [closure']

      function to list all closures of a `type`, e.g. `pacakges` or `lib`, ...
      that are defined for `system`
      */
      # TODO: does not work for systems other than the configured ones
      closures = type: lib.filter (c: c.system == system) (context.closures type);

      /*
      callPackage to call function with with instantiated nixpkgs and context
      */
      callPackageWith = auto: fn: extra: lib.callPackageWith ((context.context' system).nixpkgs // context // (context.context' system) // auto) fn extra;
    };
  };

  originalFlake = mkFlake context;
  finalFlake = context.self.__reflect.finalFlake;

  instantiatedPlugins = let
    updates =
      lib.concatMap (
        plugin: let
          pluginInputs = {
            inherit finalFlake originalFlake context;
          };
          outputs = plugin pluginInputs;
        in
          lib.flatten [outputs]
      ) (
        (
          if originalFlake ? config.plugins
          then originalFlake.config.plugins
          else inputs.self.defaultPlugins
        )
        ++ (
          if originalFlake ? config.extraPlugins
          then originalFlake.config.extraPlugins
          else []
        )
      );
  in
    lib.foldl'
    lib.recursiveUpdate
    {}
    ([
        ((originalFlake.passthru or {})
          // {
            protos = builtins.removeAttrs finalFlake ["config" "passthru"];
            __reflect = reflect;
          })
      ]
      ++ updates);

  reflect = lib.foldl' lib.recursiveUpdate (originalFlake.config or {}) [
    {
      # systems = self.systems;
      context = context;
      config = context.config;
      recapacitate = root-config: lib.capacitor.capacitate.capacitate root-config flakeArgs mkFlake;
    }
    {
      # Both originalFlake and final Flake refer to the flake definition passed to `capacitate`
      # `originalFlake` is the flake as initially passed in
      # `finalFlake` may be altered by a plugin to inject additional composed content
      #
      #  A plugin like this could inject a locally sourced lib tree:
      #
      #  (_: context: _: {
      #    path = ["__reflect" "finalFlake" "lib" "capacitor"];
      #    value = _: context.auto.localResourcesWith {root = root;} "lib" context "lib/";
      #  })
      #
      originalFlake = originalFlake;
      finalFlake = originalFlake;
    }
    {
      # deprecated: 01-19-23
      compose =
        lib.trace
        "warning: `__reflect.compose` is deprecated! Use capacitor#lib.capacitor.compose instead."
        lib.capacitor.compose;
    }
  ];
in
  instantiatedPlugins
