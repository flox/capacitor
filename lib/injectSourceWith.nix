# Search through input urls to select the source that matches the url
{lib}: flake: provided: url:
with builtins; let
  inputs = provided;
  msg = ''

    Unable to find source '${url}' in flake inputs. Run inside a clone of the flake:

        flox run '.#update-inputs'
        flox flake update

    If source is private, run the following to fetch the source code:

          flox flake prefetch '${url}'
  '';

  search = attrNames (flake.nixpkgs.lib.filterAttrs (
      _: val:
        val.url or null == url
    )
    inputs);
  a =
    if search == []
    then throw msg
    else head search;
  input = flake.${a};

  lock = with builtins;
    (
      fromJSON (readFile ((flake.self.inputs.lock.outPath or flake.self.outPath) + "/flake.lock"))
    )
    .nodes
    .${a}
    .locked;

  out = derivation {
    name = "source";
    outputHash = lock.narHash;
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    builder = "builtin:fetchurl";
    system = "dummy";
    url = msg;
  };

  # TODO: extract into lib
  computeStorePath = narHash:
    (
      derivation {
        name = "source";
        outputHash = narHash;
        outputHashAlgo = "sha256";
        outputHashMode = "recursive";
        builder = "builtin:fetchurl";
        system = "dummy";
        url = msg;
      }
    )
    .outPath;
in {
  inherit url input lock out;
  inherit (input) outPath;
}
