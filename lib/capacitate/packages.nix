{lib}: let
  self = lib.self.capacitor.capacitate.packages;
  materialize = lib.capacitor.capacitate.capacitate.materialize;
in {
  packagesMapper = context: {
    namespace,
    # innerPath,
    fn,
    system,
    ...
  }: let
    # slashSeparated = lib.removeSuffix "/default" (lib.concatStringsSep "/" namespace);
    path = [system] ++ namespace;
    pkgs = (context.context' system).nixpkgs;
    value = lib.getAttrFromPath namespace pkgs;
  in {inherit path value;};

  plugin = {context, ...}: let
    projects = lib.mapAttrsToList (_: child: child.__reflect.context.closures "packages") context.config.projects or {};
    own = context.closures "packages";
  in {
    packages = materialize (self.packagesMapper context) (lib.flatten (projects ++ [own]));
  };
}
