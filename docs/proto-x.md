
# Proto Functions

Any single flake output element (a single package, app, library function, etc) is defined as function.
Capacitor [*collects*](./lib/collect.md) those functions and calls them for each configured system (`{x86_64,aarch64}-{linux,darwin}`).

## Context set

The **function** `context` the function is called with should in principle contain anything necessary.
It is an attribute set with the following keys:


- `system`: the system this proto is generating an output for.
- `namespace`: Attribute path to the function
- `outputType`: the type of element expected as output
- `lib`: Essentially nixpkgs' library extended with the flakes' defined library (`nixpkgs.lib` // `self.lib`).
- `args`: the exact arguments passed to the flake (raw inputs).
- `args'` or `inputs`: same as `args` but with the current system preselected (`inputs.<input>.<output> = args.<input>.<output>.<system>`)
- `self`: reference to the final flake itself 
- `self'`: same as `self` but with the current system preselected
  Can be used to reference other artifacts defined in the flake e.g. as dependency or to alias them;
  ```nix
  {
    outputs = { capacitor, ... } @ args: capacitor args (context: {
        packages.default = {self',...}: self'.packages.hello; 
        packages.hello = {pkgs,...}: pkgs.hello;
    });
  }
  ```
- `nixpkgs`: the nixpkgs input
- `nixpkgs'` or `pkgs`: same as `nixpkgs` but with the current system preselected


## Hiding Systems

Flakes require one to explicitly provide derivations for individual systems. Therefore providing the same package for the four most important system types requires either four explicit definitions or the use of some boilerplate to instantiate the required nixpkgs. 

```nix 
{
    outputs = { nixpkgs, ... }: {
        packages = {
            x86_64-linux.default = nixpkgs.legacyPAckages.x86_64-linux.rustPlatform.buildRustPackage { /* ... */ };
            x86_64-darwin.default = nixpkgs.legacyPAckages.x86_64-darwin.rustPlatform.buildRustPackage { /* ... */ };
            aarch64-linux.default = nixpkgs.legacyPAckages.aarch64-linux.rustPlatform.buildRustPackage { /* ... */ };
            aarch64-darwin.default = nixpkgs.legacyPAckages.aarch64-darwin.rustPlatform.buildRustPackage { /* ... */ };
        };
    });
}
```


```nix 
{
    outputs = { nixpkgs, ... }: {
        packages = nixpkgs.lib.genAttrs (system: 
            let pkgs = nixpkgs.legacyPackages.${system};
            in
            {
                default = pkgs.rustPlatform.buildRustPackage { /* ... */ };
            }) [ /* systems */ ]
    });
}
```

While the second approach allows building attribute sets quickly its less convenient to provide different implementations for diffenrent systems.
With Capacitor if no explicit system is present in the attribute path to the definition of the proto, the proto function is called with all configured systems [./configuration.md] otherwise the call happens only with the defined system.:

```nix 
{
    outputs = { capacitor, ... } @ args: capacitor args (context: {
        packages.default = {pkgs,...}: pkgs.rustPlatform.buildRustPackage { /* ... */ };
        packages.aarch64-darwin.default = {pkgs,...}: pkgs.python3Packages.buildPythonApplication { /* ... */ };
    });
}
```

is equivalent to

```nix
{
    x86_64-linux.default = nixpkgs.legacyPackages.x86_64-linux.rustPlatform.buildRustPackage { /* ... */ };
    x86_64-darwin.default = nixpkgs.legacyPackages.x86_64-darwin.rustPlatform.buildRustPackage { /* ... */ };
    aarch64-linux.default = nixpkgs.legacyPackages.aarch64-linux.rustPlatform.buildRustPackage { /* ... */ };
    # note: other definition than the above
    aarch64-darwin.default = nixpkgs.legacyPackages.aarch64-darwin.python3Packages.buildPythonApplication { /* ... */ };
}
```
