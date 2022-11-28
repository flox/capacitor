{lib}:
# args to the capacitor
args: let
  localResourcesWith = injectedArgs: x: context: dir: let
    tree = lib.capacitor.dirToAttrs (context.self + "/${dir}") {};
    func = path: attrs:
      builtins.removeAttrs (builtins.mapAttrs (
          k: v: (
            let
              path' = path ++ [k];
            in
              if !(v ? path) || v.type == "directory"
              then func path' v
              else if v.type == "nix" || v.type == "regular"
              then import v.path
              # retain the "type" in order to allow finding it during
              # other traversal/recursion
              # then v
              else throw "unable to create attrset out of ${v.type}"
          )
        )
        attrs) ["path" "type"];
  in
    func [] tree;
  localResources = res: localResourcesWith {} res;
in {
  using = lib.flip lib.capacitor.using.using;
  usingWith = inputs: attrs: pkgs: lib.capacitor.using.using (pkgs // {inherit inputs;}) attrs;
  fetchFrom = lib.capacitor.using.fetchFrom;

  localResourcesWith = localResourcesWith;
  localResources = localResources;

  # withNamespace = namespace: fn: {
  #   namespace = namespace;
  #   __functor = self: customization: auto.callPackage fn (customisation // { namespace = self.namespace; });
  # };
}
