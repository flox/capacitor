{lib}: mapper: sets: let
  wrap = {
    path,
    value,
    ...
  }: {
    inherit path;
    update = _: value;
  };
  buildAttrSet = updates: lib.updateManyAttrsByPath updates {};
in
  lib.pipe sets [
    (lib.sort (a: b: (lib.length a.outerPath) < (lib.length b.outerPath)))
    (map mapper)
    (lib.flatten)
    (lib.filter ({
      use ? true,
      value,
      ...
    }:
      if lib.isFunction use
      then use value
      else use))
    (map wrap)
    buildAttrSet
  ]
