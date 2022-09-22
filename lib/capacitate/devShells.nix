{lib}:
let self = lib.capacitor.capacitate.devShells;
    materialize = lib.capacitor.capacitate.capacitate.materialize;
in
{
  devShellsMapper = {
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

  devShells = composed: let
    materialize' = materialize self.devShellsMapper;

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

  plugin = { capacitate, context, ... }:
    let generated = capacitate.composeSelfWith "devShells" {
        inherit (context.root.__reflect) systems;
        flakePath = [];
      };
    in
    {
      devShells = self.devShells (generated);
    };
}
