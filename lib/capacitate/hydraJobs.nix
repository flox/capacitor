{lib}: let
  materialize = lib.capacitor.capacitate.materialize;

  libMapper = context: {
    namespace,
    system,
    fn,
    ...
  }: let
    attrPath = lib.flatten [namespace system];
    pkgs = (context.context' system).nixpkgs;
    package = lib.getAttrFromPath namespace pkgs;
  in {
    value = lib.hydraJob package;
    path = attrPath;
  };
in {
  plugin = {context, ...}: let
    materialize' = materialize (libMapper context);
    own = materialize' (context.closures "packages");
    projects = lib.mapAttrs (_: child: child.hydraJobs or {}) context.config.projects;
    composed = projects // own;
  in {
    hydraJobs = composed;
  };
}
