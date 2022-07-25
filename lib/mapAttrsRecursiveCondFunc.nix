{}:
with builtins;
# premapper :: path: value: output-to-be-processed
#   default = (a: b: b)
#
# mapper :: (key -> value -> value) -> attrset -> attrset
#   default = builtins.mapAttrs
#
# cond :: [ String ] -> AttrSet -> Bool
# f :: [ String ] -> Any -> Any
premapper: mapper: cond: f: set: let
    recurse = path: let
      g = name: value: let
        path' = path ++ [name];
        try =
          builtins.tryEval
          (
            if isAttrs value && cond path' value
            then recurse path' (premapper path value)
            else f path' value
          );
      in
        if try.success
        then try.value
        else null;
    in
      mapper g;
  in
    recurse [] set
