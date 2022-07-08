# capacitor API
{ lib, ... }:
# user API
{ injectedArgs ? { } }:
# Plugin API
pluginInputs:

let resourceTypes = {
  "devShells" = "shells";
  "packages" = "pkgs";
  "apps" = "apps";
  "lib" = "lib";
};
in


  lib.foldl' lib.recursiveUpdate {} (
    lib.mapAttrsToList (type: dir:
      (lib.capacitor.plugins.localResources { inherit type dir injectedArgs; } pluginInputs)
    )
    resourceTypes)
