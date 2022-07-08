# capacitor API
{lib,...}:
# user API
{ dir ? "templates" }:
# Plugin API
{ context, capacitate, ... }:
{
    templates = builtins.mapAttrs
          (k: v: {
            path = v.path;
            description = (import (v.path + "/flake.nix")).description or "no description provided in ${v.path}/flake.nix";
          })
          (lib.capacitor.dirToAttrs  (context.self + "/${dir}") { });
}
