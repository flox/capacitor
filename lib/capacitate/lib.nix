{lib}:
let self = lib.capacitor.capacitate.lib;
    materialize = lib.capacitor.capacitate.capacitate.materialize;
in
{
  libMapper = {
    isCapacitated,
    namespace,
    flakePath,
    value,
    # system,
    # stability,
    ...
  }: let
    attrPath = lib.flatten [flakePath namespace];
  in {
    value = value;
    path =  attrPath;
  };

  lib = composed: let
    materialize' = materialize self.libMapper;

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

   plugin = { capacitate, ... }:
    {
      lib = self.lib (capacitate.composeSelf "lib");
    };
}
