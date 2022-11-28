{lib, ...}: let
  callFlake = lib.capacitor.callFlake;
in {
  rootFlake = {
    root,
    inputs,
    ...
  }:
    callFlake
    (builtins.readFile "${root}/flake.lock")
    root
    ""
    ""
    "root"
    {} {};

  localFlake = {
    root,
    inputs,
    ...
  }: rootPath: path: let
    # find the flake input for this local path
    p = builtins.concatStringsSep "/" path;
    nodes =
      builtins.filter (x: x.value == "path:./${rootPath}${p}")
      (builtins.attrValues (builtins.mapAttrs (k: v: {
          name = k;
          path = "${rootPath}${p}";
          value = v.url or "";
        })
        inputs));
    found =
      if builtins.length nodes == 1
      then builtins.head nodes
      else abort ''too few or too many results, add inputs.<name>.url = "path:./${rootPath}${p}";'';
  in
    callFlake
    (builtins.readFile "${root}/flake.lock")
    root
    ""
    found.path
    found.name
    {} # { capacitor = ["capacitor"];}
    
    {};
}
