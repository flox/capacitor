{lib, ...}: let
  all = with lib.capacitor; {
    "lib" = capacitate.lib.plugin;
    "analyzeFlake" = capacitate.analyzeFlake.plugin;
    "apps" = capacitate.apps.plugin;
    "devShells" = capacitate.devShells.plugin;
    "hydraJobs" = capacitate.hydraJobs.plugin;
    "legacyPackages" = capacitate.legacyPackages.plugin;
    "packages" = capacitate.packages.plugin;
    "bundlers" = capacitate.bundlers.plugin;
  };
in
  all // {all = lib.attrValues all;}
