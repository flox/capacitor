self-capacitor-lib: self: self-lock: let
  lib = self-capacitor-lib;
in
  rec {
  call = import ./call-flake.nix;
  lock = builtins.fromJSON (builtins.readFile (self-lock + "/flake.lock"));
  subflake = dir: k: extras: overrides:
    call (builtins.readFile (self-lock + "/flake.lock")) self "" "${dir}" "${k}" extras (
      if overrides ? inputs
      then follow overrides
      else overrides
    );
  subflakes = inputs: prefix: with lib; builtins.attrNames (filterAttrs (key: v: hasPrefix prefix (v.url or "")) inputs);

  callSubflake = dir: sub: subflake dir sub {
    # This is "register"
    # inputs.capacitor.follows = "capacitor"
    capacitor = ["capacitor"];
  };

  callSubflakeWith = dir: sub: overrides: let
    outputs = subflake dir sub {capacitor = ["capacitor"];} overrides;
  in
    outputs;

  callSubflakesWith = inputs: prefix: overrides:
    lib.genAttrs (subflakes inputs prefix) (sub: let
      outputs = callSubflakeWith (lib.strings.removePrefix "path:./" inputs.${sub}.url ) sub overrides;
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

  autoSubflakes = inputs: prefix: callSubflakesWith inputs prefix {
    inputs.capacitor.inputs.nixpkgs.follows = "capacitor/nixpkgs/nixpkgs-unstable";
  };
  flakesWith = inputs: prefix: override:
    callSubflakesWith inputs prefix {
      inputs.capacitor.inputs.nixpkgs.follows = override;
    };

}
