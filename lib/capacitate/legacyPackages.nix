{lib}: let
  self = lib.capacitor.capacitate.legacyPackages;
  materialize = lib.capacitor.capacitate.materialize;
  composeSelf = lib.capacitor.capacitate.composeSelf;
in {
  legacyPackagesMapper = {
    namespace,
    value,
    system,
    ...
  }: let
    path = lib.flatten [system namespace];
  in {
    path = path;
    value = value;
  };

  legacyPackages = systems: generated: let
    materialize' = materialize self.legacyPackagesMapper;
    joinProjects = self: children: adopted:
      lib.genAttrs systems (
        system: let
          self' = materialize' self;

          children' =
            lib.mapAttrs (
              _: c: (joinProjects c.self c.children c.adopted).${system}
            )
            children;

          adopted' =
            lib.mapAttrs (
              n: a: let
                materialized = materialize' a;
              in
                if materialized ? ${system}.${n}
                then materialized.${system}.${n}
                else {}
            )
            adopted;

          defs =
            if self' ? ${system}
            then self'.${system}
            else {};
        in
          (
            lib.foldl' lib.recursiveUpdate {} [
              adopted'
              defs
              children'
            ]
          )
          // {
            __adopted = adopted';
            __projects = children';
            __self = defs;
          }
      );
  in
    joinProjects generated.self generated.children generated.adopted;

  plugin = {context, ...}: {
    #  "legacyPackages" = self.legacyPackages context.systems (capacitate.composeSelf "packages");
  };
}
