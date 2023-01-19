# Plugins

Plugins are THE way capacitor constructs the final flake output.
As a reminder capacitor is used in place of the flake output definition:

```nix
{
    outputs = {capacitor, ...} @ args: 
        capacitor args (            # capacitor :: args
            context: { }            # -> (context  -> definitions [1])
        );                          # -> flake definition [2]
}
```

Every plugin transforms the input definitions (1) into an output which can be a flake output or an extension of the input used by another plugins. All outputs are then combined and form the final flake definition (2).


## Default Plugins

The plugins that come with Capacitor by default transform common flake outputs defined as proto-derivations to instantiated outputs.

### Packages

function: `lib.capacitor.capacitate.plugins.importers.packages`
alias: `capacitor.plugins.packages`

Generates a flat representation of the flake's **packages**.
That is: the definitions can be nested but will have flat output structure

```nix
{
    outputs = {capacitor, ...} @ args: capacitor args ( context: {
        packages.hello = {pkgs,...}: pkgs.hello;
        packages.nested.packages.are.top = {pkgs,...}: pkgs.top;
    });
}
```

```nix
{
    outputs = {nixpkgs,...}: {
        packages.<system>.hello = nixpkgs.legacyPackages.<system>.hello;
        packages.<system>."nested/packages/are/top" = {pkgs,...}: pkgs.top;
    };
}
```

### LegacyPackages

function: `lib.capacitor.capacitate.plugins.importers.legacyPackages`
alias: `capacitor.plugins.legacyPackages`

Generates a nested representation of the flake's **packages**.
Uses the same `packages` attribute as input, but lays it out differently.

```nix
{
    outputs = {capacitor, ...} @ args: capacitor args ( context: {
        packages.hello = {pkgs,...}: pkgs.hello;
        packages.nested.packages.are.top = {pkgs,...}: pkgs.top;
    });
}
```

```nix
{
    outputs = {nixpkgs,...}: {
        packages.<system>.hello = nixpkgs.legacyPackages.<system>.hello;
        packages.<system>.nested.packages.are.top = nixpkgs.legacyPackages.<system>.top;
    };
}
```

### Apps

function: `lib.capacitor.capacitate.plugins.importers.apps`
alias: `capacitor.plugins.apps`

Generates a nested representation of the flake's **apps**.

```nix
{
    outputs = {capacitor, ...} @ args: capacitor args ( context: {
        packages.nested.packages.are.top = {pkgs,...}: pkgs.top;
        apps.hello = {self',lib,...}: {
            type = "app";
            program = lib.getExe self.legacyPackages.nested.packages.are.top;
        };
    });
}
```

```nix
{
    outputs = {nixpkgs, self,...}: {
        legacyPackages.<system>.nested.packages.are.top = {pkgs,...}: nixpkgs.legacyPackages.<system>.top;

        apps.<system>.hello = <app>;
    };
}
```

### DevShells

function: `lib.capacitor.capacitate.plugins.importers.devShells`
alias: `capacitor.plugins.devShells`

```nix
{
    outputs = {capacitor, ...} @ args: capacitor args ( context: {
        packages.hello = {pkgs,...}: pkgs.hello;
        devShells.default = {self', pkgs, lib,...}: pkgs.mkShell {
            packages = [pkgs.gcc];
            inputsFrom = [self'.packages.hello];
        };
    });
}
```

```nix
{
    outputs = {nixpkgs, self,...}: {
        packages.<system>.hello = nixpkgs.legacyPackages.<system>.hello;
        devShells.<system>.default = <devShell>;
    };
}
```

### Lib

function: `lib.capacitor.capacitate.plugins.importers.lib`
alias: `capacitor.plugins.lib`

Generates library artifacts. The final type of these artifacts can be anything, i.e. utility functions, constants, sources, etc.
No matter the type, the library artifacts still need to be defined as proto functions.
The resulting library is available as `context.lib`.
Note that because of that, `lib` cannot be used to define library artifacts outside of the proto.

```nix
{
    outputs = {capacitor, ...} @ args: capacitor args ( context: {
        lib = {
            constant = _: "value";
            plus = _: a: b: a+b;
            # allowed because `plus` is a different attribute
            add5 = {self,...}: self.lib.plus 5;
            # NOT allowed as it uses `lib` in the definition of `lib` (due to merging with `nixpkgs.lib`)
            squares = context.lib.genAttrs 
                (number: context: { "${number}" = number * number; })
                [1,2,3,4,5,6,7,8,9,10];
        };
    });
}
```

## Optional Plugins

Optional plugins are plugins that are distributed through capacitor but not activated by default, because they are more general functions or not critical.

### localResources

function: `lib.capacitor.capacitate.plugins.localResources`
alias: `capacitor.plugins.localResources`
type: `{ type, path ? [type], injectedArgs ? {}, dir ? type } -> plugin`

- `type`: type of what is import
- `path`: attributePath at which the sources should be imported.
- `dir`: a path from which the files are read;
- `injectedArgs`: arguments that are passed to all files


Reads a directory recursively, calls all `*.nix` files, and exposes their values in the definition respecting the original path of the file.
Only **extends the definition**, i.e. to import packages, both the `packages` and the `localResources` plugin have to be active.

**Note**: Resources are imported using [`lib.capacitor.capacitate.auto.callPackage`](./lib.md), which allows most proto-derivations from nixpkgs to be copied into the loaded folder and provides scoped packages. 

#### Loading from directory

Any proto derivation added to the `pkgs` folder is automatically loaded.
The example given is taken directly from the nixpkgs repository.

```nix

# flake.nix
{
  outputs = {capacitor, ...} @ args: capacitor args ( context: {
    config.extraPlugins = [
        (capacitor.plugins.localResources { type = "packages"; dir = "pkgs"; })
    ];
  });
}


# pkgs/games/antsSimulator/default.nix

{ lib, stdenv, fetchFromGitHub, cmake, sfml }:

stdenv.mkDerivation rec {
  pname = "antsimulator";
  version = "3.1";

  src = fetchFromGitHub {
    owner = "johnBuffer";
    repo = "AntSimulator";
    rev = "v${version}";
    sha256 = "sha256-1KWoGbdjF8VI4th/ZjAzASgsLEuS3xiwObulzxQAppA=";
  };

  nativeBuildInputs = [ cmake ];
  buildInputs = [ sfml ];

  postPatch = ''
    substituteInPlace src/main.cpp \
      --replace "res/" "$out/opt/antsimulator/"
    substituteInPlace include/simulation/config.hpp \
      --replace "res/" "$out/opt/antsimulator/"
    substituteInPlace include/render/colony_renderer.hpp \
      --replace "res/" "$out/opt/antsimulator/"
  '';

  installPhase = ''
    install -Dm644 -t $out/opt/antsimulator res/*
    install -Dm755 ./AntSimulator $out/bin/antsimulator
  '';

  meta = with lib; {
    homepage = "https://github.com/johnBuffer/AntSimulator";
    description = "Simple Ants simulator";
    license = licenses.free;
    maintainers = with maintainers; [ ivar ];
    platforms = platforms.unix;
  };
}
```


#### Provide dependencies directory

Proto derivations in files have immediate access to peer derivations in the same folder.

```nix
# flake.nix
{

  inputs = {
    flox-examples-hello-haskell-library = {
      url = "github:flox-examples/hello-haskell-library";;
      flake = false;
    };

    flox-examples-hello-haskell = {
      url = "github:flox-examples/hello-haskell";
      flake = false;
    }
  };

  outputs = {capacitor, ...} @ args: capacitor args ( context: {
    config.extraPlugins = [
      (capacitor.plugins.localResources { type = "packages"; dir = "pkgs"; })
    ];
  });
}


# pkgs/haskellPackages/hello-haskell-library/default.nix
{ mkDerivation, acme-missiles, inputs }:
mkDerivation {
  src = inputs."flox-examples-hello-haskell-library";
  pname = "hello-haskell-library";
  version = "0.1";
  license = "MIT";
  libraryHaskellDepends = [
    acme-missiles
  ];
}

#pkgs/hello-haskell/default.nix
{ haskellPackages, fetchFromInputs}: with haskellPackages;
mkDerivation {
  src = inputs."flox-examples-hello-haskell";
  pname = "hello-haskell";
  version = "0.1";
  license = "MIT";
  libraryHaskellDepends = [
    hello-haskell-library
  ];
}
```

### allLocalResources

function: `lib.capacitor.capacitate.plugins.allLocalResources`
alias: `capacitor.plugins.allLocalResources`
type: `{ injectedArgs ? {} } -> plugin`

A default application of `localResources` loading:

- `devShells` from `./shell`
- `packages` from `./pkgs`
- `apps` from `./apps` and
- `lib` from `./lib`


This example shows packages, devShells and lib working together without additional changes to the flake (except possible flake-tracked inputs); 

```nix
# flake.nix
{
  outputs = {capacitor, ...} @ args: capacitor args ( context: {
    config.extraPlugins = [
      (capacitor.plugins.allLocalResources { })
    ];
  });
}

# lib/date-version.nix
{inputs}: version: version + "-" + inputs.self.sourceInfo.lastModified

# pkgs/somPackage/default.nix
{lib, mkDerivation}: mkDerivation {
    version = lib.date-version "2.1.1"
    #...
}

# shells/default.nix
{pkgs}: pkgs.mkShell {
    packages = [pkgs.gdb];
    inputsFrom = [ pkgs.somePackage];
}

```

## Developing Plugins

The plugin system is a vital part of the capacitor.
Almost all functions that base on this library are implemented as plugins.

In the section above we've seen how to **use** plugins. 
Now, we discuss how to **produce** plugins.


### Structure


At the core plugins are simple functions that produce (recursively merged) attribute sets.

signature: `{ context, capacitate, finalFlake, originalFlake } -> { ... }`

- `context`: the same context of the flake **using** this plugin. (see [Capacitate#Context](lib/capacitate.md)) 
- `originalFlake`: the original input to capacitate, ie. the verbatim configuration as defined by the **using** flake.
- `finalFlake` The original flake with additions or alterations applied. This value will be used to detect packages.
- `capacitate`: builtin capacitor functions
  - `capacitate.composeSelf :: String -> { self: {...}; adopted: {...}; children: {}; }`: uses `finalFlake` to generate an enumeration of the proto-\* defined under the given attribute name.
  - `capacitate.composeSelfWith:: String -> { flakePath, systems, stabilities } -> { self: {...}; adopted: {...}; children: {}; }`
    The same as `composeSelf` but allows to change the instantiated stabilites/systems.

The output of the plugin has to be an attribute set which is merged at the top namespace of the output.

### Example:

Consider the two plugins `fooPlugin` and`barPlugin`

```nix
fooPlugin = { ... }: {
  foo = {
    ... ;
  }
};
```
```nix
barPlugin = { ... }: {
  bar = {
    ... ;
  };
}
```

If applied with capacitor the resulting flake output will be:

```nix
{
  foo = {};
  bar = {};
}
```

Since keys are recursively merged you can also extend an attribute by providing an inner attribute:

```nix
fooBarPlugin = { ... }: {
  foo.bar = {
    ... ;
  };
}
```

which results in:

```nix
{
  foo = {
    bar = { ... };
    ... ;
  };
  bar = {};
}
```

Note: Generally, only a single plugin should write into the outermost namespace so as to avoid conflicts or unwanted overrides.
For example, the `fooBarPlugin` might override an exiting `foo.bar` attribute.

You can however use the `__reflect.finalFlake` attribute to store intermediate values, and these values will then be visible in the `finalFlake` input.
This is used for example to create the loaders.

The `localResources` plugin extends the collection of proto-\* for some attribute (e.g. packages)
```nix
# user API
{ type, path ? [type], injectedArgs ? {}, dir ? type }:
# plugin API
{ context, ... }:
{
  __reflect.finalFlake = lib.setAttrByPath path (context.auto.localResourcesWith injectedArgs type context "${dir}/");
}
```

Using

```nix
extraPlugins = [
  (localResources {type = "packages";})
]
```

Populates the `packages` attribute which is picked up by the (default) `packages` and `legacyPackages` plugins which expose their respective attributes at the root namespace.
