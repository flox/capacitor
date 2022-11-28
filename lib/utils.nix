{lib, ...}: let
  inherit (lib.capacitor) mapAttrsRecursiveCondFunc;
in {
  # over:: attrset.<n>.<n2> -> attrset.<n2>.<n>
  over = attrs: let
    names = builtins.attrNames attrs;
    names2 = lib.concatMap builtins.attrNames (builtins.attrValues attrs);
  in
    lib.genAttrs names2 (n2: lib.genAttrs names (n: attrs.${n}.${n2}));

  # Like recurseIntoAttrs, but do it for two levels
  recurseIntoAttrs2 = attrs: lib.recurseIntoAttrs (builtins.mapAttrs (_: x: lib.recurseIntoAttrs x) attrs);
  recurseIntoAttrs3 = attrs:
    with lib;
      recurseIntoAttrs (
        builtins.mapAttrs (_: x: recurseIntoAttrs2 x) attrs
      );

  # Like `mapAttrsRecursiveCond`, but the condition can examine the path
  mapAttrsRecursiveCondPath = mapAttrsRecursiveCondFunc builtins.mapAttrs;

  # collectPaths :: (Any -> Bool) -> AttrSet -> [Any]
  # TODO: use updateManyAttrsByPath?
  collectPaths = cond:
    mapAttrsRecursiveCondFunc lib.attrsets.mapAttrsToList cond (p: v: {
      path = p;
      value = v;
    });

  toNested = with builtins;
    i: let
      raw = lib.splitString "." (i.attrPath or i.attr);
      stripQuotes = replaceStrings [''"''] [""];
      result =
        foldl'
        (
          acc: i:
            if lib.length acc > 0 && lib.isList (lib.last acc)
            then
              if !isNull (match ''.*("+)$'' i)
              then lib.init acc ++ [(concatStringsSep "_" (lib.last acc ++ [(stripQuotes i)]))]
              else lib.init acc ++ [(lib.last acc ++ [(stripQuotes i)])]
            else if !isNull (match ''^("+).*'' i)
            then acc ++ [[(stripQuotes i)]]
            else acc ++ [i]
        ) []
        raw;
    in
      lib.attrsets.setAttrByPath (lib.drop 2 result) i;

  parsePath = with builtins;
  with lib;
    attrPath: let
      raw = splitString "." attrPath;
      stripQuotes = replaceStrings [''"''] [""];
      result =
        foldl'
        (
          acc: i:
            if length acc > 0 && isList (last acc)
            then
              if !isNull (match ''.*("+)$'' i)
              then init acc ++ [(concatStringsSep "." (last acc ++ [(stripQuotes i)]))]
              else init acc ++ [(last acc ++ [(stripQuotes i)])]
            else if !isNull (match ''^("+).*'' i)
            then acc ++ [[(stripQuotes i)]]
            else acc ++ [i]
        ) []
        raw;
    in
      result;
}
