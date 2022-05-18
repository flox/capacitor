lockFileStr: rootSrc: rootSubdir: subflakeSubdir: subflakeKey: extras: overrides: let
  lockFile = builtins.fromJSON lockFileStr;

  allNodes =
    builtins.mapAttrs
    (
      key: node: let

        overridesResolved = let a= if builtins.isList overrides
        then builtins.foldl' (acc: x: acc // x) {} (map (i: { ${resolveInput true i.path} = resolveInput true i.follows;} ) overrides)
        else overrides;
        in a;

        sourceInfo =
          if key == subflakeKey
          then {outPath = rootSrc;} // node
          else if key == lockFile.root
          then rootSrc // node
          else (fetchTree (node.info or {} // removeAttrs node.locked ["dir"])) // node;

        subdir =
          if key == subflakeKey
          then rootSubdir + "/" + subflakeSubdir
          else if key == lockFile.root
          then ""
          else node.locked.dir or "";

        flake = import (sourceInfo
          + (
            if subdir != ""
            then "/"
            else ""
          )
          + subdir
          + "/flake.nix");

        inputs =
          builtins.mapAttrs
          (inputName: inputSpec:
          if builtins.isAttrs (resolveInput true inputSpec)
          then resolveInput true inputSpec
          else allNodes.${resolveInput true inputSpec})
          (node.inputs or {});
        extraInputs =
          builtins.mapAttrs
          (_: inputSpec:
          # inputSpec)
          allNodes.${resolveInput true inputSpec})
          (if key == subflakeKey then extras else {});

        # Resolve a input spec into a node name. An input spec is
        # either a node name, or a 'follows' path from the root
        # node.
        resolveInput = first: inputSpec:
          if builtins.isList inputSpec
          then getInputByPath lockFile.root inputSpec
          else if first && overridesResolved?${inputSpec}
          then
            if builtins.isAttrs overridesResolved.${inputSpec}
            then overridesResolved.${inputSpec}
            else resolveInput false overridesResolved.${inputSpec}
          else inputSpec;

        # Follow an input path (e.g. ["dwarffs" "nixpkgs"]) from the
        # root node, returning the final node.
        getInputByPath = nodeName: path:
          if path == []
          then nodeName
          else
            getInputByPath
            # Since this could be a 'follows' input, call resolveInput.
            (resolveInput false lockFile.nodes.${nodeName}.inputs.${builtins.head path})
            (builtins.tail path);

        outputs =
          flake.outputs (extraInputs // inputs // {self = result;});

        result =
          outputs
          // sourceInfo
          // {
            inherit inputs;
            inherit outputs;
            inherit sourceInfo;
          };
      in
        if node.flake or true
        then assert builtins.isFunction flake.outputs; result
        else sourceInfo
    )
    lockFile.nodes;
in
  allNodes.${subflakeKey}
