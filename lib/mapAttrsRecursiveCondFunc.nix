with builtins;
  mapper: cond: f: set: let
    recurse = path: let
      g = name: value: let
        path' = path ++ [name];
        try =
          builtins.tryEval
          (
            if isAttrs value && cond path' value
            then recurse path' value
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
