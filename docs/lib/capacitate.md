# Capacitate


function: **`capacitor.lib.capacitate`**
alias: `capacitor.__functor`
type: `args -> (context -> definition) -> flakeOutput`

arguments:

- `args`: attributes passed tot he `outputs` function of the flake (i.e. the inputs) 
- `(context -> configuration)`: given a **flake** `context` define a set of [proto-\*](./proto-x.md) and optionally configure the capacitate process.
- `flakeOutput` the final output generated from the proto-x by builtin plugins and optional plugins configured.


## Context


- `lib`: Essentially nixpkgs' library extended with the flakes' defined library (`nixpkgs.lib` // `self.lib`).
  - **NOTE**: as `self.lib` is merged into the top level of `nixpkgs.lib` the `context` library cannot be used to construct the `lib` attribute:
    ```nix
    {
        outputs = {capacitor,...} @ args: capacitor args (context: {
            # ⚡️ ⚡️ ⚡️ infinite recursion
            lib = context.lib.genAttrs ( _: _: { /* */ }) [];

            # use nixpkgs.lib here instead
            lib = context.nixpkgs.lib.genAttrs ( _: _: { /* */ }) [];
        });
    }
    ```
- `args` or `inputs`: the exact arguments passed to the flake (raw inputs).
- `self`: reference to the final flake itself 
- `nixpkgs`: the nixpkgs input
- `auto`: helper functions (see: [./auto.md])

## Configuration

Capacitor only inspects the *optional* `config` attribute.

`config` is and attribute set with the following content:

- `systems`: A list of system keys (Default: `["aarch64-darwin" "aarch64-linux" "x86_64-darwin" "x86_64-linux"]`)
- `plugins`: A list of [plugins](../plugins.md) to be loaded (Default `[lib analyzeFlake apps devShells hydraJobs legacyPackages packages]`)
- `extraPlugins`: additional plugins, use this if you want to maintain default behavior of capacitor while adding additional ones

All other attributes are handled by respective [plugins](../plugins.md).

Top level attributes that are not processed by plugins are not added to the top-level of the resulting flake.
To pass attributes untreated, they should be defined under `passthru`.

```nix
{
    outputs = {capacitor,...} @ args: capacitor args (context: {
        
        # ⚠️ if not handled by a plugin, `hello` will not appear in the final flake
        hello = "world";

        # ⚠️ not using proto-functions will also cause pacakges to be missing from the output
        packages.aarch4-darwin.somePackage = nixpkgs.legacyPackages.aarch64-darwin.mkDerivation { /* */ };

        # using passthru the final flake will contain the required arguments:
        passthru.hello = "world";
      # --------
        
        passthru.packages.aarch4-darwin.somePackage = nixpkgs.legacyPackages.aarch64-darwin.mkDerivation { /* */ };
      # --------
    });
}
```

## Output

The output of `capacitate` is determined by the plugins configured for the capacitated flake.
To build toe final output, the partial outputs of all plugins and `passthru` attributes are merged using a recursive update.


Notes: 
The order of plugins does not matter in general unless plugins write to the same value.
Plugins may *experience infinite* recursion if they use a value they they define themself and requires changes to the plugin.



## Reflection
