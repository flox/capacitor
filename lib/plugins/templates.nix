# capacitor API
{lib, ...}:
# user API
{dir ? "templates"}:
# Plugin API
{context, ...}: {
  templates =
    builtins.mapAttrs
    (
      k: v:
        if builtins.pathExists (v.path + "/flake.nix")
        then {
          path = v.path;
          description = (import (v.path + "/flake.nix")).description or "no description provided in ${v.path}/flake.nix";
        }
        else if builtins.pathExists (v.path + "/template.nix")
        then {
          path = v.path + "/files";
          description = (import (v.path + "/template.nix")).description or "no description provided in ${v.path}/template.nix";
        }
        else throw "Invalid template directory: ${v.path}"
    )
    (lib.capacitor.dirToAttrs (context.self + "/${dir}") {});
}
