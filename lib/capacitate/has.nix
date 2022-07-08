{lib}:
flakeArgs:
let
  auto = lib.capacitor.capacitate.auto;

  both' = extra: args': (
    (
      if lib.isFunction args'
      then a: both' extra (args' a)
      else extra args'
    )
  );

  both = extra: both' (b: lib.recursiveUpdate b extra);

  versions = versions: both {config.versions = versions;};
  systems = systems: both {config.systems = systems;};
  stabilities = stabilities: both {config.stabilities = stabilities;};
  projects = projects: both {config.projects = projects;};

  localPackagesFrom =  set: let
    argsClean = builtins.removeAttrs set ["capacitor" "self"];
    capacitated = lib.filterAttrs (_: v: (lib.isAttrs v && v ? __reflect)) (argsClean);
  in
    both { packages = capacitated.protoPackages; };

  projectsFrom = set: let
    argsClean = builtins.removeAttrs set ["capacitor" "self"];
    capacitated = lib.filterAttrs (_: v: (lib.isAttrs v && v ? __reflect)) (argsClean);
  in
    both { config.projects = capacitated; };

  projectsFromInputs = projectsFrom flakeArgs;

  hydraJobs = both {hydraJobs = flakeArgs.self.packages;};


  localPkgs = path:
      both {packages = (auto.localPkgs path);};


in {
  inherit both' both;

  # Automatically wrap the other api functions with both or both'
  # // (lib.mapAttrs (
  #     fn: let
  #       consume = fn: arg: let
  #         fn' = fn arg;
  #       in
  #         if lib.isFunction
  #         then consume fn'
  #         else both fn';
  #     in
  #       if lib.isFunction fn
  #       then consume fn
  #       else both fn
  #   ) {
  inherit versions systems stabilities projects projectsFrom projectsFromInputs hydraJobs localPkgs;
}
