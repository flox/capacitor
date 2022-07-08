{lib}:
let self = lib.capacitor.capacitate.hydraJobs;
    materialize = lib.capacitor.capacitate.capacitate.materialize;
in
{
  hydraJobsMapper = {
    isCapacitated,
    namespace,
    flakePath,
    value,
    system,
    stability,
    ...
  }: let
    attrPath = lib.flatten [stability flakePath namespace system];
  in {
    value = lib.hydraJob (lib.trace attrPath value);
    path = attrPath;
    use = isCapacitated;
  };

  hydraJobs = composed: let
    materialize' = materialize self.hydraJobsMapper;

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
     let jobs = self.hydraJobs (capacitate.composeSelf "packages"); in
        {
          # TODO: generating these causes nix to segfault?
          "hydraJobsStable" = jobs.stable; 
          "hydraJobsUnstable" = jobs.unstable; 
          "hydraJobsStaging" = jobs.staging; 
        };
}
