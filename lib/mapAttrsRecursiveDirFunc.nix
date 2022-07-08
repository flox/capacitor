{lib}:
let
  inherit (lib.capacitor) mapAttrsRecursiveCondFunc flakes dirToAttrs smartType;
in
with builtins;
context@{self,root ? self,inputs,...}: dir: attrPath:
        mapAttrsRecursiveCondFunc
        (path: value: lib.filterAttrs (n: v: !builtins.elem n ["path" "type"]) value)
        builtins.mapAttrs
        (path: value: !(let type = value.type or ""; in type == "nix" || type == "flake"))
        (
          path: value: let
            type = value.type or "";
          in
            if type == "flake"
            then
            let flake = flakes.localFlake context dir path;
                attr = lib.getAttrFromPath attrPath flake;
            in
            if smartType attr == "lambda"
            then
              c: c (lib.attrByPath attrPath {} flake) {src = flake.inputs.src;}
            else attr
            else value.path
        )
        (dirToAttrs (self + "/${dir}") {})
