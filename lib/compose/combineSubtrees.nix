{lib}: let
  combineSubtrees = lib.self.capacitor.compose.combineSubtrees;
in
  # Combines a tree of flakes to a tree of package definitions
  #
  # context:: a _capacitor_ context.
  #          during the initial iteration, this is equivalent to the parent flake
  #          for the following iterations, the attrName used by the parent is
  #          apended to the flake path
  #          and the `self` attribute is substituted for the child's `self`
  #
  # prev:: an attrset <storePath> -> <processed subtree>
  # {
  #   storePath: {
  #     # the package closures defined in the flake
  #     self: { <attrpath as String>: <guarded closure> },
  #     # all packages defined by the flake and its children
  #     # conflicts and overrides are guarded
  #     subtree: { <attrpath as String>: <guarded closure> },
  #     # reexpose processed children
  #     children: <name> -> <processed subtree>
  #   }
  # }
  {
    self,
    system,
    ...
  } @ context: prev: let
    # I have no idea why the outPath has to be retrieved with such an awkward indirection
    # the inherit (inputs) seems to remove all those attributes (rev, outPath, etc)
    identifier = self.__reflect.context.self.outPath;
    identify = x: x.flake.__reflect.context.self.outPath;

    children =
      if hasPrevSelf && prevSelf.seen
      then {}
      else
        lib.mapAttrs
        (name: child:
          combineSubtrees
          (child.__reflect.context // {inherit system;})
          (prev // {${builtins.unsafeDiscardStringContext identifier} = output;}))
        #TODO use finalFlake?
        (lib.attrByPath ["config" "projects"] {} (self.__reflect));

    prunedSubtrees = let
      # list of subtrees that includes the subtree identifier
      subtrees =
        lib.mapAttrsToList (subtreeName: child: {
          inherit subtreeName;
          inherit (child) subtree;
        })
        children;
    in
      lib.foldl'
      (
        {
          conflicts,
          all,
          duplicates,
          candidates,
        }: {
          subtreeName,
          subtree,
        }: let
          intersecting = lib.intersectLists (lib.attrNames all) (lib.attrNames subtree);
          partitioned = lib.partition (candidate: (identify all.${candidate}) != (identify subtree.${candidate})) intersecting;
          conflicting = partitioned.right;
          duplicated = partitioned.wrong;

          # Conflict entry
          # This conflict function is called when accessing the conflicting attribute
          # The attribute value can not be known unless the importing flake defines a
          # resolution (i.e. an override)
          mkConflict = attrPath:
            conflicts.${attrPath}
            or {
              inherit (subtree.${attrPath}) namespace outerPath attrName circular;
              flake.outPath = identifier;
              fn = {candidates}:
                throw ''
                  ${context.lib.showAttrPath context.flakePath}: '${attrPath}' is defined in multiple inputs, do not know which to use or override.

                  ${attrPath} is defined in the following imports: ${builtins.toJSON (lib.attrNames candidates.${attrPath})}

                  Resolve the conflict
                    - A) by renaming the attribute in either or all of the imports
                    - B) manually merging the conflicting definitions
                         the definitons can be accessed through either:

                  ${lib.concatStringsSep "\n" (map (c: "\t\t- pkgs.candidates.hello.${c}") (lib.attrNames candidates.${attrPath}))}
                '';
            };
        in {
          # candidate are available in the call namespace as [pkgs].candidates.<conflicting attribute>.<subtree>;
          # Allows to resolve conflicts by choosing or overriding different candidateså
          candidates = lib.genAttrs conflicting (
            conflictAttr:
              (candidates.${conflictAttr}
                or {
                  ${lib.last all.${conflictAttr}.flakePath} = all.${conflictAttr};
                })
              // {
                ${subtreeName} = subtree.${conflictAttr};
              }
          );
          conflicts = conflicts // (lib.genAttrs conflicting mkConflict);
          duplicates = duplicates // (lib.genAttrs duplicated lib.id); # a set
          all = all // subtree // {inherit candidates;};
        }
      )
      {
        conflicts = {};
        all = {};
        duplicates = {};
        candidates = {};
      } # nul
      
      subtrees;

    # the set of packages defined in the processed flake
    # overrides of packages in included flakes cause warnings
    groupedSelf = let
      # read the proto derivations from the for the current flake
      selfBlueprints = context.closures "packages";

      addCustomAttributes = map (proto:
        proto
        // {
          inherit context;
          attrName = lib.showAttrPath proto.namespace;
        });

      addGuards = map (p: (overrideGuard (p // {flake = self;})));
      makePairs =
        map
        (
          {namespace, ...} @ p:
            lib.nameValuePair (lib.showAttrPath namespace) p
        );
    in
      lib.pipe selfBlueprints [
        addCustomAttributes
        addGuards
        makePairs
        builtins.listToAttrs
      ];

    # Injects guards preventing or warning about incompatibilities
    # If a flake redefines an existing definition of an attribute the guard will
    #   - throw an error if the definition is of an **indirect input**
    #     (to reduce impact and increase visibility)
    #   - issue a warning if the flake redefines an attribute of a **direct input**
    #     persists unless the user explicitly marks the override as backwards compatible
    #     or renames the definition.
    #   - issue a warning if the flake defines an attribute that resolves a conflict
    #     persists unless the user explictly marks the resolution as backwards compatible
    #
    # TODO: disallow any override of attributes that are not grounded in nixpkgs?
    # TODO: expose synthetic namespaces through which overridden attributes can be accessed
    #       in original form
    #       (may result in possible closure size increase and runtime incompatibilities)
    overrideGuard = closure: let
      name = closure.attrName;

      resolvesConflict = prunedSubtrees.conflicts ? ${name};

      # Collect the subtree definitions of the children
      subtrees = lib.catAttrs "subtree" (lib.attrValues children);

      # Existing definitions in hte subtrees
      baseDefinitions = let
        definitions = map (subtree: lib.attrsets.attrByPath [name] null subtree);
        valid = builtins.filter (definition: definition != null && definition.flake.outPath != identifier);
      in
        lib.pipe subtrees [
          definitions
          valid
        ];

      # if a definition exists, the current closure is an override
      overridesBaseDefinition = baseDefinitions != [];

      # collect overriden flakes' paths
      overrideBaseDefinitionFlakePaths = "[${lib.concatStringsSep ", " (map (base: lib.showAttrPath base.flakePath) baseDefinitions)}]";

      definedByDirectDependency = let
        selfDepth = lib.length closure.flakePath;
      in
        builtins.any (base: selfDepth + 1 == (lib.length base.flakePath)) baseDefinitions;

      # Users need to manually sign off overrides
      signedOffOverride = lib.elem name (closure.flake.__reflect.finalFlake.config.checkedExtensions or []);

      # whether the closure is redefined by a parent
      isRedefined =
        builtins.any
        (definer: (definer.self) ? ${name})
        (lib.attrValues prev);

      guard =
        # redefinition of an attribute defined by an **indirect** dependency
        if overridesBaseDefinition && !resolvesConflict && !definedByDirectDependency
        then
          ({context, ...}:
            lib.trace isRedefined (throw ''
              ${lib.showAttrPath closure.flakePath}: '${name}' is defined by an indirect input: ${overrideBaseDefinitionFlakePaths}
              Redefining '${name}' could break these inputs.

              If '${name}' is indeed an independent, incompatible definition consider
                - A) renaming '${name}' to a new, unique name
                - B) moving '${name}' to a new namespace
                - C) asking the maintainers of ${overrideBaseDefinitionFlakePaths} to rename or move their definition.

              If '${name}' is an extension of the definition in ${overrideBaseDefinitionFlakePaths}
                1. Declare ${overrideBaseDefinitionFlakePaths} as an input of ${lib.showAttrPath closure.flakePath}
                2. Make sure the extension is compatible with ${overrideBaseDefinitionFlakePaths}.
                   - If they are compatible, append "${name}" to `config.checkedExtensions` in ${lib.showAttrPath closure.flakePath}'s flox.nix.
            ''))
        # redefinition of an attribute defined by an **direct** dependency
        else if overridesBaseDefinition && !resolvesConflict && !signedOffOverride
        then
          {context, ...} @ args:
            lib.trace ''
              ${lib.showAttrPath closure.flakePath}: '${name}' is defined by an input: ${overrideBaseDefinitionFlakePaths}
              If '${name}' is an extension of the definition in ${overrideBaseDefinitionFlakePaths}:
                - Make sure the extension is compatible with ${overrideBaseDefinitionFlakePaths}.
                - If they are compatible, append "${name}" to `config.checkedExtensions` in ${lib.showAttrPath closure.flakePath}'s flox.nix.

              If it is not or the two versions are not compatible, consider:
                - A) renaming '${name}' to a new, unique name
                - B) moving '${name}' to a new namespace
                - C) asking the maintainers of ${overrideBaseDefinitionFlakePaths} to rename or move their definition.
            '' (context.callPackageWith {} closure.fn {})
        # Conflict resolution
        else if resolvesConflict && !signedOffOverride
        then
          {context, ...} @ args:
            lib.trace ''
              ${lib.showAttrPath closure.flakePath}: '${name}' resolves a conflict between multiple the definitions of the attribute in ${overrideBaseDefinitionFlakePaths}.

              If '${name}' is backwards compatible with all conflicting definitions in ${overrideBaseDefinitionFlakePaths}
                - append "${name}" to `config.checkedExtensions` in ${lib.showAttrPath closure.flakePath}'s flox.nix.

              If it is not possible to resolve the conflict in a acompatible manner, consider:
                - asking the maintainers of ${overrideBaseDefinitionFlakePaths} to rename or move their definition.

              If this attribute is independent from either of the conflicting attributes, consider:
                - A) renaming '${name}' to a new, unique name
                - B) moving '${name}' to a new namespace

              While neither of these solutions has been implemented, the definition of '${name}' may break some assumtions of imported flakes!

              This warning will persist unless the conflict is resolved or conflicting definitions validated as compatible.
            '' (context.callPackageWith {} closure.fn {})
        else closure.fn;
    in (
      closure
      // {
        # inherit isRedefined;
        isBaseDefinition = !overridesBaseDefinition;
        circular = false;
        fn = lib.trace context.flakePath guard;
      }
    );

    # the attrset produced by the current flake
    # includes the children's trees and adds conflics notices as well as
    # the locally defined (guarded) package definitions
    subtree = lib.pipe (lib.attrValues children) [
      # Concatenate children's definitions.
      #
      # In this step multiple definitions of the same attribute are possible
      # and may replace each other in arbitrary order.
      # The set is therefore referred to as "unsafe"
      # TODO: nested / recursive Update??
      (lib.foldl' (prev: child: prev // (child.subtree)) {})
      # Replace the conflicting attributes with error notices.
      # These can only be generated by the _importing_ (parent) flake
      # as the children are not aware of each other
      #
      # As a result of this a "safe" attrset of packages is produced
      (unsafeCombinedChildren: unsafeCombinedChildren // prunedSubtrees.conflicts // groupedSelf)
    ];

    # allow stopping recursion if `self` has already been visited earlier
    # if visited before return previous definitions, but mark them as circular
    # and redefined.
    hasPrevSelf = prev ? ${builtins.unsafeDiscardStringContext identifier};
    prevSelf = prev.${builtins.unsafeDiscardStringContext identifier};
    prevSelf' =
      lib.mapAttrs
      (_: closure: closure // {circular = true;})
      prevSelf.self;

    # The output of a combined subtree
    output = {
      inherit prunedSubtrees children;
      self =
        if hasPrevSelf
        then prevSelf'
        else groupedSelf;
      subtree =
        if hasPrevSelf && prevSelf.seen
        then {}
        else subtree;
      seen = hasPrevSelf;
    };
  in
    # lib.traceSeqN 2 ([(lib.attrNames prev) identifier groupedSelf])
    output
