self: self-capacitor-lib: let
  lib = self-capacitor-lib;
in
  rec {
  call = import ./call-flake.nix;
  lock = builtins.fromJSON (builtins.readFile (self + "/flake.lock"));
  subflake = k: extras: overrides:
    call (builtins.readFile (self + "/flake.lock")) self "" "pkgs/${k}" "${k}" extras (
      if overrides ? inputs
      then follow overrides
      else overrides
    );
  subflakes = inputs: with lib; builtins.attrNames (filterAttrs (key: v: hasPrefix "path:./" (v.url or "")) inputs);

  callSubflake = sub: subflake sub {capacitor = ["capacitor"];};

  callSubflakeWith = sub: overrides: let
    outputs = subflake sub {capacitor = ["capacitor"];} overrides;
  in
    outputs;

  callSubflakesWith = inputs: overrides:
    lib.genAttrs (subflakes inputs) (sub: let
      outputs = callSubflakeWith sub overrides;
    in
      outputs);

  follow = overrides: let
    r = path: l: o:
        lib.mapAttrsRecursiveList (_: a: !builtins.isString a)
        (path: value:
          assert (lib.last path == "follows"); {
            path = with builtins;
              lib.filter isString (lib.lists.imap0 (i: a:
                if i / 2 * 2 == i
                then a
                else [])
              path);
            follows = follows value;
          })
        o;
    val = lib.flatten (r [] lock.nodes overrides.inputs);
  in
    val;
  follows = lib.strings.splitString "/";

  autoSubflakes = inputs: callSubflakesWith inputs {
    inputs.capacitor.inputs.nixpkgs.follows = "capacitor/nixpkgs/nixpkgs-unstable";
  };
  flakesWith = inputs: override:
    callSubflakesWith inputs {
      inputs.capacitor.inputs.nixpkgs.follows = override;
    };

  # clean up an flake output schema root and generate things for systems
  mapRoot = attrs: builtins.mapAttrs (key: value:
    if lib.elem key ["legacyPackages" "packages" "devShells" "checks" "apps" "bundlers" ]
    # hydraJobs are backward, nixosConfigurations need system differently
    then lib.genAttrs (attrs.__systems or [
      "x86_64-linux"
      "x86_64-darwin"
      "aarch64-linux"
      "aarch64-darwin"
    ])
      (s: sanitizes value [key s])
    else value) attrs;

  # perform multiple sanitize actions
  # remove multiple attribute names from a level of attrset
  # TODO: perform all at once in sanitize
  sanitizes = value: builtins.foldl' (acc: x: sanitize acc x) value;

  # sanitize: attrset -> string -> attrset
  # remove an attribute name from a level of attrset
  sanitize = let
    recurse = depth: fragment: system:
      if depth <= 0
      then fragment
      else
        {
          "derivation" = fragment;
          "lambda" = arg: recurse depth (fragment arg) system;
          "list" = map (x: recurse (depth - 1) x system) fragment;
          "set" =
            if fragment ? ${system}
            then recurse depth fragment.${system} system
            else lib.mapAttrs (_: fragment: recurse (depth - 1) fragment system) fragment;
          __functor = self: type: (self.${type} or fragment);
        } (lib.smartType fragment);
  in
    recurse 6;
}
