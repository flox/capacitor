{lib}:

let self = lib.capacitor.capacitate.packages;
    materialize = lib.capacitor.capacitate.capacitate.materialize;
    composeSelf = lib.capacitor.capacitate.capacitate.composeSelf;
in {


  packagesMapper = {
      namespace,
      # innerPath,
      value,
      system,
      stability,
      ...
    }: let
      # use = stability == "default";
      slashSeparated = lib.removeSuffix "/default" (lib.concatStringsSep "/" namespace);
      path = [system slashSeparated];
    in {inherit path value;};

    packages = materialize self.packagesMapper;

    plugin = { context, capacitate, ... }:
    let generated = capacitate.composeSelfWith "packages" {
        inherit (context.root.__reflect) systems;
        stabilities = ["default"];
        flakePath = [];
      };
    in
    {
      packages = self.packages generated.self;
    };
}
