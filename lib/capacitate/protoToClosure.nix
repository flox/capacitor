{lib, ...}: {
  systems,
  flakePath ? [],
  # outputType,
  ...
} @ defaults: {
  type,
  isCapacitated,
  outerPath,
  fn,
} @ closure: let
  hasSystem =
    if lib.length outerPath == 0
    then false
    else lib.elem (lib.head outerPath) lib.platforms.all;
  namespace =
    if lib.length outerPath == 0 || (hasSystem && lib.length outerPath == 1)
    then ["default"]
    else if hasSystem
    then (lib.tail outerPath)
    else outerPath;

  # if has System only use the specified one
  # else instantiate for all systems
  systems =
    if hasSystem
    then [(lib.head outerPath)]
    else defaults.systems;

  systemlessClosure =
    closure
    // {
      inherit namespace flakePath;
      # inherit outputType;
    }
    // {
      fn = {
        __toString = self: "<<Proto Derivation>>";
        __functor = self: closure.fn;
      };
    };

  closuresForEachSystem =
    map
    (system: systemlessClosure // {inherit system;})
    systems;
in
  if systems != []
  then closuresForEachSystem
  else [systemlessClosure]
