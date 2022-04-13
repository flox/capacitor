# Search through input urls to select the source that matches the url
lib: args: inputs: url: let
  a = with builtins;
  ## TODO: detect empty list and provide warning that project cannot be found
    head (attrNames (args.nixpkgs.lib.filterAttrs (k: val: (
        (val ? url)
        && (val.url == url)
      ))
      inputs));
in
  args.${a} // {url = url;}
