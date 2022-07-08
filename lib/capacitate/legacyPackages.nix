{lib}:

let self = lib.capacitor.capacitate.legacyPackages;
    materialize = lib.capacitor.capacitate.capacitate.materialize;
    composeSelf = lib.capacitor.capacitate.capacitate.composeSelf;
in

{
    legacyPackagesMapper = {
      namespace,
      outerPath,
      # innerPath,
      # packageSet ? null,
      value,
      system,
      stability,
      ...
    }: let
      path = lib.flatten [system stability namespace];
    in {
      # use = stability == "default";
      path = path;
      value = value;
    };


    legacyPackages = systems: stabilities: generated: let
      materialize' = materialize self.legacyPackagesMapper;
      joinProjects = self: children: adopted:
        lib.genAttrs systems (
          system:
            lib.genAttrs stabilities (
              stability: let
                self' = materialize' self;

                children' =
                  lib.mapAttrs (
                    _: c: (joinProjects c.self c.children c.adopted).${system}.${stability}
                  )
                  children;

                adopted' =
                  lib.mapAttrs (
                    n: a: let
                      materialized = materialize' a;
                    in
                      if materialized ? ${system}.${stability}.${n}
                      then materialized.${system}.${stability}.${n}
                      else {}
                  )
                  adopted;

                defs =
                  if self' ? ${system}.${stability}
                  then self'.${system}.${stability}
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
            )
        );
    in
      joinProjects generated.self generated.children generated.adopted;

    plugin = { context,  capacitate, ... }:
    
       
        {
         "legacyPackages" = self.legacyPackages context.systems context.stabilities (capacitate.composeSelf "packages");
        };
  

}
