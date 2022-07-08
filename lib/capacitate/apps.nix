{lib}:
let self = lib.capacitor.capacitate.apps;
    materialize = lib.capacitor.capacitate.capacitate.materialize;
in
{
  appsMapper = {
    isCapacitated,
    namespace,
    flakePath,
    value,
    system,
    ...
  }: let
    attrPath = lib.flatten [system flakePath namespace];
  in {
    value = value;
    path = attrPath;

    use = isCapacitated;
  };

  apps = composed: let
    materialize' = materialize self.appsMapper;

    joinProjects = self': children: adopted: let
      children' =
        lib.mapAttrs (
          _: child:
            joinProjects child.self child.children child.adopted
        )
        children;

      adopted' = lib.mapAttrs (_: materialize') adopted;

      merged =
        lib.foldl'
        lib.recursiveUpdate
        (materialize' self')
        (lib.flatten [(lib.attrValues children') (lib.attrValues adopted')]);
    in
      merged;
  in
     joinProjects composed.self composed.children composed.adopted;

  plugin = { context, capacitate,... }:
    let generated = capacitate.composeSelfWith "apps" {
        inherit (context) systems;
        stabilities = ["default"];
        flakePath = [];
      };
    in
    {
      apps = self.apps (generated);
    };

}
