{}:
with builtins;
# premapper :: path: value: output-to-be-processed
#   default = (a: b: b)
#
# mapper :: (key -> value -> value) -> attrset -> attrset
#   default = builtins.mapAttrs
#
# cond :: [ String ] -> AttrSet -> Bool
# Note that even if cond evaluates to false, f will still be applied if a leaf is reached
# f :: [ String ] -> Any -> Any
  premapper: mapper: cond: f: set: let
    recurse = path: let
      g = name: value: let
        path' = path ++ [name];
      in
        if isAttrs value && cond path' value
        then recurse path' (premapper path value)
        else f path' value;
    in
      mapper g;
  in
    recurse [] set
