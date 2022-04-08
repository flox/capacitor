lib: args: inputs: n: v: (
  if !(v ? src) || v.src == null || v.src == "/" || builtins.isNull v.src
  then let
    src = let
      a = with builtins;
      ## TODO: detect empty list and provide warning that project cannot be found
        head (attrNames (lib.filterAttrs (k: val: ((val ? url)
          && (
            (v ? meta && v.meta ? project && val.url == v.meta.project)
            || (v ? passthru && v.passthru ? project && val.url == v.passthru.project)
          )))
        inputs));
    in
      args.${a};

    result =
      if builtins.isAttrs v && (v ? override && v.override.__functionArgs ? source) || builtins.isFunction v && (builtins.functionArgs v) ? source
      then v.override {source = src;}
      else v;
  in
    if builtins.isAttrs result && result ? overrideAttrs
    then
      result.overrideAttrs (old: {
        src = src;
      })
    else v
  else v
)
