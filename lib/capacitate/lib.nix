{lib}: let
  materialize = lib.capacitor.capacitate.capacitate.materialize;

  libMapper = context: {
    namespace,
    flakePath,
    fn,
    ...
  }: let
    attrPath = lib.flatten [namespace];
  in {
    value = context.callPackageWith {} fn {};
    path = attrPath;
  };
in {
  plugin = {context, ...}: let
    materialize' = materialize (libMapper context);
    own = materialize' (context.closures "lib");
    projects = lib.mapAttrs (_: child: child.lib) context.config.projects;
    composed = projects // own;
  in {
    lib = composed;
  };
}
