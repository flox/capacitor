{lib, ...}: let
  materialize = lib.capacitor.capacitate.materialize;

  genericImport = type: let
    mapper = context: {
      namespace,
      fn,
      system ? null,
      ...
    }: let
      path = (lib.optionals (system != null) [system]) ++ namespace;
      pkgs = context.context' system;
      value = pkgs.callPackageWith {} fn {}; # call closure with combined nixpkgs
    in {inherit path value;};

    plugin = {context, ...}: let
      projects = lib.mapAttrs (_: child: child."${type}" or {}) context.config.projects;
      own = context.closures "${type}";
    in {
      "${type}" = projects // (materialize (mapper context) own);
    };
  in
    plugin;
in
  genericImport
