{
  lib,
  self,
  ...
}: let
  materialize = lib.capacitor.capacitate.materialize;
  all = with self.lib.capacitor; {
    "packages" = capacitate.packages.plugin;
    "legacyPackages" = capacitate.legacyPackages.plugin;
    "hydraJobs" = capacitate.hydraJobs.plugin;
    "lib" = capacitate.lib.plugin;
    "apps" = capacitate.genericImport "apps";
    "devShells" = capacitate.genericImport "devShells";
    "bundlers" = capacitate.genericImport "bundlers";
    "checks" = capacitate.genericImport "checks";
  };
in
  all
  // {
    all = lib.attrValues all;
    generic = self.lib.capacitor.capacitate.genericImport;
  }
