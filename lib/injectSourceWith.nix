# Search through input urls to select the source that matches the url
lib: args: inputs: url: with builtins; let
  search = attrNames (args.nixpkgs.lib.filterAttrs (_: val:
      val.url or null == url
      ) inputs);
  a = if search == []
  then throw "unable to find source '${url}' in flake inputs. Tey to regenerate"
  else head search;
in
  # TODO: is this an okay place to stash the url?
  args.${a} // {url = url;}
