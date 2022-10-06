{lib, args}:
let capacitate = lib.capacitor.capacitate; 
    self = capacitate.capacitate; in
{

    makeApplyConfigsWith = {
      ...
    } @ defaults: {
      outerPath,
      fn,
      ...
    } @ closure: let
      hasSystem =
        if lib.length outerPath == 0
        then false
        else lib.elem (lib.head outerPath) lib.platforms.all;
      namespace =
        if lib.length outerPath == 0 || (hasSystem && lib.length outerPath == 1)
        then ["default"]
        else if hasSystem
        then (lib.tail outerPath)
        else outerPath;

      # if has System only use the specified one
      # else instantiate for all systems
      systems =
        if hasSystem
        then [(lib.head outerPath)]
        else defaults.systems;


      # call configs
      closures =
        map
        (system:
          closure
          // {
            inherit system namespace;
          })
        systems
        ;
    in
      closures;

    generate = packages: {
      outputType,
      systems,
      flakePath,
    } @ defaultConfiguration: flakeArgs: let
      # find all (generating) functions
      collectGens = packageSet: let
        collect = {
          path ? [],
          flakeArgs,
        }:
          if lib.isFunction flakeArgs
          then [
            {
              isCapacitated = true;
              flakePath = flakePath;
              outerPath = path;
              fn = flakeArgs;
            }
          ]
          else if lib.isAttrs flakeArgs
          then
            lib.concatMap collect
            (lib.mapAttrsToList
              (name: flakeArgs: {
                path = path ++ [name];
                inherit flakeArgs;
              })
              flakeArgs)
          else [];
        gens = collect {flakeArgs = packageSet;};
      in
        gens;

      makeApplyConfigs = self.makeApplyConfigsWith defaultConfiguration;

      apply = {
        system,
        fn,
        ...
      } @ inputs: let
        args' =
          lib.mapAttrs (name: self.instantiate system) flakeArgs;

        originalArgs =
          inputs
          // {
            lib = lib // self.root.lib;
            args = flakeArgs;
            args' = args';
            inputs = args';
            self' = self.instantiate system flakeArgs.self;
            self = flakeArgs.self;
            root =  self.root;
            root' = self.rootWith system;
            nixpkgs' = self.nixpkgsWith system;
            nixpkgs = self.nixpkgs;
            pkgs = self.nixpkgsWith system;
            withRev = version: "${version}-r${toString flakeArgs.self.revCount or "dirty"}";
            outputType = outputType;
          }
          // {};

        # TODO: call with callPackage assumably
        output = fn originalArgs;

        isProto = lib.isDerivation output; #.value;
        value = output; #= (if output.success then output.value else {});
        value' =
          if isProto && !(value ? proto)
          then value // {proto = fn;}
          else value;

        closure =
          inputs
          // {
            originalArgs = originalArgs;
            outputType = outputType;
            output = output;
            value = value';
            isProto = isProto;
          };
      in
        closure;

      # flatten = {value, ...} @ closure: let
      #   # todo retrofix for apps
      #   flattenStopType =
      #     if outputType == "apps"
      #     then "apps"
      #     else "derivation";

      #   flattened = flattenTree flattenStopType {value = value;};
      #   closures =
      #     map
      #     ({
      #       path,
      #       value,
      #     }:
      #       closure
      #       // {
      #         innerPath = lib.tail path;
      #         value = value;
      #       })
      #     flattened;
      # in
      #   closures;
    in
      lib.pipe packages [
        collectGens
        # lib.traceVal

        (lib.concatMap makeApplyConfigs)

        (map apply)
        # (lib.concatMap flatten)

        # INFO: uncomment to make generated set evaluate into console
        (map (closure:
          closure
          // {
            fn = {
              __toString = self: "<<Proto Derivation>>";
              __functor = self: closure.fn;
            };
          }))
        # (lib.traceValSeqN 3)
      ];

    generateProjects = outputType: {
      flakePath,
      systems,
    } @ defaultConfiguration: projects: flakeArgs: let
      makeProject = name: project: let
        type =
          if lib.isFunction project
          then "function"
          else if project ? __reflect
          then "capacitated"
          else "legacy";

        project' =
          if type == "legacy"
          then let
            searchProject = system:
              lib.pipe project [
                (p: p.outputs or p)
                (p: p.${outputType} or {})
                (p: p.${system} or {})
              ];
          in {
            self =
              map (
                system: {
                    inherit system;
                    outerPath = []; # for legacy Packages no inner path is / can be generated
                    namespace = []; # <-- TODO: flakePath to allow auto.callPackage?
                    value = searchProject system;
                    flakePath = flakePath ++ [name];
                    isCapacitated = false;
                    # value = project';
                  }
              )
              systems;
            children = {}; # legacy projects have no children
            adopted = {}; # legacy projects cannot adopt
          }
          else if type == "capacitated"
          then project.__reflect.composeSelfWith outputType (defaultConfiguration // {flakePath = flakePath ++ [name];})
          else if type == "function"
          then let
            generated = self.generate project (defaultConfiguration
              // {
                isCapacitated = false;
                flakePath = flakePath ++ [name];
                inherit outputType;
              }) flakeArgs;
          in {
            self = map (g: g // {namespace = [name];}) generated;
            children = {};
            adopted = {};
          }
          else if type == "flake"
          then throw "Import of non capacitated flakes not yet implemented"
          else throw "Unknown type: ${type}";
      in
        project';
      # brandPackageSet = {project, packageSet}: project //
    in
      lib.pipe projects [
        (lib.mapAttrs makeProject)
      ];

    generateAdopted = outputType: {
      flakePath,
      systems,
    } @ defaultConfiguration: adopted: parentArgs: let
      makeAdoptee = name: adoptee: (adoptee.__reflect.composeSelf outputType).self;
      reapply = name: closures:
        map (c: let
          newNamespace = [name] ++ c.namespace;
          
          newArgs = {
            namespace,
            inputs,
            args',
            self',
            self,
            system,
            ...
          } @ originalArgs:
            originalArgs
            // {
              # flakePath = flakePath;
              namespace = newNamespace;
              args = args // parentArgs;
              args' = args' // (lib.capacitor.capacitate.capacitate.instantiate system parentArgs);
              inputs = args' // (lib.capacitor.capacitate.capacitate.instantiate system parentArgs);
              self' = self' // (lib.capacitor.capacitate.capacitate.instantiate system parentArgs.self);
              self = self // parentArgs.self;
            };
        in
          c
          // {
            adopted = true;
            namespace = newNamespace;
            flakePath = flakePath;
            value = c.fn (newArgs c.originalArgs);
          })
        closures;
      # brandPackageSet = {project, packageSet}: project //
    in
      lib.pipe adopted [
        (lib.mapAttrs makeAdoptee)
        (lib.mapAttrs reapply)
      ];

    materialize = mapper: sets: let
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
      ];

    compose = outputType: config: flakeArgs: flake: projects: adopted: let
      projectsInstances = self.generateProjects outputType config projects flakeArgs;
      adoptedInstances = self.generateAdopted outputType config adopted flakeArgs;
      selfInstances = self.generate (flake.${outputType} or {}) (config // {inherit outputType;}) flakeArgs;
    in {
      self = selfInstances;
      adopted = adoptedInstances;
      children = projectsInstances;
    };

    # TODO: replace with sanitize or remove
    instantiate = system:
      lib.mapAttrs (
        _: flakeInput:
        flakeInput.${system} or flakeInput
      );
   
    nixpkgsWith = system: self.nixpkgs.legacyPackages.${system};
    rootWith = system: self.instantiate system self.root;
    
    root = args.root;
    systems = self.root.__reflect.finalFlake.config.systems or ["aarch64-darwin" "aarch64-linux" "x86_64-darwin" "x86_64-linux"];
    nixpkgs = self.root.inputs.nixpkgs or args.nixpkgs;
    defaultPlugins = lib.capacitor.plugins.importers.all;

  capacitate = 
  # arguments to the flake
  flakeArgs:
  # flake function
  mkFlake: let

    # self = lib.capacitor.capacitate;
    capacitor = lib.capacitor;

    context = {
      lib = lib // self.root.lib;
      inputs = flakeArgs;
      self = flakeArgs.self;
      root = self.root; 
      systems = self.systems;
      nixpkgs = self.nixpkgs;
      auto = capacitate.auto args;
      has =  (capacitate.has flakeArgs);
    };

    originalFlake = mkFlake context;
    finalFlake = flakeArgs.self.__reflect.finalFlake;

    # generateSelfWith = output: config: self.generate (flake.${output} or {}) (config // {outputType = output;}) flakeArgs;
    composeSelfWith = outputType: config: self.compose outputType config flakeArgs finalFlake (finalFlake.config.projects or {}) (finalFlake.config.adopted or {});
    composeSelf =  x: composeSelfWith x {
      flakePath = [];
      systems = self.systems;
    };
    composed = composeSelf "packages";

    selfWith = system: self.instantiate system flakeArgs.self;

    instantiatedPlugins = let updates = lib.concatMap (
        plugin: let 
          pluginInputs = {
            inherit finalFlake originalFlake ;
            context = context;
            # // { self = (instantiatedPlugins // {outPath = (flakeArgs.self.sourceInfo.outPath);} ); };
            capacitate = {
              inherit composeSelf composeSelfWith;
            };
          }; 
          outputs = plugin pluginInputs;
          in
          lib.flatten [outputs]
        ) (
          (if originalFlake ? config.plugins then originalFlake.config.plugins else self.defaultPlugins)
          ++ (if originalFlake ? config.extraPlugins then originalFlake.config.extraPlugins else [])
          ); in

        lib.foldl'
          lib.recursiveUpdate 
          {}
          ([ ((originalFlake.passthru or {}) // {__reflect = reflect;} ) ] ++ updates)
          ;

    reflect = lib.foldl' lib.recursiveUpdate (originalFlake.config or {}) [
      { 
          systems = self.systems;
          config = self.finalFlake.config;
      }
      { 
        # Both originalFlake and final Flake refer to the flake definition passed to `capacitate`
        # `originalFlake` is the flake as initially passed in
        # `finalFlake` may be altered by a plugin to inject additional composed content
        #
        #  A plugin like this could inject a locally sourced lib tree:
        #
        #  (_: context: _: {
        #    path = ["__reflect" "finalFlake" "lib" "capacitor"];
        #    value = _: context.auto.localResourcesWith {root = root;} "lib" context "lib/";
        #  })
        #
        originalFlake = originalFlake;
        finalFlake = originalFlake;
      }
      {
          inherit (self)
            compose;
          inherit
            composeSelfWith
            composeSelf
            ;
      }
      # TODO: remove, or wait for overlay trees?
      {
        proto = x:
          (lib.mapAttrsRecursiveCond
            (f: !(lib.isFunction f))
            (
               p: f: {
                __functor = _: {
                  system,
                  ...
                } @ args:
                  f (args
                    // {
                      inputs = args.inputs // (lib.capacitor.capacitate.capacitate.instantiate system flakeArgs.self.inputs);
                      args' = args.args' // (lib.capacitor.capacitate.capacitate.instantiate system flakeArgs.self.inputs);
                      args = args.args // flakeArgs.self.inputs;
                    });
              }
            )
            {_ = finalFlake.${x};})
          ._;
      }
    ];
  in
    instantiatedPlugins;

}
