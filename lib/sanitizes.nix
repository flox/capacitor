{lib, ...}: values: fragment: let
  inherit (lib.capacitor) smartType;
  # sanitizes: [string] -> attrset -> attrset
  # remove multiple attribute names from a level of attrset
  #
  #
  # sanitizes ["legacyPackages" "x86_64-linux" "foo"]
  # {
  #   legacyPackages.x86-64-linux.foo = {a=2;};
  #   legacyPackages.foo = {a=1;};
  # }
  #
  # {
  #   a = 2;
  # }
  len = builtins.length values;
  recurse = depth: fragment:
    if depth >= len
    then fragment
    else
      {
        "null" = null;
        "derivation" = fragment;
        "bool" = fragment;
        "lambda" = arg: recurse depth (fragment arg);
        "list" = map (x: recurse depth x) fragment;
        "set" = let
          head = builtins.elemAt values depth;
          elem = fragment.${head} or null;
        in
          if elem == null
          then lib.mapAttrs (_: recurse (depth + 1)) fragment
          else recurse (depth + 1) elem;

        __functor = self: type: (self.${type} or fragment);
      } (smartType fragment);
in
  recurse 0 fragment
