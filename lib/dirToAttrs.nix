{lib,...}:
let
  func = dir: overrides: let
    dirToAttrsWith = let
      exists = builtins.pathExists dir;

      importPath = name: type: let
        path = dir + "/${name}";
      in
        {
          directory =
            lib.nameValuePair name
            ({
                inherit type path;
              }
              // (
                if builtins.pathExists "${path}/default.nix"
                then {
                  type = "nix";
                }
                # ignore flakes: todo: call them via callLockless
                else if builtins.pathExists "${path}/flake.nix"
                then {
                  type = "flake";
                }
                else if builtins.pathExists "${path}/default.toml"
                then {
                  type = "toml";
                  path = "${path}/default.toml";
                }
                else func path overrides
              ));
          #directory = lib.nameValuePair name
          ##(lib.callPackageWith pkgs path overrides);
          #{
          #  inherit path type;
          #};

          regular =
            if lib.hasSuffix ".nix" name && !lib.hasSuffix "flake.nix" name
            then
              lib.nameValuePair (lib.removeSuffix ".nix" name) {
                inherit path;
                type = "nix";
              }
            else if lib.hasSuffix ".toml" name
            then
              lib.nameValuePair (lib.removeSuffix ".toml" name) {
                inherit path;
                type = "toml";
              }
            else null;
        }
        .${type}
        or (throw
          "Can't auto-call file type ${type} at ${toString path}");

      # Mapping from <package name> -> { value = <package fun>; deep = <bool>; }
      # This caches the imports of the auto-called package files, such that they don't need to be imported for every version separately
      entries =
        lib.filter (v: (v?value && v != null
        && v.value!= {}
        ))
        (lib.attrValues (lib.mapAttrs importPath (builtins.readDir dir)));

      # Regular files should be preferred over directories, so that e.g.
      # foo.nix can be used to declare a further import of the foo directory
      entryAttrs =
        lib.listToAttrs (lib.sort (a: b: a.value.type == "regular") entries);

      result =
        if exists
        then entryAttrs
        else (builtins.traceVerbose or (x: y: y)) "Not importing any attributes because the directory ${dir} doesn't exist" {};
    in
      result;
  in
    dirToAttrsWith;
in
  func
