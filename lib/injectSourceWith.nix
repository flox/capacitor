# Search through input urls to select the source that matches the url
lib: args: provided: url: with builtins; let
  system = provided.system; # or (throw "fetchFrom argument must be given stdenv");
  inputs = provided;
  msg = ''

Unable to find source '${url}' in flake inputs. Run inside a clone of the flake:

    flox run '.#update-inputs'
    flox flake update

If source is private, run the following to fetch the source code:

      flox path-info '${url}#'

it should provide an error about not finding a nix file, after that perform a build.
  '';

  search = attrNames (args.nixpkgs.lib.filterAttrs (_: val:
      val.url or null == url
      ) inputs);
  a = if search == []
  then throw msg
  else head search;
  input = args.${a};

  lock = with builtins; (
    fromJSON (readFile (args.self.outPath + "/flake.lock"))
    ).nodes.${a}.locked;

  out = derivation {
    name = "source";
    builder = "/bin/sh";
    args = ["-c" ''
read -d "" msg <<- EOF
${msg}
EOF
echo "$msg"
exit 2
    ''];
    system = system;
    outputHash = lock.narHash;
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
  };

in
{ inherit url input lock out;
  inherit (out) outPath;
}
