lib:
args: inputs: n: v: (
        if !(v ? src) || v.src == null || v.src == "/" || builtins.isNull v.src
        then let
          src = let
            a = with builtins;
              head (attrNames (lib.filterAttrs (k: val: ((val ? url)
                && (
                  (v ? meta && v.meta ? project && val.url == v.meta.project)
                  || (v ? passthru && v.passthru ? project && val.url == v.passthru.project)
                )))
              inputs));
          in
            args.${a};
        in
          (
            if (v ? override && v.override.__functionArgs ? source) || builtins.isFunction v && (builtins.functionArgs v) ? source
            then v.override {source = src;}
            else v
          )
          .overrideAttrs (old: {
            src = src;
          })
        else v
      )
