{lib}: set: let
  collect = {
    path ? [],
    setOrProto,
  }:
  # [sic]
    if builtins.isFunction setOrProto
    then [
      {
        type = "proto";
        isCapacitated = true;
        outerPath = path;
        fn = setOrProto;
      }
    ]
    else if lib.isAttrs setOrProto
    then
      lib.concatMap collect
      (lib.mapAttrsToList
        (name: setOrProto: {
          path = path ++ [name];
          inherit setOrProto;
        })
        setOrProto)
    else [];
  gens = collect {setOrProto = set;};
in
  gens
